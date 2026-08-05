#pragma once
#include <QObject>
#include <QStringList>

class TTSEngine : public QObject {
    Q_OBJECT
public:
    enum class State { Idle, Playing, Paused };
    Q_ENUM(State)
    explicit TTSEngine(QObject *parent = nullptr) : QObject(parent) {}
    virtual ~TTSEngine() = default;
    virtual bool available() const = 0;
    virtual QStringList voices() const { return {}; }
    virtual QString currentVoice() const { return {}; }
    virtual void setVoice(const QString &name) { Q_UNUSED(name); }
    virtual void setRate(double rate) { Q_UNUSED(rate); }   // 系统引擎: -1..1；OpenAI: 0.25..4.0
    virtual void speak(const QString &text) = 0;
    virtual void pause() = 0;
    virtual void resume() = 0;
    virtual void stop() = 0;
signals:
    void finished();   // 一句播放完毕
    void error(const QString &message);
};
