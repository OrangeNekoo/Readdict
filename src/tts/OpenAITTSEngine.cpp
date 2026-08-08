#include "OpenAITTSEngine.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>

OpenAITTSEngine::OpenAITTSEngine(QObject *parent)
    : TTSEngine(parent)
{
    m_player.setAudioOutput(&m_audioOutput);
    // 自然播放到末尾（EndOfMedia）→ finished；手动 stop 不触发。
    // InvalidMedia（200 但 body 不可解码，如代理返回错误页）→ error，避免调用方悬挂；
    // 不用 NoMedia：它在正常换源/自然结束后 stop() 时也会出现，会误报。
    connect(&m_player, &QMediaPlayer::mediaStatusChanged, this,
            [this](QMediaPlayer::MediaStatus status) {
                if (status == QMediaPlayer::EndOfMedia) {
                    emit finished();
                } else if (status == QMediaPlayer::InvalidMedia && m_hasSource) {
                    emit error(QStringLiteral("音频解码失败（服务端可能返回了非音频内容）"));
                }
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
    // 新一轮 speak：立即中断旧播放（等响应到达再停，旧音频会在网络窗口内继续播完，
    // 其 EndOfMedia 触发 finished → 控制器误 next() → 串音/跳句——用户反馈
    // "朗读一直重复测试语音"的根因之一）；同时使在途请求作废，避免旧响应乱序覆盖
    m_player.stop();
    const quint64 seq = ++m_reqSeq;
    if (m_activeReply) m_activeReply->abort();
    QNetworkReply *reply = m_net.post(req, buildPayload(text, m_model, m_voice, m_speed));
    m_activeReply = reply;
    connect(reply, &QNetworkReply::finished, this, [this, reply, seq] {
        if (m_activeReply == reply) m_activeReply = nullptr;
        reply->deleteLater();
        if (seq != m_reqSeq) return;   // 过期响应（新一轮 speak / stop 已作废）→ 丢弃
        if (reply->error() != QNetworkReply::NoError) {
            emit error(QStringLiteral("TTS 请求失败：%1").arg(reply->errorString()));
            return;
        }
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (status != 200) {
            emit error(QStringLiteral("TTS 服务返回错误（HTTP %1）").arg(status));
            return;
        }
        const QByteArray audio = reply->readAll();
        if (audio.isEmpty()) {
            emit error(QStringLiteral("TTS 服务返回空音频"));
            return;
        }
        // 播放内存音频：先让播放器完全脱离旧源再改写成员 QBuffer——
        // 若播放器仍在读旧缓冲时 setData，可能读到新旧混合数据或重播旧音频
        // （"重复测试语音"的另一根因），故先 setSourceDevice(nullptr) + close 再换数据。
        m_player.stop();
        m_player.setSourceDevice(nullptr);
        m_audioBuffer.close();
        m_audioBuffer.setData(audio);
        m_audioBuffer.open(QIODevice::ReadOnly);
        m_audioBuffer.seek(0);
        m_player.setSourceDevice(&m_audioBuffer, QUrl(QStringLiteral("speech.mp3")));
        m_hasSource = true;
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
    // 使在途请求作废并中止：响应到达后不再触发播放
    ++m_reqSeq;
    if (m_activeReply) {
        m_activeReply->abort();
        m_activeReply = nullptr;
    }
    m_player.stop();
    // 与 SystemTTSEngine 对齐（QTextToSpeech::stop → 异步 Ready → finished）：
    // stop 也会产生一个 finished，由控制器 m_suppressFinished 抑制。
    // 此前不发 → 试音自然结束的 finished 误消费抑制标志 → m_testing 残留
    // （设置页"测试发音"后状态机被污染，朗读串音/跳句的根因）。
    emit finished();
}
