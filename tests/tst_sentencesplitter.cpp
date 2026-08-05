#include <QtTest>
#include "SentenceSplitter.h"

class TestSentence : public QObject {
    Q_OBJECT
private slots:
    void splitsChinese() {
        const auto s = SentenceSplitter::split("你好世界。这是第二句？还有第三句！第四句");
        QCOMPARE(s.size(), 4);
        QCOMPARE(s[0], QString("你好世界。"));
    }
    void splitsEnglish() {
        const auto s = SentenceSplitter::split("Hello world. This is two. Dr. Smith left!");
        QCOMPARE(s.size(), 3);
        QCOMPARE(s[1], QString("This is two. "));
    }
    void handlesEllipsisAndAbbr() {
        const auto s = SentenceSplitter::split("等等…继续。U.S.A. is big.");
        QCOMPARE(s.size(), 2); // 省略号不算断句；U.S.A. 缩写不误断
    }
    void handlesNewlines() {
        const auto s = SentenceSplitter::split("第一行\n第二行\n\n第三段。");
        QCOMPARE(s.size(), 2); // 段落边界合入前一句，不单独成句
    }
    void handlesCrlfParagraphs() {
        const auto s = SentenceSplitter::split("第一段\r\n\r\n第二段。");
        QCOMPARE(s.size(), 2); // CRLF 段落边界同样识别（TXT 导入常见）
    }
    void handlesConsecutivePunctuation() {
        QCOMPARE(SentenceSplitter::split("你好..").size(), 1);    // 连续句点视为省略号，不断句
        QCOMPARE(SentenceSplitter::split("真的吗？！").size(), 1); // ？！ 组合只断一次
    }
    void abbreviationWhitelistOnly() {
        const auto s = SentenceSplitter::split("Wait for me. I'll go.");
        QCOMPARE(s.size(), 2); // me. 不在缩写白名单，应正常断句
    }
};
QTEST_MAIN(TestSentence)
#include "tst_sentencesplitter.moc"
