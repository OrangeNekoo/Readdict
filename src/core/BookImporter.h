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
    // importedId（可选）：导入成功后回填新书 id（C8：全文索引由导入流程驱动）
    QString importFile(const QString &srcPath, bool moveIntoLibrary, qint64 *importedId = nullptr);
    // C8：为指定书同步建 FTS5 全文索引（解析全书 → SearchEngine 逐章入库）。
    // ":memory:" 库（每连接独立实例）下索引无从共享，直接跳过。
    void indexBook(qint64 bookId);
    // C8 复审：存量书索引回填——遍历书库，对 fts_content 无行的书建索引
    // （功能上线前已入库的书没有全文索引）。逐本经事件循环调度（每本索引后
    // singleShot(0) 让出），UI 在书与书之间保持响应；PDF 无章节模型跳过。
    void backfillMissingIndexes();
    QVector<Book> books() const;
    // 最近一次导入的非致命错误（如 EPUB 解析失败导致封面回退占位）；成功或
    // 无错误时为空串。致命错误仍由 importFile 的返回值表达。
    QString lastError() const { return m_lastError; }
    // QML 导入入口：本地文件 URL → importFile(file, true)；成功发 imported() 由
    // 主程序连接刷新 Books 单例（本实例内部 BookManager 用独立连接名，booksChanged
    // 不会到达 UI 绑定的 Books 单例）；失败发 importFailed(message, fileName) 供 UI 提示。
    Q_INVOKABLE void doImport(const QUrl &url);
    // 刷新全部书籍封面：对 EPUB/PDF 重新提取真实封面（覆盖旧占位封面），
    // 返回成功更新的本数；TXT/MD/FB2/MOBI 无内嵌封面，保留原封面不动。
    Q_INVOKABLE int refreshCovers();
signals:
    void imported();
    void importFailed(const QString &message, const QString &fileName);
private:
    // 回填队列的逐本处理（经 QTimer::singleShot 调度）
    void backfillNext();
    static QString coverPathFor(const QString &title, const QString &destDir);
    QString generatePlaceholderCover(const QString &title, const QString &destDir) const;
    // 从 EPUB 提取封面（OPF cover 声明优先，其次 DocumentModel 首个内嵌图片），
    // 缩放到 300x400 存为 covers/cover_<书文件 md5>.png；失败返回空串。
    QString extractEpubCover(const QString &epubPath, const QString &coverDir);
    // 从 PDF 渲染第 1 页为封面（QPdfDocument），缩放到 300x400 存为
    // covers/cover_<书文件 md5>.png；加载/渲染失败返回空串（回退占位）。
    QString extractPdfCover(const QString &pdfPath, const QString &coverDir);
    QString m_libraryDir;
    QString m_dbPath;
    QString m_lastError;
    class BookManager *m_books;
    QVector<Book> m_backfillQueue;  // 存量书回填队列（逐本出队，空=完成）
};
