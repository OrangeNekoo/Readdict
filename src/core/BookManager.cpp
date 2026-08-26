#include "BookManager.h"
#include "DatabaseManager.h"
#include "parsers/ParserFactory.h"
#include "SettingsStore.h"
#include <QSqlQuery>
#include <QSqlError>
#include <QVariant>
#include <QDateTime>
#include <QDebug>
#include <QFontDatabase>
#include <QJsonValue>
#include <QSet>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonArray>
BookManager::BookManager(const QString &dbPath, const QString &connection, QObject *parent)
    : QObject(parent) {
    DatabaseManager dbm(dbPath, connection);
    m_db = dbm.database();
}

qint64 BookManager::addBook(const Book &b) {
    const bool inTx = m_db.transaction(); // 失败则退回自动提交，写入仍会执行
    QSqlQuery q(m_db);
    q.prepare("INSERT INTO books(title,author,publisher,category,format,path,cover,progress,added_at,page_count)"
              " VALUES(?,?,?,?,?,?,?,?,?,?)");
    q.addBindValue(b.title); q.addBindValue(b.author); q.addBindValue(b.publisher);
    q.addBindValue(b.category); q.addBindValue(b.format); q.addBindValue(b.path);
    q.addBindValue(b.cover); q.addBindValue(b.progress);
    q.addBindValue(QDateTime::currentDateTime().toString(Qt::ISODate));
    q.addBindValue(b.pageCount);
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
    // L9（P2#27）：级联清理——删书同时清本书划线，避免 highlights 残留孤儿行
    //（笔记页/划线渲染按 book_id 查表，书没了行还在，重导入同 id 时串线）
    QSqlQuery h(m_db);
    h.prepare("DELETE FROM highlights WHERE book_id=?");
    h.addBindValue(id);
    if (!h.exec())
        qWarning() << "removeBook: 划线清理失败:" << h.lastError().text();
    // 页缓存级联清理：book_page_cache 按 book_id 关联，删书不清则残留孤儿行
    QSqlQuery pc(m_db);
    pc.prepare("DELETE FROM book_page_cache WHERE book_id=?");
    pc.addBindValue(id);
    if (!pc.exec())
        qWarning() << "removeBook: book_page_cache 清理失败:" << pc.lastError().text();
    // L9（P2#27）：阅读进度键残留清理——progress/<id>（章节索引）与
    // progress/scroll_<id>（滚动偏移）。键按 bookId 命名，删书不清则永久残留；
    // 自增 id 不复用，不会串扰，但 settings.json 只增不减
    if (m_settings) {
        m_settings->removeValue(QStringLiteral("progress/%1").arg(id));
        m_settings->removeValue(QStringLiteral("progress/scroll_%1").arg(id));
    }
    // 同步清理 FTS 索引，避免残留条目（search 的 JOIN 本可掩盖，仍保持索引干净）。
    QSqlQuery f(m_db);
    f.prepare("DELETE FROM books_fts WHERE rowid=?");
    f.addBindValue(id);
    if (!f.exec())
        qWarning() << "removeBook: books_fts 索引清理失败:" << f.lastError().text();
    // C8：全文索引（fts_content）由 SearchEngine 按需创建；表不存在时（未索引过
    // 任何书，如仅测试 BookManager 的场景）静默跳过，保持删除路径一致。
    QSqlQuery has(m_db);
    has.exec("SELECT 1 FROM sqlite_master WHERE name='fts_content'");
    if (has.next()) {
        QSqlQuery fts(m_db);
        fts.prepare("DELETE FROM fts_content WHERE book_id=?");
        fts.addBindValue(id);
        if (!fts.exec())
            qWarning() << "removeBook: 全文索引清理失败:" << fts.lastError().text();
    }
    m_docCache.remove(id); // 阅读器文档缓存一并失效
    m_docError.remove(id); // 解析错误缓存同步失效
    m_chapterCounts.remove(id); // L6：总章数缓存同步失效
    m_lastPos.remove(id);       // L6：位置变化写记忆同步失效
    emit booksChanged();
}

void BookManager::removeBookWithFiles(qint64 id, bool deleteFiles) {
    QString path, cover;
    if (deleteFiles) {
        QSqlQuery q(m_db);
        q.prepare("SELECT path, cover FROM books WHERE id=?");
        q.addBindValue(id);
        if (q.exec() && q.next()) {
            path = q.value(0).toString();
            cover = q.value(1).toString();
        }
    }
    removeBook(id);
    if (!deleteFiles) return;
    // 真实封面命名 cover_<md5>.png（B7）；占位封面 <hash6>.png 按书名哈希共享（A5），
    // 同书名多本书共用，删它会影响其他书——只删真实封面。
    if (!path.isEmpty())
        QFile::remove(path);
    if (!cover.isEmpty() && QFileInfo(cover).fileName().startsWith("cover_"))
        QFile::remove(cover);
}

void BookManager::updateCover(qint64 id, const QString &cover) {
    QSqlQuery q(m_db);
    q.prepare("UPDATE books SET cover=? WHERE id=?");
    q.addBindValue(cover);
    q.addBindValue(id);
    if (!q.exec()) {
        qWarning() << "updateCover 失败:" << q.lastError().text();
        return;
    }
    emit booksChanged();
}

QVector<Book> BookManager::selectBooks(const QString &where, const QString &order) const {
    QVector<Book> out;
    QSqlQuery q(m_db);
    q.exec("SELECT id,title,author,publisher,category,format,path,cover,progress,read_seconds,last_read_at,added_at,page_count"
           " FROM books " + where + " " + order);
    while (q.next()) {
        Book b;
        b.id = q.value(0).toLongLong(); b.title = q.value(1).toString();
        b.author = q.value(2).toString(); b.publisher = q.value(3).toString();
        b.category = q.value(4).toString(); b.format = q.value(5).toString();
        b.path = q.value(6).toString(); b.cover = q.value(7).toString();
        b.progress = q.value(8).toDouble(); b.readSeconds = q.value(9).toLongLong();
        b.lastReadAt = q.value(10).toString(); b.addedAt = q.value(11).toString();
        b.pageCount = q.value(12).toInt();
        out.append(b);
    }
    return out;
}

Book BookManager::bookById(qint64 id) const {
    QSqlQuery q(m_db);
    q.prepare("SELECT id,title,author,publisher,category,format,path,cover,progress,read_seconds,last_read_at,added_at,page_count"
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
    b.pageCount = q.value(12).toInt();
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
        b.pageCount = q.value(12).toInt();   // 在 b.addedAt = q.value(11) 之后追加
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

void BookManager::reportProgress(qint64 id, int ch1, int total) {
    // L6（P1#13）：进度取 max 不 regress——回翻章节只刷 last_read_at，不动 progress，
    // 书架模型仍不重建；readingActivityChanged 让主页更新最近阅读排序和统计。
    if (total <= 0) return;
    const double p = double(ch1) / total;
    QSqlQuery q(m_db);
    q.prepare("SELECT progress FROM books WHERE id=?");
    q.addBindValue(id);
    double old = 0;
    if (q.exec() && q.next()) old = q.value(0).toDouble();
    QSqlQuery up(m_db);
    if (p > old) {
        up.prepare("UPDATE books SET progress=?, last_read_at=? WHERE id=?");
        up.addBindValue(p);
    } else {
        up.prepare("UPDATE books SET last_read_at=? WHERE id=?"); // 位置变化不 regress 进度
        up.addBindValue(QDateTime::currentDateTime().toString(Qt::ISODate));
        up.addBindValue(id);
        if (!up.exec()) return;
        emit readingActivityChanged();
        return; // 进度未变：不 emit booksChanged（避免书架模型重建，P1#13）
    }
    up.addBindValue(QDateTime::currentDateTime().toString(Qt::ISODate));
    up.addBindValue(id);
    if (up.exec()) emit booksChanged();
}

void BookManager::addReadSeconds(qint64 id, qint64 seconds) {
    if (seconds <= 0) return;
    QSqlQuery q(m_db);
    q.prepare("UPDATE books SET read_seconds=read_seconds+? WHERE id=?");
    q.addBindValue(seconds);
    q.addBindValue(id);
    if (q.exec()) emit booksChanged();
}

void BookManager::savePosition(qint64 bookId, int chapter, double scrollY) {
    if (!m_settings) return;
    // L6（P1#16）：变化写——(chapter, scrollY) 与上次相同直接跳过（阅读页 5s 定时 +
    // 退出补写高频触发，无变化不落盘不触发 SettingsStore 原子写）
    const auto it = m_lastPos.constFind(bookId);
    if (it != m_lastPos.constEnd() && it->first == chapter && it->second == scrollY)
        return;
    m_lastPos.insert(bookId, qMakePair(chapter, scrollY));
    m_settings->setValue(QStringLiteral("progress/%1").arg(bookId), chapter);
    m_settings->setValue(QStringLiteral("progress/scroll_%1").arg(bookId), scrollY);
}

double BookManager::lastScrollY(qint64 bookId) const {
    if (!m_settings) return 0;
    return m_settings->value(QStringLiteral("progress/scroll_%1").arg(bookId)).toDouble();
}

void BookManager::startTracking(qint64 bookId) {
    if (m_trackBookId && m_trackBookId != bookId)
        stopTracking(); // 切换阅读书：先结算上一本
    m_trackBookId = bookId;
    m_trackTimer.restart();
}

void BookManager::stopTracking() {
    if (!m_trackBookId) return;
    addReadSeconds(m_trackBookId, m_trackTimer.elapsed() / 1000);
    m_trackBookId = 0;
}

void BookManager::setSort(SortField field) { m_sort = field; }

// ---- QML 封装 ----

QVariantList BookManager::booksModel() const {
    const QVector<Book> list = m_searchQuery.isEmpty() ? books() : search(m_searchQuery);
    QVariantList out;
    out.reserve(list.size());
    for (const Book &b : list) out.append(bookToMap(b));
    return out;
}

QVariantList BookManager::recentBooks(int limit) const {
    // U1：只收有进度（progress>0）且有阅读记录的书，last_read_at DESC（id DESC 兜底）
    const QVector<Book> list = selectBooks("WHERE progress > 0 AND last_read_at IS NOT NULL",
                                           " ORDER BY last_read_at DESC, id DESC");
    QVariantList out;
    for (int i = 0; i < list.size() && out.size() < limit; ++i)
        out.append(bookToMap(list.at(i)));
    return out;
}

QVariantMap BookManager::bookToMap(const Book &b) {
    // L6：单书 → QML map 的唯一构造源（booksModel 逐行 / bookByIdModel 单行共用）
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
    m.insert("pageCount", b.pageCount);
    return m;
}

QVariantMap BookManager::bookByIdModel(qint64 id) const {
    // L6（P0#7）：全库单书查询——绕过 books()/search() 的 filter/search 条件，
    // 全文搜索结果跳转时目标书可能不在当前过滤后的书架中，仍能取到完整字段。
    // 书不存在返回空 map（QML 侧按 m.id === undefined 判 null，见 ShelfPage）
    const Book b = bookById(id);
    if (b.id < 0) return QVariantMap();
    return bookToMap(b);
}

QVariantList BookManager::categoriesModel() const {
    // 分类来源为书籍实际填写的分类值（导入时 category 恒空，A8 补分类编辑入口后生效）；
    // UI 分类栏以书籍分类为准（categories 表独立字典，无读写入口，已移除）。
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

void BookManager::setCategory(qint64 bookId, const QString &category) {
    QSqlQuery q(m_db);
    q.prepare("UPDATE books SET category=? WHERE id=?");
    q.addBindValue(category);
    q.addBindValue(bookId);
    if (q.exec()) emit booksChanged();
}

void BookManager::setPageCount(qint64 id, int count) {
    QSqlQuery q(m_db);
    q.prepare("UPDATE books SET page_count=? WHERE id=?");
    q.addBindValue(count);
    q.addBindValue(id);
    if (!q.exec()) qWarning() << "setPageCount 失败:" << q.lastError().text();
}

QVariantMap BookManager::loadBookPageCache(qint64 bookId, const QString &signature) {
    QVariantMap out;
    QSqlQuery q(m_db);
    q.prepare("SELECT total, pages FROM book_page_cache WHERE book_id=? AND signature=?");
    q.addBindValue(bookId);
    q.addBindValue(signature);
    if (!q.exec() || !q.next()) return out;
    out.insert("total", q.value(0).toInt());
    const QJsonDocument doc = QJsonDocument::fromJson(q.value(1).toString().toUtf8());
    if (doc.isArray()) {
        QVariantList pages;
        const QJsonArray arr = doc.array();
        for (const QJsonValue &v : arr) pages.append(v.toInt());
        out.insert("pages", pages);
    }
    return out;
}

void BookManager::saveBookPageCache(qint64 bookId, const QString &signature,
                                    int total, const QVariantList &pages) {
    QJsonArray arr;
    for (const QVariant &p : pages) arr.append(p.toInt());
    const QString json = QString::fromUtf8(QJsonDocument(arr).toJson(QJsonDocument::Compact));
    QSqlQuery q(m_db);
    q.prepare("INSERT OR REPLACE INTO book_page_cache(book_id,signature,total,pages,updated_at)"
              " VALUES(?,?,?,?,?)");
    q.addBindValue(bookId);
    q.addBindValue(signature);
    q.addBindValue(total);
    q.addBindValue(json);
    q.addBindValue(QDateTime::currentDateTime().toString(Qt::ISODate));
    if (!q.exec()) qWarning() << "saveBookPageCache 失败:" << q.lastError().text();
}

void BookManager::clearBookPageCache(qint64 bookId) {
    QSqlQuery q(m_db);
    q.prepare("DELETE FROM book_page_cache WHERE book_id=?");
    q.addBindValue(bookId);
    if (!q.exec())
        qWarning() << "clearBookPageCache 失败:" << q.lastError().text();
}

void BookManager::doSearch(const QString &query) {
    m_searchQuery = query;
    emit booksChanged();
}

QVariantMap BookManager::stats() const {
    // D4：阅读统计。聚合查询 COUNT/SUM/AVG：COUNT 恒有值，SUM/AVG 空库时为 NULL，
    // COALESCE 兜底归零（QML 侧无需判空）。分类分布按书籍实际分类 GROUP BY，
    // 未分类（category=''）一并计入（QML 显示为"未分类"），保证计数与总藏书一致。
    QVariantMap out;
    QSqlQuery q(m_db);
    q.exec("SELECT COUNT(*), COALESCE(SUM(read_seconds),0), COALESCE(AVG(progress),0) FROM books");
    if (q.next()) {
        out.insert("totalBooks", q.value(0).toLongLong());
        out.insert("totalReadSeconds", q.value(1).toLongLong());
        out.insert("totalProgress", q.value(2).toDouble());
    } else {
        out.insert("totalBooks", 0);
        out.insert("totalReadSeconds", 0);
        out.insert("totalProgress", 0.0);
    }
    QVariantList byCategory;
    QSqlQuery c(m_db);
    c.exec("SELECT category, COUNT(*) FROM books GROUP BY category ORDER BY category");
    while (c.next()) {
        QVariantMap m;
        m.insert("name", c.value(0).toString());
        m.insert("count", c.value(1).toLongLong());
        byCategory.append(m);
    }
    out.insert("byCategory", byCategory);
    return out;
}

// ---- 阅读器接口（B8）----

void BookManager::setSettingsStore(SettingsStore *settings) { m_settings = settings; }

DocumentModel BookManager::documentFor(qint64 bookId) {
    const auto it = m_docCache.constFind(bookId);
    if (it != m_docCache.constEnd()) return it.value();
    DocumentModel doc;
    const Book b = bookById(bookId);
    QString err;
    if (!b.path.isEmpty())
        doc = ParserFactory::parse(b.path, b.format, &err);
    // L4（P0#5）：解析失败（空文档+错误）记录原因，loadChapter 上抛 QML
    if (doc.empty() && !err.isEmpty())
        m_docError.insert(bookId, err);
    m_docCache.insert(bookId, doc);
    return doc;
}

QVariantMap BookManager::paragraphToVariant(const Paragraph &p) {
    QVariantMap m;
    m.insert("text", p.text);
    m.insert("html", p.html);
    m.insert("level", p.level);
    m.insert("imagePath", p.imagePath);
    // C5：逐句朗读/高亮依赖段落句子——QML 侧按 sentences 长度累加出每段起始索引
    QStringList sl;
    sl.reserve(p.sentences.size());
    for (const QString &s : p.sentences) sl.append(s);
    m.insert("sentences", sl);
    return m;
}

QStringList BookManager::uniqueChapterTitles(const DocumentModel &doc) {
    QStringList out;
    out.reserve(doc.chapters.size());
    QSet<QString> used;
    for (int i = 0; i < doc.chapters.size(); ++i) {
        QString t = doc.chapters.at(i).title.trimmed();
        if (t.isEmpty() || used.contains(t)) {
            // 空/重复标题 → "第N章"（对齐 EpubParser/MobiParser 解析器行为）；
            // 序号递增直至未占用，避免与字面 "第N章" 标题（前章 h2）撞名
            int n = i + 1;
            do { t = QStringLiteral("第%1章").arg(n++); } while (used.contains(t));
        }
        used.insert(t);
        out.append(t);
    }
    return out;
}

QVariantList BookManager::chapterTitles(qint64 bookId) {
    m_activeBookId = bookId;
    const DocumentModel doc = documentFor(bookId);
    m_chapterCounts[bookId] = doc.chapters.size(); // L6（P1#14）：解析即刷新总章数缓存
    const QStringList titles = uniqueChapterTitles(doc);
    QVariantList out;
    out.reserve(titles.size());
    for (const QString &t : titles) out.append(t);
    return out;
}

QVariant BookManager::loadChapter(qint64 bookId, int index) {
    m_activeBookId = bookId;
    const DocumentModel doc = documentFor(bookId);
    m_chapterCounts[bookId] = doc.chapters.size(); // L6（P1#14）：解析即刷新总章数缓存
    // L4（P0#5）：空文档且解析报错 → 上抛错误信息（QML 错误页）；
    // 空文档且无错误（如零章 TXT）维持旧行为返回空 map
    if (doc.empty() && m_docError.value(bookId).isEmpty() == false) {
        QVariantMap out;
        out.insert("error", m_docError.value(bookId));
        return out;
    }
    QVariantMap out;
    if (index < 0 || index >= doc.chapters.size()) return out;
    const QStringList titles = uniqueChapterTitles(doc);
    const Chapter &c = doc.chapters.at(index);
    out.insert("title", titles.at(index));
    QVariantList paras;
    paras.reserve(c.paragraphs.size());
    for (const Paragraph &p : c.paragraphs) paras.append(paragraphToVariant(p));
    out.insert("paragraphs", paras);
    // L6（P1#13）：进度上报移出 loadChapter——换章不直接写 books.progress，
    // 改由阅读页章节加载成功后显式 Books.reportProgress（取 max 不 regress）
    return out;
}

int BookManager::chapterCount(qint64 bookId) {
    // L6（P1#14）：优先命中缓存（chapterTitles/loadChapter 已解析过本书）；
    // 无缓存时按需 documentFor 计算（documentFor 自带解析缓存，不重复解盘）
    const auto it = m_chapterCounts.constFind(bookId);
    if (it != m_chapterCounts.constEnd()) return it.value();
    const DocumentModel doc = documentFor(bookId);
    m_chapterCounts.insert(bookId, doc.chapters.size());
    return doc.chapters.size();
}

int BookManager::lastChapter(qint64 bookId) {
    if (!m_settings) return 0;
    return m_settings->value(QStringLiteral("progress/%1").arg(bookId)).toInt();
}

int BookManager::currentChapter() const { return m_currentChapter; }

void BookManager::setCurrentChapter(int index) {
    if (m_currentChapter == index) return;
    m_currentChapter = index;
    emit currentChapterChanged();
    if (m_settings && m_activeBookId)
        m_settings->setValue(QStringLiteral("progress/%1").arg(m_activeBookId), index);
}

QString BookManager::resolveFontFamily(const QString &preferred) const {
    if (preferred.isEmpty() || QFontDatabase::hasFamily(preferred)) return preferred;
    // D4：得意黑——name 表无中文族名，CoreText 只暴露 "Smiley Sans"；
    // 按 token（得意黑/Smiley*）直接映射，避免落入系统字体兜底
    if (preferred.contains(QStringLiteral("得意"))
        || preferred.contains(QStringLiteral("Smiley"), Qt::CaseInsensitive)) {
        if (QFontDatabase::hasFamily(QStringLiteral("Smiley Sans")))
            return QStringLiteral("Smiley Sans");
        return preferred;
    }
    // D4：思源黑体 HW VF——半宽字形变体，独立字族 "Source Han Sans HW VF"；
    // 须在通用无衬线链之前命中，否则 HW token 会静默回退到非 HW 黑体（字形差异丢失）
    if (preferred.contains(QStringLiteral("HW"), Qt::CaseInsensitive)) {
        const QStringList hw = {
            QStringLiteral("Source Han Sans HW VF"),
            QStringLiteral("Source Han Sans HW SC VF"),
            QStringLiteral("Source Han Sans HW K VF"),
        };
        for (const QString &f : hw)
            if (QFontDatabase::hasFamily(f)) return f;
        // 未命中 HW 族 → 回落通用无衬线链（保底渲染）
    }
    // 思源 VF 字族在 CoreText 下可能只暴露英文族名（name 表含 "Source Han Sans VF" 等），
    // 按首选字体（衬线宋体 / 无衬线黑体）选择对应回退链；全部未命中则返回首选值
    // 交给 Qt 系统字体兜底。C5：默认字体为思源宋体 VF，衬线链不回退到黑体（避免
    // CoreText 只暴露英文族名时衬线默认被悄悄替换成无衬线）。
    const bool serif = preferred.contains(QStringLiteral("宋体"))
                       || preferred.contains(QStringLiteral("Serif"), Qt::CaseInsensitive);
    const QStringList fallbacks = serif
        ? QStringList{
            QStringLiteral("Source Han Serif VF"),
            QStringLiteral("Source Han Serif SC VF"),
            QStringLiteral("Source Han Serif SC"),
            QStringLiteral("思源宋体 VF"),
            QStringLiteral("Songti SC"),
          }
        : QStringList{
            QStringLiteral("Source Han Sans VF"),
            QStringLiteral("Source Han Sans SC VF"),
            QStringLiteral("Source Han Sans SC"),
            QStringLiteral("思源黑体 VF"),
          };
    for (const QString &f : fallbacks)
        if (QFontDatabase::hasFamily(f)) return f;
    return preferred;
}
