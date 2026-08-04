#include "DatabaseManager.h"
#include <QSqlQuery>
#include <QSqlError>
#include <QDebug>
#include <QVariant>

DatabaseManager::DatabaseManager(const QString &path, const QString &connection) {
    open(path, connection);
    migrate();
}

void DatabaseManager::open(const QString &path, const QString &connection) {
    m_db = QSqlDatabase::addDatabase("QSQLITE", connection);
    m_db.setDatabaseName(path);
    if (!m_db.open())
        qFatal("无法打开数据库: %s", qPrintable(m_db.lastError().text()));
}

int DatabaseManager::schemaVersion() const {
    QSqlQuery q(m_db);
    q.exec("PRAGMA user_version");
    return q.next() ? q.value(0).toInt() : -1;
}

void DatabaseManager::migrate() {
    if (schemaVersion() >= 1) return;
    QSqlQuery q(m_db);
    q.exec("BEGIN");
    q.exec("CREATE TABLE IF NOT EXISTS books("
           "id INTEGER PRIMARY KEY AUTOINCREMENT,"
           "title TEXT NOT NULL, author TEXT DEFAULT '', publisher TEXT DEFAULT '',"
           "category TEXT DEFAULT '', format TEXT NOT NULL,"
           "path TEXT NOT NULL UNIQUE, cover TEXT DEFAULT '',"
           "progress REAL DEFAULT 0.0, read_seconds INTEGER DEFAULT 0,"
           "last_read_at TEXT, added_at TEXT NOT NULL)");
    q.exec("CREATE TABLE IF NOT EXISTS categories("
           "id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL)");
    q.exec("CREATE TABLE IF NOT EXISTS highlights("
           "id INTEGER PRIMARY KEY AUTOINCREMENT, book_id INTEGER NOT NULL,"
           "chapter TEXT, sentence_index INTEGER, text TEXT, color TEXT,"
           "note TEXT, created_at TEXT NOT NULL)");
    q.exec("CREATE VIRTUAL TABLE IF NOT EXISTS books_fts USING fts5("
           "title, author, publisher, content='books', content_rowid='id')");
    q.exec("PRAGMA user_version = 1");
    q.exec("COMMIT");
}
