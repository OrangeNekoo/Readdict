#include <QtTest>
#include "OpenAITTSEngine.h"

class TestTtsUrl : public QObject {
    Q_OBJECT
private slots:
    void normalizesV1() {
        QCOMPARE(OpenAITTSEngine::speechUrl("https://api.openai.com/v1"),
                 QString("https://api.openai.com/v1/audio/speech"));
    }
    void normalizesV1TrailingSlash() {
        QCOMPARE(OpenAITTSEngine::speechUrl("https://api.openai.com/v1/"),
                 QString("https://api.openai.com/v1/audio/speech"));
    }
    void handlesCustomBase() {
        QCOMPARE(OpenAITTSEngine::speechUrl("https://myproxy.example.com/v1/"),
                 QString("https://myproxy.example.com/v1/audio/speech"));
    }
    void rejectsNoV1() {
        QCOMPARE(OpenAITTSEngine::speechUrl("https://api.openai.com/"), QString());
        QCOMPARE(OpenAITTSEngine::speechUrl("not a url"), QString());
    }
};
QTEST_MAIN(TestTtsUrl)
#include "tst_ttsurl.moc"
