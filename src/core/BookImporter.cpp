#include "BookImporter.h"
#include "BookManager.h"
#include <QDebug>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QPainter>
#include <QFont>
#include <QPixmap>
#include <QCryptographicHash>

BookImporter::BookImporter(const QString &libraryDir, const QString &dbPath, QObject *parent)
    : QObject(parent), m_libraryDir(libraryDir), m_books(new BookManager(dbPath, "readdict_importer")) {}

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
    const QString coverDir = m_libraryDir + "/covers/";
    const QString title = QFileInfo(fileName).completeBaseName();
    // 封面由 MD5(标题) 前 6 位命名，同标题书籍共享同一封面文件：
    // 记录生成前是否已存在，回滚时不得删除仍被健康记录引用的封面。
    const QString coverPath = coverPathFor(title, coverDir);
    const bool coverExisted = QFile::exists(coverPath);
    const QString cover = generatePlaceholderCover(title, coverDir);
    Book b;
    b.title = title;
    b.format = format; b.path = dest; b.cover = cover;
    // addBook 返回 -1 表示写入失败（如 path 唯一约束冲突、FTS 索引写入失败），此时回滚文件副作用。
    if (m_books->addBook(b) < 0) {
        QFile::remove(dest);
        if (!coverExisted) QFile::remove(cover);
        return "写入数据库失败";
    }
    return {};
}

QString BookImporter::coverPathFor(const QString &title, const QString &destDir) {
    const QString hash = QCryptographicHash::hash(title.toUtf8(), QCryptographicHash::Md5).toHex().left(6);
    return destDir + "/" + hash + ".png";
}

QString BookImporter::generatePlaceholderCover(const QString &title, const QString &destDir) const {
    QDir(destDir).mkpath(".");
    const QString path = coverPathFor(title, destDir);
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

void BookImporter::doImport(const QUrl &url) {
    const QString file = url.toLocalFile();
    if (file.isEmpty()) {
        qWarning() << "doImport: 无法解析本地文件路径:" << url;
        emit importFailed("无法解析本地文件路径", url.toString());
        return;
    }
    const QString err = importFile(file, true);
    if (!err.isEmpty()) {
        qWarning() << "导入失败:" << err << "(" << file << ")";
        emit importFailed(err, file);
        return;
    }
    emit imported();
}
