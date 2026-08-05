#include <QtTest>
#include "core/BookImporter.h"

#include <QBuffer>
#include <QCryptographicHash>
#include <QFile>
#include <QFileInfo>
#include <QImage>
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
        const QString err = imp.importFile(src.fileName(), true);
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
        QVERIFY(imp.importFile(src.fileName(), true).isEmpty());
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
        const QString err = imp.importFile(epubPath, true);
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
        const QString err = imp.importFile(bad.fileName(), true);
        QVERIFY(err.isEmpty()); // 解析失败不影响入库
        QCOMPARE(imp.books().size(), 1);
        const QString cover = imp.books()[0].cover;
        QVERIFY(QFile::exists(cover));
        QVERIFY(!QFileInfo(cover).fileName().startsWith(QStringLiteral("cover_"))); // 仍是占位
        QVERIFY(!imp.lastError().isEmpty()); // 失败原因记入 lastError
    }
    void epubFirstImageFallback() {
        // 无 OPF 封面声明：回退「解析首图」，须取第一章首图（红），
        // 不得被后续章节图片覆盖（锁定嵌套循环 break 修复）
        QTemporaryDir libDir;
        QTemporaryDir srcDir;
        const QString epubPath = makeNoCoverMetaEpub(srcDir.path() + "/twoc.epub");
        QVERIFY(!epubPath.isEmpty());
        BookImporter imp(libDir.path(), ":memory:");
        QVERIFY(imp.importFile(epubPath, true).isEmpty());
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
        QVERIFY(imp.importFile(epubPath, true).isEmpty());
        const QString cover = imp.books()[0].cover;
        QVERIFY(QFileInfo(cover).fileName().startsWith(QStringLiteral("cover_")));
        QImage img(cover);
        QVERIFY(!img.isNull());
        QCOMPARE(img.pixelColor(150, 200), QColor("#00C000")); // IRI 命中的绿图
        QVERIFY(img.pixelColor(150, 200) != QColor("#E00000")); // 非 manifest 首图（红）
    }
    // 真实书验证：设置环境变量 READDICT_REAL_EPUB=<epub 路径> 时执行
    // （本机真实书文件，CI 环境未设置则跳过）
    void realEpubCover() {
        const QString real = qEnvironmentVariable("READDICT_REAL_EPUB");
        if (real.isEmpty() || !QFile::exists(real))
            QSKIP("未设置 READDICT_REAL_EPUB，跳过真实书封面验证");
        QTemporaryDir libDir;
        BookImporter imp(libDir.path(), ":memory:");
        const QString err = imp.importFile(real, true);
        QVERIFY(err.isEmpty());
        QCOMPARE(imp.books().size(), 1);
        const QString cover = imp.books()[0].cover;
        QVERIFY(QFileInfo(cover).fileName().startsWith(QStringLiteral("cover_")));
        QVERIFY(QFile::exists(cover));
        QImage img(cover);
        QVERIFY(!img.isNull());
        QCOMPARE(img.size(), QSize(300, 400));
    }
};
QTEST_MAIN(TestImporter)
#include "tst_bookimporter.moc"
