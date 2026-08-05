#include <QtTest>
#include "parsers/ParserFactory.h"

#include <QDir>
#include <QFile>
#include <QTemporaryDir>

// 编译期注入 fixture 目录（构建目录与源码目录不同，ctest 工作目录为 build/tests）
#ifndef PARSER_FIXTURES_DIR
#  define PARSER_FIXTURES_DIR "tests/fixtures"
#endif

class TestParserFactory : public QObject {
    Q_OBJECT
private slots:
    void unknownFormatReturnsEmpty() {
        QVERIFY(ParserFactory::parse("/nonexistent/file.bin", "XYZ").empty());
        QVERIFY(ParserFactory::parse("/nonexistent/file.bin", QString()).empty());
    }
    void txtFormatParses() {
        QTemporaryDir dir;
        QFile f(dir.path() + "/a.txt");
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("第一章 出发\n\n这是正文。\n第二段。\n"); f.close();
        const DocumentModel m = ParserFactory::parse(f.fileName(), "TXT");
        QVERIFY(!m.empty());
        QVERIFY(m.chapters[0].paragraphs[1].text.contains("这是正文"));
    }
    void mdFormatParses() {
        QTemporaryDir dir;
        QFile f(dir.path() + "/a.md");
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("# 大标题\n\n正文内容。\n"); f.close();
        QVERIFY(!ParserFactory::parse(f.fileName(), "MD").empty());
    }
    void epubFormatParsesFixture() {
        const DocumentModel m = ParserFactory::parse(
            QStringLiteral(PARSER_FIXTURES_DIR) + "/sample.epub", "EPUB");
        QCOMPARE(m.title, QStringLiteral("测试书"));
        QVERIFY(!m.empty());
    }
    void fb2FormatParsesFixture() {
        const DocumentModel m = ParserFactory::parse(
            QStringLiteral(PARSER_FIXTURES_DIR) + "/sample.fb2", "FB2");
        QVERIFY(!m.empty());
    }
    void missingFileReturnsEmpty() {
        QVERIFY(ParserFactory::parse("/nonexistent/a.txt", "TXT").empty());
        QVERIFY(ParserFactory::parse("/nonexistent/a.epub", "EPUB").empty());
        QVERIFY(ParserFactory::parse("/nonexistent/a.fb2", "FB2").empty());
        QVERIFY(ParserFactory::parse("/nonexistent/a.mobi", "MOBI").empty());
        QVERIFY(ParserFactory::parse("/nonexistent/a.azw3", "AZW3").empty());
    }
};
QTEST_MAIN(TestParserFactory)
#include "tst_parserfactory.moc"
