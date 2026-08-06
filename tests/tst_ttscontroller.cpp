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
    void resume() override { resumed = true; }
    void stop() override { stopped = true; }
    void setRate(double rate) override { lastRate = rate; }
    void setVoice(const QString &name) override { lastVoice = name; }

    bool m_available = true;
    QStringList spoken;
    bool stopped = false;
    bool resumed = false;
    double lastRate = -999;
    QString lastVoice;

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
    // C5：rate/voice 属性转发引擎并带信号
    void rateAndVoiceForwardToEngine() {
        TtsController c;
        FakeEngine e;
        c.setEngine(&e);
        QSignalSpy rs(&c, &TtsController::rateChanged);
        QSignalSpy vs(&c, &TtsController::voiceChanged);
        c.setRate(1.5);
        QCOMPARE(c.rate(), 1.5);
        QCOMPARE(e.lastRate, 1.5);
        QCOMPARE(rs.count(), 1);
        c.setVoice("fake-voice");
        QCOMPARE(c.voice(), QString("fake-voice"));
        QCOMPARE(e.lastVoice, QString("fake-voice"));
        QCOMPARE(vs.count(), 1);
    }
    // C5：reconfigure 重建引擎——openai 可用性由 key 决定，旧引擎信号被断开
    void reconfigureCreatesOpenAiEngine() {
        TtsController c;
        QSignalSpy avail(&c, &TtsController::engineAvailableChanged);
        c.reconfigure("openai", "https://api.openai.com/v1", "", "tts-1", "nova", 1.2);
        QVERIFY(!c.engineAvailable());            // 未配置 key → 不可用
        QCOMPARE(avail.count(), 1);
        c.reconfigure("openai", "https://api.openai.com/v1", "sk-test-fake", "tts-1", "nova", 1.2);
        QVERIFY(c.engineAvailable());
        QVERIFY(c.voices().isEmpty());            // OpenAI 引擎无音色列表（音色为配置项）
    }
    // C5：reconfigure 切 system 引擎（本机有系统语音 → 可用）
    void reconfigureCreatesSystemEngine() {
        TtsController c;
        c.reconfigure("system", "", "", "", "", 1.0);
        QVERIFY(c.engineAvailable());
    }
    // C5：重配置后新引擎复用当前 rate/voice
    void reconfigureKeepsRateAndVoice() {
        TtsController c;
        FakeEngine e;
        c.setEngine(&e);
        c.setRate(1.7);
        c.setVoice("fake-voice");
        c.reconfigure("system", "", "", "", "", 1.0);  // 换真实系统引擎
        QCOMPARE(c.rate(), 1.7);
        c.reconfigure("openai", "https://api.openai.com/v1", "sk-test-fake", "tts-1", "nova", 1.3);
        QCOMPARE(c.rate(), 1.7);                        // rate 是控制器级属性，不受重配置影响
    }
    // C5：testVoice 朗读固定文本，结束后不推进句子游标
    void testVoiceSpeaksWithoutAdvancing() {
        TtsController c;
        FakeEngine e;
        c.setEngine(&e);
        c.setSentences({"一。", "二。"});
        c.play();
        QCOMPARE(e.spoken, QStringList{"一。"});
        c.testVoice("测试文本");
        QCOMPARE(e.spoken.last(), QString("测试文本"));
        e.emitFinished();                               // 试音结束：不得推进到下一句
        QCOMPARE(c.currentIndex(), 0);
        c.play();                                       // 恢复播放正常
        QCOMPARE(e.spoken.last(), QString("一。"));
    }
    // C5：testVoice 在无引擎/引擎不可用时明确报错
    void testVoiceWithoutEngineEmitsError() {
        TtsController c;
        QSignalSpy err(&c, &TtsController::errorOccurred);
        c.testVoice("你好");
        QCOMPARE(err.count(), 1);
    }
    // C5：播放到章末（atEnd）后再 play → 从头开始
    void playAfterEndRestartsFromBeginning() {
        TtsController c;
        FakeEngine e;
        c.setEngine(&e);
        c.setSentences({"a.", "b."});
        c.play();
        e.emitFinished();
        e.emitFinished();
        QVERIFY(c.atEnd());
        QSignalSpy spy(&c, &TtsController::sentenceChanged);
        c.play();
        QCOMPARE(c.currentIndex(), 0);
        QCOMPARE(e.spoken.last(), QString("a."));
        QCOMPARE(spy.count(), 1);
    }
    // C5：暂停后 play → resume（不重读当前句）
    void playAfterPauseResumes() {
        TtsController c;
        FakeEngine e;
        c.setEngine(&e);
        c.setSentences({"a."});
        c.play();
        c.pause();
        QVERIFY(!e.resumed);
        c.play();
        QVERIFY(e.resumed);
        QCOMPARE(e.spoken.size(), 1);   // 未重新 speak
    }
    // C5：seekTo 无引擎时也推进高亮游标（sentenceChanged 通知）
    void seekToEmitsSentenceChangedWithoutEngine() {
        TtsController c;
        QSignalSpy spy(&c, &TtsController::sentenceChanged);
        c.setSentences({"a.", "b.", "c."});
        spy.clear();
        c.seekTo(2);
        QCOMPARE(c.currentIndex(), 2);
        QVERIFY(spy.count() >= 1);
    }
};
QTEST_MAIN(TestTtsController)
#include "tst_ttscontroller.moc"
