// tst_mobiparser.cpp — MobiParser 单元测试
// 无真实 .mobi fixture（用户仅提供 epub/pdf），故用程序化构造的 PalmDB 字节
// 覆盖三条路径：
//   1) 合法最小 KF7 文件（无压缩、UTF-8、MOBI 头 24 字节）→ 正常解析出
//      标题/章节/段落/预分句/内联 <b>
//   2) 伪造"加密"文件（PDB 头 + record0 声明 encryption_type=2，无正文）→
//      libmobi 识别为加密（mobi_is_encrypted），报"加密"错误、模型为空、不崩溃
//   3) 64 字节零文件 → 不足 78 字节 PDB 头，libmobi 报 MOBI_DATA_CORRUPT →
//      非空错误、模型为空
// 构造细节与 libmobi 校验逻辑对应（见 MobiParser.cpp 顶部注释）。
#include <QtTest>
#include "MobiParser.h"

#include <QByteArray>
#include <QDir>
#include <QTemporaryDir>

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

// 构造最小 PalmDB（MOBI）文件字节。
//  - html 为空且 encryptionType != 0 时：仅 record0（16 字节 PalmDOC 头），
//    用于伪造"加密"文件（libmobi 加载成功后 mobi_is_encrypted 判定为真）。
//  - 否则：record0 = PalmDOC 头(16) + MOBI 头(24, UTF-8/version 6)，
//    record1 = 未压缩 html 文本记录。
QByteArray buildMobiPdb(const QByteArray &html, quint16 encryptionType) {
    const bool withMobiHeader = !html.isEmpty();
    const int recCount = withMobiHeader ? 2 : 1;
    const int rec0Size = withMobiHeader ? 40 : 16;
    const int rec1Size = html.size() + (html.size() % 2); // PDB 记录按 2 字节对齐

    QByteArray pdb;
    pdb.fill('\0', 78 + 8 * recCount + rec0Size + rec1Size);
    pdb.replace(0, 32, QByteArray("Test Book").leftJustified(32, '\0'));
    pdb.replace(60, 4, "BOOK");   // 数据库类型
    pdb.replace(64, 4, "MOBI");   // creator
    putBE16(pdb, 76, quint16(recCount));

    const quint32 rec0Off = 78 + 8 * recCount;
    const quint32 rec1Off = rec0Off + rec0Size;
    putBE32(pdb, 78, rec0Off);              // record 0 偏移
    pdb[82] = 0;                            // attributes
    putBE32(pdb, 83, 0);                    // uid（3 字节，高位在 83）
    putBE32(pdb, 86, rec1Off);              // record 1 偏移
    pdb[90] = 0;
    putBE32(pdb, 91, 1);

    // record 0：PalmDOC 头（16 字节）
    putBE16(pdb, rec0Off, 1);               // compression = 1（无压缩）
    putBE16(pdb, rec0Off + 2, 0);           // unused
    putBE32(pdb, rec0Off + 4, quint32(html.size())); // text_length
    putBE16(pdb, rec0Off + 8, quint16(withMobiHeader ? 1 : 0)); // text_record_count
    putBE16(pdb, rec0Off + 10, 4096);       // text_record_size
    putBE16(pdb, rec0Off + 12, encryptionType);
    putBE16(pdb, rec0Off + 14, 0);          // unknown1

    if (withMobiHeader) {
        // MOBI 头（24 字节，libmobi 其余字段读为 NOTSET/NULL 亦可）
        pdb.replace(rec0Off + 16, 4, "MOBI");
        putBE32(pdb, rec0Off + 20, 24);     // header_length
        putBE32(pdb, rec0Off + 24, 2);      // mobi_type = book
        putBE32(pdb, rec0Off + 28, 65001);  // text_encoding = UTF-8
        putBE32(pdb, rec0Off + 32, 1);      // uid
        putBE32(pdb, rec0Off + 36, 6);      // version = MOBI6（KF7）
        pdb.replace(rec1Off, html.size(), html);
    }
    return pdb;
}

} // namespace

class TestMobi : public QObject {
    Q_OBJECT
private slots:
    // 加密文件应报"加密"错误而非崩溃（伪造 encryption_type=2 的 PDB）
    void drmDetection() {
        MobiParser p;
        QTemporaryDir dir;
        QFile f(dir.path() + "/drm.mobi");
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(buildMobiPdb({}, /*encryptionType=*/2));
        f.close();
        QVERIFY(p.parse(f.fileName()).empty());
        QVERIFY(p.lastError().contains("加密"));
    }
    // 垃圾文件（64 字节零）→ 非空错误 + 空模型，不崩溃
    void invalidFileReturnsError() {
        MobiParser p;
        QTemporaryDir dir;
        QFile f(dir.path() + "/garbage.mobi");
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(QByteArray(64, '\x00'));
        f.close();
        QVERIFY(p.parse(f.fileName()).empty());
        QVERIFY(!p.lastError().isEmpty());
    }
    // 不存在的文件 → 空模型 + 非空错误
    void noFileReturnsEmpty() {
        MobiParser p;
        QVERIFY(p.parse("tests/fixtures/nope.mobi").empty());
        QVERIFY(!p.lastError().isEmpty());
    }
    // 最小合法 KF7 文件：标题/章节（h1/h2 开新章）/段落/预分句/<b>
    void parsesMinimalMobi() {
        const QByteArray html =
            "<html><head><title>Test Book</title></head><body>"
            "<h1>第一章 开始</h1>"
            "<p>这是第一段。包含两个句子。</p>"
            "<p>第二段 <b>加粗</b> 内容。</p>"
            "<h2>第二章 继续</h2>"
            "<p>第三段。</p>"
            "<p>第四段<br>换行后。</p>"
            "</body></html>";
        MobiParser p;
        QTemporaryDir dir;
        QFile f(dir.path() + "/minimal.mobi");
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(buildMobiPdb(html, 0));
        f.close();

        const DocumentModel model = p.parse(f.fileName());
        QVERIFY2(p.lastError().isEmpty(), qUtf8Printable(p.lastError()));
        QCOMPARE(model.title, QString("Test Book"));
        QCOMPARE(model.chapters.size(), 2);

        const Chapter &c1 = model.chapters[0];
        QCOMPARE(c1.title, QString("第一章 开始"));
        QCOMPARE(c1.paragraphs.size(), 3);
        QCOMPARE(c1.paragraphs[0].level, 1);
        QCOMPARE(c1.paragraphs[0].text, QString("第一章 开始"));
        QCOMPARE(c1.paragraphs[0].html, QString("<h1>第一章 开始</h1>"));
        QCOMPARE(c1.paragraphs[1].text, QString("这是第一段。包含两个句子。"));
        QCOMPARE(c1.paragraphs[1].sentences.size(), 2);
        QCOMPARE(c1.paragraphs[2].text, QString("第二段 加粗 内容。"));
        QVERIFY(c1.paragraphs[2].html.contains("<b>加粗</b>"));

        const Chapter &c2 = model.chapters[1];
        QCOMPARE(c2.title, QString("第二章 继续"));
        QCOMPARE(c2.paragraphs.size(), 3);
        QCOMPARE(c2.paragraphs[0].level, 2);
        QCOMPARE(c2.paragraphs[1].text, QString("第三段。"));
        // <br> 在 html 中保留结构、text 中换行，文本不粘连
        QCOMPARE(c2.paragraphs[2].text, QString("第四段\n换行后。"));
        QVERIFY(c2.paragraphs[2].html.contains("<br>"));
        QCOMPARE(c2.paragraphs[2].sentences.size(), 1);
    }
};

QTEST_MAIN(TestMobi)
#include "tst_mobiparser.moc"
