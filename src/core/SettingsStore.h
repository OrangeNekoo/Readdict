#pragma once
#include <QJsonObject>
#include <QObject>
#include <QString>

// QObject 基类 + Q_INVOKABLE：经 qmlRegisterSingletonInstance 注册为 QML 单例
// （Readdict.Backend.Settings），QML 侧用 value/setValue 读写点分键；
// QJsonValue 与 QML 的 string/number/bool 由 Qt 元类型系统自动互转。
class SettingsStore : public QObject {
    Q_OBJECT
public:
    explicit SettingsStore(const QString &path, QObject *parent = nullptr);
    Q_INVOKABLE QJsonValue value(const QString &dottedKey) const;
    Q_INVOKABLE void setValue(const QString &dottedKey, const QJsonValue &value);
    void save();
    QString filePath() const { return m_path; }
private:
    QString m_path;
    QJsonObject m_root;
};
