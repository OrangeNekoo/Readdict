#include "HighlightManager.h"
#include "DatabaseManager.h"
#include <QSqlQuery>
#include <QSqlError>
#include <QDateTime>
#include <QDebug>

HighlightManager::HighlightManager(const QString &dbPath, QObject *parent)
    : QObject(parent) {
    // 复用 DatabaseManager 打开连接（schema 含 highlights 表，见 A2）；与 BookManager 同模式
    DatabaseManager dbm(dbPath);
    m_db = dbm.database();
}

qint64 HighlightManager::addHighlight(qint64 bookId, const QString &chapter, int sentenceIndex,
                                      const QString &text, const QString &color, const QString &note) {
    QSqlQuery q(m_db);
    q.prepare("INSERT INTO highlights(book_id,chapter,sentence_index,text,color,note,created_at)"
              " VALUES(?,?,?,?,?,?,?)");
    q.addBindValue(bookId);
    q.addBindValue(chapter);
    q.addBindValue(sentenceIndex);
    q.addBindValue(text);
    q.addBindValue(color);
    q.addBindValue(note);
    q.addBindValue(QDateTime::currentDateTime().toString(Qt::ISODate));
    if (!q.exec()) {
        qWarning() << "addHighlight:" << q.lastError().text();
        return -1;
    }
    const qint64 id = q.lastInsertId().toLongLong();
    emit highlightsChanged(bookId);
    return id;
}

void HighlightManager::removeHighlight(qint64 id) {
    // 先取 book_id 供信号携带（接口只给 id，信号需要 bookId）；查不到则无事可做
    QSqlQuery sel(m_db);
    sel.prepare("SELECT book_id FROM highlights WHERE id=?");
    sel.addBindValue(id);
    if (!sel.exec() || !sel.next())
        return;
    const qint64 bookId = sel.value(0).toLongLong();
    QSqlQuery del(m_db);
    del.prepare("DELETE FROM highlights WHERE id=?");
    del.addBindValue(id);
    if (!del.exec()) {
        qWarning() << "removeHighlight:" << del.lastError().text();
        return;
    }
    emit highlightsChanged(bookId);
}

void HighlightManager::updateNote(qint64 id, const QString &note) {
    QSqlQuery sel(m_db);
    sel.prepare("SELECT book_id FROM highlights WHERE id=?");
    sel.addBindValue(id);
    if (!sel.exec() || !sel.next())
        return;
    const qint64 bookId = sel.value(0).toLongLong();
    QSqlQuery upd(m_db);
    upd.prepare("UPDATE highlights SET note=? WHERE id=?");
    upd.addBindValue(note);
    upd.addBindValue(id);
    if (!upd.exec()) {
        qWarning() << "updateNote:" << upd.lastError().text();
        return;
    }
    emit highlightsChanged(bookId);
}

QVector<Highlight> HighlightManager::highlightsForBook(qint64 bookId) const {
    QVector<Highlight> out;
    QSqlQuery q(m_db);
    // sentence_index, id 双序保证阅读顺序稳定（NULL 在 SQLite 中排最前，无影响）
    q.prepare("SELECT id,book_id,chapter,sentence_index,text,color,note"
              " FROM highlights WHERE book_id=? ORDER BY sentence_index, id");
    q.addBindValue(bookId);
    if (!q.exec()) {
        qWarning() << "highlightsForBook:" << q.lastError().text();
        return out;
    }
    while (q.next()) {
        Highlight h;
        h.id = q.value(0).toLongLong();
        h.bookId = q.value(1).toLongLong();
        h.chapter = q.value(2).toString();
        h.sentenceIndex = q.value(3).toInt();
        h.text = q.value(4).toString();
        h.color = q.value(5).toString();
        h.note = q.value(6).toString();
        out.append(h);
    }
    return out;
}
