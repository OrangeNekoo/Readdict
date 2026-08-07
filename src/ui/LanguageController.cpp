#include "LanguageController.h"
#include <QCoreApplication>
#include <QLoggingCategory>

static Q_LOGGING_CATEGORY(lcI18n, "readdict.i18n")

LanguageController::LanguageController(const QString &initialCode, QObject *parent)
    : QObject(parent), m_code(initialCode) {
    m_translator = new QTranslator(this);
    if (!m_translator->load(QStringLiteral("readdict_") + m_code, QStringLiteral(":/i18n"))) {
        qCWarning(lcI18n) << "启动语言翻译加载失败（界面回落源串）:" << m_code;
        m_code.clear();
        return;
    }
    qApp->installTranslator(m_translator);
}

LanguageController::~LanguageController() {
    if (m_translator)
        qApp->removeTranslator(m_translator);
}

void LanguageController::applyLanguage(const QString &code) {
    if (code == m_code || code.isEmpty())
        return;
    auto *next = new QTranslator(this);
    if (!next->load(QStringLiteral("readdict_") + code, QStringLiteral(":/i18n"))) {
        qCWarning(lcI18n) << "语言翻译加载失败（保持当前语言）:" << code;
        delete next;
        return;
    }
    if (m_translator) {
        qApp->removeTranslator(m_translator);
        m_translator->deleteLater();
    }
    m_translator = next;
    qApp->installTranslator(m_translator);
    m_code = code;
    emit languageChanged();
}
