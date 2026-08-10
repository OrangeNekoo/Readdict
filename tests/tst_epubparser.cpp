#include <QtTest>
#include "EpubParser.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTemporaryDir>

#include <zip.h>   // minizip 写端（构造畸形测试 EPUB）
#include <zlib.h>

// 编译期注入 fixture 目录（构建目录与源码目录不同，ctest 工作目录为 build/tests）
#ifndef EPUB_FIXTURES_DIR
#  define EPUB_FIXTURES_DIR "tests/fixtures"
#endif

// 用 minizip 把 entries（zip 内路径 → 内容）打包成 zip 文件（同 tst_bookimporter 模式）
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

class TestEpubParser : public QObject {
    Q_OBJECT
private slots:
    void parsesStructure() {
        EpubParser p;
        DocumentModel m = p.parse(QStringLiteral(EPUB_FIXTURES_DIR) + "/sample.epub");
        QCOMPARE(m.title, QStringLiteral("测试书"));
        QCOMPARE(m.author, QStringLiteral("作者甲"));
        QCOMPARE(m.publisher, QStringLiteral("出版社甲"));
        QCOMPARE(m.chapters.size(), 2);
        QCOMPARE(m.chapters[0].title, QStringLiteral("第一章"));
        // 段落按 <p>/<h*> 切分：h1 + 4 个 p（含实体段）
        QCOMPARE(m.chapters[0].paragraphs.size(), 5);
        QCOMPARE(m.chapters[0].paragraphs[0].level, 1);
        QVERIFY(m.chapters[0].paragraphs[1].html.contains("<b>第一段</b>"));
        // 段落纯文本与 html 分离
        QCOMPARE(m.chapters[0].paragraphs[1].text, QStringLiteral("这是第一段内容。"));
        // 嵌套 h2 段落带级别
        QVERIFY(m.chapters[1].paragraphs[2].level == 2);
        QVERIFY(m.chapters[1].paragraphs[2].html.contains("<h2>小节</h2>"));
    }
    void missingFileReturnsEmpty() {
        EpubParser p;
        QVERIFY(p.parse(QStringLiteral(EPUB_FIXTURES_DIR) + "/nope.epub").empty());
    }
    void invalidZipReturnsEmpty() {
        QTemporaryDir dir;
        QFile f(dir.path() + "/bad.epub");
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("this is not a zip file at all"); f.close();
        EpubParser p;
        QVERIFY(p.parse(f.fileName()).empty());
    }
    // 任务4 复审：有效容器 + OPF 有元数据但缺 spine——readMetadata 必须与完整
    // parse() 一样判失败返回空元数据，不能把 OPF 里的 dc:title 带出来
    // （BookImporter 按"元数据缺失"处理：标题回退文件名、作者/出版社空）。
    void readMetadataMissingSpineReturnsEmpty() {
        QTemporaryDir dir;
        const QString path = dir.path() + "/nospine.epub";
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
        QVERIFY(writeZipFile(path, {
            {QStringLiteral("META-INF/container.xml"), container.toUtf8()},
            {QStringLiteral("OEBPS/content.opf"), opf.toUtf8()},
        }));
        EpubParser p;
        const DocumentModel m = p.readMetadata(path);
        QVERIFY(m.title.isEmpty());
        QVERIFY(m.author.isEmpty());
        QVERIFY(m.publisher.isEmpty());
        // 与完整 parse 的有效性语义一致：parse 同样因缺 spine 失败
        QVERIFY(p.parse(path).empty());
    }
    // 任务4 复审：有效容器 + OPF 元数据后有 XML 良构错误（<itemref> 未闭合即遇
    // </spine>）——readMetadata 不能忽略 QXmlStreamReader error 带出已读元数据。
    void readMetadataMalformedOpfReturnsEmpty() {
        QTemporaryDir dir;
        const QString path = dir.path() + "/badopf.epub";
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
        QVERIFY(writeZipFile(path, {
            {QStringLiteral("META-INF/container.xml"), container.toUtf8()},
            {QStringLiteral("OEBPS/content.opf"), opf.toUtf8()},
            {QStringLiteral("OEBPS/Text/ch1.xhtml"),
                QByteArrayLiteral("<?xml version=\"1.0\"?><html xmlns=\"http://www.w3.org/1999/xhtml\">"
                                  "<body><p>正文。</p></body></html>")},
        }));
        EpubParser p;
        const DocumentModel m = p.readMetadata(path);
        QVERIFY(m.title.isEmpty());
        QVERIFY(m.author.isEmpty());
        QVERIFY(m.publisher.isEmpty());
        // 与完整 parse 的有效性语义一致：OPF XML 错误时 parse 也必须整体失败
        // （不能拿错误 OPF 里的 spine 继续解析章节）
        QVERIFY(p.parse(path).empty());
    }
    void extractsImagesToTemp() {
        EpubParser p;
        DocumentModel m = p.parse(QStringLiteral(EPUB_FIXTURES_DIR) + "/sample.epub");
        // 含 <img> 的段落：imagePath 指向解出的临时文件，且文件存在、非空
        const Paragraph *imgPara = nullptr;
        for (const Chapter &c : m.chapters)
            for (const Paragraph &pp : c.paragraphs)
                if (!pp.imagePath.isEmpty()) imgPara = &pp;
        QVERIFY(imgPara);
        QFileInfo fi(imgPara->imagePath);
        QVERIFY(fi.exists());
        QVERIFY(fi.size() > 0);
        QVERIFY(imgPara->imagePath.startsWith(QDir::tempPath()));
        // html 中保留 img 标签并指向本地解出文件
        QVERIFY(imgPara->html.contains("<img src="));
        QVERIFY(imgPara->html.contains(fi.fileName()));
    }
    void presplitsSentences() {
        EpubParser p;
        DocumentModel m = p.parse(QStringLiteral(EPUB_FIXTURES_DIR) + "/sample.epub");
        // 正文段 "这是第一段内容。" 预分句为 1 句
        QCOMPARE(m.chapters[0].paragraphs[1].sentences.size(), 1);
        QCOMPARE(m.chapters[0].paragraphs[1].sentences[0],
                 QStringLiteral("这是第一段内容。"));
    }
    void handlesNamedEntities() {
        // 已映射实体（&nbsp;/&mdash;/&hellip;/&Auml;）解析为对应码点；未映射实体
        // （&frac13;）按字面保留——两种情况都不能让解析截断
        EpubParser p;
        DocumentModel m = p.parse(QStringLiteral(EPUB_FIXTURES_DIR) + "/sample.epub");
        bool found = false;
        for (const Chapter &c : m.chapters) {
            for (const Paragraph &pp : c.paragraphs) {
                if (!pp.text.contains(QStringLiteral("实体")) || !pp.text.contains(QStringLiteral("完。")))
                    continue;
                found = true;
                QVERIFY(pp.text.contains(QChar(0x00A0)));     // &nbsp;
                QVERIFY(pp.text.contains(QChar(0x2014)));     // &mdash;
                QVERIFY(pp.text.contains(QChar(0x2026)));     // &hellip;
                QVERIFY(pp.text.contains(QChar(0x00C4)));     // &Auml; → Ä（大写 Latin-1 映射）
                QVERIFY(pp.text.contains(QStringLiteral("&frac13;"))); // 未映射：字面保留
                QVERIFY(pp.text.endsWith(QStringLiteral("完。"))); // 实体后正文不截断
            }
        }
        QVERIFY(found);
    }
    void reusesImageCacheOnRepeatedParse() {
        // 二次解析同一书：同一图片条目复用同一缓存文件，不新增/不重写副本。
        // 拷贝到 QTemporaryDir 保证图片缓存目录（键为 epub 路径 md5）全新
        QTemporaryDir tmp;
        const QString path = tmp.path() + "/copy.epub";
        QVERIFY(QFile::copy(QStringLiteral(EPUB_FIXTURES_DIR) + "/sample.epub", path));
        EpubParser p;
        const DocumentModel m1 = p.parse(path);
        QString imgPath;
        for (const Chapter &c : m1.chapters)
            for (const Paragraph &pp : c.paragraphs)
                if (!pp.imagePath.isEmpty()) { imgPath = pp.imagePath; break; }
        QVERIFY(!imgPath.isEmpty());
        const QDir dir(QFileInfo(imgPath).absolutePath());
        QCOMPARE(dir.entryList(QDir::Files).size(), 1); // 一次解析只产生一个图片文件
        const DocumentModel m2 = p.parse(path);
        QCOMPARE(dir.entryList(QDir::Files).size(), 1); // 二次解析不新增/不重写
        QString p2;
        for (const Chapter &c : m2.chapters)
            for (const Paragraph &pp : c.paragraphs)
                if (!pp.imagePath.isEmpty()) { p2 = pp.imagePath; break; }
        QCOMPARE(p2, imgPath); // 同一条目仍指向同一文件
    }
};
QTEST_MAIN(TestEpubParser)
#include "tst_epubparser.moc"
