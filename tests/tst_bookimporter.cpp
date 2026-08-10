#include <QtTest>
#include "core/BookImporter.h"
#include "core/BookManager.h"
#include "core/SearchEngine.h"

#include <QBuffer>
#include <QCryptographicHash>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QDir>
#include <QTemporaryDir>

#include <zip.h>   // minizip 写端（构造测试 EPUB）
#include <zlib.h>

// 用 minizip 把 entries（zip 内路径 → 内容）打包成 zip 文件
static bool writeZipFile(const QString &zipPath,
                         const QList<QPair<QString, QByteArray>> &entries) {
    zipFile zf = zipOpen64(zipPath.toUtf8().constData(), APPEND_STATUS_CREATE);
    if (!zf) return false;
    for (const auto &e : entries) {
        zip_fileinfo zi = {};
        if (zipOpenNewFileInZip(zf, e.first.toUtf8().constData(), &zi,
                                nullptr, 0, nullptr, 0, nullptr,
                                Z_DEFLATED, Z_DEFAULT_COMPRESSION) != ZIP_OK) {
            zipClose(zf, nullptr);
            return false;
        }
        if (zipWriteInFileInZip(zf, e.second.constData(),
                                static_cast<unsigned>(e.second.size())) != ZIP_OK) {
            zipClose(zf, nullptr);
            return false;
        }
        zipCloseFileInZip(zf);
    }
    return zipClose(zf, nullptr) == ZIP_OK;
}

// 生成一张纯色 PNG（850x1214，模拟常见 EPUB 封面比例）：纯色保证缩放/裁剪后
// 任意像素颜色不变，可用中心像素判别封面来源。
static QByteArray makeCoverPng(const QColor &color) {
    QImage img(850, 1214, QImage::Format_RGB32);
    img.fill(color);
    QByteArray out;
    QBuffer buf(&out);
    buf.open(QIODevice::WriteOnly);
    img.save(&buf, "PNG");
    return out;
}

// 构造带封面的最小 EPUB：OPF 声明指向图 A（红色），正文首图为图 B（绿色），
// 两图不同——用于锁定「OPF cover 声明优先于解析首图」的提取顺序。
static QString makeCoverEpub(const QString &path) {
    const QString container =
        QStringLiteral("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                       "<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">"
                       "<rootfiles><rootfile full-path=\"OEBPS/content.opf\" "
                       "media-type=\"application/oebps-package+xml\"/></rootfiles></container>");
    const QString opf =
        QStringLiteral("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                       "<package xmlns=\"http://www.idpf.org/2007/opf\" unique-identifier=\"id\" version=\"2.0\">"
                       "<metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">"
                       "<dc:title>封面测试书</dc:title><dc:creator>测试作者</dc:creator>"
                       "<dc:publisher>测试出版社</dc:publisher>"
                       "<meta name=\"cover\" content=\"cover-img\"/>"
                       "</metadata>"
                       "<manifest>"
                       "<item href=\"Text/cover.xhtml\" id=\"cover.xhtml\" media-type=\"application/xhtml+xml\"/>"
                       "<item href=\"Images/coverA.png\" id=\"cover-img\" media-type=\"image/png\"/>"
                       "<item href=\"Images/coverB.png\" id=\"imgB\" media-type=\"image/png\"/>"
                       "</manifest>"
                       "<spine toc=\"ncx\"><itemref idref=\"cover.xhtml\"/></spine>"
                       "</package>");
    const QString coverXhtml =
        QStringLiteral("<?xml version=\"1.0\" encoding=\"utf-8\"?>"
                       "<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>Cover</title></head>"
                       "<body><p style=\"text-align:center\"><img src=\"../Images/coverB.png\"/></p></body></html>");
    const QList<QPair<QString, QByteArray>> entries = {
        {QStringLiteral("META-INF/container.xml"), container.toUtf8()},
        {QStringLiteral("OEBPS/content.opf"), opf.toUtf8()},
        {QStringLiteral("OEBPS/Text/cover.xhtml"), coverXhtml.toUtf8()},
        {QStringLiteral("OEBPS/Images/coverA.png"), makeCoverPng(QColor("#E00000"))},
        {QStringLiteral("OEBPS/Images/coverB.png"), makeCoverPng(QColor("#00C000"))},
    };
    return writeZipFile(path, entries) ? path : QString();
}

// 无 OPF 封面声明的 EPUB：两章各含一张不同图（红/绿），manifest 不含图片条目
// （锁定「解析首图」回退路径，排除 manifest 兜底干扰）。
static QString makeNoCoverMetaEpub(const QString &path) {
    const QString container =
        QStringLiteral("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                       "<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">"
                       "<rootfiles><rootfile full-path=\"OEBPS/content.opf\" "
                       "media-type=\"application/oebps-package+xml\"/></rootfiles></container>");
    const QString opf =
        QStringLiteral("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                       "<package xmlns=\"http://www.idpf.org/2007/opf\" unique-identifier=\"id\" version=\"2.0\">"
                       "<metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">"
                       "<dc:title>无封面声明书</dc:title>"
                       "</metadata>"
                       "<manifest>"
                       "<item href=\"Text/ch1.xhtml\" id=\"ch1\" media-type=\"application/xhtml+xml\"/>"
                       "<item href=\"Text/ch2.xhtml\" id=\"ch2\" media-type=\"application/xhtml+xml\"/>"
                       "</manifest>"
                       "<spine toc=\"ncx\"><itemref idref=\"ch1\"/><itemref idref=\"ch2\"/></spine>"
                       "</package>");
    const QString ch1 =
        QStringLiteral("<?xml version=\"1.0\" encoding=\"utf-8\"?>"
                       "<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>Ch1</title></head>"
                       "<body><p><img src=\"../Images/img1.png\"/></p><p>第一章文本。</p></body></html>");
    const QString ch2 =
        QStringLiteral("<?xml version=\"1.0\" encoding=\"utf-8\"?>"
                       "<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>Ch2</title></head>"
                       "<body><p><img src=\"../Images/img2.png\"/></p><p>第二章文本。</p></body></html>");
    const QList<QPair<QString, QByteArray>> entries = {
        {QStringLiteral("META-INF/container.xml"), container.toUtf8()},
        {QStringLiteral("OEBPS/content.opf"), opf.toUtf8()},
        {QStringLiteral("OEBPS/Text/ch1.xhtml"), ch1.toUtf8()},
        {QStringLiteral("OEBPS/Text/ch2.xhtml"), ch2.toUtf8()},
        {QStringLiteral("OEBPS/Images/img1.png"), makeCoverPng(QColor("#E00000"))},
        {QStringLiteral("OEBPS/Images/img2.png"), makeCoverPng(QColor("#00C000"))},
    };
    return writeZipFile(path, entries) ? path : QString();
}

// EPUB3 风格封面声明：<meta property="cover-image" content="Images/coverB.png">
// content 为相对 IRI 而非 manifest item id；manifest 文档序首个图片条目是另一张
// 图（红 imgA）——断言最终封面为 IRI 命中的绿图，锁定 resolveZipEntry 兜底分支。
static QString makeIriCoverEpub(const QString &path) {
    const QString container =
        QStringLiteral("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                       "<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">"
                       "<rootfiles><rootfile full-path=\"OEBPS/content.opf\" "
                       "media-type=\"application/oebps-package+xml\"/></rootfiles></container>");
    const QString opf =
        QStringLiteral("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                       "<package xmlns=\"http://www.idpf.org/2007/opf\" unique-identifier=\"id\" version=\"2.0\">"
                       "<metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">"
                       "<dc:title>IRI封面书</dc:title>"
                       "<meta property=\"cover-image\" content=\"Images/coverB.png\"/>"
                       "</metadata>"
                       "<manifest>"
                       "<item href=\"Text/cover.xhtml\" id=\"cover.xhtml\" media-type=\"application/xhtml+xml\"/>"
                       "<item href=\"Images/imgA.png\" id=\"imgA\" media-type=\"image/png\"/>"
                       "<item href=\"Images/coverB.png\" id=\"imgB\" media-type=\"image/png\"/>"
                       "</manifest>"
                       "<spine toc=\"ncx\"><itemref idref=\"cover.xhtml\"/></spine>"
                       "</package>");
    const QString coverXhtml =
        QStringLiteral("<?xml version=\"1.0\" encoding=\"utf-8\"?>"
                       "<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>Cover</title></head>"
                       "<body><p><img src=\"../Images/imgA.png\"/></p></body></html>");
    const QList<QPair<QString, QByteArray>> entries = {
        {QStringLiteral("META-INF/container.xml"), container.toUtf8()},
        {QStringLiteral("OEBPS/content.opf"), opf.toUtf8()},
        {QStringLiteral("OEBPS/Text/cover.xhtml"), coverXhtml.toUtf8()},
        {QStringLiteral("OEBPS/Images/imgA.png"), makeCoverPng(QColor("#E00000"))},
        {QStringLiteral("OEBPS/Images/coverB.png"), makeCoverPng(QColor("#00C000"))},
    };
    return writeZipFile(path, entries) ? path : QString();
}

// 任务4 复审：有效容器 + OPF 有元数据但缺 spine 的 EPUB（元数据可读但整书无效）
static QString makeNoSpineEpub(const QString &path) {
    const QString container =
        QStringLiteral("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                       "<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">"
                       "<rootfiles><rootfile full-path=\"OEBPS/content.opf\" "
                       "media-type=\"application/oebps-package+xml\"/></rootfiles></container>");
    const QString opf =
        QStringLiteral("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                       "<package xmlns=\"http://www.idpf.org/2007/opf\" unique-identifier=\"id\" version=\"2.0\">"
                       "<metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">"
                       "<dc:title>缺spine书</dc:title><dc:creator>作者乙</dc:creator>"
                       "<dc:publisher>出版社乙</dc:publisher>"
                       "</metadata>"
                       "<manifest>"
                       "<item href=\"Text/ch1.xhtml\" id=\"ch1\" media-type=\"application/xhtml+xml\"/>"
                       "</manifest>"
                       "</package>");
    const QList<QPair<QString, QByteArray>> entries = {
        {QStringLiteral("META-INF/container.xml"), container.toUtf8()},
        {QStringLiteral("OEBPS/content.opf"), opf.toUtf8()},
    };
    return writeZipFile(path, entries) ? path : QString();
}

// 任务4 复审：有效容器 + OPF 元数据后有 XML 良构错误的 EPUB（<itemref> 未闭合
// 即遇 </spine>）；含 ch1.xhtml，确保错误前收集到的 spine 引用足以"看似可解析"。
static QString makeBadOpfEpub(const QString &path) {
    const QString container =
        QStringLiteral("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                       "<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">"
                       "<rootfiles><rootfile full-path=\"OEBPS/content.opf\" "
                       "media-type=\"application/oebps-package+xml\"/></rootfiles></container>");
    const QString opf =
        QStringLiteral("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                       "<package xmlns=\"http://www.idpf.org/2007/opf\" unique-identifier=\"id\" version=\"2.0\">"
                       "<metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">"
                       "<dc:title>坏书</dc:title><dc:creator>坏作者</dc:creator>"
                       "<dc:publisher>坏出版社</dc:publisher>"
                       "</metadata>"
                       "<manifest>"
                       "<item href=\"Text/ch1.xhtml\" id=\"ch1\" media-type=\"application/xhtml+xml\"/>"
                       "</manifest>"
                       "<spine><itemref idref=\"ch1\"></spine>"
                       "</package>");
    const QString ch1 =
        QStringLiteral("<?xml version=\"1.0\" encoding=\"utf-8\"?>"
                       "<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>Ch1</title></head>"
                       "<body><p>第一章文本。</p></body></html>");
    const QList<QPair<QString, QByteArray>> entries = {
        {QStringLiteral("META-INF/container.xml"), container.toUtf8()},
        {QStringLiteral("OEBPS/content.opf"), opf.toUtf8()},
        {QStringLiteral("OEBPS/Text/ch1.xhtml"), ch1.toUtf8()},
    };
    return writeZipFile(path, entries) ? path : QString();
}

// 任务4 复审：description 良构但其后正文 XML 错配的 FB2
static QString makeBadTrailingFb2(const QString &path) {
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly)) return QString();
    f.write("<?xml version=\"1.0\"?><FictionBook><description><title-info>"
            "<book-title>坏书</book-title><author><first-name>坏</first-name>"
            "<last-name>作者</last-name></author></title-info></description>"
            "<body><section><p>未闭合</section></body></FictionBook>");
    f.close();
    return path;
}

class TestImporter : public QObject {
    Q_OBJECT
private slots:
    void detectsFormats() {
        QCOMPARE(BookImporter::detectFormat("a.epub"), QString("EPUB"));
        QCOMPARE(BookImporter::detectFormat("b.PDF"), QString("PDF"));
        QCOMPARE(BookImporter::detectFormat("c.mobi"), QString("MOBI"));
        QCOMPARE(BookImporter::detectFormat("d.azw3"), QString("AZW3"));
        QCOMPARE(BookImporter::detectFormat("e.txt"), QString("TXT"));
        QCOMPARE(BookImporter::detectFormat("f.md"), QString("MD"));
        QCOMPARE(BookImporter::detectFormat("g.fb2"), QString("FB2"));
        QCOMPARE(BookImporter::detectFormat("h.xyz"), QString());
    }
    void importsCopyIntoLibrary() {
        QTemporaryDir libDir;
        QTemporaryDir srcDir;
        QFile src(srcDir.path() + "/book.txt");
        QVERIFY(src.open(QIODevice::WriteOnly)); src.write("hello world"); src.close();
        BookImporter imp(libDir.path(), ":memory:");
        const QString err = imp.importFile(src.fileName());
        QVERIFY(err.isEmpty());
        QVERIFY(QFile::exists(src.fileName())); // 复制语义：源文件保留
        QVERIFY(QFile::exists(libDir.path() + "/books/book.txt"));
        QCOMPARE(imp.books().size(), 1);
    }
    void txtImportKeepsPlaceholderCover() {
        QTemporaryDir libDir;
        QTemporaryDir srcDir;
        QFile src(srcDir.path() + "/书.txt");
        QVERIFY(src.open(QIODevice::WriteOnly)); src.write("正文"); src.close();
        BookImporter imp(libDir.path(), ":memory:");
        QVERIFY(imp.importFile(src.fileName()).isEmpty());
        const QString cover = imp.books()[0].cover;
        QVERIFY(QFile::exists(cover));
        // 占位封面命名：MD5(标题) 前 6 位 + .png（非真实封面的 cover_<md5>.png）
        const QString placeholder = QString::fromLatin1(
            QCryptographicHash::hash(QStringLiteral("书").toUtf8(), QCryptographicHash::Md5)
                .toHex().left(6)) + ".png";
        QCOMPARE(QFileInfo(cover).fileName(), placeholder);
        QImage img(cover);
        QVERIFY(!img.isNull());
        QCOMPARE(img.size(), QSize(300, 400));
    }
    void epubImportExtractsRealCover() {
        QTemporaryDir libDir;
        QTemporaryDir srcDir;
        const QString epubPath = makeCoverEpub(srcDir.path() + "/coverbook.epub");
        QVERIFY(!epubPath.isEmpty());
        BookImporter imp(libDir.path(), ":memory:");
        const QString err = imp.importFile(epubPath);
        QVERIFY(err.isEmpty());
        QCOMPARE(imp.books().size(), 1);
        const QString cover = imp.books()[0].cover;
        const QFileInfo coverFi(cover);
        QVERIFY(coverFi.exists());
        // 真实封面：covers/cover_<md5>.png（不同于占位的 <hash6>.png）
        QVERIFY(coverFi.fileName().startsWith(QStringLiteral("cover_")));
        QVERIFY(coverFi.fileName().endsWith(QStringLiteral(".png")));
        QVERIFY(cover.startsWith(libDir.path() + "/covers/"));
        const QString placeholder = QString::fromLatin1(
            QCryptographicHash::hash(QStringLiteral("coverbook").toUtf8(), QCryptographicHash::Md5)
                .toHex().left(6)) + ".png";
        QVERIFY(coverFi.fileName() != placeholder);
        // 封面可加载且统一缩放到 300x400
        QImage img(cover);
        QVERIFY(!img.isNull());
        QCOMPARE(img.size(), QSize(300, 400));
        // OPF cover 声明优先：fixture 的 OPF 指向图 A（红），正文首图为图 B（绿），
        // 缩放裁剪后整体仍为纯色，取中心像素即可判别来源
        QCOMPARE(img.pixelColor(150, 200), QColor("#E00000"));
        QVERIFY(img.pixelColor(150, 200) != QColor("#00C000"));
    }
    void epubParseFailureKeepsPlaceholder() {
        QTemporaryDir libDir;
        QTemporaryDir srcDir;
        QFile bad(srcDir.path() + "/bad.epub");
        QVERIFY(bad.open(QIODevice::WriteOnly));
        bad.write("this is not a zip file at all"); bad.close();
        BookImporter imp(libDir.path(), ":memory:");
        const QString err = imp.importFile(bad.fileName());
        QVERIFY(err.isEmpty()); // 解析失败不影响入库
        QCOMPARE(imp.books().size(), 1);
        // 解析失败：标题回退文件名，作者/出版社保持空（不伪造）
        QCOMPARE(imp.books()[0].title, QStringLiteral("bad"));
        QCOMPARE(imp.books()[0].author, QString());
        QCOMPARE(imp.books()[0].publisher, QString());
        const QString cover = imp.books()[0].cover;
        QVERIFY(QFile::exists(cover));
        QVERIFY(!QFileInfo(cover).fileName().startsWith(QStringLiteral("cover_"))); // 仍是占位
        QVERIFY(!imp.lastError().isEmpty()); // 失败原因记入 lastError
    }
    // 任务4：EPUB 导入写出 OPF 元数据（标题/作者/出版社），元数据优先于文件名；
    // 并用独立 BookManager 连接回读——publisher 确实持久化到 books 表。
    void epubImportWritesAuthorAndPublisher() {
        QTemporaryDir libDir;
        QTemporaryDir srcDir;
        const QString epubPath = makeCoverEpub(srcDir.path() + "/coverbook.epub");
        QVERIFY(!epubPath.isEmpty());
        const QString dbPath = libDir.path() + "/lib.db";
        BookImporter imp(libDir.path(), dbPath);
        QVERIFY(imp.importFile(epubPath).isEmpty());
        QCOMPARE(imp.books().size(), 1);
        // 元数据优先：OPF dc:title 覆盖文件名 coverbook
        const Book imported = imp.books()[0];
        QCOMPARE(imported.title, QStringLiteral("封面测试书"));
        QCOMPARE(imported.author, QStringLiteral("测试作者"));
        QCOMPARE(imported.publisher, QStringLiteral("测试出版社"));
        // 数据库持久化：独立连接按 id 回读同一行
        BookManager mgr(dbPath, "readdict_meta_test");
        const Book b = mgr.bookById(imported.id);
        QCOMPARE(b.title, QStringLiteral("封面测试书"));
        QCOMPARE(b.author, QStringLiteral("测试作者"));
        QCOMPARE(b.publisher, QStringLiteral("测试出版社"));
    }
    // 任务4：元数据缺失时不伪造——TXT 无元数据（标题=文件名，作者/出版社空）；
    // 无作者/出版社声明的 EPUB 仅标题来自 OPF，其余字段保持空。
    void metadataMissingKeepsFieldsEmpty() {
        QTemporaryDir libDir;
        QTemporaryDir srcDir;
        // TXT：无元数据来源，标题=文件名
        QFile txt(srcDir.path() + "/无作者书.txt");
        QVERIFY(txt.open(QIODevice::WriteOnly)); txt.write("正文"); txt.close();
        BookImporter imp(libDir.path(), ":memory:");
        QVERIFY(imp.importFile(txt.fileName()).isEmpty());
        QCOMPARE(imp.books()[0].title, QStringLiteral("无作者书"));
        QCOMPARE(imp.books()[0].author, QString());
        QCOMPARE(imp.books()[0].publisher, QString());
        // EPUB 只有 dc:title（无 creator/publisher）：标题进库，其余为空
        const QString epubPath = makeNoCoverMetaEpub(srcDir.path() + "/nometa.epub");
        QVERIFY(!epubPath.isEmpty());
        QVERIFY(imp.importFile(epubPath).isEmpty());
        QCOMPARE(imp.books().size(), 2);
        // books() 按 added_at DESC 排序：EPUB 为最新导入，按格式定位不依赖顺序
        // （局部向量保证指针生命周期覆盖断言，避免悬垂）
        const QVector<Book> all = imp.books();
        const Book *epub = nullptr;
        for (const Book &b : all)
            if (b.format == QLatin1String("EPUB")) { epub = &b; break; }
        QVERIFY(epub);
        QCOMPARE(epub->title, QStringLiteral("无封面声明书"));
        QCOMPARE(epub->author, QString());
        QCOMPARE(epub->publisher, QString());
    }
    // 任务4 复审：畸形 OPF（缺 spine / XML 良构错误）仍允许入库，但元数据视为
    // 缺失——标题回退文件名、作者/出版社为空（不阻断、不伪造）。
    void malformedEpubImportsWithFallbackTitle() {
        QTemporaryDir libDir;
        QTemporaryDir srcDir;
        BookImporter imp(libDir.path(), ":memory:");
        // 缺 spine：OPF 有 dc:title/creator/publisher，但整书无效
        const QString noSpine = makeNoSpineEpub(srcDir.path() + "/nospine.epub");
        QVERIFY(!noSpine.isEmpty());
        QVERIFY(imp.importFile(noSpine).isEmpty());
        QCOMPARE(imp.books().size(), 1);
        QCOMPARE(imp.books()[0].title, QStringLiteral("nospine"));
        QCOMPARE(imp.books()[0].author, QString());
        QCOMPARE(imp.books()[0].publisher, QString());
        // OPF XML 良构错误：同样回退文件名
        const QString badOpf = makeBadOpfEpub(srcDir.path() + "/badopf.epub");
        QVERIFY(!badOpf.isEmpty());
        QVERIFY(imp.importFile(badOpf).isEmpty());
        QCOMPARE(imp.books().size(), 2);
        const QVector<Book> all = imp.books();
        const Book *epub = nullptr;
        for (const Book &b : all)
            if (b.format == QLatin1String("EPUB") && b.title == QStringLiteral("badopf"))
                { epub = &b; break; }
        QVERIFY(epub);
        QCOMPARE(epub->title, QStringLiteral("badopf"));
        QCOMPARE(epub->author, QString());
        QCOMPARE(epub->publisher, QString());
    }
    // 任务4 复审：description 后正文 XML 错配的 FB2——readMetadataOnly 必须判失败，
    // 入库时标题回退文件名、作者/出版社为空。
    void malformedFb2ImportsWithFallbackTitle() {
        QTemporaryDir libDir;
        QTemporaryDir srcDir;
        const QString bad = makeBadTrailingFb2(srcDir.path() + "/bad.fb2");
        QVERIFY(!bad.isEmpty());
        BookImporter imp(libDir.path(), ":memory:");
        QVERIFY(imp.importFile(bad).isEmpty());
        QCOMPARE(imp.books().size(), 1);
        QCOMPARE(imp.books()[0].title, QStringLiteral("bad"));
        QCOMPARE(imp.books()[0].author, QString());
        QCOMPARE(imp.books()[0].publisher, QString());
    }
    void epubFirstImageFallback() {
        // 无 OPF 封面声明：回退「解析首图」，须取第一章首图（红），
        // 不得被后续章节图片覆盖（锁定嵌套循环 break 修复）
        QTemporaryDir libDir;
        QTemporaryDir srcDir;
        const QString epubPath = makeNoCoverMetaEpub(srcDir.path() + "/twoc.epub");
        QVERIFY(!epubPath.isEmpty());
        BookImporter imp(libDir.path(), ":memory:");
        QVERIFY(imp.importFile(epubPath).isEmpty());
        const QString cover = imp.books()[0].cover;
        QVERIFY(QFileInfo(cover).fileName().startsWith(QStringLiteral("cover_")));
        QImage img(cover);
        QVERIFY(!img.isNull());
        QCOMPARE(img.size(), QSize(300, 400));
        QCOMPARE(img.pixelColor(150, 200), QColor("#E00000")); // 第一章图（红）
        QVERIFY(img.pixelColor(150, 200) != QColor("#00C000")); // 非第二章图（绿）
    }
    void epubIriCoverExtraction() {
        // EPUB3 <meta property="cover-image" content="相对IRI">：content 非 item id，
        // 直接相对 OPF 目录解析命中（绿图），而非 manifest 文档序首图（红图）
        QTemporaryDir libDir;
        QTemporaryDir srcDir;
        const QString epubPath = makeIriCoverEpub(srcDir.path() + "/iri.epub");
        QVERIFY(!epubPath.isEmpty());
        BookImporter imp(libDir.path(), ":memory:");
        QVERIFY(imp.importFile(epubPath).isEmpty());
        const QString cover = imp.books()[0].cover;
        QVERIFY(QFileInfo(cover).fileName().startsWith(QStringLiteral("cover_")));
        QImage img(cover);
        QVERIFY(!img.isNull());
        QCOMPARE(img.pixelColor(150, 200), QColor("#00C000")); // IRI 命中的绿图
        QVERIFY(img.pixelColor(150, 200) != QColor("#E00000")); // 非 manifest 首图（红）
    }
    // C8：导入后同步建全文索引——同一 db 文件的 SearchEngine 应能搜到书内内容。
    // TXT 路径（fixture 级真实文件导入）；文件库（":memory:" 各连接独立，索引不可共享）。
    void importIndexesFulltext() {
        QTemporaryDir libDir;
        QTemporaryDir srcDir;
        QFile src(srcDir.path() + "/魔女书.txt");
        QVERIFY(src.open(QIODevice::WriteOnly));
        src.write("第一章正文，魔女在森林中现身。\n");
        src.close();
        const QString dbPath = libDir.path() + "/lib.db";
        BookImporter imp(libDir.path(), dbPath);
        qint64 id = -1;
        const QString err = imp.importFile(src.fileName(), &id);
        QVERIFY(err.isEmpty());
        QVERIFY(id > 0);
        SearchEngine se(dbPath);
        const auto hits = se.search(id, "魔女");
        QCOMPARE(hits.size(), 1);
        QCOMPARE(hits[0].chapterIndex, 0);
        QCOMPARE(hits[0].paragraphIndex, 0);
        QVERIFY(hits[0].snippet.contains("魔女"));
        QCOMPARE(se.searchAll("魔女").size(), 1);
    }

    // C8 复审：存量书索引回填——功能上线前已入库的书（books 表有、fts_content 无行）
    // 经 backfillMissingIndexes 逐本补建索引，回填后即可全文搜索。
    // 书直接经 BookManager 入库（模拟非导入路径的历史书），不触发 importFile 的索引。
    void backfillIndexesExistingBooks() {
        QTemporaryDir libDir;
        const QString dbPath = libDir.path() + "/lib.db";
        QDir(libDir.path()).mkpath("books");
        const QString bookPath = libDir.path() + "/books/old.txt";
        QFile f(bookPath);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("旧书正文，魔女与贤者。\n");
        f.close();
        BookManager mgr(dbPath, "readdict_backfill_test");
        const qint64 id = mgr.addBook(Book{-1, "旧书", "作者", "社", "类",
                                           "TXT", bookPath, QString(), 0.0});
        QVERIFY(id > 0);
        // 回填前：该书无索引行
        {
            SearchEngine se(dbPath);
            QVERIFY(!se.isBookIndexed(id));
            QVERIFY(se.searchAll("魔女").isEmpty());
        }
        BookImporter imp(libDir.path(), dbPath);
        imp.backfillMissingIndexes();  // 异步逐本：QTRY 驱动事件循环使 singleShot 生效
        SearchEngine se(dbPath);
        QTRY_VERIFY_WITH_TIMEOUT(!se.search(id, "魔女").isEmpty(), 5000);
        QCOMPARE(se.search(id, "魔女")[0].paragraphIndex, 0);
    }

    // B2：refreshCovers 存量书封面刷新——导入带封面 EPUB（真实封面 cover_*.png）
    // → 把 cover 字段改回占位（模拟早期导入落库的占位封面）→ refreshCovers()
    // 应重提真实封面：返回 ≥1、cover 变回 cover_*.png 且文件存在、可加载 300x400。
    // 用文件 db（":memory:" 各连接独立，外部 BookManager 改不动 importer 的库）。
    void refreshCoversRestoresRealCover() {
        QTemporaryDir libDir;
        QTemporaryDir srcDir;
        const QString epubPath = makeCoverEpub(srcDir.path() + "/rc.epub");
        QVERIFY(!epubPath.isEmpty());
        const QString dbPath = libDir.path() + "/lib.db";
        BookImporter imp(libDir.path(), dbPath);
        QVERIFY(imp.importFile(epubPath).isEmpty());
        QCOMPARE(imp.books().size(), 1);
        const QString realCover = imp.books()[0].cover;
        QVERIFY(QFileInfo(realCover).fileName().startsWith(QStringLiteral("cover_")));
        // 模拟早期导入：独立连接把 cover 改回占位（空串即无封面，卡片显示占位）
        BookManager mgr(dbPath, "readdict_refresh_test");
        const qint64 id = imp.books()[0].id;
        mgr.updateCover(id, QString());
        QVERIFY(imp.books()[0].cover.isEmpty());
        const int updated = imp.refreshCovers();
        QVERIFY(updated >= 1);
        const QString cover = imp.books()[0].cover;
        const QFileInfo fi(cover);
        QVERIFY(fi.fileName().startsWith(QStringLiteral("cover_")));
        QVERIFY(fi.fileName().endsWith(QStringLiteral(".png")));
        QVERIFY(QFile::exists(cover));
        QImage img(cover);
        QVERIFY(!img.isNull());
        QCOMPARE(img.size(), QSize(300, 400));
    }
    // B2：幂等性——已持有真实封面时 refreshCovers 重提取同路径（按书文件 md5 命名），
    // newCover == b.cover 跳过 updateCover，返回 0、封面文件不动。
    void refreshCoversIdempotent() {
        QTemporaryDir libDir;
        QTemporaryDir srcDir;
        const QString epubPath = makeCoverEpub(srcDir.path() + "/idem.epub");
        QVERIFY(!epubPath.isEmpty());
        BookImporter imp(libDir.path(), ":memory:");
        QVERIFY(imp.importFile(epubPath).isEmpty());
        const QString cover = imp.books()[0].cover;
        QVERIFY(QFileInfo(cover).fileName().startsWith(QStringLiteral("cover_")));
        QCOMPARE(imp.refreshCovers(), 0);
        QCOMPARE(imp.books()[0].cover, cover);
    }
    // B2：非 EPUB/PDF 不刷新——TXT（占位封面）与无法加载的 PDF（提取失败回退占位）
    // 都不该被 refreshCovers 改动：返回 0、cover 原样保留。
    void refreshCoversSkipsNonEpubPdf() {
        QTemporaryDir libDir;
        QTemporaryDir srcDir;
        QFile txt(srcDir.path() + "/无封面书.txt");
        QVERIFY(txt.open(QIODevice::WriteOnly)); txt.write("正文"); txt.close();
        QFile badPdf(srcDir.path() + "/fake.pdf");
        QVERIFY(badPdf.open(QIODevice::WriteOnly)); badPdf.write("not a pdf"); badPdf.close();
        BookImporter imp(libDir.path(), ":memory:");
        QVERIFY(imp.importFile(txt.fileName()).isEmpty());
        QVERIFY(imp.importFile(badPdf.fileName()).isEmpty());
        QCOMPARE(imp.books().size(), 2);
        const QString txtCover = imp.books()[0].cover;
        const QString pdfCover = imp.books()[1].cover;
        QCOMPARE(imp.refreshCovers(), 0);
        QCOMPARE(imp.books()[0].cover, txtCover);
        QCOMPARE(imp.books()[1].cover, pdfCover);
    }

    // C8：真实 EPUB 验证——导入 Re从零… 后，从正文提取实际出现的词断言命中
    void realEpubFulltext() {
        const QString real = qEnvironmentVariable("READDICT_REAL_EPUB");
        if (real.isEmpty() || !QFile::exists(real))
            QSKIP("未设置 READDICT_REAL_EPUB，跳过真实书全文搜索验证");
        QTemporaryDir libDir;
        const QString dbPath = libDir.path() + "/lib.db";
        BookImporter imp(libDir.path(), dbPath);
        qint64 id = -1;
        QVERIFY(imp.importFile(real, &id).isEmpty());
        QVERIFY(id > 0);
        SearchEngine se(dbPath);
        // 从书内容提取真实词：加载首章文本，取第一个 ≥4 字的 CJK 片段。
        // 拆字 AND 保证该片段四个字都在原文 → 必命中，断言无歧义。
        BookManager mgr(dbPath, "readdict_fts_real");
        const QVariant ch = mgr.loadChapter(id, 0);
        const QVariantList paras = ch.toMap().value("paragraphs").toList();
        // 从单个段落的文本提取 ≥4 字的纯字母 CJK 片段（拼接多段会让片段跨段
        // 边界、标点字符拆字后为空 token 破坏 MATCH——提取与索引粒度必须一致）。
        QString term;
        for (const auto &p : paras) {
            const QString t = p.toMap().value("text").toString();
            for (int i = 0; i + 4 <= t.size(); ++i) {
                bool cjk = true;
                for (int k = 0; k < 4; ++k) {
                    const QChar ch = t.at(i + k);
                    if (ch.unicode() < 0x2E80 || !ch.isLetter()) { cjk = false; break; }
                }
                if (cjk) { term = t.mid(i, 4); break; }
            }
            if (!term.isEmpty()) break;
        }
        QVERIFY(!term.isEmpty());
        const auto hits = se.search(id, term);
        QVERIFY(!hits.isEmpty());
        for (const auto &h : hits)
            QCOMPARE(h.bookId, id);
    }

    // 真实书验证：设置环境变量 READDICT_REAL_EPUB=<epub 路径> 时执行
    // （本机真实书文件，CI 环境未设置则跳过）
    void realEpubCover() {
        const QString real = qEnvironmentVariable("READDICT_REAL_EPUB");
        if (real.isEmpty() || !QFile::exists(real))
            QSKIP("未设置 READDICT_REAL_EPUB，跳过真实书封面验证");
        QTemporaryDir libDir;
        BookImporter imp(libDir.path(), ":memory:");
        const QString err = imp.importFile(real);
        QVERIFY(err.isEmpty());
        QCOMPARE(imp.books().size(), 1);
        const QString cover = imp.books()[0].cover;
        QVERIFY(QFileInfo(cover).fileName().startsWith(QStringLiteral("cover_")));
        QVERIFY(QFile::exists(cover));
        QImage img(cover);
        QVERIFY(!img.isNull());
        QCOMPARE(img.size(), QSize(300, 400));
    }
    // 真实 PDF 验证：设置环境变量 READDICT_REAL_PDF=<pdf 路径> 时执行；
    // 断言封面为首页缩略图（covers/cover_<md5>.png，300x400，非占位命名）
    void realPdfCover() {
        const QString real = qEnvironmentVariable("READDICT_REAL_PDF");
        if (real.isEmpty() || !QFile::exists(real))
            QSKIP("未设置 READDICT_REAL_PDF，跳过真实 PDF 封面验证");
        QTemporaryDir libDir;
        BookImporter imp(libDir.path(), ":memory:");
        const QString err = imp.importFile(real);
        QVERIFY(err.isEmpty());
        QCOMPARE(imp.books().size(), 1);
        const QString cover = imp.books()[0].cover;
        QVERIFY(QFileInfo(cover).fileName().startsWith(QStringLiteral("cover_")));
        QVERIFY(QFile::exists(cover));
        QImage img(cover);
        QVERIFY(!img.isNull());
        QCOMPARE(img.size(), QSize(300, 400));
        QVERIFY(imp.lastError().isEmpty()); // 真实封面成功，不得记入占位回退原因
    }
    // L3（P0#3）：同步下载落盘注册——文件已在书库目录内，adoptFile 跳过复制直接注册
    void adoptFileRegistersWithoutCopy() {
        // 已在书库目录内的文件（模拟同步下载落盘）→ adoptFile 直接注册不复制
        QTemporaryDir dir;
        QDir().mkpath(dir.path() + "/books");
        const QString src = QStringLiteral(EPUB_FIXTURES_DIR) + "/sample.epub";
        const QString dest = dir.path() + "/books/sample.epub";
        QVERIFY(QFile::copy(src, dest));
        BookImporter imp(dir.path(), dir.path() + "/Readdict.db");
        const QString err = imp.adoptFile(dest);
        QVERIFY2(err.isEmpty(), qPrintable(err));
        bool found = false;
        for (const Book &b : imp.books())
            if (b.path == dest) found = true;
        QVERIFY(found); // 注册且 path 指向原文件（无二次复制）
    }
};
QTEST_MAIN(TestImporter)
#include "tst_bookimporter.moc"
