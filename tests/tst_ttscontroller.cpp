#include <QtTest>
#include <QSignalSpy>
#include "TtsController.h"

// 桩引擎：记录 speak/stop 调用，可手动发射 finished/error
class FakeEngine : public TTSEngine {
    Q_OBJECT
public:
    bool available() const override { return m_available; }
    QStringList voices() const override { return {"fake-voice"}; }
    void speak(const QString &text) override { spoken.append(text); }
    void pause() override {}
    void resume() override {}
    void stop() override { stopped = true; }

    bool m_available = true;
    QStringList spoken;
    bool stopped = false;

    void emitFinished() { emit finished(); }
    void emitError(const QString &msg) { emit error(msg); }
};

class TestTtsController : public QObject {
    Q_OBJECT
private slots:
    void advancesSentences() {
        TtsController c;
        c.setSentences({"第一句。", "第二句！", "第三句？"});
        QCOMPARE(c.currentIndex(), 0);
        QCOMPARE(c.currentSentence(), QString("第一句。"));
        c.next(); QCOMPARE(c.currentIndex(), 1);
        c.previous(); QCOMPARE(c.currentIndex(), 0);
    }
    void stopsAtEnd() {
        TtsController c;
        c.setSentences({"a.", "b."});
        c.next(); c.next();
        QVERIFY(c.atEnd());
    }
    void setsChapter() {
        TtsController c;
        c.setChapter(3); QCOMPARE(c.chapter(), 3);
    }
    // 引擎 finished → 自动朗读下一句
    void engineFinishedAdvancesToNextSentence() {
        TtsController c;
        FakeEngine e;
        c.setEngine(&e);
        c.setSentences({"一。", "二。", "三。"});
        c.play();
        QCOMPARE(e.spoken, QStringList{"一。"});
        QSignalSpy spy(&c, &TtsController::sentenceChanged);
        e.emitFinished();
        QCOMPARE(c.currentIndex(), 1);
        QCOMPARE(e.spoken, (QStringList{"一。", "二。"}));
        QCOMPARE(spy.count(), 1);
    }
    // 最后一句播放完 → chapterCompleted，索引停在末尾（atEnd）而非越界
    void finishedOnLastSentenceEmitsChapterCompleted() {
        TtsController c;
        FakeEngine e;
        c.setEngine(&e);
        c.setSentences({"a.", "b."});
        c.play();
        QSignalSpy spy(&c, &TtsController::chapterCompleted);
        e.emitFinished();  // → 第二句
        e.emitFinished();  // → 章节完成
        QCOMPARE(spy.count(), 1);
        QCOMPARE(spy.takeFirst().at(0).toInt(), 0);
        QVERIFY(c.atEnd());
        QCOMPARE(c.currentSentence(), QString());  // 不越界
        QCOMPARE(e.spoken.size(), 2);              // 不再 speak 越界内容
    }
    // 空句子列表 play：不崩溃，明确报错
    void playWithEmptySentencesDoesNotCrash() {
        TtsController c;
        FakeEngine e;
        c.setEngine(&e);
        QSignalSpy err(&c, &TtsController::errorOccurred);
        c.play();
        QCOMPARE(err.count(), 1);
        QCOMPARE(e.spoken.size(), 0);
    }
    // 未设置引擎 play：报错
    void playWithoutEngineEmitsError() {
        TtsController c;
        c.setSentences({"a."});
        QSignalSpy err(&c, &TtsController::errorOccurred);
        c.play();
        QCOMPARE(err.count(), 1);
        QVERIFY(err.takeFirst().at(0).toString().contains("引擎"));
    }
    // seekTo 越界忽略
    void seekToOutOfRangeIsIgnored() {
        TtsController c;
        c.setSentences({"a.", "b.", "c."});
        c.seekTo(5); QCOMPARE(c.currentIndex(), 0);
        c.seekTo(-1); QCOMPARE(c.currentIndex(), 0);
        c.seekTo(1); QCOMPARE(c.currentIndex(), 1);
    }
    // previous 在 0 处保持
    void previousAtZeroStays() {
        TtsController c;
        c.setSentences({"a."});
        c.previous();
        QCOMPARE(c.currentIndex(), 0);
    }
    // 切换引擎：断开旧引擎信号，只响应新引擎
    void switchingEngineDisconnectsOldSignals() {
        TtsController c;
        FakeEngine oldEngine, newEngine;
        c.setEngine(&oldEngine);
        c.setEngine(&newEngine);
        c.setSentences({"一。", "二。"});
        c.play();
        QCOMPARE(newEngine.spoken, QStringList{"一。"});
        oldEngine.emitFinished();
        QCOMPARE(c.currentIndex(), 0);   // 旧引擎 finished 无效
        newEngine.emitFinished();
        QCOMPARE(c.currentIndex(), 1);
    }
    // voices / engineAvailable 转发引擎
    void forwardsVoicesAndAvailability() {
        TtsController c;
        QVERIFY(!c.engineAvailable());
        QVERIFY(c.voices().isEmpty());
        FakeEngine e;
        c.setEngine(&e);
        QVERIFY(c.engineAvailable());
        QCOMPARE(c.voices(), QStringList{"fake-voice"});
        e.m_available = false;
        QVERIFY(!c.engineAvailable());
    }
    // 引擎 error → errorOccurred
    void forwardsEngineError() {
        TtsController c;
        FakeEngine e;
        c.setEngine(&e);
        QSignalSpy spy(&c, &TtsController::errorOccurred);
        e.emitError("boom");
        QCOMPARE(spy.count(), 1);
        QCOMPARE(spy.takeFirst().at(0).toString(), QString("boom"));
    }
    // play/pause/stop 状态机
    void reportsStateTransitions() {
        TtsController c;
        FakeEngine e;
        c.setEngine(&e);
        c.setSentences({"a."});
        QSignalSpy spy(&c, &TtsController::stateChanged);
        c.play();
        QCOMPARE(spy.takeLast().at(0).toInt(), 1);
        c.pause();
        QCOMPARE(spy.takeLast().at(0).toInt(), 2);
        c.stop();
        QCOMPARE(spy.takeLast().at(0).toInt(), 0);
        QVERIFY(e.stopped);
    }
};
QTEST_MAIN(TestTtsController)
#include "tst_ttscontroller.moc"
