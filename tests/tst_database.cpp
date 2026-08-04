#include <QtTest>
#include "core/DatabaseManager.h"

class TestDatabase : public QObject {
    Q_OBJECT
private slots:
    void init() { m_mgr.reset(new DatabaseManager(":memory:")); }
    void createsSchema() {
        QSqlDatabase db = m_mgr->database();
        QVERIFY(db.tables().contains("books"));
        QVERIFY(db.tables().contains("categories"));
        QVERIFY(db.tables().contains("highlights"));
        QVERIFY(db.tables().contains("books_fts"));
        QCOMPARE(m_mgr->schemaVersion(), 1);
    }
    void reopensWithSameVersion() {
        QTemporaryDir dir;
        const QString path = dir.filePath("t.db");
        { DatabaseManager a(path); QCOMPARE(a.schemaVersion(), 1); }
        { DatabaseManager b(path); QCOMPARE(b.schemaVersion(), 1); }
    }
private:
    std::unique_ptr<DatabaseManager> m_mgr;
};
QTEST_MAIN(TestDatabase)
#include "tst_database.moc"
