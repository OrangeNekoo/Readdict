#pragma once
#include <QHash>
#include <QObject>
#include <QPair>
#include <QSqlDatabase>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVector>

// C8：FTS5 全文搜索。
//
// 单表方案：所有书共用一个 FTS5 虚拟表 fts_content（对比简报的"每本书一张
// fts_book_<id> 表"）。理由：schema 单一、searchAll 免 UNION ALL 多表遍历、
// removeBook 免 DROP 建表、表名注入问题从根上消失；代价是 book_id 过滤在
// MATCH 结果集上做（UNINDEXED 列），量级对本地书库无感。简报允许二选一。
//
// CJK 处理：SQLite unicode61 把连续中文当单个 token，"包含关键词的段落" 无法被
// '"关键词"*' 前缀命中。入库前（spaceForIndexing）在 CJK 字符与 ASCII 词之间插入
// 空格（中文逐字成 token），search 对含中文的查询拆成逐字 AND（'"关" AND "键" AND
// "词"'），句中任意位置的关键词都能命中；纯 ASCII 词保持 '"word"*' 前缀。
//
// 引号/元字符清理：MATCH 中未转义的 '"' 与 FTS5 元字符（* ( ) { } : ^）会截断
// 语法导致 q.exec 静默失败，查询前统一剔除（A3 修复先例）。
struct SearchHit {
    qint64 bookId;
    int chapterIndex;
    int paragraphIndex;
    QString chapterTitle;  // 索引时传入的章节标题（展示用；跳转以 chapterIndex 为准）
    QString snippet;       // 命中词前后各 20 字，超界补省略号
};

class SearchEngine : public QObject {
    Q_OBJECT
public:
    // connection 为空时自动生成唯一连接名（每个实例独占一个 SQLite 连接；
    // 同进程多实例共享同一 db 文件时互不干扰）；指定时复用固定名（QML 单例）。
    explicit SearchEngine(const QString &dbPath, const QString &connection = QString());
    ~SearchEngine() override;

    // 原子整书重建：清空该书 + 全部章节在**单个事务**内写入，中途失败整体回滚
    // （不留部分索引，isBookIndexed 仍可作完整性判据，下次可安全重试）。
    // chapters 元素为 (章节标题, 段落文本列表)，章节索引按列表序。
    // 空章节也占用一个槽位（章节索引与解析器章节序对齐）。
    void rebuildBook(qint64 bookId, const QVector<QPair<QString, QStringList>> &chapters);
    // 清空一书的全部索引（删除书时调用）
    void removeBook(qint64 bookId);
    // 该书是否已有索引行（存量书回填检查用；空文档书无行，会被反复重试）
    bool isBookIndexed(qint64 bookId) const;
    QVector<SearchHit> search(qint64 bookId, const QString &query) const;
    QVector<SearchHit> searchAll(const QString &query) const;

    // ---- QML 可见封装 ----
    Q_INVOKABLE QVariantList searchModel(qint64 bookId, const QString &query);
    Q_INVOKABLE QVariantList searchAllModel(const QString &query);

private:
    QVector<SearchHit> runQuery(const QString &query, const QString &extraWhere,
                                const QVariantList &extraBinds) const;
    static QVariantList hitsToModel(const QVector<SearchHit> &hits);
    QSqlDatabase m_db;
};
