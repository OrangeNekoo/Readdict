#include <QtTest>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSignalSpy>
#include "OpenAITTSEngine.h"

class TestTtsEngine : public QObject {
    Q_OBJECT
private slots:
    void buildsRequestPayload() {
        OpenAITTSEngine e;
        const QByteArray body = e.buildPayload("你好世界", "tts-1", "nova", 1.5);
        const QJsonDocument doc = QJsonDocument::fromJson(body);
        QVERIFY(doc.isObject());
        QCOMPARE(doc.object()["model"].toString(), QString("tts-1"));
        QCOMPARE(doc.object()["voice"].toString(), QString("nova"));
        QCOMPARE(doc.object()["speed"].toDouble(), 1.5);
        QVERIFY(doc.object()["input"].toString().contains("你好"));
    }
    // 未配置 API Key 时 speak 不发请求，直接 error
    void errorsWhenNotConfigured() {
        OpenAITTSEngine e;
        QSignalSpy spy(&e, &TTSEngine::error);
        e.speak("你好");
        QCOMPARE(spy.count(), 1);
        QVERIFY(spy.takeFirst().at(0).toString().contains("API Key"));
    }
    // 空文本不发请求，直接 error
    void errorsWhenTextEmpty() {
        OpenAITTSEngine e;
        e.configure("https://api.openai.com/v1", "test-key", "tts-1", "alloy", 1.0);
        QSignalSpy spy(&e, &TTSEngine::error);
        e.speak("   ");
        QCOMPARE(spy.count(), 1);
        QVERIFY(spy.takeFirst().at(0).toString().contains("文本为空"));
    }
    // 非 https 地址不发请求，直接 error
    void errorsWhenBaseUrlInvalid() {
        OpenAITTSEngine e;
        e.configure("http://api.openai.com/v1", "test-key", "tts-1", "alloy", 1.0);
        QSignalSpy spy(&e, &TTSEngine::error);
        e.speak("你好");
        QCOMPARE(spy.count(), 1);
        QVERIFY(spy.takeFirst().at(0).toString().contains("地址无效"));
    }
};
QTEST_MAIN(TestTtsEngine)
#include "tst_ttsengine.moc"
