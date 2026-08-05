#pragma once
#include "TTSEngine.h"
#include <QObject>
#include <QStringList>

class TtsController : public QObject {
    Q_OBJECT
    Q_PROPERTY(int chapter READ chapter NOTIFY chapterChanged)
    Q_PROPERTY(int currentIndex READ currentIndex NOTIFY sentenceChanged)
    Q_PROPERTY(QStringList voices READ voices NOTIFY voicesChanged)
    Q_PROPERTY(bool engineAvailable READ engineAvailable NOTIFY engineAvailableChanged)
public:
    explicit TtsController(QObject *parent = nullptr);
    void setEngine(TTSEngine *engine);
    Q_INVOKABLE void setSentences(const QStringList &s);   // 当前章全部句子
    Q_INVOKABLE void setChapter(int ch);
    int chapter() const { return m_chapter; }
    int currentIndex() const { return m_index; }
    QString currentSentence() const;
    QStringList voices() const;
    bool engineAvailable() const { return m_engine && m_engine->available(); }
    bool atEnd() const { return m_index >= m_sentences.size(); }
    Q_INVOKABLE void play();      // 从 currentIndex 播放
    Q_INVOKABLE void pause();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    Q_INVOKABLE void seekTo(int index);
signals:
    void stateChanged(int state);          // 0 idle 1 playing 2 paused
    void sentenceChanged(int index);       // QML 据此高亮当前句
    void chapterChanged(int chapter);
    void voicesChanged();
    void engineAvailableChanged();
    void chapterCompleted(int chapter);
    void errorOccurred(const QString &msg);
private:
    void speakCurrent();
    TTSEngine *m_engine = nullptr;
    QStringList m_sentences;
    int m_index = 0, m_chapter = 0;
};
