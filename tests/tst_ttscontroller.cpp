#include <QtTest>
#include <QSignalSpy>
#include <QTextToSpeech>
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
    // D1：stopEmitsFinished=true 模拟修复后的 OpenAITTSEngine 契约（stop() 发一个
    // finished，与 SystemTTSEngine 的异步 Ready→finished 对齐）；false 为旧行为。
    void stop() override {
        stopped = true;
        if (stopEmitsFinished) emit finished();
    }
    void setRate(double rate) override { lastRate = rate; }
    void setVoice(const QString &name) override { lastVoice = name; }

    bool m_available = true;
    bool stopEmitsFinished = false;
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
        // currentSentence 已删（L7 死接口）：游标语义经 currentIndex 断言
        c.next(); QCOMPARE(c.currentIndex(), 1);
        c.previous(); QCOMPARE(c.currentIndex(), 0);
    }
    void startsFromRequestedSentenceIndex() {
        TtsController c;
        FakeEngine e;
        c.setEngine(&e);
        c.setSentences({"第一句。", "第二句！", "第三句？"});
        c.setCurrentIndex(1);
        QCOMPARE(c.currentIndex(), 1);
        c.play();
        QCOMPARE(e.spoken, QStringList{"第二句！"});
        c.stop();
        c.setCurrentIndex(99);
        QCOMPARE(c.currentIndex(), 2);
    }
    void stopsAtEnd() {
        TtsController c;
        c.setSentences({"a.", "b."});
        c.next(); c.next();
        QCOMPARE(c.currentIndex(), 2);   // atEnd 语义改经游标断言：游标 == 句数（停在末尾）
        QCOMPARE(c.state(), 0);
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
    // 最后一句播放完 → chapterCompleted，游标停在末尾（atEnd 语义）而非越界
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
        QCOMPARE(c.currentIndex(), 2);   // 游标停在末尾，不越界
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
    // C5：reconfigure 切 system 引擎——可用性依赖宿主系统语音，无语音环境跳过断言
    void reconfigureCreatesSystemEngine() {
        TtsController c;
        QTextToSpeech probe;
        if (probe.availableVoices().isEmpty() || probe.state() == QTextToSpeech::Error)
            QSKIP("宿主无系统语音，跳过系统引擎可用性断言");
        c.reconfigure("system", "", "", "", "", 1.0);
        QVERIFY(c.engineAvailable());
    }
    // C5：重配置后新引擎复用当前 rate/voice
    // 注：FakeEngine 必须堆分配——reconfigure 对旧引擎调 deleteLater（栈对象即 UB）
    void reconfigureKeepsRateAndVoice() {
        TtsController c;
        auto *e = new FakeEngine;
        c.setEngine(e);
        c.setRate(1.7);
        c.setVoice("fake-voice");
        c.reconfigure("system", "", "", "", "", 1.0);  // 换真实系统引擎（旧 FakeEngine deleteLater）
        QCOMPARE(c.rate(), 1.7);
        c.reconfigure("openai", "https://api.openai.com/v1", "sk-test-fake", "tts-1", "nova", 1.3);
        QCOMPARE(c.rate(), 1.7);                        // rate 是控制器级属性，不受重配置影响
    }
    // C5 复审：stop() 引发的异步 finished 必须被抑制——否则 ⏹ 变跳句继续朗读
    void stopSuppressesAsyncFinished() {
        TtsController c;
        FakeEngine e;
        c.setEngine(&e);
        c.setSentences({"一。", "二。", "三。"});
        c.play();
        QCOMPARE(e.spoken, QStringList{"一。"});
        c.stop();
        QVERIFY(e.stopped);
        e.emitFinished();   // 模拟 QTextToSpeech::stop() 后异步 Ready → finished
        QCOMPARE(c.currentIndex(), 0);
        QCOMPARE(e.spoken.size(), 1);
        // 抑制只消费一次：再来一个 finished（模拟换章后新句自然结束）不得再次误吞
        c.play();           // 新发声清除抑制
        QCOMPARE(e.spoken.last(), QString("一。"));
        e.emitFinished();   // 新句自然结束 → 正常推进
        QCOMPARE(c.currentIndex(), 1);
        QCOMPARE(e.spoken.last(), QString("二。"));
    }
    // C5 复审：换章路径 stop → setSentences：旧章残留 finished 不得推进新章游标
    void stopThenSetSentencesIgnoresStaleFinished() {
        TtsController c;
        FakeEngine e;
        c.setEngine(&e);
        c.setSentences({"一。", "二。"});
        c.play();
        c.stop();
        c.setSentences({"新章一。", "新章二。"});   // 模拟 loadChapter：stop + 重拍平
        QCOMPARE(c.currentIndex(), 0);
        e.emitFinished();   // 旧章 stop 引发的 finished 延迟到达
        QCOMPARE(c.currentIndex(), 0);
        QCOMPARE(e.spoken.size(), 1);
    }
    // C5 复审：testVoice 打断朗读并复位状态（stateChanged → 0）
    void testVoiceResetsStateToIdle() {
        TtsController c;
        FakeEngine e;
        c.setEngine(&e);
        c.setSentences({"一。", "二。"});
        c.play();
        QSignalSpy spy(&c, &TtsController::stateChanged);
        c.testVoice("测试");
        QCOMPARE(spy.count(), 1);
        QCOMPARE(spy.takeFirst().at(0).toInt(), 0);
        e.emitFinished();   // stop 引发的 finished（被抑制消费）
        e.emitFinished();   // 试音文本自然结束（m_testing 消费）
        QCOMPARE(c.currentIndex(), 0);
        QCOMPARE(e.spoken.last(), QString("测试"));
        c.play();
        QCOMPARE(e.spoken.last(), QString("一。"));
    }
    // C5 复审：reconfigure 后回空闲态（stateChanged → 0）
    void reconfigureResetsStateToIdle() {
        TtsController c;
        FakeEngine e;
        c.setEngine(&e);
        c.setSentences({"a."});
        c.play();
        QSignalSpy spy(&c, &TtsController::stateChanged);
        c.reconfigure("openai", "https://api.openai.com/v1", "sk-test-fake", "tts-1", "nova", 1.0);
        QCOMPARE(spy.count(), 1);
        QCOMPARE(spy.takeFirst().at(0).toInt(), 0);
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
        QCOMPARE(c.currentIndex(), 2);   // 游标停在末尾（atEnd 语义）
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
    // D1（用户反馈 BUG）：设置 OpenAI → 测试发音 → 进入书 → 朗读
    // 一直重复"测试语音"。锁定修复后契约（引擎 stop() 发一个 finished 供抑制标志消费，
    // 试音自然结束由 m_testing 消费）下完整用户序列：
    // 试音文本只出现一次，朗读流逐句推进书中句子，末尾 chapterCompleted，无串音。
    void userFlowTestVoiceThenReadingSpeaksBookSentencesOnly() {
        TtsController c;
        FakeEngine e;
        e.stopEmitsFinished = true;   // 修复后的 OpenAITTSEngine 契约
        c.setEngine(&e);
        c.setSentences({"一。", "二。", "三。"});
        // 1. 设置页点"测试发音"：stop 的 finished 被抑制消费，试音开始
        c.testVoice("这是一段测试语音");
        QCOMPARE(e.spoken, QStringList{"这是一段测试语音"});
        // 2. 试音自然播完：m_testing 消费 → 两标志清零，不推进游标
        e.emitFinished();
        QCOMPARE(c.currentIndex(), 0);
        // 3. 进入书：loadChapter → stop + 喂新章句子
        c.stop();
        c.setSentences({"第一句。", "第二句！", "第三句？"});
        // 4. 点朗读：从首句逐句推进，测试文本绝不串入
        c.play();
        QCOMPARE(e.spoken.last(), QString("第一句。"));
        e.emitFinished();
        QCOMPARE(e.spoken.last(), QString("第二句！"));
        e.emitFinished();
        QCOMPARE(e.spoken.last(), QString("第三句？"));
        e.emitFinished();
        QCOMPARE(c.currentIndex(), 3);   // 游标停在末尾（atEnd 语义）
        QCOMPARE(e.spoken, (QStringList{
            "这是一段测试语音", "第一句。", "第二句！", "第三句？"}));
    }
    // D1：试音结束（自然 finished 已消费）后，任何顺序下两标志都不残留——
    // 后续 play + 正常 finished 必须照常推进（不被 m_testing 吞掉、不误跳）。
    void testVoiceEndLeavesNoStateResidue() {
        TtsController c;
        FakeEngine e;
        e.stopEmitsFinished = true;
        c.setEngine(&e);
        c.setSentences({"一。", "二。"});
        c.testVoice("测试");
        e.emitFinished();                       // 试音自然结束
        c.play();                               // 朗读开始
        QCOMPARE(e.spoken.last(), QString("一。"));
        e.emitFinished();                       // 第一句结束 → 必须推进
        QCOMPARE(c.currentIndex(), 1);
        QCOMPARE(e.spoken.last(), QString("二。"));
    }
    // L7（P2#37）：reconfigure 销毁旧引擎前必须先 stop——朗读中热切换引擎，
    // 旧引擎的音频不得继续播放。FakeEngine 即文件既有记录 stop 的桩（简报 SpyEngine 意图）
    void reconfigureStopsOldEngine() {
        TtsController c;
        auto *first = new FakeEngine;
        c.setEngine(first);
        c.setSentences({"一。"});
        c.play();
        QCOMPARE(first->spoken, QStringList{"一。"});   // 播放确已进行（旧引擎正在发声）
        c.reconfigure("system", "", "", "", "", 1.0);
        QVERIFY(first->stopped);
    }
};
QTEST_MAIN(TestTtsController)
#include "tst_ttscontroller.moc"
