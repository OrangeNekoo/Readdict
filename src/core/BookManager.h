#pragma once
#include "Book.h"
#include "parsers/DocumentModel.h"
#include <QElapsedTimer>
#include <QHash>
#include <QObject>
#include <QSqlDatabase>
#include <QStringList>
#include <QPair>
#include <QVariantMap>
#include <QVector>

class SettingsStore;

class BookManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList booksModel READ booksModel NOTIFY booksChanged)
    Q_PROPERTY(QVariantList categoriesModel READ categoriesModel NOTIFY booksChanged)
    // 阅读器当前章节：写时持久化到 settings.json 的 progress/<bookId>（B8，章节级进度）
    Q_PROPERTY(int currentChapter READ currentChapter WRITE setCurrentChapter NOTIFY currentChapterChanged)
public:
    // connection：SQLite 连接名，默认 readdict_main；主程序 importer 内部实例用独立连接名
    explicit BookManager(const QString &dbPath, const QString &connection = "readdict_main", QObject *parent = nullptr);
    qint64 addBook(const Book &book);
    Q_INVOKABLE void removeBook(qint64 id);
    // 删除书籍并可选删除书库文件（books.path + 真实封面 cover_*.png；占位封面共享不删）
    Q_INVOKABLE void removeBookWithFiles(qint64 id, bool deleteFiles);
    // 更新书籍封面路径（封面刷新/重提取用；成功后发 booksChanged）
    Q_INVOKABLE void updateCover(qint64 id, const QString &cover);
    QVector<Book> books() const;
    Book bookById(qint64 id) const;
    Q_INVOKABLE void setProgress(qint64 id, double progress);
    void addReadSeconds(qint64 id, qint64 seconds);
    // L6（P1#13）：章节进度上报——p=chapterOneBased/totalChapters 只在超过库内进度时
    // 写 progress 并发 booksChanged；否则只刷新 last_read_at（位置变化不让进度回退，
    // 也不重建书架模型）。totalChapters<=0 忽略。
    Q_INVOKABLE void reportProgress(qint64 id, int chapterOneBased, int totalChapters);
    // 阅读页写入进度：章节索引 + 章内滚动偏移（settings.json 的 progress/<bookId> 与 progress/scroll_<bookId>）
    Q_INVOKABLE void savePosition(qint64 bookId, int chapter, double scrollY);
    // 阅读页恢复滚动偏移（无记录返回 0）
    Q_INVOKABLE double lastScrollY(qint64 bookId) const;
    // 阅读计时（B10）：进入阅读页 startTracking，离开/退出 stopTracking 时把
    // 会话内已读秒数累加到 books.read_seconds（QElapsedTimer 实测，不依赖 QML 定时器）。
    Q_INVOKABLE void startTracking(qint64 bookId);
    Q_INVOKABLE void stopTracking();
    void setSort(SortField field);
    QVector<Book> search(const QString &query) const;
    // ---- QML 可见封装 ----
    QVariantList booksModel() const;
    QVariantList categoriesModel() const;
    Q_INVOKABLE void setSort(int index); // 0 Added 1 Author 2 Publisher 3 Category 4 Recent
    Q_INVOKABLE void setFilter(const QString &category);
    Q_INVOKABLE void setCategory(qint64 bookId, const QString &category);
    // L6（P0#7）：按 id 全库查单书（QML 友好 map），不受 filter/search 影响——
    // 全文搜索结果跳转时目标书可能不在当前过滤后的书架模型中
    Q_INVOKABLE QVariantMap bookByIdModel(qint64 id) const;
    // L6（P1#14）：总章数（chapterTitles/loadChapter 解析时刷新的缓存值；
    // 无缓存时按需 documentFor 计算）——chapterProgress 绑定不再每次重算 chapterTitles
    Q_INVOKABLE int chapterCount(qint64 bookId);
    Q_INVOKABLE void doSearch(const QString &query);
    // D4：阅读统计聚合——{totalBooks, totalReadSeconds, totalProgress(平均进度 0..1),
    // byCategory:[{name,count}]}；空库时 COUNT=0、SUM/AVG 的 NULL 归零、byCategory 为空
    Q_INVOKABLE QVariantMap stats() const;
    // ---- 阅读器接口（B8）：文档解析缓存 + 章节/进度/字体族 ----
    void setSettingsStore(SettingsStore *settings);
    Q_INVOKABLE QVariantList chapterTitles(qint64 bookId);
    Q_INVOKABLE QVariant loadChapter(qint64 bookId, int index);
    Q_INVOKABLE int lastChapter(qint64 bookId);
    // 把首选字体族映射到实际已安装的族（思源 VF 在 CoreText 下可能只暴露英文族名）
    Q_INVOKABLE QString resolveFontFamily(const QString &preferred) const;
    int currentChapter() const;
    void setCurrentChapter(int index);
signals:
    void booksChanged();
    void currentChapterChanged();
private:
    QVector<Book> selectBooks(const QString &where, const QString &order) const;
    // 解析并缓存文档（QHash<bookId, DocumentModel>）；清缓存时机见 B10
    DocumentModel documentFor(qint64 bookId);
    static QVariantMap paragraphToVariant(const Paragraph &p);
    // L6：单书 → QML map（booksModel 逐行与 bookByIdModel 共用单一构造源）
    static QVariantMap bookToMap(const Book &b);
    // C7b：章节标题唯一化——划线查重键（"章节标题|句索引"）依赖标题唯一。
    // FB2 无 <title> 的 section 与 TXT 重复 h2 会产出空/重复标题 → 跨章键碰撞
    // （渲染串染、updateColor 误改他章行、笔记跳转恒指首章）。空/重复标题兜底
    // 为 "第N章"（对齐 EpubParser/MobiParser 行为），chapterTitles/loadChapter
    // 共用保证两者一致（划线落库标题与查表标题必须对得上）。
    static QStringList uniqueChapterTitles(const DocumentModel &doc);
    // 与 m_sort 对应的 ORDER BY 子句（books/search 共用单一来源）；t 为列名前缀
    // （search 中 JOIN books_fts 后裸列名歧义，须传 "b."），空串用于 books() 单表查询
    QString orderSql(const QString &t = QString()) const;
    QSqlDatabase m_db;
    SortField m_sort = SortField::Added;
    QString m_filter;
    QString m_searchQuery;
    SettingsStore *m_settings = nullptr;
    QHash<qint64, DocumentModel> m_docCache;
    // L4（P0#5）：解析失败原因缓存（documentFor 空文档且解析器报错时记录），
    // loadChapter 对空文档+错误的书上抛 {error} 供 QML 错误页显示；
    // 空文档无错误（零章 TXT 等）维持旧行为返回空 map
    QHash<qint64, QString> m_docError;
    // L6（P1#14）：总章数缓存——chapterTitles/loadChapter 解析文档后刷新；chapterCount 命中
    QHash<qint64, int> m_chapterCounts;
    // L6（P1#16）：savePosition 变化写记忆——上次 (chapter, scrollY)，相同跳过 settings 写
    QHash<qint64, QPair<int, double>> m_lastPos;
    qint64 m_activeBookId = 0;   // 最近打开的阅读书（currentChapter 持久化目标）
    int m_currentChapter = 0;
    QElapsedTimer m_trackTimer;  // 阅读计时：startTracking 启动，stopTracking 结算
    qint64 m_trackBookId = 0;    // 正在计时的书（0 = 未在计时）
};
