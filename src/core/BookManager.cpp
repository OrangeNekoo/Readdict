#include "BookManager.h"
#include "DatabaseManager.h"
#include <QSqlQuery>
#include <QSqlError>
#include <QVariant>
#include <QDateTime>
#include <QDebug>

BookManager::BookManager(const QString &dbPath, const QString &connection, QObject *parent)
    : QObject(parent) {
    DatabaseManager dbm(dbPath, connection);
    m_db = dbm.database();
}

qint64 BookManager::addBook(const Book &b) {
    const bool inTx = m_db.transaction(); // 失败则退回自动提交，写入仍会执行
    QSqlQuery q(m_db);
    q.prepare("INSERT INTO books(title,author,publisher,category,format,path,cover,progress,added_at)"
              " VALUES(?,?,?,?,?,?,?,?,?)");
    q.addBindValue(b.title); q.addBindValue(b.author); q.addBindValue(b.publisher);
    q.addBindValue(b.category); q.addBindValue(b.format); q.addBindValue(b.path);
    q.addBindValue(b.cover); q.addBindValue(b.progress);
    q.addBindValue(QDateTime::currentDateTime().toString(Qt::ISODate));
    if (!q.exec()) { if (inTx) m_db.rollback(); return -1; }
    const qint64 id = q.lastInsertId().toLongLong();
    // books_fts 是 external-content 表，索引不会自动填充；两条写入同事务，保证原子一致。
    QSqlQuery f(m_db);
    f.prepare("INSERT INTO books_fts(rowid,title,author,publisher) VALUES(?,?,?,?)");
    f.addBindValue(id); f.addBindValue(b.title); f.addBindValue(b.author); f.addBindValue(b.publisher);
    if (!f.exec()) {
        qWarning() << "addBook: books_fts 索引写入失败:" << f.lastError().text();
        if (inTx) m_db.rollback();
        return -1;
    }
    if (inTx) m_db.commit();
    emit booksChanged();
    return id;
}

void BookManager::removeBook(qint64 id) {
    QSqlQuery q(m_db);
    q.prepare("DELETE FROM books WHERE id=?");
    q.addBindValue(id);
    if (!q.exec()) return;
    // 同步清理 FTS 索引，避免残留条目（search 的 JOIN 本可掩盖，仍保持索引干净）。
    QSqlQuery f(m_db);
    f.prepare("DELETE FROM books_fts WHERE rowid=?");
    f.addBindValue(id);
    if (!f.exec())
        qWarning() << "removeBook: books_fts 索引清理失败:" << f.lastError().text();
    emit booksChanged();
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
    return selectBooks(where, orderSql());
}

QVector<Book> BookManager::search(const QString &query) const {
    if (query.isEmpty()) return books();
    // FTS5 MATCH 中未转义的 '"' 会截断字符串导致语法错误（q.exec 静默失败），剔除后再构造前缀查询。
    QString term = query;
    term.remove('"');
    if (term.isEmpty()) return books();
    // 与 books() 相同的排序；叠加分类过滤：books_fts 无 category 列，JOIN books 后在 b.category 上加条件，
    // 搜索限定在所选分类内进行（排序框/分类高亮与网格结果保持一致）。
    QString sql = "SELECT b.* FROM books_fts f JOIN books b ON b.id=f.rowid WHERE books_fts MATCH ?";
    if (!m_filter.isEmpty()) {
        QString filter = m_filter;
        sql += " AND b.category='" + filter.replace('\'', "''") + "'";
    }
    sql += orderSql("b.");
    QVector<Book> out;
    QSqlQuery q(m_db);
    q.prepare(sql);
    q.addBindValue("\"" + term + "\"*");
    if (!q.exec()) return out;
    while (q.next()) {
        Book b; b.id = q.value(0).toLongLong(); b.title = q.value(1).toString();
        b.author = q.value(2).toString(); b.publisher = q.value(3).toString();
        b.category = q.value(4).toString(); b.format = q.value(5).toString();
        b.path = q.value(6).toString(); b.cover = q.value(7).toString();
        b.progress = q.value(8).toDouble(); b.readSeconds = q.value(9).toLongLong();
        b.lastReadAt = q.value(10).toString(); b.addedAt = q.value(11).toString();
        out.append(b);
    }
    return out;
}

QString BookManager::orderSql(const QString &t) const {
    switch (m_sort) {
    case SortField::Author: return " ORDER BY " + t + "author, " + t + "title";
    case SortField::Publisher: return " ORDER BY " + t + "publisher, " + t + "title";
    case SortField::Category: return " ORDER BY " + t + "category, " + t + "title";
    case SortField::Recent: return " ORDER BY " + t + "last_read_at DESC, " + t + "id DESC";
    // 裁定：added_at DESC（最近添加在前），id DESC 兜底保证同毫秒时间戳下排序稳定
    default: return " ORDER BY " + t + "added_at DESC, " + t + "id DESC";
    }
}

void BookManager::setProgress(qint64 id, double progress) {
    QSqlQuery q(m_db);
    q.prepare("UPDATE books SET progress=?, last_read_at=? WHERE id=?");
    q.addBindValue(progress);
    q.addBindValue(QDateTime::currentDateTime().toString(Qt::ISODate));
    q.addBindValue(id);
    if (q.exec()) emit booksChanged();
}

void BookManager::addReadSeconds(qint64 id, qint64 seconds) {
    QSqlQuery q(m_db);
    q.prepare("UPDATE books SET read_seconds=read_seconds+? WHERE id=?");
    q.addBindValue(seconds);
    q.addBindValue(id);
    if (q.exec()) emit booksChanged();
}

void BookManager::setSort(SortField field) { m_sort = field; }

// ---- QML 封装 ----

QVariantList BookManager::booksModel() const {
    const QVector<Book> list = m_searchQuery.isEmpty() ? books() : search(m_searchQuery);
    QVariantList out;
    out.reserve(list.size());
    for (const Book &b : list) {
        QVariantMap m;
        m.insert("id", b.id);
        m.insert("title", b.title);
        m.insert("author", b.author);
        m.insert("publisher", b.publisher);
        m.insert("category", b.category);
        m.insert("format", b.format);
        m.insert("path", b.path);
        m.insert("cover", b.cover);
        m.insert("progress", b.progress);
        m.insert("readSeconds", b.readSeconds);
        m.insert("lastReadAt", b.lastReadAt);
        m.insert("addedAt", b.addedAt);
        out.append(m);
    }
    return out;
}

QVariantList BookManager::categoriesModel() const {
    // 分类来源为书籍实际填写的分类值（导入时 category 恒空，A8 补分类编辑入口后生效）；
    // categories 表是独立维护的字典（addCategory/removeCategory），UI 分类栏以书籍分类为准。
    QVariantList out;
    QSqlQuery q(m_db);
    q.exec("SELECT DISTINCT category FROM books WHERE category != '' ORDER BY category");
    while (q.next()) out.append(q.value(0).toString());
    return out;
}

void BookManager::setSort(int index) {
    switch (index) {
    case 0: m_sort = SortField::Added; break;
    case 1: m_sort = SortField::Author; break;
    case 2: m_sort = SortField::Publisher; break;
    case 3: m_sort = SortField::Category; break;
    default: m_sort = SortField::Recent; break;
    }
    emit booksChanged();
}

void BookManager::setFilter(const QString &category) {
    m_filter = category;
    emit booksChanged();
}

void BookManager::doSearch(const QString &query) {
    m_searchQuery = query;
    emit booksChanged();
}

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
    if (q.exec()) emit booksChanged();
}

void BookManager::removeCategory(const QString &name) {
    QSqlQuery q(m_db);
    q.prepare("DELETE FROM categories WHERE name=?");
    q.addBindValue(name);
    if (q.exec()) emit booksChanged();
}
