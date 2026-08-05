#include "BookImporter.h"
#include "BookManager.h"
#include "parsers/ParserFactory.h"

#include <unzip.h>   // minizip：EPUB 封面条目读取（与 EpubParser 同源）

#include <QPdfDocument>
#include <QCryptographicHash>
#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFont>
#include <QImage>
#include <QPainter>
#include <QPixmap>
#include <QRegularExpression>
#include <QUrl>
#include <QXmlStreamReader>
#include <utility>

namespace {

// 单条 zip 条目大小上限（与 EpubParser 一致，防恶意/损坏压缩包撑爆内存）
constexpr qint64 kMaxZipEntrySize = 64LL * 1024 * 1024;

QByteArray readZipEntry(const QString &zipPath, const QString &entry) {
    unzFile zip = unzOpen64(zipPath.toUtf8().constData());
    if (!zip) return {};
    QByteArray out;
    // 先精确匹配，再大小写不敏感兜底（真实书条目名大小写偶有出入）
    int rc = unzLocateFile(zip, entry.toUtf8().constData(), 1);
    if (rc != UNZ_OK) rc = unzLocateFile(zip, entry.toUtf8().constData(), 2);
    if (rc == UNZ_OK && unzOpenCurrentFile(zip) == UNZ_OK) {
        char buf[4096];
        int n;
        while ((n = unzReadCurrentFile(zip, buf, sizeof(buf))) > 0) {
            out.append(buf, n);
            if (out.size() > kMaxZipEntrySize) {
                qWarning("BookImporter: 条目 %s 超过 %lld MB，跳过",
                         qUtf8Printable(entry),
                         static_cast<long long>(kMaxZipEntrySize / (1024 * 1024)));
                out.clear();
                break;
            }
        }
        unzCloseCurrentFile(zip);
    }
    unzClose(zip);
    return out;
}

// 解析 zip 内相对路径（href 相对条目所在目录），支持 ./ 与 ../；href 可能含
// 百分号编码、#fragment、?query。与 EpubParser 的 resolveEntry 同一语义。
QString resolveZipEntry(const QString &href, const QString &baseEntry) {
    QString rel = href;
    const int frag = rel.indexOf('#');
    if (frag >= 0) rel.truncate(frag);
    const int query = rel.indexOf('?');
    if (query >= 0) rel.truncate(query);
    rel = QUrl::fromPercentEncoding(rel.toUtf8());
    rel.replace('\\', '/');
    if (rel.isEmpty() || rel.contains("://") || rel.startsWith("data:"))
        return {};
    if (rel.startsWith('/')) rel.remove(0, 1); // 以 / 开头视为相对 zip 根
    QString base = baseEntry;
    const int slash = base.lastIndexOf('/');
    if (slash >= 0) base.truncate(slash + 1); // 保留目录部分（含尾部 '/'）
    QStringList parts = (base + rel).split('/');
    QStringList out;
    for (const QString &p : std::as_const(parts)) {
        if (p.isEmpty() || p == ".")
            continue;
        if (p == "..") {
            if (!out.isEmpty()) out.removeLast();
            continue;
        }
        out.append(p);
    }
    return out.join('/');
}

// 解析 container.xml，取 rootfile full-path（优先 media-type 为 oebps-package+xml 者）
QString containerRootfile(const QByteArray &xml) {
    QXmlStreamReader r(xml);
    QString fallback;
    while (!r.atEnd()) {
        r.readNext();
        if (!r.isStartElement() || r.name().toString() != QLatin1String("rootfile"))
            continue;
        const QString full = r.attributes().value("full-path").toString();
        const QString mt = r.attributes().value("media-type").toString();
        if (full.isEmpty())
            continue;
        if (mt == QLatin1String("application/oebps-package+xml"))
            return full;
        if (fallback.isEmpty())
            fallback = full;
    }
    return fallback;
}

// 从 content.opf 解析封面条目：EPUB2 <meta name="cover" content="id">、
// EPUB3 <meta property="cover-image"> / <item properties="cover-image">；
// 均未声明时兜底取 manifest 中第一个图片条目（按文档序，QHash 迭代序
// 随进程随机化不可用）。返回 zip 内条目路径。
QString opfCoverEntry(const QByteArray &opf, const QString &opfEntry) {
    QXmlStreamReader r(opf);
    QString coverId;
    QHash<QString, QPair<QString, QString>> itemById; // id → (href, media-type)
    QVector<QPair<QString, QString>> imageItems;      // manifest 文档序的图片条目
    while (!r.atEnd()) {
        r.readNext();
        if (!r.isStartElement()) continue;
        QString tag = r.name().toString();
        const int colon = tag.indexOf(':');
        if (colon >= 0) tag.remove(0, colon + 1);
        if (tag == QLatin1String("meta")) {
            const QString name = r.attributes().value("name").toString();
            const QString prop = r.attributes().value("property").toString();
            if (name == QLatin1String("cover") || prop == QLatin1String("cover-image"))
                coverId = r.attributes().value("content").toString();
        } else if (tag == QLatin1String("item")) {
            const QString id = r.attributes().value("id").toString();
            const QString href = r.attributes().value("href").toString();
            const QString mt = r.attributes().value("media-type").toString();
            if (r.attributes().value("properties").toString()
                    .split(' ').contains(QLatin1String("cover-image")))
                coverId = id;
            if (!id.isEmpty() && !href.isEmpty()) {
                itemById.insert(id, qMakePair(href, mt));
                if (mt.startsWith("image/"))
                    imageItems.append(qMakePair(href, mt));
            }
        }
    }
    if (!coverId.isEmpty()) {
        const auto it = itemById.constFind(coverId);
        if (it != itemById.constEnd())
            return resolveZipEntry(it.value().first, opfEntry);
        // EPUB3 的 cover-image 声明 content 也可能是相对 IRI（如 "Images/cover.jpg"）
        // 而非 manifest item id：直接相对 OPF 目录解析（绝对 URL/data URI 会解析失败，
        // 落入下方兜底）。item 查找与文档序兜底均确定，不依赖 QHash 无序迭代。
        const QString direct = resolveZipEntry(coverId, opfEntry);
        if (!direct.isEmpty())
            return direct;
    }
    // 兜底：manifest 文档序第一个图片条目
    if (!imageItems.isEmpty())
        return resolveZipEntry(imageItems.first().first, opfEntry);
    return {};
}

// 统一封面归一化：等比放大至填满 300x400 后居中裁剪（书架 3:4 裁切显示，
// 避免白边，封面顶部标题约 1% 的裁剪可接受）。EPUB 提取与 PDF 首页渲染共用。
QImage normalizeCover(QImage img) {
    const QSize target(300, 400);
    if (img.size() != target) {
        img = img.scaled(target, Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);
        const QRect crop((img.width() - target.width()) / 2,
                         (img.height() - target.height()) / 2,
                         target.width(), target.height());
        img = img.copy(crop);
    }
    return img;
}

// 真实封面统一命名：covers/cover_<书文件路径 md5>.png（与占位 <hash6>.png 区分）
QString realCoverPath(const QString &bookPath, const QString &coverDir) {
    return coverDir + QStringLiteral("cover_") + QString::fromLatin1(
        QCryptographicHash::hash(bookPath.toUtf8(), QCryptographicHash::Md5).toHex())
        + QStringLiteral(".png");
}

} // namespace

BookImporter::BookImporter(const QString &libraryDir, const QString &dbPath, QObject *parent)
    : QObject(parent), m_libraryDir(libraryDir), m_books(new BookManager(dbPath, "readdict_importer")) {}

BookImporter::~BookImporter() {
    delete m_books;
}

QString BookImporter::detectFormat(const QString &fileName) {
    const QString ext = QFileInfo(fileName).suffix().toLower();
    if (ext == "epub") return "EPUB";
    if (ext == "pdf") return "PDF";
    if (ext == "mobi") return "MOBI";
    if (ext == "azw3" || ext == "azw") return "AZW3";
    if (ext == "txt") return "TXT";
    if (ext == "md") return "MD";
    if (ext == "fb2") return "FB2";
    return {};
}

QString BookImporter::importFile(const QString &srcPath, bool moveIntoLibrary) {
    const QString format = detectFormat(srcPath);
    if (format.isEmpty()) return "不支持的文件格式";
    QDir lib(m_libraryDir); lib.mkpath("books");
    const QString fileName = QFileInfo(srcPath).fileName();
    const QString dest = m_libraryDir + "/books/" + fileName;
    if (QFile::exists(dest)) return "同名文件已存在于书库";
    if (!QFile::copy(srcPath, dest)) return "复制文件失败";
    const QString coverDir = m_libraryDir + "/covers/";
    const QString title = QFileInfo(fileName).completeBaseName();
    // 封面由 MD5(标题) 前 6 位命名，同标题书籍共享同一封面文件：
    // 记录生成前是否已存在，回滚时不得删除仍被健康记录引用的封面。
    const QString placeholderPath = coverPathFor(title, coverDir);
    const bool coverExisted = QFile::exists(placeholderPath);
    m_lastError.clear();
    QString cover;
    QString rollbackCover; // 本次新建、入库失败时需删除的封面（真实封面按书文件命名必为新建）
    if (format == "EPUB") {
        // EPUB 提取真实封面（OPF cover 声明 → 解析结果首个内嵌图片）；失败回退占位。
        // TXT/MD/FB2/MOBI 无内嵌封面保留占位。
        const QString realCover = extractEpubCover(dest, coverDir);
        if (!realCover.isEmpty()) {
            cover = realCover;
            rollbackCover = realCover;
        } else {
            cover = generatePlaceholderCover(title, coverDir);
            if (!coverExisted) rollbackCover = cover;
        }
    } else if (format == "PDF") {
        // PDF 渲染首页为真实封面（B9）；加载/渲染失败回退占位。
        const QString realCover = extractPdfCover(dest, coverDir);
        if (!realCover.isEmpty()) {
            cover = realCover;
            rollbackCover = realCover;
        } else {
            cover = generatePlaceholderCover(title, coverDir);
            if (!coverExisted) rollbackCover = cover;
        }
    } else {
        cover = generatePlaceholderCover(title, coverDir);
        if (!coverExisted) rollbackCover = cover;
    }
    Book b;
    b.title = title;
    b.format = format; b.path = dest; b.cover = cover;
    // addBook 返回 -1 表示写入失败（如 path 唯一约束冲突、FTS 索引写入失败），此时回滚文件副作用。
    if (m_books->addBook(b) < 0) {
        QFile::remove(dest);
        if (!rollbackCover.isEmpty()) QFile::remove(rollbackCover);
        return "写入数据库失败";
    }
    return {};
}

QString BookImporter::coverPathFor(const QString &title, const QString &destDir) {
    const QString hash = QCryptographicHash::hash(title.toUtf8(), QCryptographicHash::Md5).toHex().left(6);
    return destDir + "/" + hash + ".png";
}

QString BookImporter::generatePlaceholderCover(const QString &title, const QString &destDir) const {
    QDir(destDir).mkpath(".");
    const QString path = coverPathFor(title, destDir);
    QPixmap pm(300, 400); pm.fill(QColor("#3D5AFE"));
    QPainter p(&pm);
    p.setPen(Qt::white);
    QFont f = p.font(); f.setPointSize(120); f.setBold(true); p.setFont(f);
    const QChar ch = title.isEmpty() ? QChar('?') : title.at(0);
    p.drawText(pm.rect(), Qt::AlignCenter, QString(ch));
    p.end();
    pm.save(path, "PNG");
    return path;
}

QString BookImporter::extractEpubCover(const QString &epubPath, const QString &coverDir) {
    QImage img;
    // 候选 1：OPF 声明的封面（EPUB2 <meta name="cover"> / EPUB3 cover-image），
    // 直接读 zip 条目。优先于解析结果：SVG 包裹的封面页（<image> 而非 <img>）
    // 不会被 EpubParser 提取，但 OPF 声明对这类书仍然可靠。
    const QByteArray container = readZipEntry(epubPath, "META-INF/container.xml");
    const QString opfEntry = containerRootfile(container);
    if (!opfEntry.isEmpty()) {
        const QByteArray opf = readZipEntry(epubPath, opfEntry);
        const QString entry = opfCoverEntry(opf, opfEntry);
        if (!entry.isEmpty()) {
            const QByteArray data = readZipEntry(epubPath, entry);
            if (!data.isEmpty()) img.loadFromData(data);
        }
    }
    // 候选 2：解析 DocumentModel 后取首个内嵌图片（无封面声明的书，封面多为
    // 首图）。解析失败不影响入库：封面回退占位，原因记入 lastError。
    if (img.isNull()) {
        const DocumentModel model = ParserFactory::parse(epubPath, "EPUB");
        if (model.empty()) {
            m_lastError = QStringLiteral("EPUB 解析失败，封面回退占位");
            qWarning() << "BookImporter: 封面提取失败（EPUB 解析为空），保留占位封面" << epubPath;
            return {};
        }
        for (const Chapter &c : model.chapters) {
            for (const Paragraph &p : c.paragraphs) {
                if (!p.imagePath.isEmpty()) {
                    img.load(p.imagePath);
                    if (!img.isNull()) break;
                }
            }
            if (!img.isNull()) break; // 锁定首章首图：外层循环不得覆盖已加载图片
        }
    }
    if (img.isNull()) {
        m_lastError = QStringLiteral("未找到内嵌封面，保留占位封面");
        qWarning() << "BookImporter: 未找到 EPUB 内嵌封面，保留占位封面" << epubPath;
        return {};
    }
    // 统一缩放到 300x400（normalizeCover：等比放大至填满后居中裁剪）
    QDir(coverDir).mkpath(".");
    // 真实封面按书文件路径 md5 命名（covers/cover_<md5>.png），与占位命名区分
    const QString path = realCoverPath(epubPath, coverDir);
    if (!normalizeCover(img).save(path, "PNG")) {
        m_lastError = QStringLiteral("封面保存失败，保留占位封面");
        qWarning() << "BookImporter: 封面保存失败" << path;
        return {};
    }
    return path;
}

QString BookImporter::extractPdfCover(const QString &pdfPath, const QString &coverDir) {
    QPdfDocument doc;
    doc.load(pdfPath);
    // 加载可能异步完成（QPdfDocument::load 返回后 status 为 Loading）：同步轮询等待
    // Ready/Error，避免首帧即取 status() 误判失败（正常 PDF 首次加载即 Ready）。
    for (int i = 0; i < 200 && doc.status() == QPdfDocument::Status::Loading; ++i)
        QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
    if (doc.status() != QPdfDocument::Status::Ready) {
        m_lastError = QStringLiteral("PDF 加载失败，封面回退占位");
        qWarning() << "BookImporter: PDF 封面提取失败（无法加载），保留占位封面" << pdfPath;
        return {};
    }
    QImage img = doc.render(0, QSize(300, 400));
    if (img.isNull()) {
        m_lastError = QStringLiteral("PDF 首页渲染失败，封面回退占位");
        qWarning() << "BookImporter: PDF 首页渲染失败，保留占位封面" << pdfPath;
        return {};
    }
    QDir(coverDir).mkpath(".");
    // 真实封面与 EPUB 同命名：covers/cover_<书文件路径 md5>.png
    const QString path = realCoverPath(pdfPath, coverDir);
    if (!normalizeCover(img).save(path, "PNG")) {
        m_lastError = QStringLiteral("封面保存失败，保留占位封面");
        qWarning() << "BookImporter: 封面保存失败" << path;
        return {};
    }
    return path;
}

QVector<Book> BookImporter::books() const {
    return m_books->books();
}

void BookImporter::doImport(const QUrl &url) {
    const QString file = url.toLocalFile();
    if (file.isEmpty()) {
        qWarning() << "doImport: 无法解析本地文件路径:" << url;
        emit importFailed("无法解析本地文件路径", url.toString());
        return;
    }
    const QString err = importFile(file, true);
    if (!err.isEmpty()) {
        qWarning() << "导入失败:" << err << "(" << file << ")";
        emit importFailed(err, file);
        return;
    }
    emit imported();
}
