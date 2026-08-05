#include <QtTest>
#include "TextParser.h"

class TestTextParser : public QObject {
    Q_OBJECT
private slots:
    void parsesUtf8Txt() {
        QTemporaryDir dir;
        QFile f(dir.path() + "/a.txt");
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("第一章 出发\n\n这是正文。\n第二段。\n"); f.close();
        TextParser p;
        DocumentModel m = p.parse(f.fileName());
        QCOMPARE(m.chapters.size(), 1);
        QCOMPARE(m.chapters[0].paragraphs.size(), 2);
        QVERIFY(m.chapters[0].paragraphs[1].text.contains("这是正文"));
    }
    void detectsGb18030() {
        // Qt 6 的 QTextStream 无法写出 GB18030，手动构造 GB18030 字节序列：
        // "中文标题\n\n正文内容。"（经 iconv -f UTF-8 -t GB18030 验证）
        const QByteArray gbBytes = QByteArray::fromHex(
            "d6d0cec4b1eacce20a0ad5fdcec4c4dac8dda1a3");
        QTemporaryDir dir;
        QFile f(dir.path() + "/gb.txt");
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(gbBytes); f.close();
        TextParser p;
        DocumentModel m = p.parse(f.fileName());
        QVERIFY(m.chapters[0].paragraphs.size() >= 1);
        QCOMPARE(m.chapters[0].paragraphs[0].text, QStringLiteral("中文标题"));
        QVERIFY(m.chapters[0].paragraphs[1].text.contains("正文内容"));
    }
    void parsesMarkdownHeadings() {
        QTemporaryDir dir;
        QFile f(dir.path() + "/a.md");
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("# 大标题\n\n## 小节\n\n**粗体**和*斜体*。\n"); f.close();
        TextParser p;
        DocumentModel m = p.parse(f.fileName());
        QCOMPARE(m.chapters.size(), 2); // "## 小节" 开新章
        QVERIFY(m.chapters[0].paragraphs[0].html.contains("<h1>"));
        QVERIFY(m.chapters[1].paragraphs[1].html.contains("<b>粗体</b>"));
    }
    void decodesUtf16Bom() {
        // Qt 6 无 QTextCodec（Core5Compat 未安装），UTF-16 走 QStringDecoder，
        // 这里直接验证 UTF-16LE BOM 路径
        QTemporaryDir dir;
        QFile f(dir.path() + "/u16.txt");
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(QByteArray::fromHex("fffe076898980a000a00636b87650230")); f.close();
        TextParser p;
        DocumentModel m = p.parse(f.fileName());
        QVERIFY(m.chapters[0].paragraphs[0].text.contains("标题"));
    }
};
QTEST_MAIN(TestTextParser)
#include "tst_textparser.moc"
