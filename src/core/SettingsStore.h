#pragma once
#include <QJsonObject>
#include <QObject>
#include <QString>

// QObject 基类仅为 qmlRegisterSingletonInstance 注册为单例所需；QML 可见接口后续任务补充
class SettingsStore : public QObject {
    Q_OBJECT
public:
    explicit SettingsStore(const QString &path, QObject *parent = nullptr);
    QJsonValue value(const QString &dottedKey) const;
    void setValue(const QString &dottedKey, const QJsonValue &value);
    void save();
    QString filePath() const { return m_path; }
private:
    QString m_path;
    QJsonObject m_root;
};
