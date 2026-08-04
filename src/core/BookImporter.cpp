#include "BookImporter.h"
#include "BookManager.h"
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QPainter>
#include <QFont>
#include <QPixmap>
#include <QCryptographicHash>

BookImporter::BookImporter(const QString &libraryDir, const QString &dbPath)
    : m_libraryDir(libraryDir), m_books(new BookManager(dbPath)) {}

BookImporter::~BookImporter() {
    delete m_books;
}

QString BookImporter::detectFormat(const QString &fileName) {
    const QString ext = QFileInfo(fileName).suffix().toLower();
    if (ext == "epub") return "EPUB";
    if (ext == "pdf") return "PDF";
    if (ext == "mobi") return "MOBI";
    if (ext == "azw3" || ext == "azw") return "AZW3";
    if (ext == "txt") return "TXT";
    if (ext == "md") return "MD";
    if (ext == "fb2") return "FB2";
    return {};
}

QString BookImporter::importFile(const QString &srcPath, bool moveIntoLibrary) {
    const QString format = detectFormat(srcPath);
    if (format.isEmpty()) return "不支持的文件格式";
    QDir lib(m_libraryDir); lib.mkpath("books");
    const QString fileName = QFileInfo(srcPath).fileName();
    const QString dest = m_libraryDir + "/books/" + fileName;
    if (QFile::exists(dest)) return "同名文件已存在于书库";
    if (!QFile::copy(srcPath, dest)) return "复制文件失败";
    const QString cover = generatePlaceholderCover(QFileInfo(fileName).completeBaseName(), m_libraryDir + "/covers/");
    Book b;
    b.title = QFileInfo(fileName).completeBaseName();
    b.format = format; b.path = dest; b.cover = cover;
    // addBook 返回 -1 表示写入失败（如 path 唯一约束冲突、FTS 索引写入失败），此时回滚文件副作用。
    if (m_books->addBook(b) < 0) {
        QFile::remove(dest);
        if (!cover.isEmpty()) QFile::remove(cover);
        return "写入数据库失败";
    }
    return {};
}

QString BookImporter::generatePlaceholderCover(const QString &title, const QString &destDir) const {
    QDir(destDir).mkpath(".");
    const QString hash = QCryptographicHash::hash(title.toUtf8(), QCryptographicHash::Md5).toHex().left(6);
    const QString path = destDir + "/" + hash + ".png";
    QPixmap pm(300, 400); pm.fill(QColor("#3D5AFE"));
    QPainter p(&pm);
    p.setPen(Qt::white);
    QFont f = p.font(); f.setPointSize(120); f.setBold(true); p.setFont(f);
    const QChar ch = title.isEmpty() ? QChar('?') : title.at(0);
    p.drawText(pm.rect(), Qt::AlignCenter, QString(ch));
    p.end();
    pm.save(path, "PNG");
    return path;
}

QVector<Book> BookImporter::books() const {
    return m_books->books();
}
