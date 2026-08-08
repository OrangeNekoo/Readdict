#include <QtTest>
#include "parsers/ParserFactory.h"
#include "parsers/MobiParser.h"

#include <QDir>
#include <QFile>
#include <QTemporaryDir>

// 编译期注入 fixture 目录（构建目录与源码目录不同，ctest 工作目录为 build/tests）
#ifndef PARSER_FIXTURES_DIR
#  define PARSER_FIXTURES_DIR "tests/fixtures"
#endif

namespace {

void putBE16(QByteArray &b, int off, quint16 v) {
    b[off] = char(v >> 8);
    b[off + 1] = char(v & 0xff);
}

void putBE32(QByteArray &b, int off, quint32 v) {
    b[off] = char(v >> 24);
    b[off + 1] = char((v >> 16) & 0xff);
    b[off + 2] = char((v >> 8) & 0xff);
    b[off + 3] = char(v & 0xff);
}

// 构造最小 PalmDB（MOBI）文件字节：与 tst_mobiparser 的 parsesMinimalMobi
// 同一套构造逻辑（无压缩、UTF-8、MOBI 头 24 字节），用于 MOBI/AZW3 分发测试。
QByteArray buildMobiPdb(const QByteArray &html) {
    const int recCount = 2;
    const int rec0Size = 40;
    const int rec1Size = html.size() + (html.size() % 2); // PDB 记录按 2 字节对齐
    QByteArray pdb;
    pdb.fill('\0', 78 + 8 * recCount + rec0Size + rec1Size);
    pdb.replace(0, 32, QByteArray("Test Book").leftJustified(32, '\0'));
    pdb.replace(60, 4, "BOOK");
    pdb.replace(64, 4, "MOBI");
    putBE16(pdb, 76, quint16(recCount));
    const quint32 rec0Off = 78 + 8 * recCount;
    const quint32 rec1Off = rec0Off + rec0Size;
    putBE32(pdb, 78, rec0Off);
    putBE32(pdb, 86, rec1Off);
    putBE32(pdb, 91, 1);
    putBE16(pdb, rec0Off, 1);               // compression = 1（无压缩）
    putBE32(pdb, rec0Off + 4, quint32(html.size()));
    putBE16(pdb, rec0Off + 8, 1);           // text_record_count
    putBE16(pdb, rec0Off + 10, 4096);       // text_record_size
    putBE16(pdb, rec0Off + 12, 0);          // encryption_type = 0
    pdb.replace(rec0Off + 16, 4, "MOBI");
    putBE32(pdb, rec0Off + 20, 24);         // header_length
    putBE32(pdb, rec0Off + 24, 2);          // mobi_type = book
    putBE32(pdb, rec0Off + 28, 65001);      // text_encoding = UTF-8
    putBE32(pdb, rec0Off + 32, 1);          // uid
    putBE32(pdb, rec0Off + 36, 6);          // version = MOBI6（KF7）
    pdb.replace(rec1Off, html.size(), html);
    return pdb;
}

} // namespace

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
    void mobiFormatParsesMinimal() {
        const QByteArray html =
            "<html><head><title>Test Book</title></head><body>"
            "<h1>第一章 开始</h1><p>这是第一段。</p></body></html>";
        QTemporaryDir dir;
        QFile f(dir.path() + "/minimal.mobi");
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(buildMobiPdb(html)); f.close();
        const DocumentModel m = ParserFactory::parse(f.fileName(), "MOBI");
        QVERIFY(!m.empty());
        QCOMPARE(m.title, QString("Test Book"));
        QCOMPARE(m.chapters.size(), 1);
        QCOMPARE(m.chapters[0].title, QString("第一章 开始"));
    }
    void azw3RoutesToMobiParser() {
        // AZW3 与 MOBI 同为 PalmDB 容器（KF8），MobiParser 同一管线解析；
        // 断言分发到 MobiParser 且结果与直接解析一致。
        const QByteArray html =
            "<html><head><title>Test Book</title></head><body>"
            "<h1>第一章 开始</h1><p>这是第一段。</p></body></html>";
        QTemporaryDir dir;
        QFile f(dir.path() + "/minimal.azw3");
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(buildMobiPdb(html)); f.close();
        const DocumentModel viaFactory = ParserFactory::parse(f.fileName(), "AZW3");
        const DocumentModel direct = MobiParser().parse(f.fileName());
        QVERIFY(!viaFactory.empty());
        QCOMPARE(viaFactory.title, direct.title);
        QCOMPARE(viaFactory.chapters.size(), direct.chapters.size());
        QCOMPARE(viaFactory.chapters[0].title, direct.chapters[0].title);
    }
    void missingFileReturnsEmpty() {
        QVERIFY(ParserFactory::parse("/nonexistent/a.txt", "TXT").empty());
        QVERIFY(ParserFactory::parse("/nonexistent/a.epub", "EPUB").empty());
        QVERIFY(ParserFactory::parse("/nonexistent/a.fb2", "FB2").empty());
        QVERIFY(ParserFactory::parse("/nonexistent/a.mobi", "MOBI").empty());
        QVERIFY(ParserFactory::parse("/nonexistent/a.azw3", "AZW3").empty());
    }
    void errorOutParamReportsDrmAndMissing() {
        QString err;
        ParserFactory::parse(QStringLiteral("/nonexistent/x.mobi"), "MOBI", &err);
        QVERIFY(!err.isEmpty()); // 文件不存在错误上抛
        // DRM fixture（若 fixtures 含 drm.mobi 则断言含 "DRM"，否则跳过该断言）
        const QString drm = QStringLiteral(PARSER_FIXTURES_DIR) + "/drm.mobi";
        if (QFile::exists(drm)) {
            QString drmErr;
            ParserFactory::parse(drm, "MOBI", &drmErr);
            QVERIFY2(drmErr.contains(QStringLiteral("DRM")), qPrintable(drmErr));
        }
    }
    void successLeavesErrorEmpty() {
        QString err;
        ParserFactory::parse(QStringLiteral(PARSER_FIXTURES_DIR) + "/sample.epub", "EPUB", &err);
        QVERIFY(err.isEmpty());
    }
};
QTEST_MAIN(TestParserFactory)
#include "tst_parserfactory.moc"
