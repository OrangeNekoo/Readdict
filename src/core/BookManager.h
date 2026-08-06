#pragma once
#include "Book.h"
#include "parsers/DocumentModel.h"
#include <QElapsedTimer>
#include <QHash>
#include <QObject>
#include <QSqlDatabase>
#include <QStringList>
#include <QVariantList>
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
    QVector<Book> books() const;
    Book bookById(qint64 id) const;
    Q_INVOKABLE void setProgress(qint64 id, double progress);
    void addReadSeconds(qint64 id, qint64 seconds);
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
    QStringList categories() const;
    void addCategory(const QString &name);
    void removeCategory(const QString &name);
    // ---- QML 可见封装 ----
    QVariantList booksModel() const;
    QVariantList categoriesModel() const;
    Q_INVOKABLE void setSort(int index); // 0 Added 1 Author 2 Publisher 3 Category 4 Recent
    Q_INVOKABLE void setFilter(const QString &category);
    Q_INVOKABLE void setCategory(qint64 bookId, const QString &category);
    Q_INVOKABLE void doSearch(const QString &query);
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
    qint64 m_activeBookId = 0;   // 最近打开的阅读书（currentChapter 持久化目标）
    int m_currentChapter = 0;
    QElapsedTimer m_trackTimer;  // 阅读计时：startTracking 启动，stopTracking 结算
    qint64 m_trackBookId = 0;    // 正在计时的书（0 = 未在计时）
};
