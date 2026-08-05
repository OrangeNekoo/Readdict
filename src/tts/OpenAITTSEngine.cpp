#include "OpenAITTSEngine.h"

OpenAITTSEngine::OpenAITTSEngine(QObject *parent)
    : TTSEngine(parent)
{
}

QString OpenAITTSEngine::speechUrl(const QString &baseUrl) {
    QUrl url(baseUrl.trimmed());
    if (!url.isValid() || url.scheme() != "https") return {};
    QString path = url.path();
    if (!path.endsWith('/')) path += '/';
    if (!path.endsWith("v1/")) return {};   // 仅接受 .../v1 或 .../v1/
    url.setPath(path + "audio/speech");
    return url.toString();
}

// ---- 以下占位：网络请求与播放由 C3 完整实现 ----
void OpenAITTSEngine::configure(const QString &baseUrl, const QString &apiKey,
                                const QString &model, const QString &voice, double speed) {
    Q_UNUSED(baseUrl); Q_UNUSED(apiKey); Q_UNUSED(model); Q_UNUSED(voice); Q_UNUSED(speed);
}
void OpenAITTSEngine::speak(const QString &text) { Q_UNUSED(text); }
void OpenAITTSEngine::pause() {}
void OpenAITTSEngine::resume() {}
void OpenAITTSEngine::stop() {}
