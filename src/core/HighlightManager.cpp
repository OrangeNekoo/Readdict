#include "HighlightManager.h"
#include "DatabaseManager.h"
#include <QSqlQuery>
#include <QSqlError>
#include <QDateTime>
#include <QDebug>

HighlightManager::HighlightManager(const QString &dbPath, const QString &connection, QObject *parent)
    : QObject(parent) {
    // 复用 DatabaseManager 打开连接（schema 含 highlights 表，见 A2）；与 BookManager 同模式。
    // 连接名可注入（空则默认 readdict_main）：C7 接线应传独立连接名（如 readdict_highlights），
    // 避免与 Books 单例的 readdict_main 重名（同名 addDatabase 会替换全局连接条目，见 DatabaseManager.h 注释）。
    DatabaseManager dbm(dbPath, connection.isEmpty() ? QStringLiteral("readdict_main") : connection);
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
    if (!sel.exec()) {
        qWarning() << "removeHighlight: 查询划线失败:" << sel.lastError().text();
        return;
    }
    if (!sel.next()) // 行不存在（id 无对应划线）：无变化，静默返回
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
    if (!sel.exec()) {
        qWarning() << "updateNote: 查询划线失败:" << sel.lastError().text();
        return;
    }
    if (!sel.next()) // 行不存在：无变化，静默返回
        return;
    const qint64 bookId = sel.value(0).toLongLong();
    QSqlQuery upd(m_db);
    // D2 复审：created_at 兼作"最后变更时刻"（同步版本时钟取 MAX(created_at)）——
    // 纯 note 编辑必须 bump，否则两端版本不变、sync 恒 Skip，修改永不传播
    upd.prepare("UPDATE highlights SET note=?, created_at=? WHERE id=?");
    upd.addBindValue(note);
    upd.addBindValue(QDateTime::currentDateTime().toString(Qt::ISODate));
    upd.addBindValue(id);
    if (!upd.exec()) {
        qWarning() << "updateNote:" << upd.lastError().text();
        return;
    }
    emit highlightsChanged(bookId);
}

void HighlightManager::updateColor(qint64 id, const QString &color) {
    // 与 updateNote 同模式：先取 book_id 供信号携带，查不到行则无变化静默返回
    QSqlQuery sel(m_db);
    sel.prepare("SELECT book_id FROM highlights WHERE id=?");
    sel.addBindValue(id);
    if (!sel.exec()) {
        qWarning() << "updateColor: 查询划线失败:" << sel.lastError().text();
        return;
    }
    if (!sel.next()) // 行不存在：无变化，静默返回
        return;
    const qint64 bookId = sel.value(0).toLongLong();
    QSqlQuery upd(m_db);
    // D2 复审：同 updateNote——颜色编辑也 bump created_at，同步版本时钟才能感知
    upd.prepare("UPDATE highlights SET color=?, created_at=? WHERE id=?");
    upd.addBindValue(color);
    upd.addBindValue(QDateTime::currentDateTime().toString(Qt::ISODate));
    upd.addBindValue(id);
    if (!upd.exec()) {
        qWarning() << "updateColor:" << upd.lastError().text();
        return;
    }
    emit highlightsChanged(bookId);
}

QVariantList HighlightManager::highlightsForBook(qint64 bookId) const {
    QVariantList out;
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
        QVariantMap m;
        m[QStringLiteral("id")] = q.value(0).toLongLong();
        m[QStringLiteral("bookId")] = q.value(1).toLongLong();
        m[QStringLiteral("chapter")] = q.value(2).toString();
        m[QStringLiteral("sentenceIndex")] = q.value(3).isNull() ? -1 : q.value(3).toInt();
        m[QStringLiteral("text")] = q.value(4).toString();
        m[QStringLiteral("color")] = q.value(5).toString();
        m[QStringLiteral("note")] = q.value(6).toString();
        out.append(m);
    }
    return out;
}
