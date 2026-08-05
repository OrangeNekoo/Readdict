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
        // 段落按 <p>/<h*> 切分：h1 + 3 个 p
        QCOMPARE(m.chapters[0].paragraphs.size(), 4);
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
};
QTEST_MAIN(TestEpubParser)
#include "tst_epubparser.moc"
