#include "BookImporter.h"
#include "BookManager.h"
#include "SearchEngine.h"
#include "parsers/DocumentModel.h"
#include "parsers/ParserFactory.h"

#include <unzip.h>   // minizip：EPUB 封面条目读取（与 EpubParser 同源）

#include <QPdfDocument>
#include <QCryptographicHash>
#include <QCoreApplication>
#include <QDebug>
#include <QTimer>
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
#include <QJsonDocument>
#include <QJsonObject>
#include <utility>

namespace {

// 单条 zip 条目大小上限（与 EpubParser 一致，防恶意/损坏压缩包撑爆内存）
constexpr qint64 kMaxZipEntrySize = 64LL * 1024 * 1024;

// L4（P2#31）：backfill 失败标记文件（书库目录下隐藏 JSON）——
// QJsonObject{书 id 字符串: 解析失败次数}；indexBook 解析失败 +1 写回，
// 次数 ≥2 的书 backfill 跳过（避免每次启动反复解析注定失败的坏书）
QString indexFailMarkerPath(const QString &libraryDir) {
    return libraryDir + "/.readdict_index_fail.json";
}

QJsonObject readIndexFailCounts(const QString &libraryDir) {
    QFile f(indexFailMarkerPath(libraryDir));
    if (!f.open(QIODevice::ReadOnly)) return {};
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    return doc.isObject() ? doc.object() : QJsonObject{};
}

void writeIndexFailCounts(const QString &libraryDir, const QJsonObject &counts) {
    QFile f(indexFailMarkerPath(libraryDir));
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning("BookImporter: 失败标记写入失败 %s",
                 qUtf8Printable(indexFailMarkerPath(libraryDir)));
        return;
    }
    f.write(QJsonDocument(counts).toJson(QJsonDocument::Compact));
}

QByteArray readZipEntry(const QString &zipPath, const QString &entry) {
    // Windows fopen 按系统 ANSI 代码页解析窄路径，统一 toLocal8Bit（Unix 等价 UTF-8）
    unzFile zip = unzOpen64(zipPath.toLocal8Bit().constData());
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

// 自动裁掉封面四周的纯色空白边（PDF 首页渲染常见整页白边；EPUB 封面图偶有
// 装饰边框）。取样四角中位色作背景色，按 8% 容差扫描内容包围盒，四边各留 2%
// 边距；全部空白或扫描异常时返回原图。
QImage trimCoverBorder(const QImage &src) {
    QImage img = src.convertToFormat(QImage::Format_RGB32);
    const int w = img.width(), h = img.height();
    if (w < 8 || h < 8) return src;
    // 背景色取四角像素的中位分量（封面背景几乎总是四角同色）
    const QColor corners[4] = { img.pixelColor(0, 0), img.pixelColor(w - 1, 0),
                                img.pixelColor(0, h - 1), img.pixelColor(w - 1, h - 1) };
    int br = 0, bg = 0, bb = 0;
    for (const QColor &c : corners) { br += c.red(); bg += c.green(); bb += c.blue(); }
    br /= 4; bg /= 4; bb /= 4;
    const int tol = 20; // 每分量容差：抗 JPEG 噪声与渐变压缩痕
    auto isBg = [&](const QColor &c) {
        return qAbs(c.red() - br) <= tol && qAbs(c.green() - bg) <= tol
            && qAbs(c.blue() - bb) <= tol;
    };
    // 逐边扫描内容包围盒：从四边向内找第一个非背景行/列（步进 2 像素加速）
    int top = 0, bottom = h - 1, left = 0, right = w - 1;
    auto rowHasContent = [&](int y) {
        for (int x = 0; x < w; x += 2) if (!isBg(img.pixelColor(x, y))) return true;
        return false;
    };
    auto colHasContent = [&](int x) {
        for (int y = 0; y < h; y += 2) if (!isBg(img.pixelColor(x, y))) return true;
        return false;
    };
    while (top < bottom && !rowHasContent(top)) top += 2;
    while (bottom > top && !rowHasContent(bottom)) bottom -= 2;
    while (left < right && !colHasContent(left)) left += 2;
    while (right > left && !colHasContent(right)) right -= 2;
    const QRect box(left, top, right - left + 1, bottom - top + 1);
    if (box.width() < 8 || box.height() < 8 || box == img.rect()) return src;
    // 内容区四边各留 2% 边距（clamp 到图界），避免贴边裁掉标题描边
    const int mx = qMax(1, box.width() / 50), my = qMax(1, box.height() / 50);
    const QRect padded = box.adjusted(-mx, -my, mx, my).intersected(img.rect());
    return img.copy(padded);
}

// 统一封面归一化：先裁掉四周空白边，再等比放大至填满 300x400 后居中裁剪
// （书架 3:4 裁切显示，避免白边，封面顶部标题约 1% 的裁剪可接受）。
// EPUB 提取与 PDF 首页渲染共用。
QImage normalizeCover(QImage img) {
    const QSize target(300, 400);
    img = trimCoverBorder(img);
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
    : QObject(parent), m_libraryDir(libraryDir), m_dbPath(dbPath),
      m_books(new BookManager(dbPath, "readdict_importer")) {}

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

QString BookImporter::importFile(const QString &srcPath, qint64 *importedId) {
    const QString format = detectFormat(srcPath);
    if (format.isEmpty()) return "不支持的文件格式";
    QDir lib(m_libraryDir); lib.mkpath("books");
    const QString fileName = QFileInfo(srcPath).fileName();
    const QString dest = m_libraryDir + "/books/" + fileName;
    if (QFile::exists(dest)) return "同名文件已存在于书库";
    if (!QFile::copy(srcPath, dest)) return "复制文件失败";
    return registerBook(dest, format, importedId);
}

QString BookImporter::adoptFile(const QString &pathInLibrary) {
    // 同步下载落盘入口：文件已在书库目录内，不复制。去重命中（(title,author,format)
    // 或 path 与已有书相同）→ 返回空串视为成功，不重复注册。
    const QString format = detectFormat(pathInLibrary);
    if (format.isEmpty()) return "不支持的文件格式";
    if (!QFile::exists(pathInLibrary)) return "文件不存在";
    const QString title = QFileInfo(pathInLibrary).completeBaseName();
    for (const Book &b : m_books->books()) {
        if (b.path == pathInLibrary) return {};
        if (b.title == title && b.author.isEmpty() && b.format == format) return {};
    }
    return registerBook(pathInLibrary, format, nullptr);
}

QString BookImporter::registerBook(const QString &destPath, const QString &format,
                                   qint64 *importedId) {
    const QString coverDir = m_libraryDir + "/covers/";
    int pageCount = 0;
    // 任务4：注册前以最小开销解析一次元数据（EPUB 只扫 OPF、FB2 完整扫描 XML
    // 校验良构但不收 binary/正文、MOBI 只 init/load+EXTH，避免整书二次解析）。
    // 标题元数据优先、文件名兜底；解析失败（含缺 spine/畸形 OPF、FB2 尾部 XML
    // 错误）不阻断入库（标题回退文件名，作者/出版社留空不伪造）。
    const DocumentModel meta = ParserFactory::readMetadata(destPath, format);
    const QString title = meta.title.isEmpty()
        ? QFileInfo(destPath).completeBaseName() : meta.title;
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
        const QString realCover = extractEpubCover(destPath, coverDir);
        if (!realCover.isEmpty()) {
            cover = realCover;
            rollbackCover = realCover;
        } else {
            cover = generatePlaceholderCover(title, coverDir);
            if (!coverExisted) rollbackCover = cover;
        }
    } else if (format == "PDF") {
        // PDF 渲染首页为真实封面（B9）；加载/渲染失败回退占位。
        // 加载成功后回传固定页数（pageCountOut）随 addBook 落库。
        const QString realCover = extractPdfCover(destPath, coverDir, &pageCount);
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
    b.author = meta.author;
    b.publisher = meta.publisher;
    b.format = format; b.path = destPath; b.cover = cover; b.pageCount = pageCount;
    // addBook 返回 -1 表示写入失败（如 path 唯一约束冲突、FTS 索引写入失败），此时回滚文件副作用。
    const qint64 id = m_books->addBook(b);
    if (id < 0) {
        QFile::remove(destPath);
        if (!rollbackCover.isEmpty()) QFile::remove(rollbackCover);
        return "写入数据库失败";
    }
    if (importedId) *importedId = id;
    // C8：入库后立即建全文索引（同步：解析全书 + FTS5 写入；大书耗时留 D 优化——
    // 若卡顿改为 QtConcurrent 后台线程 + indexed 信号，索引结果对搜索即时可见）。
    indexBook(id);
    return {};
}

QString BookImporter::coverPathFor(const QString &title, const QString &destDir) {
    const QString hash = QCryptographicHash::hash(title.toUtf8(), QCryptographicHash::Md5).toHex().left(6);
    return destDir + "/" + hash + ".png";
}

QString BookImporter::generatePlaceholderCover(const QString &title, const QString &destDir) const {
    QDir(destDir).mkpath(".");
    const QString path = coverPathFor(title, destDir);
    // U1：去 Material 靛蓝——占位底色改 Kindle 选中 Token 近黑 #1A1A1A（UITheme
    // lightBorderActive 同值；C++ 侧无法引用 QML Token，注释锚定 Theme.qml 值源），
    // 白字在其上对比度两模式恒保证（与 BookCard 占位同风格）
    QPixmap pm(300, 400); pm.fill(QColor("#1A1A1A"));
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

QString BookImporter::extractPdfCover(const QString &pdfPath, const QString &coverDir,
                                      int *pageCountOut) {
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
    if (pageCountOut) *pageCountOut = doc.pageCount();
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

void BookImporter::indexBook(qint64 bookId) {
    // ":memory:" 下每个连接是独立数据库，索引写入无法被其它连接读到，跳过
    // （测试用内存库时也免于对 fixture 重复解析）。
    if (m_dbPath == QLatin1String(":memory:")) return;
    const Book b = m_books->bookById(bookId);
    if (b.path.isEmpty()) return;
    const DocumentModel doc = ParserFactory::parse(b.path, b.format);
    if (doc.empty()) {  // PDF 等无章节模型的书不建全文索引
        // L4（P2#31）：解析失败计数 +1 写回失败标记——≥2 次后 backfill 不再重试，
        // 避免每次启动反复解析注定失败的坏书。PDF 走 doc.empty() 但已被 backfill
        // 按格式跳过；导入路径的 registerBook 对零章书（合法空 TXT）会计入一次，
        // 阈值 2 保留一次重试余量。
        QJsonObject counts = readIndexFailCounts(m_libraryDir);
        const QString key = QString::number(bookId);
        counts.insert(key, counts.value(key).toInt() + 1);
        writeIndexFailCounts(m_libraryDir, counts);
        return;
    }
    SearchEngine se(m_dbPath);  // 独立连接名，析构自动清理
    // 原子整书重建：removeBook + 全部章节在单个事务内提交——中途失败（进程退出/
    // 某章写入失败）整体回滚，不留部分索引；isBookIndexed 仍可作完整性判据，
    // 下次启动回填会安全重试整书（无"后半章节永远搜不到"的自愈缺口）。
    QVector<QPair<QString, QStringList>> chapters;
    chapters.reserve(doc.chapters.size());
    for (const Chapter &c : doc.chapters) {
        QStringList texts;
        texts.reserve(c.paragraphs.size());
        for (const Paragraph &p : c.paragraphs)
            texts.append(p.text);
        chapters.append(qMakePair(c.title, texts));
    }
    se.rebuildBook(bookId, chapters);
}

void BookImporter::backfillMissingIndexes() {
    if (m_dbPath == QLatin1String(":memory:")) return;
    m_backfillQueue = m_books->books();
    QTimer::singleShot(0, this, [this] { backfillNext(); });
}

// 私有：从队列逐本处理。PDF（无章节模型）与已有索引的书廉价跳过（本 tick 内
// 连续出队）；遇到缺索引的书则建索引（可能耗时），完成后 singleShot(0) 调度下一
// 本，让出事件循环——UI 在书与书之间可响应。
void BookImporter::backfillNext() {
    // L4（P2#31）：失败标记计数 ≥2 的书跳过（坏书不再每次启动反复解析）
    const QJsonObject failCounts = readIndexFailCounts(m_libraryDir);
    while (!m_backfillQueue.isEmpty()) {
        const Book b = m_backfillQueue.takeFirst();
        if (b.format == QLatin1String("PDF")) continue;
        if (failCounts.value(QString::number(b.id)).toInt() >= 2) continue;
        SearchEngine se(m_dbPath);
        if (se.isBookIndexed(b.id)) continue;
        indexBook(b.id);
        QTimer::singleShot(0, this, [this] { backfillNext(); });
        return;
    }
}

void BookImporter::backfillPageCounts() {
    if (m_dbPath == QLatin1String(":memory:")) return;
    m_pageCountQueue = m_books->books();
    QTimer::singleShot(0, this, [this] { backfillPageCountsNext(); });
}

// 私有：从队列逐本补固定页数。非 PDF 与已有页数的书廉价跳过（本 tick 内连续
// 出队）；缺页数的 PDF 则加载文档取 pageCount（可能耗时），写入后 singleShot(0)
// 调度下一本，让出事件循环——UI 在书与书之间可响应。加载失败的书保持 pageCount=0，
// 下次启动回填会重试（页数读取开销小，不做失败标记）。
void BookImporter::backfillPageCountsNext() {
    while (!m_pageCountQueue.isEmpty()) {
        const Book b = m_pageCountQueue.takeFirst();
        if (b.format != QLatin1String("PDF") || b.pageCount > 0) continue;
        QPdfDocument doc;
        doc.load(b.path);
        for (int i = 0; i < 200 && doc.status() == QPdfDocument::Status::Loading; ++i)
            QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
        if (doc.status() == QPdfDocument::Status::Ready && doc.pageCount() > 0)
            m_books->setPageCount(b.id, doc.pageCount());
        QTimer::singleShot(0, this, [this] { backfillPageCountsNext(); });
        return;
    }
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
    const QString err = importFile(file);
    if (!err.isEmpty()) {
        qWarning() << "导入失败:" << err << "(" << file << ")";
        emit importFailed(err, file);
        return;
    }
    emit imported();
}

int BookImporter::refreshCovers() {
    // 刷新全部书籍封面：EPUB/PDF 重新提取真实封面（覆盖旧占位封面），
    // 成功且路径有变才 updateCover；TXT/MD/FB2/MOBI 无内嵌封面保留原封面不动。
    // 真实封面按书文件路径 md5 命名（covers/cover_<md5>.png），重提取同路径幂等。
    const QString coverDir = m_libraryDir + "/covers/";
    int updated = 0;
    const QVector<Book> books = m_books->books();
    for (const Book &b : books) {
        QString newCover;
        if (b.format == "EPUB")
            newCover = extractEpubCover(b.path, coverDir);
        else if (b.format == "PDF")
            newCover = extractPdfCover(b.path, coverDir, nullptr);
        else
            continue;
        if (newCover.isEmpty() || newCover == b.cover) continue;
        m_books->updateCover(b.id, newCover);
        ++updated;
    }
    if (updated > 0) emit coversRefreshed();
    return updated;
}
