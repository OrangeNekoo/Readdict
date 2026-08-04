#pragma once
#include "Book.h"
#include <QObject>
#include <QString>
#include <QUrl>
#include <QVector>

class BookImporter : public QObject {
    Q_OBJECT
public:
    explicit BookImporter(const QString &libraryDir, const QString &dbPath, QObject *parent = nullptr);
    ~BookImporter();
    static QString detectFormat(const QString &fileName);
    // 返回空串表示成功，否则为错误信息
    // moveIntoLibrary：当前恒为复制语义（QFile::copy），参数保留供后续启用移动语义
    QString importFile(const QString &srcPath, bool moveIntoLibrary);
    QVector<Book> books() const;
    // QML 导入入口：本地文件 URL → importFile(file, true)；成功发 imported() 由
    // 主程序连接刷新 Books 单例（本实例内部 BookManager 用独立连接名，booksChanged
    // 不会到达 UI 绑定的 Books 单例）。
    Q_INVOKABLE void doImport(const QUrl &url);
signals:
    void imported();
private:
    static QString coverPathFor(const QString &title, const QString &destDir);
    QString generatePlaceholderCover(const QString &title, const QString &destDir) const;
    QString m_libraryDir;
    class BookManager *m_books;
};
