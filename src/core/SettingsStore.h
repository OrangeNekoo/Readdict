#pragma once
#include <QJsonObject>
#include <QString>

class SettingsStore {
public:
    explicit SettingsStore(const QString &path);
    QJsonValue value(const QString &dottedKey) const;
    void setValue(const QString &dottedKey, const QJsonValue &value);
    void save();
    QString filePath() const { return m_path; }
private:
    QString m_path;
    QJsonObject m_root;
};
