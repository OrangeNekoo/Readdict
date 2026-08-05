#include <QtTest>
#include "EpubParser.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTemporaryDir>

// 编译期注入 fixture 目录（构建目录与源码目录不同，ctest 工作目录为 build/tests）
#ifndef EPUB_FIXTURES_DIR
#  define EPUB_FIXTURES_DIR "tests/fixtures"
#endif

class TestEpubParser : public QObject {
    Q_OBJECT
private slots:
    void parsesStructure() {
        EpubParser p;
        DocumentModel m = p.parse(QStringLiteral(EPUB_FIXTURES_DIR) + "/sample.epub");
        QCOMPARE(m.title, QStringLiteral("测试书"));
        QCOMPARE(m.author, QStringLiteral("作者甲"));
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
