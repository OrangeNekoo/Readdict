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
    const int v = schemaVersion();
    QSqlQuery q(m_db);
    if (v < 1) {
        // L9（P2#32）：迁移失败致命化——与 open 失败同等 qFatal 终止进程，
        // 绝不在半套 schema 上继续运行（进程终止时 SQLite 自动回滚未提交事务）。
        if (!q.exec("BEGIN"))
            qFatal("数据库迁移失败: %s", qPrintable(q.lastError().text()));
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
            qFatal("数据库迁移失败: %s\nSQL: %s",
                   qPrintable(q.lastError().text()), qPrintable(sql));
        }
        if (!q.exec("COMMIT"))
            qFatal("数据库迁移失败: %s", qPrintable(q.lastError().text()));
    }
    if (v < 2) {
        // v1→v2：highlights 增 chapter_index（旧行默认 0，经 backfillChapterIndexes 回填）
        QSqlQuery q2(m_db);
        if (!q2.exec("BEGIN") || !q2.exec("ALTER TABLE highlights ADD COLUMN chapter_index INTEGER DEFAULT 0")
            || !q2.exec("PRAGMA user_version = 2") || !q2.exec("COMMIT"))
            qFatal("数据库迁移 v2 失败: %s", qPrintable(q2.lastError().text()));
    }
}
