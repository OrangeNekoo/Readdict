#include "TtsController.h"

TtsController::TtsController(QObject *parent) : QObject(parent) {}

void TtsController::setEngine(TTSEngine *engine) {
    if (m_engine == engine) return;
    // 引擎切换：先断开旧引擎的联动
    if (m_engine) {
        disconnect(m_engine, &TTSEngine::finished, this, &TtsController::next);
        disconnect(m_engine, &TTSEngine::error, this, &TtsController::errorOccurred);
    }
    m_engine = engine;
    if (m_engine) {
        // finished → 自动朗读下一句；error → errorOccurred（信号转信号转发）
        connect(m_engine, &TTSEngine::finished, this, &TtsController::next);
        connect(m_engine, &TTSEngine::error, this, &TtsController::errorOccurred);
    }
    emit voicesChanged();
    emit engineAvailableChanged();
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

void TtsController::speakCurrent() {
    if (!m_engine || m_index < 0 || m_index >= m_sentences.size()) return;
    emit sentenceChanged(m_index);
    m_engine->speak(m_sentences[m_index]);
}

void TtsController::play() {
    if (!m_engine) { emit errorOccurred("未选择 TTS 引擎"); return; }
    if (m_sentences.isEmpty()) { emit errorOccurred("没有可朗读的句子"); return; }
    speakCurrent();
    emit stateChanged(1);
}

void TtsController::pause() {
    if (m_engine) m_engine->pause();
    emit stateChanged(2);
}

void TtsController::stop() {
    if (m_engine) m_engine->stop();
    emit stateChanged(0);
}

void TtsController::next() {
    if (m_sentences.isEmpty() || m_index >= m_sentences.size()) return;
    // 越过最后一句：停在末尾（atEnd），发 chapterCompleted，不越界访问
    if (m_index + 1 >= m_sentences.size()) {
        m_index = m_sentences.size();
        emit chapterCompleted(m_chapter);
        return;
    }
    ++m_index;
    speakCurrent();
}

void TtsController::previous() {
    if (m_index > 0) { --m_index; speakCurrent(); }
}

void TtsController::seekTo(int index) {
    if (index >= 0 && index < m_sentences.size()) {
        m_index = index;
        speakCurrent();
    }
}
