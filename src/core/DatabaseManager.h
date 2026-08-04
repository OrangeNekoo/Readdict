#pragma once
#include <QSqlDatabase>
#include <QString>

class DatabaseManager {
public:
    // connection：SQLite 连接名。主程序需为 importer 内部 BookManager 传独立连接名，
    // 避免与 Books 单例的 readdict_main 重名（addDatabase 同名会移除旧连接）。
    explicit DatabaseManager(const QString &path, const QString &connection = "readdict_main");
    QSqlDatabase database() const { return m_db; }
    int schemaVersion() const;
private:
    void open(const QString &path, const QString &connection);
    void migrate();
    QSqlDatabase m_db;
};
