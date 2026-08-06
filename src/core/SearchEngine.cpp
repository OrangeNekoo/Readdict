#include "SearchEngine.h"

#include <QAtomicInt>
#include <QDebug>
#include <QRegularExpression>
#include <QSqlError>
#include <QSqlQuery>
#include <QVariant>

namespace {

QAtomicInt g_connCounter;

// CJK 表意/假名/谚文等非 ASCII 字符按单字切分；ASCII 保持整词。
// 用 0x2E80（CJK 部首扩展起点）判定，非 ASCII 一律视为"字级"处理。
bool isCjkLike(QChar c) { return c.unicode() >= 0x2E80; }

// 入库文本：连续 CJK 字符之间以及 CJK↔ASCII 边界插入空格。unicode61 按空白切
// token，中文逐字成 token 后，"关键" 这类句中词才能被拆字 AND 查询命中；
// ASCII 词保持整词（前缀查询 '"key"*' 仍可用），ASCII 内部不插空格。
// 判定：前一字符存在且（当前或前一字符是 CJK）→ 插空格（ASCII-ASCII 除外）。
QString spaceForIndexing(const QString &in) {
    QString out;
    out.reserve(in.size() + in.size() / 2);
    QChar prev(0);
    for (const QChar c : in) {
        const bool cjk = isCjkLike(c);
        if (!out.isEmpty() && (cjk || isCjkLike(prev)))
            out += QLatin1Char(' ');
        out += c;
        prev = c;
    }
    return out;
}

// 用户查询 → FTS5 MATCH 表达式。返回空串表示"无查询"（调用方直接返回空结果）。
QString ftsExpressionFor(const QString &raw) {
    QString q = raw;
    q.remove('"');  // A3 先例：未转义引号截断 MATCH 语法
    q.remove(QRegularExpression(QStringLiteral("[*(){}:^]")));  // FTS5 元字符同害
    q = q.trimmed();
    if (q.isEmpty()) return QString();
    QStringList terms;
    QString asciiRun;
    const auto flushAscii = [&terms, &asciiRun] {
        if (!asciiRun.isEmpty()) {
            terms.append(QStringLiteral("\"%1\"*").arg(asciiRun));
            asciiRun.clear();
        }
    };
    for (const QChar c : q) {
        if (isCjkLike(c)) {
            flushAscii();
            // 标点（，。！？『』：…）经 unicode61 tokenize 后是空 token，
            // 会破坏 MATCH；只保留字母/数字参与拆字 AND
            if (c.isLetterOrNumber())
                terms.append(QStringLiteral("\"%1\"").arg(c));
        } else if (c.isSpace()) {
            flushAscii();
        } else if (c.isLetterOrNumber()) {
            asciiRun += c;
        } else {
            flushAscii();  // ASCII 标点视为词间分隔
        }
    }
    flushAscii();
    return terms.join(QStringLiteral(" AND "));
}

// 摘要：命中词（去引号原文）前后各 20 字；字级 AND 近似命中（词未整段出现）时
// 退化为取开头 40 字。超界侧补省略号。
QString makeSnippet(const QString &text, const QString &term) {
    const int pos = text.indexOf(term);
    const int start = pos >= 0 ? qMax(0, pos - 20) : 0;
    const int len = pos >= 0 ? qMin(term.size() + 40, text.size() - start) : qMin(40, text.size());
    QString s = text.mid(start, len);
    if (start > 0) s.prepend(QChar(0x2026));
    if (start + len < text.size()) s.append(QChar(0x2026));
    return s;
}

} // namespace

SearchEngine::SearchEngine(const QString &dbPath, const QString &connection)
    : QObject(nullptr) {
    const QString conn = connection.isEmpty()
        ? QStringLiteral("readdict_search_%1").arg(g_connCounter.fetchAndAddRelaxed(1))
        : connection;
    m_db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), conn);
    m_db.setDatabaseName(dbPath);
    if (!m_db.open()) {
        qWarning() << "SearchEngine: 打开数据库失败:" << m_db.lastError().text();
        return;
    }
    QSqlQuery q(m_db);
    if (!q.exec(QStringLiteral(
            "CREATE VIRTUAL TABLE IF NOT EXISTS fts_content USING fts5("
            "book_id UNINDEXED, chapter_index UNINDEXED, paragraph_index UNINDEXED,"
            "chapter_title UNINDEXED, text, text_orig UNINDEXED)")))
        qWarning() << "SearchEngine: 创建 fts_content 失败:" << q.lastError().text();
}

SearchEngine::~SearchEngine() {
    if (m_db.isValid()) {
        const QString name = m_db.connectionName();
        m_db.close();
        m_db = QSqlDatabase();
        QSqlDatabase::removeDatabase(name);
    }
}

void SearchEngine::indexBook(qint64 bookId, const QString &chapterTitle,
                             const QStringList &paragraphTexts) {
    // 章节槽位 = 调用序游标。只清理本槽旧行（重复索引同一槽位时替换），
    // 不动其它章节——整书重建由调用方先 removeBook（BookImporter 逐章调用，
    // 若整书 DELETE 会把已索引的其它章节一起清掉）。
    const int chapterIndex = m_chapterCursor.value(bookId, 0);
    QSqlQuery del(m_db);
    del.prepare(QStringLiteral("DELETE FROM fts_content WHERE book_id=? AND chapter_index=?"));
    del.addBindValue(bookId);
    del.addBindValue(chapterIndex);
    if (!del.exec())
        qWarning() << "SearchEngine::indexBook: 清理旧索引失败:" << del.lastError().text();
    // 空章节也占一个槽位（章节索引与解析器章节序对齐），先推进游标
    m_chapterCursor.insert(bookId, chapterIndex + 1);
    if (paragraphTexts.isEmpty()) return;
    const bool inTx = m_db.transaction();
    QSqlQuery ins(m_db);
    ins.prepare(QStringLiteral("INSERT INTO fts_content"
                               "(book_id, chapter_index, paragraph_index, chapter_title, text, text_orig)"
                               " VALUES(?,?,?,?,?,?)"));
    for (int i = 0; i < paragraphTexts.size(); ++i) {
        const QString &t = paragraphTexts.at(i);
        ins.addBindValue(bookId);
        ins.addBindValue(chapterIndex);
        ins.addBindValue(i);
        ins.addBindValue(chapterTitle);
        ins.addBindValue(spaceForIndexing(t));
        ins.addBindValue(t);
        if (!ins.exec()) {
            qWarning() << "SearchEngine::indexBook: 写入索引失败:" << ins.lastError().text();
            if (inTx) m_db.rollback();
            return;
        }
    }
    if (inTx) m_db.commit();
}

void SearchEngine::removeBook(qint64 bookId) {
    QSqlQuery q(m_db);
    q.prepare(QStringLiteral("DELETE FROM fts_content WHERE book_id=?"));
    q.addBindValue(bookId);
    if (!q.exec())
        qWarning() << "SearchEngine::removeBook: 清理索引失败:" << q.lastError().text();
    m_chapterCursor.remove(bookId);  // 复位章节游标，重索引用新 id 从第 0 章开始
}

QVector<SearchHit> SearchEngine::search(qint64 bookId, const QString &query) const {
    return runQuery(query, QStringLiteral(" AND book_id=?"), QVariantList{bookId});
}

QVector<SearchHit> SearchEngine::searchAll(const QString &query) const {
    return runQuery(query, QString(), QVariantList());
}

QVector<SearchHit> SearchEngine::runQuery(const QString &query, const QString &extraWhere,
                                          const QVariantList &extraBinds) const {
    QVector<SearchHit> out;
    const QString expr = ftsExpressionFor(query);
    if (expr.isEmpty()) return out;
    QSqlQuery q(m_db);
    q.prepare(QStringLiteral("SELECT book_id, chapter_index, paragraph_index, chapter_title, text_orig"
                             " FROM fts_content WHERE fts_content MATCH ?") + extraWhere +
              QStringLiteral(" ORDER BY rank LIMIT 200"));
    q.addBindValue(expr);
    for (const QVariant &v : extraBinds) q.addBindValue(v);
    if (!q.exec()) return out;  // 语法错误已被清理层排除；失败即无结果
    // 与 ftsExpressionFor 同一清理口径：snippet 用剔除引号/元字符后的原文定位命中词
    QString term = query;
    term.remove('"');
    term.remove(QRegularExpression(QStringLiteral("[*(){}:^]")));
    while (q.next()) {
        SearchHit h;
        h.bookId = q.value(0).toLongLong();
        h.chapterIndex = q.value(1).toInt();
        h.paragraphIndex = q.value(2).toInt();
        h.chapterTitle = q.value(3).toString();
        h.snippet = makeSnippet(q.value(4).toString(), term);
        out.append(h);
    }
    return out;
}

QVariantList SearchEngine::searchModel(qint64 bookId, const QString &query) {
    return hitsToModel(search(bookId, query));
}

QVariantList SearchEngine::searchAllModel(const QString &query) {
    return hitsToModel(searchAll(query));
}

QVariantList SearchEngine::hitsToModel(const QVector<SearchHit> &hits) {
    QVariantList out;
    out.reserve(hits.size());
    for (const SearchHit &h : hits) {
        QVariantMap m;
        m.insert(QStringLiteral("bookId"), h.bookId);
        m.insert(QStringLiteral("chapterIndex"), h.chapterIndex);
        m.insert(QStringLiteral("paragraphIndex"), h.paragraphIndex);
        m.insert(QStringLiteral("chapterTitle"), h.chapterTitle);
        m.insert(QStringLiteral("snippet"), h.snippet);
        out.append(m);
    }
    return out;
}
