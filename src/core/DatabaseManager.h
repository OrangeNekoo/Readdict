#pragma once
#include <QSqlDatabase>
#include <QString>

class DatabaseManager {
public:
    explicit DatabaseManager(const QString &path);
    QSqlDatabase database() const { return m_db; }
    int schemaVersion() const;
private:
    void open(const QString &path);
    void migrate();
    QSqlDatabase m_db;
};
