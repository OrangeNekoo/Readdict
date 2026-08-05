#include <QtTest>
#include "core/BookImporter.h"

#include <QBuffer>
#include <QCryptographicHash>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QPainter>
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

// 生成一张确定的封面 PNG（850x1214，模拟常见 EPUB 封面比例）
static QByteArray makeCoverPng() {
    QImage img(850, 1214, QImage::Format_RGB32);
    img.fill(QColor("#123456"));
    QPainter p(&img);
    p.setPen(Qt::white);
    p.setFont(QFont(QStringLiteral("Helvetica"), 48, QFont::Bold));
    p.drawText(img.rect(), Qt::AlignCenter, QStringLiteral("COVER"));
    p.end();
    QByteArray out;
    QBuffer buf(&out);
    buf.open(QIODevice::WriteOnly);
    img.save(&buf, "PNG");
    return out;
}

// 构造带封面（OPF <meta name="cover"> + cover.xhtml <img>）的最小 EPUB
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
                       "<item href=\"Images/cover.png\" id=\"cover-img\" media-type=\"image/png\"/>"
                       "</manifest>"
                       "<spine toc=\"ncx\"><itemref idref=\"cover.xhtml\"/></spine>"
                       "</package>");
    const QString coverXhtml =
        QStringLiteral("<?xml version=\"1.0\" encoding=\"utf-8\"?>"
                       "<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>Cover</title></head>"
                       "<body><p style=\"text-align:center\"><img src=\"../Images/cover.png\"/></p></body></html>");
    const QList<QPair<QString, QByteArray>> entries = {
        {QStringLiteral("META-INF/container.xml"), container.toUtf8()},
        {QStringLiteral("OEBPS/content.opf"), opf.toUtf8()},
        {QStringLiteral("OEBPS/Text/cover.xhtml"), coverXhtml.toUtf8()},
        {QStringLiteral("OEBPS/Images/cover.png"), makeCoverPng()},
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
