#include <QtTest>
#include <QSqlQuery>
#include <QSqlError>
#include "core/DatabaseManager.h"

// L9（P2#32）：迁移失败已致命化（qFatal 终止进程，与 open 失败同等）——失败路径
// 不再可测（进程终止，SQLite 自动回滚未提交事务）。故不保留/新增失败迁移用例；
// 此处仅覆盖成功路径（建 schema、同版本重开）。
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
        QCOMPARE(m_mgr->schemaVersion(), 2);
    }
    void reopensWithSameVersion() {
        QTemporaryDir dir;
        const QString path = dir.filePath("t.db");
        { DatabaseManager a(path); QCOMPARE(a.schemaVersion(), 2); }
        { DatabaseManager b(path); QCOMPARE(b.schemaVersion(), 2); }
    }
private:
    std::unique_ptr<DatabaseManager> m_mgr;
};
QTEST_MAIN(TestDatabase)
#include "tst_database.moc"
