#pragma once
#include "Book.h"
#include <QObject>
#include <QSqlDatabase>
#include <QStringList>
#include <QVector>

class BookManager : public QObject {
    Q_OBJECT
public:
    explicit BookManager(const QString &dbPath, QObject *parent = nullptr);
    qint64 addBook(const Book &book);
    void removeBook(qint64 id);
    QVector<Book> books() const;
    Book bookById(qint64 id) const;
    void setProgress(qint64 id, double progress);
    void addReadSeconds(qint64 id, qint64 seconds);
    void setSort(SortField field);
    void setFilter(const QString &category);
    QVector<Book> search(const QString &query) const;
    QStringList categories() const;
    void addCategory(const QString &name);
    void removeCategory(const QString &name);
signals:
    void booksChanged();
private:
    QVector<Book> selectBooks(const QString &where, const QString &order) const;
    QSqlDatabase m_db;
    SortField m_sort = SortField::Added;
    QString m_filter;
};
