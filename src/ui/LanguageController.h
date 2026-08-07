#pragma once
#include <QObject>
#include <QString>
#include <QTranslator>

// D6：三语（zh_CN/zh_TW/en）切换控制器。
// 持久化在 QML 侧（Settings.setValue("ui/language", code)），本类只负责
// 从资源 :/i18n/readdict_<code>.qm 加载翻译并替换安装到 QGuiApplication。
// main.cpp 连接 languageChanged → QQmlEngine::retranslate，重估全部 qsTr 绑定；
// QML 侧（设置页语言下拉）调用 applyLanguage 完成即时切换。
class LanguageController : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString currentLanguage READ currentLanguage NOTIFY languageChanged)
public:
    explicit LanguageController(const QString &initialCode, QObject *parent = nullptr);
    // 析构时从 QCoreApplication 移除已安装翻译，避免悬垂 translator（测试进程
    // 每用例重建控制器时尤甚）
    ~LanguageController() override;
    // 切换并安装指定语言（zh_CN/zh_TW/en）；qm 缺失时保持当前语言并告警。
    Q_INVOKABLE void applyLanguage(const QString &code);
    QString currentLanguage() const { return m_code; }
signals:
    void languageChanged();
private:
    QTranslator *m_translator = nullptr;
    QString m_code;
};
