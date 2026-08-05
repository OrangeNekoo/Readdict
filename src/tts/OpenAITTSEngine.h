#pragma once
#include "TTSEngine.h"
#include <QNetworkAccessManager>
#include <QMediaPlayer>
#include <QUrl>

class OpenAITTSEngine : public TTSEngine {
    Q_OBJECT
public:
    explicit OpenAITTSEngine(QObject *parent = nullptr);
    static QString speechUrl(const QString &baseUrl);   // 规范化
    void configure(const QString &baseUrl, const QString &apiKey,
                   const QString &model, const QString &voice, double speed);
    bool available() const override { return !m_apiKey.isEmpty(); }
    void speak(const QString &text) override;
    void pause() override; void resume() override; void stop() override;
private:
    QString m_baseUrl, m_apiKey, m_model = "tts-1", m_voice = "alloy";
    double m_speed = 1.0;
    QNetworkAccessManager m_net;
    QMediaPlayer m_player;
};
