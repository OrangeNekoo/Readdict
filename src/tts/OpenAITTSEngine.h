#pragma once
#include "TTSEngine.h"
#include <QAudioOutput>
#include <QBuffer>
#include <QMediaPlayer>
#include <QNetworkAccessManager>
#include <QUrl>

class OpenAITTSEngine : public TTSEngine {
    Q_OBJECT
public:
    explicit OpenAITTSEngine(QObject *parent = nullptr);
    static QString speechUrl(const QString &baseUrl);   // 规范化
    QByteArray buildPayload(const QString &text, const QString &model,
                            const QString &voice, double speed) const;
    void configure(const QString &baseUrl, const QString &apiKey,
                   const QString &model, const QString &voice, double speed);
    bool available() const override { return !m_apiKey.isEmpty(); }
    // C5：Tts.rate 滑块（0.25..4.0）直接映射请求 speed，与 configure 的 speed 同一来源
    void setRate(double rate) override { m_speed = rate; }
    void speak(const QString &text) override;
    void pause() override; void resume() override; void stop() override;
private:
    QString m_baseUrl, m_apiKey, m_model = "tts-1", m_voice = "alloy";
    double m_speed = 1.0;
    QNetworkAccessManager m_net;
    QNetworkReply *m_activeReply = nullptr;   // 在途请求（新一轮 speak / stop 时 abort）
    quint64 m_reqSeq = 0;                     // 请求序号：过期响应按序号丢弃
    bool m_hasSource = false;                 // 已设置过播放源（InvalidMedia 才据此报错）
    QMediaPlayer m_player;
    QAudioOutput m_audioOutput;
    QBuffer m_audioBuffer;      // 内存音频源（每次 speak 复用）
};
