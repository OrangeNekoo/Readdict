#pragma once
#include <QString>

struct Book {
    qint64 id = -1;
    QString title, author, publisher, category, format, path, cover;
    double progress = 0.0;
    int pageCount = 0;                 // PDF 固定页数；非 PDF 恒 0
    qint64 readSeconds = 0;
    QString lastReadAt, addedAt;
};

enum class SortField { Added, Author, Publisher, Category, Recent };
