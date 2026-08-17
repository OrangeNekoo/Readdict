#include <QtTest>
#include "ui/ReaderTextHelper.h"

// 桥接契约：QML 暴露的 splitSentences 必须保持 SentenceSplitter 的句子边界，
// 且过滤掉 trim 后为空的片段（纯空白输入返回空列表）。
// 注：Qt 6.11 移除了 char16_t* 到 QString 的隐式转换，u"" 字面量须经 fromUtf16 显式构造。
class ReaderTextHelperTest : public QObject {
    Q_OBJECT
private slots:
    void splitSentencesMatchesParserContract();
};

void ReaderTextHelperTest::splitSentencesMatchesParserContract() {
    ReaderTextHelper helper;
    QCOMPARE(helper.splitSentences(QString::fromUtf16(u"第一句。第二句！")),
             QStringList({QString::fromUtf16(u"第一句。"), QString::fromUtf16(u"第二句！")}));
    QCOMPARE(helper.splitSentences(QString::fromUtf16(u"Dr. Smith reads. Next.")),
             QStringList({QString::fromUtf16(u"Dr. Smith reads. "), QString::fromUtf16(u"Next.")}));
    QVERIFY(helper.splitSentences(QString::fromUtf16(u" \n\t ")).isEmpty());
}

QTEST_MAIN(ReaderTextHelperTest)
#include "tst_readertexthelper.moc"
