#include "TtsController.h"
#include "OpenAITTSEngine.h"
#include "SystemTTSEngine.h"
#include <QDebug>

TtsController::TtsController(QObject *parent) : QObject(parent) {}

void TtsController::setEngine(TTSEngine *engine) {
    if (m_engine == engine) return;
    // 引擎切换：先断开旧引擎的联动
    if (m_engine) {
        disconnect(m_engine, &TTSEngine::finished, this, nullptr);
        disconnect(m_engine, &TTSEngine::error, this, nullptr);
    }
    m_engine = engine;
    if (m_engine) {
        // finished → 自动朗读下一句（testVoice 进行中抑制推进）；
        // error → errorOccurred（信号转信号转发）
        connect(m_engine, &TTSEngine::finished, this, [this] {
            if (m_testing) { m_testing = false; return; }
            next();
        });
        connect(m_engine, &TTSEngine::error, this, &TtsController::errorOccurred);
    }
    emit voicesChanged();
    emit engineAvailableChanged();
}

void TtsController::reconfigure(const QString &engine, const QString &url,
                                const QString &apiKey, const QString &model,
                                const QString &voice, double speed) {
    TTSEngine *old = m_engine;
    TTSEngine *fresh = nullptr;
    if (engine == QLatin1String("openai")) {
        auto *e = new OpenAITTSEngine(this);
        e->configure(url, apiKey,
                     model.isEmpty() ? QStringLiteral("tts-1") : model,
                     voice.isEmpty() ? QStringLiteral("alloy") : voice,
                     speed > 0 ? speed : 1.0);
        fresh = e;
    } else {
        fresh = new SystemTTSEngine(this);
    }
    // 先换指针再销毁旧引擎：setEngine 内部会断开旧引擎信号
    m_testing = false;
    setEngine(fresh);
    if (old) old->deleteLater();
    // 新引擎恢复当前语速/音色（OpenAI 的 setRate 映射到请求 speed）
    if (fresh) {
        fresh->setRate(m_rate);
        fresh->setVoice(m_voice);
    }
    // 引擎已被替换：原朗读必然中断，回到空闲态（TtsBar 切回 ▶）
    m_state = 0;
    emit stateChanged(0);
}

void TtsController::testVoice(const QString &text) {
    if (!m_engine) { emit errorOccurred(QStringLiteral("未选择 TTS 引擎")); return; }
    if (!m_engine->available()) { emit errorOccurred(QStringLiteral("当前 TTS 引擎不可用")); return; }
    if (text.trimmed().isEmpty()) return;
    // 试音打断当前朗读：引擎 stop + 回到空闲态（TtsBar 显示 ▶），finished 不推进游标
    m_testing = true;
    m_state = 0;
    emit stateChanged(0);
    m_engine->stop();
    m_engine->speak(text);
}

void TtsController::setSentences(const QStringList &s) {
    m_sentences = s;
    m_index = 0;
    emit sentenceChanged(0);
}

void TtsController::setChapter(int ch) {
    if (m_chapter == ch) return;
    m_chapter = ch;
    emit chapterChanged(ch);
}

QString TtsController::currentSentence() const {
    if (m_index >= 0 && m_index < m_sentences.size())
        return m_sentences[m_index];
    return QString();
}

QStringList TtsController::voices() const {
    return m_engine ? m_engine->voices() : QStringList();
}

void TtsController::setRate(double rate) {
    rate = qBound(0.25, rate, 4.0);
    if (qFuzzyCompare(m_rate, rate)) return;
    m_rate = rate;
    if (m_engine) m_engine->setRate(rate);
    emit rateChanged(rate);
}

void TtsController::setVoice(const QString &name) {
    if (m_voice == name) return;
    m_voice = name;
    if (m_engine) m_engine->setVoice(name);
    emit voiceChanged(name);
}

void TtsController::speakCurrent() {
    if (!m_engine || m_index < 0 || m_index >= m_sentences.size()) return;
    emit sentenceChanged(m_index);
    m_engine->speak(m_sentences[m_index]);
}

void TtsController::play() {
    if (!m_engine) { emit errorOccurred(QStringLiteral("未选择 TTS 引擎")); return; }
    if (m_sentences.isEmpty()) { emit errorOccurred(QStringLiteral("没有可朗读的句子")); return; }
    m_testing = false;
    // 暂停中 → 恢复播放（不重读当前句）
    if (m_state == 2) {
        m_engine->resume();
        m_state = 1;
        emit stateChanged(1);
        return;
    }
    // 播到章末（atEnd）再点播放 → 从头开始
    if (m_index >= m_sentences.size()) m_index = 0;
    speakCurrent();
    m_state = 1;
    emit stateChanged(1);
}

void TtsController::pause() {
    m_testing = false;
    if (m_engine) m_engine->pause();
    m_state = 2;
    emit stateChanged(2);
}

void TtsController::stop() {
    m_testing = false;
    if (m_engine) m_engine->stop();
    m_state = 0;
    emit stateChanged(0);
}

void TtsController::next() {
    m_testing = false;
    if (m_sentences.isEmpty() || m_index >= m_sentences.size()) return;
    // 越过最后一句：停在末尾（atEnd），发 chapterCompleted，不越界访问
    if (m_index + 1 >= m_sentences.size()) {
        m_index = m_sentences.size();
        emit sentenceChanged(m_index);
        m_state = 0;
        emit stateChanged(0);
        emit chapterCompleted(m_chapter);
        return;
    }
    ++m_index;
    speakCurrent();
    m_state = 1;
    emit stateChanged(1);
}

void TtsController::previous() {
    m_testing = false;
    if (m_index > 0) { --m_index; speakCurrent(); m_state = 1; emit stateChanged(1); }
}

void TtsController::seekTo(int index) {
    if (index < 0 || index >= m_sentences.size()) return;
    m_testing = false;
    m_index = index;
    // 先发游标变更（无引擎时也能驱动 QML 高亮），speakCurrent 内部会再发一次（幂等）
    emit sentenceChanged(index);
    speakCurrent();
    m_state = 1;
    emit stateChanged(1);
}
