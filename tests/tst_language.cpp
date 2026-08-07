// D6：LanguageController 三语切换单元测试。
// 真实 .qm 已编入测试资源（tests/CMakeLists.txt 的 i18n_qm，PREFIX /i18n），
// 验证 applyLanguage 后 QCoreApplication::translate 命中对应语言翻译，
// 以及 qm 缺失/同语言时不重复切换（不触发 languageChanged）。
#include <QtTest>

#include "ui/LanguageController.h"

class TestLanguage : public QObject {
    Q_OBJECT
private slots:
    void init() {
        m_lang = new LanguageController(QStringLiteral("zh_CN"));
        m_changes = 0;
        connect(m_lang, &LanguageController::languageChanged, this,
                [this] { ++m_changes; });
    }
    void cleanup() {
        delete m_lang;
        m_lang = nullptr;
    }
    void zhCnDefault() {
        QCOMPARE(m_lang->currentLanguage(), QStringLiteral("zh_CN"));
        QCOMPARE(QCoreApplication::translate("SettingsPage", "设置"),
                 QStringLiteral("设置"));
        QCOMPARE(QCoreApplication::translate("ReaderPage", "笔记"),
                 QStringLiteral("笔记"));
    }
    void switchToEnglish() {
        m_lang->applyLanguage(QStringLiteral("en"));
        QCOMPARE(m_lang->currentLanguage(), QStringLiteral("en"));
        QCOMPARE(QCoreApplication::translate("SettingsPage", "设置"),
                 QStringLiteral("Settings"));
        QCOMPARE(QCoreApplication::translate("ShelfPage", "导入"),
                 QStringLiteral("Import"));
        QCOMPARE(QCoreApplication::translate("ReaderPage", "书内搜索"),
                 QStringLiteral("Search in book"));
        QCOMPARE(m_changes, 1); // 切换成功应恰好发一次 languageChanged
    }
    void switchToTraditional() {
        m_lang->applyLanguage(QStringLiteral("zh_TW"));
        QCOMPARE(m_lang->currentLanguage(), QStringLiteral("zh_TW"));
        QCOMPARE(QCoreApplication::translate("SettingsPage", "设置"),
                 QStringLiteral("設定"));
        QCOMPARE(QCoreApplication::translate("ReaderPage", "笔记"),
                 QStringLiteral("筆記"));
        QCOMPARE(QCoreApplication::translate("ShelfPage", "导入"),
                 QStringLiteral("匯入"));
        QCOMPARE(m_changes, 1);
    }
    void switchBackToSimplified() {
        m_lang->applyLanguage(QStringLiteral("en"));
        m_lang->applyLanguage(QStringLiteral("zh_CN"));
        QCOMPARE(m_lang->currentLanguage(), QStringLiteral("zh_CN"));
        QCOMPARE(QCoreApplication::translate("SettingsPage", "设置"),
                 QStringLiteral("设置"));
        QCOMPARE(m_changes, 2); // en→zh_CN 两次切换各发一次 languageChanged
    }
    void sameCodeNoReload() {
        m_lang->applyLanguage(QStringLiteral("zh_CN"));
        QCOMPARE(m_changes, 0); // 同语言重复调用不应触发切换
    }
    void invalidCodeKeepsCurrent() {
        m_lang->applyLanguage(QStringLiteral("fr"));
        QCOMPARE(m_lang->currentLanguage(), QStringLiteral("zh_CN")); // qm 缺失时应保持当前语言
        QCOMPARE(QCoreApplication::translate("SettingsPage", "设置"),
                 QStringLiteral("设置"));
        QCOMPARE(m_changes, 0);
    }
private:
    LanguageController *m_lang = nullptr;
    int m_changes = 0;
};

QTEST_GUILESS_MAIN(TestLanguage)
#include "tst_language.moc"
