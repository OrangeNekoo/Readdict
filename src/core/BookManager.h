#pragma once
#include "Book.h"
#include <QObject>
#include <QSqlDatabase>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QVector>

class BookManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList booksModel READ booksModel NOTIFY booksChanged)
    Q_PROPERTY(QVariantList categoriesModel READ categoriesModel NOTIFY booksChanged)
public:
    // connection：SQLite 连接名，默认 readdict_main；主程序 importer 内部实例用独立连接名
    explicit BookManager(const QString &dbPath, const QString &connection = "readdict_main", QObject *parent = nullptr);
    qint64 addBook(const Book &book);
    void removeBook(qint64 id);
    QVector<Book> books() const;
    Book bookById(qint64 id) const;
    void setProgress(qint64 id, double progress);
    void addReadSeconds(qint64 id, qint64 seconds);
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
    Q_INVOKABLE void doSearch(const QString &query);
signals:
    void booksChanged();
private:
    QVector<Book> selectBooks(const QString &where, const QString &order) const;
    // 与 m_sort 对应的 ORDER BY 子句（books/search 共用单一来源）；t 为列名前缀
    // （search 中 JOIN books_fts 后裸列名歧义，须传 "b."），空串用于 books() 单表查询
    QString orderSql(const QString &t = QString()) const;
    QSqlDatabase m_db;
    SortField m_sort = SortField::Added;
    QString m_filter;
    QString m_searchQuery;
};
