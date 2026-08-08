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
    // D1：stop() 必须发出一个 finished，与 SystemTTSEngine 对齐
    // （QTextToSpeech::stop → 异步 Ready → finished）。
    // 控制器用 m_suppressFinished 抑制这个事件；若引擎不发，试音自然结束的 finished
    // 会误消费抑制标志 → m_testing 残留 → 正式朗读状态机被污染（用户反馈根因）。
    void stopEmitsFinished() {
        OpenAITTSEngine e;
        QSignalSpy spy(&e, &TTSEngine::finished);
        e.stop();
        QCOMPARE(spy.count(), 1);   // RED：当前实现 stop 不发 finished（count==0）
    }
};
QTEST_MAIN(TestTtsEngine)
#include "tst_ttsengine.moc"
