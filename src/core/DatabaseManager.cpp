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
    // 迁移必须是原子的：任一语句失败即回滚，避免留下半套 schema + 悬空事务
    // （悬空事务会在连接关闭时被 SQLite 隐式回滚，后续写入静默丢失）。
    if (!q.exec("BEGIN")) {
        qWarning("数据库迁移: BEGIN 失败: %s", qPrintable(q.lastError().text()));
        return;
    }
    const QStringList steps = {
        QStringLiteral("CREATE TABLE IF NOT EXISTS books("
                       "id INTEGER PRIMARY KEY AUTOINCREMENT,"
                       "title TEXT NOT NULL, author TEXT DEFAULT '', publisher TEXT DEFAULT '',"
                       "category TEXT DEFAULT '', format TEXT NOT NULL,"
                       "path TEXT NOT NULL UNIQUE, cover TEXT DEFAULT '',"
                       "progress REAL DEFAULT 0.0, read_seconds INTEGER DEFAULT 0,"
                       "last_read_at TEXT, added_at TEXT NOT NULL)"),
        QStringLiteral("CREATE TABLE IF NOT EXISTS categories("
                       "id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL)"),
        QStringLiteral("CREATE TABLE IF NOT EXISTS highlights("
                       "id INTEGER PRIMARY KEY AUTOINCREMENT, book_id INTEGER NOT NULL,"
                       "chapter TEXT, sentence_index INTEGER, text TEXT, color TEXT,"
                       "note TEXT, created_at TEXT NOT NULL)"),
        QStringLiteral("CREATE VIRTUAL TABLE IF NOT EXISTS books_fts USING fts5("
                       "title, author, publisher, content='books', content_rowid='id')"),
        QStringLiteral("PRAGMA user_version = 1"),
    };
    for (const QString &sql : steps) {
        if (q.exec(sql))
            continue;
        qWarning("数据库迁移: 步骤失败: %s\nSQL: %s",
                 qPrintable(q.lastError().text()), qPrintable(sql));
        // 回滚使 user_version 与 schema 保持一致（保持 0，下次启动重试完整迁移）；
        // 绝不让事务悬空——否则连接关闭时 SQLite 隐式回滚，后续写入静默丢失
        if (!q.exec("ROLLBACK"))
            qWarning("数据库迁移: ROLLBACK 失败: %s", qPrintable(q.lastError().text()));
        return;
    }
    if (!q.exec("COMMIT")) {
        qWarning("数据库迁移: COMMIT 失败: %s", qPrintable(q.lastError().text()));
        q.exec("ROLLBACK");
    }
}
