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
    // 裸域名自动补全：https://host 与 https://host/ 均补 /v1/audio/speech
    void acceptsBareDomain() {
        QCOMPARE(OpenAITTSEngine::speechUrl("https://api.openai.com"),
                 QString("https://api.openai.com/v1/audio/speech"));
        QCOMPARE(OpenAITTSEngine::speechUrl("https://api.openai.com/"),
                 QString("https://api.openai.com/v1/audio/speech"));
    }
    // 带端口 / 带路径前缀：保留并补全
    void handlesPortAndPathPrefix() {
        QCOMPARE(OpenAITTSEngine::speechUrl("https://host.example.com:8443"),
                 QString("https://host.example.com:8443/v1/audio/speech"));
        QCOMPARE(OpenAITTSEngine::speechUrl("https://myproxy.example.com/api/v1"),
                 QString("https://myproxy.example.com/api/v1/audio/speech"));
    }
    // 已含完整端点：幂等保持标准形式（去尾斜杠）
    void idempotentForCompleteEndpoint() {
        QCOMPARE(OpenAITTSEngine::speechUrl("https://api.openai.com/v1/audio/speech"),
                 QString("https://api.openai.com/v1/audio/speech"));
        QCOMPARE(OpenAITTSEngine::speechUrl("https://api.openai.com/v1/audio/speech/"),
                 QString("https://api.openai.com/v1/audio/speech"));
    }
    // 非 https / 无效输入 → 空串
    void rejectsInvalidOrNonHttps() {
        QCOMPARE(OpenAITTSEngine::speechUrl("not a url"), QString());
        QCOMPARE(OpenAITTSEngine::speechUrl("http://api.openai.com/v1"), QString());
        QCOMPARE(OpenAITTSEngine::speechUrl("ftp://api.openai.com/v1"), QString());
        QCOMPARE(OpenAITTSEngine::speechUrl(""), QString());
    }
};
QTEST_MAIN(TestTtsUrl)
#include "tst_ttsurl.moc"
