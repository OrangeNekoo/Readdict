#include <QtTest>
#include <QSqlQuery>
#include <QSqlError>
#include "core/DatabaseManager.h"

// 迁移失败路径注入：用第二个连接（A）持写锁（BEGIN IMMEDIATE），迁移连接（B）的
// CREATE TABLE 首条写语句即 SQLITE_BUSY——模拟迁移中途失败，验证：
//  1) 失败后不残留悬空事务（B 上能重新开启事务；旧实现 BEGIN 未回滚 → 新 BEGIN 失败）
//  2) user_version 保持一致（仍为 0，锁释放后重开可完整重试迁移，无半套 schema）
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
    void migrateRollsBackOnFailure() {
        QTemporaryDir dir;
        const QString path = dir.filePath("t.db");
        // 连接 A 持写锁（RESERVED）：阻塞迁移连接的写语句
        QSqlDatabase a = QSqlDatabase::addDatabase("QSQLITE", "readdict_lock_a");
        a.setDatabaseName(path);
        QVERIFY2(a.open(), qPrintable(a.lastError().text()));
        QSqlQuery qa(a);
        QVERIFY2(qa.exec("BEGIN IMMEDIATE"), qPrintable(qa.lastError().text()));
        {
            DatabaseManager mgr(path, QStringLiteral("readdict_lock_b")); // 迁移在此失败
            // 迁移未完成：user_version 保持 0（有效空库的初始值；-1 仅见于损坏文件），
            // 未半提交成 1/2，锁释放后重试可完整迁移
            QCOMPARE(mgr.schemaVersion(), 0);
            // 失败路径不得留下悬空事务：migrate 内部已 ROLLBACK，新事务应能正常开启
            //（旧实现 BEGIN 后失败不回滚 → 此处 BEGIN 报 "cannot start a transaction…"）
            QSqlQuery qb(mgr.database());
            QVERIFY2(qb.exec("BEGIN"), "migrate 失败后不应残留活动事务");
            qb.exec("ROLLBACK");
        }
        QSqlQuery qa2(a);
        QVERIFY2(qa2.exec("ROLLBACK"), qPrintable(qa2.lastError().text()));
        // 锁释放后完整重试迁移成功：无半套 schema、user_version 一致（v2 含 chapter_index）
        DatabaseManager ok(path, QStringLiteral("readdict_lock_c"));
        QCOMPARE(ok.schemaVersion(), 2);
        QVERIFY(ok.database().tables().contains("books"));
        QVERIFY(ok.database().tables().contains("books_fts"));
        {   // L5：v2 增量列存在且可查询（旧行默认 0）
            QSqlQuery qc(ok.database());
            QVERIFY2(qc.exec("SELECT chapter_index FROM highlights"),
                     qPrintable(qc.lastError().text()));
        }
    }
private:
    std::unique_ptr<DatabaseManager> m_mgr;
};
QTEST_MAIN(TestDatabase)
#include "tst_database.moc"
