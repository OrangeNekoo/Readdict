#include <QtTest>
#include "core/BookImporter.h"

class TestImporter : public QObject {
    Q_OBJECT
private slots:
    void detectsFormats() {
        QCOMPARE(BookImporter::detectFormat("a.epub"), QString("EPUB"));
        QCOMPARE(BookImporter::detectFormat("b.PDF"), QString("PDF"));
        QCOMPARE(BookImporter::detectFormat("c.mobi"), QString("MOBI"));
        QCOMPARE(BookImporter::detectFormat("d.azw3"), QString("AZW3"));
        QCOMPARE(BookImporter::detectFormat("e.txt"), QString("TXT"));
        QCOMPARE(BookImporter::detectFormat("f.md"), QString("MD"));
        QCOMPARE(BookImporter::detectFormat("g.fb2"), QString("FB2"));
        QCOMPARE(BookImporter::detectFormat("h.xyz"), QString());
    }
    void importsCopyIntoLibrary() {
        QTemporaryDir libDir;
        QTemporaryDir srcDir;
        QFile src(srcDir.path() + "/book.txt");
        QVERIFY(src.open(QIODevice::WriteOnly)); src.write("hello world"); src.close();
        BookImporter imp(libDir.path(), ":memory:");
        const QString err = imp.importFile(src.fileName(), true);
        QVERIFY(err.isEmpty());
        QVERIFY(QFile::exists(libDir.path() + "/books/book.txt"));
        QCOMPARE(imp.books().size(), 1);
    }
};
QTEST_MAIN(TestImporter)
#include "tst_bookimporter.moc"
