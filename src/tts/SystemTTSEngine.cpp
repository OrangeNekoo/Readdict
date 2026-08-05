#include "SystemTTSEngine.h"

SystemTTSEngine::SystemTTSEngine(QObject *parent) : TTSEngine(parent) {
    connect(&m_tts, &QTextToSpeech::stateChanged, this, [this](QTextToSpeech::State s) {
        if (s == QTextToSpeech::Ready) emit finished();
    });
    connect(&m_tts, &QTextToSpeech::errorOccurred, this,
            [this](QTextToSpeech::ErrorReason, const QString &msg) { emit error(msg); });
}

QStringList SystemTTSEngine::voices() const {
    QStringList out;
    for (const QVoice &v : m_tts.availableVoices()) out << v.name();
    return out;
}
QString SystemTTSEngine::currentVoice() const {
    return m_tts.voice().name();
}
void SystemTTSEngine::setVoice(const QString &name) {
    for (const QVoice &v : m_tts.availableVoices())
        if (v.name() == name) { m_tts.setVoice(v); return; }
}
void SystemTTSEngine::setRate(double rate) { m_tts.setRate(qBound(-1.0, (rate - 1.0), 1.0)); }
void SystemTTSEngine::speak(const QString &text) { m_tts.say(text); }
