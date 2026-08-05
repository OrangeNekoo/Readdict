#pragma once
#include "TTSEngine.h"
#include <QTextToSpeech>

class SystemTTSEngine : public TTSEngine {
    Q_OBJECT
public:
    explicit SystemTTSEngine(QObject *parent = nullptr);
    bool available() const override { return m_tts.state() != QTextToSpeech::Error; }
    QStringList voices() const override;
    QString currentVoice() const override;
    void setVoice(const QString &name) override;
    void setRate(double rate) override;   // rate: 0..2 → QTextToSpeech -1..1
    void speak(const QString &text) override;
    void pause() override { m_tts.pause(); }
    void resume() override { m_tts.resume(); }
    void stop() override { m_tts.stop(); }
private:
    QTextToSpeech m_tts;
};
