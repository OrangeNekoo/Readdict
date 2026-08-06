#pragma once
#include "TTSEngine.h"
#include <QObject>
#include <QStringList>

// 朗读控制器：持有句子列表与当前句游标，驱动引擎播放/暂停/停止/跳句；
// QML 侧经 qmlRegisterSingletonInstance 注册为 Readdict.Backend.Tts。
// C5 新增：rate/voice 属性（转发引擎）、reconfigure（按配置重建引擎）、
// testVoice（不推进游标的试音）、内部状态机（m_state：0 idle/1 playing/2 paused）。
class TtsController : public QObject {
    Q_OBJECT
    Q_PROPERTY(int chapter READ chapter NOTIFY chapterChanged)
    Q_PROPERTY(int currentIndex READ currentIndex NOTIFY sentenceChanged)
    Q_PROPERTY(QStringList voices READ voices NOTIFY voicesChanged)
    Q_PROPERTY(bool engineAvailable READ engineAvailable NOTIFY engineAvailableChanged)
    Q_PROPERTY(double rate READ rate WRITE setRate NOTIFY rateChanged)
    Q_PROPERTY(QString voice READ voice WRITE setVoice NOTIFY voiceChanged)
public:
    explicit TtsController(QObject *parent = nullptr);
    void setEngine(TTSEngine *engine);
    // 按配置重建引擎：engine 为 "system" 或 "openai"；openai 时用其余参数 configure。
    // 旧引擎销毁（deleteLater），新引擎复用当前 rate/voice；完成后 voices/可用性信号已发。
    Q_INVOKABLE void reconfigure(const QString &engine, const QString &url,
                                 const QString &apiKey, const QString &model,
                                 const QString &voice, double speed);
    // 朗读固定文本（试音）：不改变句子游标，结束后不自动推进（finished 被抑制）。
    Q_INVOKABLE void testVoice(const QString &text);
    Q_INVOKABLE void setSentences(const QStringList &s);   // 当前章全部句子
    Q_INVOKABLE void setChapter(int ch);
    int chapter() const { return m_chapter; }
    int currentIndex() const { return m_index; }
    QString currentSentence() const;
    QStringList voices() const;
    bool engineAvailable() const { return m_engine && m_engine->available(); }
    bool atEnd() const { return m_index >= m_sentences.size(); }
    Q_INVOKABLE void play();      // 从 currentIndex 播放；暂停中恢复；末尾则从头
    Q_INVOKABLE void pause();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    Q_INVOKABLE void seekTo(int index);
    double rate() const { return m_rate; }
    QString voice() const { return m_voice; }
    void setRate(double rate);
    void setVoice(const QString &name);
signals:
    void stateChanged(int state);          // 0 idle 1 playing 2 paused
    void sentenceChanged(int index);       // QML 据此高亮当前句
    void chapterChanged(int chapter);
    void voicesChanged();
    void engineAvailableChanged();
    void chapterCompleted(int chapter);
    void errorOccurred(const QString &msg);
    void rateChanged(double rate);
    void voiceChanged(const QString &voice);
private:
    void speakCurrent();
    TTSEngine *m_engine = nullptr;
    QStringList m_sentences;
    int m_index = 0, m_chapter = 0;
    double m_rate = 1.0;      // 语速倍率（0.25..4.0，TtsBar 滑块 0.5..2.0）
    QString m_voice;          // 当前音色名（重配置后尝试在新引擎上恢复）
    int m_state = 0;          // 状态机：0 idle 1 playing 2 paused
    bool m_testing = false;   // testVoice 进行中：finished 不推进句子
};
