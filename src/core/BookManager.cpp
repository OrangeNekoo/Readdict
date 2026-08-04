#include "BookManager.h"
#include "DatabaseManager.h"
#include <QSqlQuery>
#include <QVariant>
#include <QDateTime>

BookManager::BookManager(const QString &dbPath, QObject *parent) : QObject(parent) {
    DatabaseManager dbm(dbPath);
    m_db = dbm.database();
}

qint64 BookManager::addBook(const Book &b) {
    QSqlQuery q(m_db);
    q.prepare("INSERT INTO books(title,author,publisher,category,format,path,cover,progress,added_at)"
              " VALUES(?,?,?,?,?,?,?,?,?)");
    q.addBindValue(b.title); q.addBindValue(b.author); q.addBindValue(b.publisher);
    q.addBindValue(b.category); q.addBindValue(b.format); q.addBindValue(b.path);
    q.addBindValue(b.cover); q.addBindValue(b.progress);
    q.addBindValue(QDateTime::currentDateTime().toString(Qt::ISODate));
    if (!q.exec()) return -1;
    const qint64 id = q.lastInsertId().toLongLong();
    // books_fts 是 external-content 表，索引不会自动填充；新增后同步写入，否则 search 查不到。
    QSqlQuery f(m_db);
    f.prepare("INSERT INTO books_fts(rowid,title,author,publisher) VALUES(?,?,?,?)");
    f.addBindValue(id); f.addBindValue(b.title); f.addBindValue(b.author); f.addBindValue(b.publisher);
    f.exec();
    return id;
}

void BookManager::removeBook(qint64 id) {
    QSqlQuery q(m_db);
    q.prepare("DELETE FROM books WHERE id=?");
    q.addBindValue(id);
    q.exec();
    // 同步清理 FTS 索引，避免残留条目（search 的 JOIN 本可掩盖，仍保持索引干净）。
    QSqlQuery f(m_db);
    f.prepare("DELETE FROM books_fts WHERE rowid=?");
    f.addBindValue(id);
    f.exec();
}

QVector<Book> BookManager::selectBooks(const QString &where, const QString &order) const {
    QVector<Book> out;
    QSqlQuery q(m_db);
    q.exec("SELECT id,title,author,publisher,category,format,path,cover,progress,read_seconds,last_read_at,added_at"
           " FROM books " + where + " " + order);
    while (q.next()) {
        Book b;
        b.id = q.value(0).toLongLong(); b.title = q.value(1).toString();
        b.author = q.value(2).toString(); b.publisher = q.value(3).toString();
        b.category = q.value(4).toString(); b.format = q.value(5).toString();
        b.path = q.value(6).toString(); b.cover = q.value(7).toString();
        b.progress = q.value(8).toDouble(); b.readSeconds = q.value(9).toLongLong();
        b.lastReadAt = q.value(10).toString(); b.addedAt = q.value(11).toString();
        out.append(b);
    }
    return out;
}

Book BookManager::bookById(qint64 id) const {
    QSqlQuery q(m_db);
    q.prepare("SELECT id,title,author,publisher,category,format,path,cover,progress,read_seconds,last_read_at,added_at"
              " FROM books WHERE id=?");
    q.addBindValue(id);
    if (!q.exec() || !q.next()) return Book();
    Book b;
    b.id = q.value(0).toLongLong(); b.title = q.value(1).toString();
    b.author = q.value(2).toString(); b.publisher = q.value(3).toString();
    b.category = q.value(4).toString(); b.format = q.value(5).toString();
    b.path = q.value(6).toString(); b.cover = q.value(7).toString();
    b.progress = q.value(8).toDouble(); b.readSeconds = q.value(9).toLongLong();
    b.lastReadAt = q.value(10).toString(); b.addedAt = q.value(11).toString();
    return b;
}

QVector<Book> BookManager::books() const {
    QString filter = m_filter;
    QString where = filter.isEmpty() ? QString() : QString("WHERE category='%1'").arg(filter.replace('\'', "''"));
    QString order;
    switch (m_sort) {
    case SortField::Author: order = "ORDER BY author, title"; break;
    case SortField::Publisher: order = "ORDER BY publisher, title"; break;
    case SortField::Category: order = "ORDER BY category, title"; break;
    case SortField::Recent: order = "ORDER BY last_read_at DESC"; break;
    // 裁定：added_at DESC（最近添加在前），id DESC 兜底保证同毫秒时间戳下排序稳定
    default: order = "ORDER BY added_at DESC, id DESC"; break;
    }
    return selectBooks(where, order);
}

QVector<Book> BookManager::search(const QString &query) const {
    if (query.isEmpty()) return books();
    QVector<Book> out;
    QSqlQuery q(m_db);
    q.prepare("SELECT b.* FROM books_fts f JOIN books b ON b.id=f.rowid WHERE books_fts MATCH ?");
    q.addBindValue("\"" + query + "\"*");
    if (!q.exec()) return out;
    while (q.next()) {
        Book b; b.id = q.value(0).toLongLong(); b.title = q.value(1).toString();
        b.author = q.value(2).toString(); b.publisher = q.value(3).toString();
        b.category = q.value(4).toString(); b.format = q.value(5).toString();
        b.path = q.value(6).toString(); b.cover = q.value(7).toString();
        b.progress = q.value(8).toDouble();
        out.append(b);
    }
    return out;
}

void BookManager::setProgress(qint64 id, double progress) {
    QSqlQuery q(m_db);
    q.prepare("UPDATE books SET progress=?, last_read_at=? WHERE id=?");
    q.addBindValue(progress);
    q.addBindValue(QDateTime::currentDateTime().toString(Qt::ISODate));
    q.addBindValue(id);
    q.exec();
}

void BookManager::addReadSeconds(qint64 id, qint64 seconds) {
    QSqlQuery q(m_db);
    q.prepare("UPDATE books SET read_seconds=read_seconds+? WHERE id=?");
    q.addBindValue(seconds);
    q.addBindValue(id);
    q.exec();
}

void BookManager::setSort(SortField field) { m_sort = field; }

void BookManager::setFilter(const QString &category) { m_filter = category; }

QStringList BookManager::categories() const {
    QStringList out;
    QSqlQuery q(m_db);
    q.exec("SELECT name FROM categories ORDER BY name");
    while (q.next()) out.append(q.value(0).toString());
    return out;
}

void BookManager::addCategory(const QString &name) {
    QSqlQuery q(m_db);
    q.prepare("INSERT OR IGNORE INTO categories(name) VALUES(?)");
    q.addBindValue(name);
    q.exec();
}

void BookManager::removeCategory(const QString &name) {
    QSqlQuery q(m_db);
    q.prepare("DELETE FROM categories WHERE name=?");
    q.addBindValue(name);
    q.exec();
}
