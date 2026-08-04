#pragma once
#include "Book.h"
#include <QString>
#include <QVector>

class BookImporter {
public:
    BookImporter(const QString &libraryDir, const QString &dbPath);
    ~BookImporter();
    static QString detectFormat(const QString &fileName);
    // 返回空串表示成功，否则为错误信息
    QString importFile(const QString &srcPath, bool moveIntoLibrary);
    QVector<Book> books() const;
private:
    QString generatePlaceholderCover(const QString &title, const QString &destDir) const;
    QString m_libraryDir;
    class BookManager *m_books;
};
