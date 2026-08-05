#include "OpenAITTSEngine.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>

OpenAITTSEngine::OpenAITTSEngine(QObject *parent)
    : TTSEngine(parent)
{
    m_player.setAudioOutput(&m_audioOutput);
    // 自然播放到末尾（EndOfMedia）→ finished；手动 stop 不触发
    connect(&m_player, &QMediaPlayer::mediaStatusChanged, this,
            [this](QMediaPlayer::MediaStatus status) {
                if (status == QMediaPlayer::EndOfMedia)
                    emit finished();
            });
}

QString OpenAITTSEngine::speechUrl(const QString &baseUrl) {
    QUrl url(baseUrl.trimmed());
    if (!url.isValid() || url.scheme() != "https") return {};
    QString path = url.path();
    // 已含 /audio/speech：幂等保持标准形式（去尾斜杠）
    if (path.endsWith("/audio/speech/")) path.chop(1);
    if (path.endsWith("/audio/speech")) { url.setPath(path); return url.toString(); }
    // 裸域名 / .../v1（可带尾斜杠或路径前缀）→ 统一补全为 .../v1/audio/speech
    if (path.endsWith('/')) path.chop(1);
    if (!path.endsWith("v1")) path += "/v1";
    url.setPath(path + "/audio/speech");
    return url.toString();
}

void OpenAITTSEngine::configure(const QString &baseUrl, const QString &apiKey,
                                const QString &model, const QString &voice, double speed) {
    m_baseUrl = baseUrl;
    m_apiKey = apiKey;
    m_model = model;
    m_voice = voice;
    m_speed = speed;
}

QByteArray OpenAITTSEngine::buildPayload(const QString &text, const QString &model,
                                         const QString &voice, double speed) const {
    QJsonObject o;
    o["model"] = model;
    o["input"] = text;
    o["voice"] = voice;
    o["speed"] = speed;
    return QJsonDocument(o).toJson(QJsonDocument::Compact);
}

void OpenAITTSEngine::speak(const QString &text) {
    if (!available()) { emit error(QStringLiteral("OpenAI TTS 未配置 API Key")); return; }
    if (text.trimmed().isEmpty()) { emit error(QStringLiteral("朗读文本为空")); return; }
    const QString endpoint = speechUrl(m_baseUrl);
    if (endpoint.isEmpty()) { emit error(QStringLiteral("TTS 服务地址无效（需 https）")); return; }

    const QUrl endpointUrl(endpoint);
    QNetworkRequest req(endpointUrl);
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    req.setRawHeader("Authorization", "Bearer " + m_apiKey.toUtf8());
    QNetworkReply *reply = m_net.post(req, buildPayload(text, m_model, m_voice, m_speed));
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit error(QStringLiteral("TTS 请求失败：%1").arg(reply->errorString()));
            return;
        }
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (status != 200) {
            emit error(QStringLiteral("TTS 服务返回错误（HTTP %1）").arg(status));
            return;
        }
        // 播放内存音频：复用成员 QBuffer，先停掉旧播放再换源
        m_player.stop();
        m_audioBuffer.setData(reply->readAll());
        m_audioBuffer.open(QIODevice::ReadOnly);
        m_player.setSourceDevice(&m_audioBuffer, QUrl(QStringLiteral("speech.mp3")));
        m_player.play();
    });
}

void OpenAITTSEngine::pause() {
    if (m_player.playbackState() == QMediaPlayer::PlayingState)
        m_player.pause();
}

void OpenAITTSEngine::resume() {
    if (m_player.playbackState() == QMediaPlayer::PausedState)
        m_player.play();
}

void OpenAITTSEngine::stop() {
    m_player.stop();
}
