#include <QtTest>
#include <QJsonDocument>
#include <QJsonObject>
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
};
QTEST_MAIN(TestTtsEngine)
#include "tst_ttsengine.moc"
