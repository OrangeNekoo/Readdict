// D2：SyncManager（数据打包、合并、冲突解决）
// - 简报 3 用例：buildsPayloads / mergesProgressNewerWins / equalTimestampsSkip
// - 补充：progress 合并 ts 语义（含等值重放幂等）、highlights 四元组去重（id 不参与
//   去重键，note/color 差异合并更新）、settings 敏感分区排除与合并（损坏文件跳过不覆盖）、
//   sync 全流程（内容版本比较：上传/下载/保留本地/采用远端/跳过）、书籍文件体按需
//   上传/下载、put/get 失败日志
// mock 方案：WebDavClient 方法抽成 virtual，测试内嵌 MockWebDavClient 以内存
// QHash 模拟远端存储（list/put/get/remove），避免为 sync 多轮有状态交互搭 TCP mock。
#include <QtTest>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QSqlQuery>
#include <QSqlDatabase>
#include <QSqlError>
#include <QTemporaryDir>
#include <QFile>
#include <QTimeZone>
#include <QRegularExpression>
#include "SyncManager.h"
#include "core/DatabaseManager.h"
#include "core/HighlightManager.h"

// ---- 远端 mock：内存文件表 + 可控 mtime，记录调用 ----
class MockWebDavClient : public WebDavClient {
public:
    MockWebDavClient() : WebDavClient("http://mock.invalid/", "", "") {}
    QHash<QString, QByteArray> files;
    QHash<QString, QDateTime> mtimes;
    QDateTime mtimeDefault = QDateTime::currentDateTimeUtc();
    QString err;
    bool putReturnsFalse = false;
    bool getReturnsFalse = false;
    QStringList putNames, getNames;

    bool put(const QString &name, const QByteArray &data) override {
        putNames.append(name);
        if (putReturnsFalse) { err = "mock put 失败"; return false; }
        files.insert(name, data);
        mtimes.insert(name, QDateTime::currentDateTimeUtc());
        err.clear();
        return true;
    }
    QByteArray get(const QString &name) override {
        getNames.append(name);
        if (getReturnsFalse) { err = "mock get 失败"; return QByteArray(); }
        const auto it = files.constFind(name);
        if (it == files.constEnd()) { err = "404 Not Found"; return QByteArray(); }
        err.clear();
        return it.value();
    }
    bool remove(const QString &name) override {
        files.remove(name);
        err.clear();
        return true;
    }
    QVector<DavEntry> list() override {
        QVector<DavEntry> out;
        out.reserve(files.size());
        for (auto it = files.constBegin(); it != files.constEnd(); ++it) {
            DavEntry e;
            e.name = it.key();
            e.size = it.value().size();
            e.modified = mtimes.value(it.key(), mtimeDefault);
            out.append(e);
        }
        return out;
    }
    QString lastError() const override { return err; }
};

// ---- 种子/校验辅助 ----
// 连接名每次固定（跨用例重复 addDatabase 移除旧连接属已知良性，见 tst_highlights 注释）
static QSqlDatabase seedDb(const QString &path) {
    DatabaseManager dbm(path, QStringLiteral("seed_conn"));
    return dbm.database();
}

static void seedBook(QSqlDatabase db, qint64 id, const QString &title, double progress,
                     const QString &lastReadAt) {
    QSqlQuery q(db);
    q.prepare("INSERT INTO books(id,title,format,path,added_at,progress,last_read_at)"
              " VALUES(?,?,?,?,?,?,?)");
    q.addBindValue(id);
    q.addBindValue(title);
    q.addBindValue("EPUB");
    q.addBindValue(QStringLiteral("/lib/books/%1.epub").arg(title));
    q.addBindValue(QStringLiteral("2026-01-01T00:00:00"));
    q.addBindValue(progress);
    q.addBindValue(lastReadAt);
    QVERIFY2(q.exec(), qPrintable(q.lastError().text()));
}

static void seedHighlight(QSqlDatabase db, qint64 id, qint64 bookId, const QString &chapter,
                          int sentenceIndex, const QString &text, const QString &createdAt) {
    QSqlQuery q(db);
    q.prepare("INSERT INTO highlights(id,book_id,chapter,sentence_index,text,color,note,created_at)"
              " VALUES(?,?,?,?,?,?,?,?)");
    q.addBindValue(id);
    q.addBindValue(bookId);
    q.addBindValue(chapter);
    q.addBindValue(sentenceIndex);
    q.addBindValue(text);
    q.addBindValue(QStringLiteral("#FFD54F"));
    q.addBindValue(QString());
    q.addBindValue(createdAt);
    QVERIFY2(q.exec(), qPrintable(q.lastError().text()));
}

static QVariant progressOf(const QString &dbPath, qint64 id) {
    QSqlDatabase v = QSqlDatabase::addDatabase("QSQLITE", "verify_conn");
    v.setDatabaseName(dbPath);
    if (!v.open())
        return QVariant();
    QSqlQuery q(v);
    q.prepare("SELECT progress FROM books WHERE id=?");
    q.addBindValue(id);
    QVariant out;
    if (q.exec() && q.next())
        out = q.value(0);
    v = QSqlDatabase(); // 先释放句柄再移除连接，避免 "still in use" 告警
    QSqlDatabase::removeDatabase("verify_conn");
    return out;
}

static qint64 countRows(const QString &dbPath, const QString &table) {
    QSqlDatabase v = QSqlDatabase::addDatabase("QSQLITE", "verify_conn");
    v.setDatabaseName(dbPath);
    if (!v.open())
        return -1;
    QSqlQuery q(v);
    qint64 out = -1;
    if (q.exec(QStringLiteral("SELECT COUNT(*) FROM %1").arg(table)) && q.next())
        out = q.value(0).toLongLong();
    v = QSqlDatabase(); // 先释放句柄再移除连接，避免 "still in use" 告警
    QSqlDatabase::removeDatabase("verify_conn");
    return out;
}

static QByteArray readFileBytes(const QString &path) {
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
}

class TestSync : public QObject {
    Q_OBJECT
private slots:
    // ---- 简报用例 1：打包 ----
    void buildsPayloads() {
        SyncManager m(":memory:", "/tmp/libdir");
        const QByteArray p = m.buildProgressJson({{1, 0.5}, {2, 0.8}});
        const QJsonObject root = QJsonDocument::fromJson(p).object();
        QVERIFY(root.contains("books"));
        QCOMPARE(root["books"].toArray().size(), 2);
        // 每项含 bookId/progress/ts（ts 无书可查时回退打包时刻，UTC 序列化）
        const QJsonObject first = root["books"].toArray().first().toObject();
        QCOMPARE(first["bookId"].toVariant().toLongLong(), 1);
        QCOMPARE(first["progress"].toDouble(), 0.5);
        QVERIFY(QDateTime::fromString(first["ts"].toString(), Qt::ISODate).isValid());
    }
    // ---- 简报用例 2：冲突判定 ----
    void mergesProgressNewerWins() {
        SyncManager m(":memory:", "/tmp/libdir");
        const QDateTime local = QDateTime::currentDateTimeUtc();
        const QDateTime remote = local.addSecs(-60);
        QCOMPARE(m.resolveConflict(local, remote), SyncManager::KeepLocal);
        QCOMPARE(m.resolveConflict(remote, local), SyncManager::TakeRemote);
    }
    // ---- 简报用例 3：时间戳相等跳过 ----
    void equalTimestampsSkip() {
        SyncManager m(":memory:", "/tmp/libdir");
        const QDateTime t = QDateTime::currentDateTimeUtc();
        QCOMPARE(m.resolveConflict(t, t), SyncManager::Skip);
    }

    // ---- 补充：progress 合并 ts 语义 ----
    void progressMergeTsSemantics() {
        QTemporaryDir dir;
        const QString db = dir.filePath("t.db");
        {
            QSqlDatabase seed = seedDb(db);
            seedBook(seed, 1, "a", 0.2, "2026-01-01T00:00:00");
        }
        SyncManager m(db, dir.path());
        // 远端 ts 比本地最近阅读新 → 采用
        m.applyProgressJson("{\"books\":[{\"bookId\":1,\"progress\":0.9,\"ts\":\"2026-01-02T00:00:00\"}]}");
        QCOMPARE(progressOf(db, 1).toDouble(), 0.9);
        // 远端 ts 早于本地最近阅读 → 保留本地
        m.applyProgressJson("{\"books\":[{\"bookId\":1,\"progress\":0.5,\"ts\":\"2025-12-31T00:00:00\"}]}");
        QCOMPARE(progressOf(db, 1).toDouble(), 0.9);
        // 本地无此书（bookId=99）→ 跳过，不建书
        m.applyProgressJson("{\"books\":[{\"bookId\":99,\"progress\":1.0,\"ts\":\"2026-01-02T00:00:00\"}]}");
        QCOMPARE(countRows(db, "books"), 1);
        // 本地无 last_read_at（NULL）→ 远端 ts 无条件采用
        {
            QSqlDatabase seed = seedDb(db);
            seedBook(seed, 2, "b", 0.0, QString());
        }
        m.applyProgressJson("{\"books\":[{\"bookId\":2,\"progress\":0.6,\"ts\":\"2026-01-02T00:00:00\"}]}");
        QCOMPARE(progressOf(db, 2).toDouble(), 0.6);
        // 复审：远端 ts == 本地最近阅读 → 等值重放不写（幂等，sync 重复下载即 Skip 的前提）
        {
            QSqlDatabase seed = seedDb(db);
            seedBook(seed, 3, "c", 0.1, "2026-01-03T00:00:00");
        }
        m.applyProgressJson("{\"books\":[{\"bookId\":3,\"progress\":0.9,\"ts\":\"2026-01-03T00:00:00\"}]}");
        QCOMPARE(progressOf(db, 3).toDouble(), 0.1);
        // 复审：采用远端后 last_read_at 采用载荷 ts（而非合并时刻），转本地无时区格式
        {
            QSqlDatabase seed = seedDb(db);
            QSqlQuery q(seed);
            q.prepare("SELECT last_read_at FROM books WHERE id=2");
            QVERIFY(q.exec() && q.next());
            QCOMPARE(q.value(0).toString(), QString("2026-01-02T00:00:00"));
        }
    }

    // ---- 补充：highlights 全量打包 + 四元组去重合并 ----
    void highlightsRoundtripAndDedup() {
        QTemporaryDir dir;
        const QString db = dir.filePath("t.db");
        {
            QSqlDatabase seed = seedDb(db);
            seedHighlight(seed, 1, 1, "第一章", 3, "高亮文本", "2026-01-01T00:00:00");
            seedHighlight(seed, 2, 1, "第一章", 4, "另一句", "2026-01-02T00:00:00");
        }
        SyncManager m(db, dir.path());
        const QJsonArray arr = QJsonDocument::fromJson(m.buildHighlightsJson())
                                   .object()["highlights"].toArray();
        QCOMPARE(arr.size(), 2); // 全量（含 id，供去重/后续增量）
        const QJsonObject first = arr.first().toObject();
        QCOMPARE(first["id"].toVariant().toLongLong(), 1);
        QCOMPARE(first["bookId"].toVariant().toLongLong(), 1);
        QCOMPARE(first["text"].toString(), QString("高亮文本"));
        QVERIFY(first.contains("chapter") && first.contains("sentenceIndex"));
        // 复审：createdAt UTC 归一化 + 毫秒精度（跨设备时区不偏移、同秒编辑可区分）
        QCOMPARE(first["createdAt"].toString(),
                 QDateTime::fromString("2026-01-01T00:00:00", Qt::ISODate).toUTC().toString(Qt::ISODateWithMs));

        // 重放全量：四元组全重复 → 零插入
        m.applyHighlightsJson(m.buildHighlightsJson());
        QCOMPARE(countRows(db, "highlights"), 2);
        // 新四元组 → 插入
        m.applyHighlightsJson("{\"highlights\":[{\"bookId\":1,\"chapter\":\"第一章\",\"sentenceIndex\":5,\"text\":\"新句\",\"color\":\"#FFF\",\"note\":\"n\"}]}");
        QCOMPARE(countRows(db, "highlights"), 3);
        // id 不参与去重键：id 相同但文本不同 → 仍插入新行
        m.applyHighlightsJson("{\"highlights\":[{\"id\":1,\"bookId\":1,\"chapter\":\"第一章\",\"sentenceIndex\":3,\"text\":\"不同文本\",\"color\":\"#FFF\"}]}");
        QCOMPARE(countRows(db, "highlights"), 4);
        // 复审：四元组已存在且远端改了 note/color → 合并更新（行数不增）；无差异 → 不写
        m.applyHighlightsJson("{\"highlights\":[{\"bookId\":1,\"chapter\":\"第一章\",\"sentenceIndex\":5,\"text\":\"新句\",\"color\":\"#000\",\"note\":\"n2\"}]}");
        QCOMPARE(countRows(db, "highlights"), 4);
        {
            QSqlDatabase seed = seedDb(db);
            QSqlQuery q(seed);
            q.prepare("SELECT color,note FROM highlights WHERE book_id=1 AND chapter='第一章'"
                      " AND sentence_index=5");
            QVERIFY(q.exec() && q.next());
            QCOMPARE(q.value(0).toString(), QString("#000")); // 远端颜色合并过来
            QCOMPARE(q.value(1).toString(), QString("n2"));   // 远端笔记合并过来
        }
        // 无差异重放：不写（颜色保持 #000）
        m.applyHighlightsJson("{\"highlights\":[{\"bookId\":1,\"chapter\":\"第一章\",\"sentenceIndex\":5,\"text\":\"新句\",\"color\":\"#000\",\"note\":\"n2\"}]}");
        {
            QSqlDatabase seed = seedDb(db);
            QSqlQuery q(seed);
            q.prepare("SELECT color FROM highlights WHERE book_id=1 AND chapter='第一章'"
                      " AND sentence_index=5");
            QVERIFY(q.exec() && q.next());
            QCOMPARE(q.value(0).toString(), QString("#000"));
        }
    }

    // ---- 补充：settings 打包排除敏感分区 ----
    void settingsPayloadExcludesSensitive() {
        QTemporaryDir dir;
        QFile f(dir.filePath("settings.json"));
        QVERIFY(f.open(QIODevice::WriteOnly));
        QVERIFY(f.write("{\"theme\":{\"mode\":\"dark\"},\"typography\":{\"fontSize\":20,\"lineHeight\":1.8},"
                        "\"tts\":{\"engine\":\"system\"},\"webdav\":{\"url\":\"http://x\",\"user\":\"u\",\"password\":\"secret\"},"
                        "\"progress\":{\"1\":3}}") > 0);
        f.close();
        SyncManager m(dir.filePath("Readdict.db"), dir.path()); // settings 与 db 同目录
        const QByteArray p = m.buildSettingsJson();
        const QJsonObject root = QJsonDocument::fromJson(p).object();
        QVERIFY(root.contains("theme"));
        QVERIFY(root.contains("typography"));
        QVERIFY(root.contains("tts"));
        QVERIFY(!root.contains("webdav"));   // 凭据分区不出本机
        QVERIFY(!root.contains("progress")); // 章内阅读位置不随设置同步
        QVERIFY(!p.contains("secret"));      // 密码字符串绝不出现在载荷
        QCOMPARE(root["theme"].toObject()["mode"].toString(), QString("dark"));
        // 本地无 settings.json → 空载荷（远端缺文件时上传空对象，应用侧由 SettingsStore 兜底默认）
        SyncManager m2(":memory:", "/tmp/libdir", "readdict_sync_2");
        QCOMPARE(QJsonDocument::fromJson(m2.buildSettingsJson()).object().isEmpty(), true);
    }

    // ---- 补充：settings 合并（远端叶子覆盖 + webdav/progress 不动） ----
    void settingsMergeAppliesRemote() {
        QTemporaryDir dir;
        QFile f(dir.filePath("settings.json"));
        QVERIFY(f.open(QIODevice::WriteOnly));
        QVERIFY(f.write("{\"theme\":{\"mode\":\"light\"},\"webdav\":{\"url\":\"http://x\",\"user\":\"u\",\"password\":\"p\"}}") > 0);
        f.close();
        SyncManager m(dir.filePath("Readdict.db"), dir.path());
        m.applySettingsJson("{\"theme\":{\"mode\":\"dark\"},\"typography\":{\"fontSize\":20},"
                            "\"webdav\":{\"password\":\"hacked\"},\"progress\":{\"9\":9}}");
        const QJsonObject root =
            QJsonDocument::fromJson(readFileBytes(dir.filePath("settings.json"))).object();
        QCOMPARE(root["theme"].toObject()["mode"].toString(), QString("dark")); // 远端覆盖
        QCOMPARE(root["typography"].toObject()["fontSize"].toInt(), 20);        // 新增分区
        // 本地 webdav 保留、远端 webdav/progress 被忽略（永不写入）
        QCOMPARE(root["webdav"].toObject()["password"].toString(), QString("p"));
        QVERIFY(!root.contains("progress"));
        // 本地无 settings.json → 由远端生成
        QTemporaryDir dir2;
        SyncManager m2(dir2.filePath("Readdict.db"), dir2.path(), "readdict_sync_2");
        m2.applySettingsJson("{\"theme\":{\"mode\":\"dark\"}}");
        QVERIFY(QFile::exists(dir2.filePath("settings.json")));
        const QJsonObject root2 =
            QJsonDocument::fromJson(readFileBytes(dir2.filePath("settings.json"))).object();
        QCOMPARE(root2["theme"].toObject()["mode"].toString(), QString("dark"));
    }

    // ---- 补充：sync 流程——远端缺文件 → 上传 ----
    void syncFlowUploadsWhenRemoteMissing() {
        QTemporaryDir dir;
        const QString db = dir.filePath("t.db");
        {
            QSqlDatabase seed = seedDb(db);
            seedBook(seed, 1, "a", 0.5, "2026-08-01T10:00:00");
        }
        MockWebDavClient mock;
        SyncManager m(db, dir.path());
        SyncManager::Options o; o.settings = false; o.progress = true;
        o.highlights = false; o.books = false;
        m.sync(mock, o);
        QVERIFY(mock.files.contains("progress.json"));
        const QJsonArray arr = QJsonDocument::fromJson(mock.files["progress.json"])
                                   .object()["books"].toArray();
        QCOMPARE(arr.size(), 1);
        QCOMPARE(arr.first().toObject()["bookId"].toVariant().toLongLong(), 1);
        QCOMPARE(arr.first().toObject()["progress"].toDouble(), 0.5);
        QVERIFY(m.log().join('\n').contains("上传 progress.json"));
    }

    // ---- 补充：sync 流程——本地无数据 → 下载并应用 ----
    void syncFlowDownloadsWhenLocalEmpty() {
        QTemporaryDir dir;
        const QString db = dir.filePath("t.db");
        {
            QSqlDatabase seed = seedDb(db);
            seedBook(seed, 1, "a", 0.0, QString()); // 有书无进度 → 本地视为无进度数据
        }
        MockWebDavClient mock;
        mock.files["progress.json"] =
            "{\"books\":[{\"bookId\":1,\"progress\":0.7,\"ts\":\"2026-08-01T00:00:00Z\"}]}";
        mock.mtimes["progress.json"] = QDateTime(QDate(2026, 8, 1), QTime(0, 0, 0), QTimeZone::UTC);
        SyncManager m(db, dir.path());
        SyncManager::Options o; o.settings = false; o.progress = true;
        o.highlights = false; o.books = false;
        m.sync(mock, o);
        QCOMPARE(progressOf(db, 1).toDouble(), 0.7);
        QVERIFY(m.log().join('\n').contains("下载 progress.json"));
        QCOMPARE(mock.getNames, QStringList({"progress.json"}));
    }

    // ---- 补充：sync 流程——本地更新 → 保留本地上传 ----
    void syncFlowKeepLocalOnNewerLocal() {
        QTemporaryDir dir;
        const QString db = dir.filePath("t.db");
        {
            QSqlDatabase seed = seedDb(db);
            seedBook(seed, 1, "a", 0.5, "2026-08-05T10:00:00");
        }
        MockWebDavClient mock;
        mock.files["progress.json"] = "{\"books\":[{\"bookId\":1,\"progress\":0.1,\"ts\":\"2026-08-01T00:00:00Z\"}]}";
        mock.mtimes["progress.json"] = QDateTime(QDate(2026, 8, 1), QTime(0, 0, 0), QTimeZone::UTC);
        SyncManager m(db, dir.path());
        SyncManager::Options o; o.settings = false; o.progress = true;
        o.highlights = false; o.books = false;
        m.sync(mock, o);
        // 远端文件被本地上传覆盖（本地 last_read_at 8/5 > 远端 mtime 8/1）
        const QJsonArray arr = QJsonDocument::fromJson(mock.files["progress.json"])
                                   .object()["books"].toArray();
        QCOMPARE(arr.first().toObject()["progress"].toDouble(), 0.5);
        QCOMPARE(progressOf(db, 1).toDouble(), 0.5); // 本地未被远端 0.1 覆盖
        QVERIFY(m.log().join('\n').contains("保留本地 progress.json"));
    }

    // ---- 补充：sync 流程——远端更新 → 采用远端 ----
    void syncFlowTakeRemoteOnNewerRemote() {
        QTemporaryDir dir;
        const QString db = dir.filePath("t.db");
        {
            QSqlDatabase seed = seedDb(db);
            seedBook(seed, 1, "a", 0.5, "2026-08-01T10:00:00");
        }
        MockWebDavClient mock;
        mock.files["progress.json"] =
            "{\"books\":[{\"bookId\":1,\"progress\":0.9,\"ts\":\"2026-08-02T00:00:00Z\"}]}";
        mock.mtimes["progress.json"] = QDateTime(QDate(2026, 8, 2), QTime(0, 0, 0), QTimeZone::UTC);
        SyncManager m(db, dir.path());
        SyncManager::Options o; o.settings = false; o.progress = true;
        o.highlights = false; o.books = false;
        m.sync(mock, o);
        QCOMPARE(progressOf(db, 1).toDouble(), 0.9); // 远端 8/2 > 本地 8/1 → 采用
        QVERIFY(m.log().join('\n').contains("采用远端 progress.json"));
    }

    // ---- 补充：sync 流程——内容版本相等 → 跳过（载荷 max ts 与本地同钟比较） ----
    void syncFlowSkipsEqualTimestamps() {
        QTemporaryDir dir;
        const QString db = dir.filePath("t.db");
        {
            QSqlDatabase seed = seedDb(db);
            seedBook(seed, 1, "a", 0.5, "2026-08-01T10:00:00"); // 本地无时区 → LocalTime
        }
        MockWebDavClient mock;
        // 远端载荷 ts = 本地 last_read_at 的 UTC 瞬时（同内容版本 → Skip，无需下载应用）
        const QDateTime localRead = QDateTime::fromString("2026-08-01T10:00:00", Qt::ISODate);
        const QByteArray remotePayload =
            QStringLiteral("{\"books\":[{\"bookId\":1,\"progress\":0.5,\"ts\":\"%1\"}]}")
                .arg(localRead.toUTC().toString(Qt::ISODate)).toUtf8();
        mock.files["progress.json"] = remotePayload;
        SyncManager m(db, dir.path());
        SyncManager::Options o; o.settings = false; o.progress = true;
        o.highlights = false; o.books = false;
        m.sync(mock, o);
        QVERIFY(m.log().join('\n').contains("跳过 progress.json"));
        QCOMPARE(mock.getNames.size(), 1);                    // 仅一次版本 GET，无下载应用
        QCOMPARE(mock.files["progress.json"], remotePayload); // 未被覆盖上传
        QCOMPARE(progressOf(db, 1).toDouble(), 0.5);
    }

    // ---- 补充：sync 流程——settings 项（本地文件 mtime 为本地版本） ----
    void syncFlowSettingsKeepLocal() {
        QTemporaryDir dir;
        QFile f(dir.filePath("settings.json"));
        QVERIFY(f.open(QIODevice::WriteOnly));
        QVERIFY(f.write("{\"theme\":{\"mode\":\"dark\"},\"webdav\":{\"password\":\"local-secret\"}}") > 0);
        f.close();
        MockWebDavClient mock;
        mock.files["settings.json"] = "{\"theme\":{\"mode\":\"light\"}}";
        mock.mtimes["settings.json"] =
            QFileInfo(dir.filePath("settings.json")).lastModified().addSecs(-3600).toUTC();
        SyncManager m(dir.filePath("Readdict.db"), dir.path());
        SyncManager::Options o; o.settings = true; o.progress = false;
        o.highlights = false; o.books = false;
        m.sync(mock, o);
        // KeepLocal → 本地上传（载荷不含 webdav 凭据）
        const QJsonObject up = QJsonDocument::fromJson(mock.files["settings.json"]).object();
        QCOMPARE(up["theme"].toObject()["mode"].toString(), QString("dark"));
        QVERIFY(!up.contains("webdav"));
        QVERIFY(m.log().join('\n').contains("保留本地 settings.json"));
    }

    // ---- 补充：sync 流程——settings 同秒 mtime → 跳过（本地截断到秒级对齐远端） ----
    void syncFlowSettingsSkipsOnEqualSecond() {
        QTemporaryDir dir;
        QFile f(dir.filePath("settings.json"));
        QVERIFY(f.open(QIODevice::WriteOnly));
        QVERIFY(f.write("{\"theme\":{\"mode\":\"dark\"}}") > 0);
        f.close();
        MockWebDavClient mock;
        // 内容不同（否则走内容相等分支），但远端 mtime = 本地文件 mtime 截断到秒
        mock.files["settings.json"] = "{\"theme\":{\"mode\":\"light\"}}";
        mock.mtimes["settings.json"] = QDateTime::fromSecsSinceEpoch(
            QFileInfo(dir.filePath("settings.json")).lastModified().toSecsSinceEpoch());
        SyncManager m(dir.filePath("Readdict.db"), dir.path());
        SyncManager::Options o; o.settings = true; o.progress = false;
        o.highlights = false; o.books = false;
        m.sync(mock, o);
        QVERIFY(m.log().join('\n').contains("跳过 settings.json")); // mtime 同秒 → Skip
        QCOMPARE(mock.getNames, QStringList({"settings.json"}));    // 一次内容 GET
        QVERIFY(mock.putNames.isEmpty());                           // 未上传
        QCOMPARE(mock.files["settings.json"], QByteArray("{\"theme\":{\"mode\":\"light\"}}"));
    }

    // ---- 补充：sync 流程——settings 上传后内容趋同 → 下次同步 Skip（收敛） ----
    void syncFlowSettingsConvergesAfterUpload() {
        QTemporaryDir dir;
        QFile f(dir.filePath("settings.json"));
        QVERIFY(f.open(QIODevice::WriteOnly));
        QVERIFY(f.write("{\"theme\":{\"mode\":\"dark\"}}") > 0);
        f.close();
        MockWebDavClient mock;
        mock.files["settings.json"] = "{\"typography\":{\"fontSize\":20}}"; // 内容不同
        mock.mtimes["settings.json"] = QDateTime(QDate(2026, 1, 1), QTime(0, 0, 0), QTimeZone::UTC);
        SyncManager m(dir.filePath("Readdict.db"), dir.path());
        SyncManager::Options o; o.settings = true; o.progress = false;
        o.highlights = false; o.books = false;
        // #1：内容不同 → mtime 本地(截断 now) > 2026-01-01 → KeepLocal 上传
        m.sync(mock, o);
        QVERIFY(m.log().join('\n').contains("保留本地 settings.json"));
        const QJsonObject up = QJsonDocument::fromJson(mock.files["settings.json"]).object();
        QCOMPARE(up["theme"].toObject()["mode"].toString(), QString("dark"));
        QCOMPARE(mock.putNames.size(), 1);
        // #2：内容一致（本地已上传内容 == 远端）→ 内容相等分支直接 Skip，
        // 不再因"服务器盖章新 mtime"而交替往返
        m.sync(mock, o);
        QVERIFY(m.log().join('\n').contains("跳过 settings.json"));
        QCOMPARE(mock.putNames.size(), 1); // 未再上传
    }

    // ---- 补充：applySettingsJson 内容无差异不写盘（保留 mtime） ----
    void applySettingsNoopPreservesMtime() {
        QTemporaryDir dir;
        QFile f(dir.filePath("settings.json"));
        QVERIFY(f.open(QIODevice::WriteOnly));
        QVERIFY(f.write("{\"theme\":{\"mode\":\"dark\"}}") > 0);
        f.close();
        SyncManager m(dir.filePath("Readdict.db"), dir.path());
        const QString path = dir.filePath("settings.json");
        const QDateTime before = QFileInfo(path).lastModified();
        QTest::qWait(1100); // 确保跨秒：若发生重写 mtime 必然前移
        m.applySettingsJson("{\"theme\":{\"mode\":\"dark\"}}"); // 内容一致 → 不写
        QCOMPARE(QFileInfo(path).lastModified(), before);
        // 内容不同 → 仍写
        m.applySettingsJson("{\"typography\":{\"fontSize\":20}}");
        QVERIFY(QFileInfo(path).lastModified() >= before);
    }

    // ---- 补充：sync 流程——本地 settings.json 损坏 → 跳过且不覆盖远端 ----
    void syncFlowCorruptSettingsSkipsUpload() {
        QTemporaryDir dir;
        QFile f(dir.filePath("settings.json"));
        QVERIFY(f.open(QIODevice::WriteOnly));
        QVERIFY(f.write("{{{ 不是 JSON") > 0);
        f.close();
        MockWebDavClient mock;
        const QByteArray remotePayload = "{\"theme\":{\"mode\":\"light\"}}";
        mock.files["settings.json"] = remotePayload;
        mock.mtimes["settings.json"] = QDateTime(QDate(2026, 1, 1), QTime(0, 0, 0), QTimeZone::UTC);
        SyncManager m(dir.filePath("Readdict.db"), dir.path());
        SyncManager::Options o; o.settings = true; o.progress = false;
        o.highlights = false; o.books = false;
        m.sync(mock, o);
        // KeepLocal 判定后 build() 得空 → 跳过（空载荷绝不上传覆盖远端）
        QVERIFY(m.log().join('\n').contains("跳过 settings.json"));
        QCOMPARE(mock.files["settings.json"], remotePayload);
        QVERIFY(m.buildSettingsJson().isEmpty());
    }

    // ---- 补充：sync 流程——books 元数据 + 书籍文件体按需上传/下载 ----
    void syncFlowBookBodies() {
        QTemporaryDir dir;
        const QString db = dir.filePath("t.db");
        QDir(dir.path()).mkpath("books");
        QFile localBook(dir.path() + "/books/a.epub");
        QVERIFY(localBook.open(QIODevice::WriteOnly));
        QVERIFY(localBook.write("LOCAL-EPUB-CONTENT") > 0);
        localBook.close();
        {
            QSqlDatabase seed = seedDb(db);
            QSqlQuery q(seed);
            QVERIFY2(q.exec(QStringLiteral(
                        "INSERT INTO books(id,title,author,publisher,category,format,path,cover,"
                        "progress,added_at) VALUES(1,'a','作者','社','类','EPUB','%1','',0.0,"
                        "'2026-01-01T00:00:00')").arg(dir.path() + "/books/a.epub")),
                     qPrintable(q.lastError().text()));
            // 五轮复审：FTS 索引行（external-content 表无触发器，addBook 手动维护；
            // 本测试直插 SQL 故手动补，验证 applyBooksJson 采纳元数据时同步维护索引）
            QVERIFY2(q.exec("INSERT INTO books_fts(rowid,title,author,publisher)"
                            " VALUES(1,'a','作者','社')"),
                     qPrintable(q.lastError().text()));
        }
        MockWebDavClient mock;
        // 远端：books.json 元数据（含本地没有的 book 2，addedAt 供内容版本比较）
        // + 已存在的书籍文件体 b2_r.epub
        mock.files["books.json"] =
            "{\"books\":[{\"id\":2,\"title\":\"remote\",\"author\":\"\",\"publisher\":\"\",\"category\":\"\","
            "\"format\":\"EPUB\",\"path\":\"books/r.epub\",\"cover\":\"\","
            "\"addedAt\":\"2026-08-02T00:00:00\"}]}";
        mock.mtimes["books.json"] = QDateTime(QDate(2026, 8, 2), QTime(0, 0, 0), QTimeZone::UTC);
        mock.files["b2_r.epub"] = "REMOTE-EPUB-CONTENT";
        SyncManager m(db, dir.path());
        SyncManager::Options o; o.settings = false; o.progress = false;
        o.highlights = false; o.books = true;
        m.sync(mock, o);
        // 本地书籍文件体缺失于远端 → 上传 b1_a.epub
        QCOMPARE(mock.files.value("b1_a.epub"), QByteArray("LOCAL-EPUB-CONTENT"));
        // 远端书籍文件体缺失于本地 → 下载到 libraryDir/books/r.epub
        QFile downloaded(dir.path() + "/books/r.epub");
        QVERIFY(downloaded.open(QIODevice::ReadOnly));
        QCOMPARE(downloaded.readAll(), QByteArray("REMOTE-EPUB-CONTENT"));
        const QString joined = m.log().join('\n');
        QVERIFY(joined.contains("上传书籍 b1_a.epub"));
        QVERIFY(joined.contains("下载书籍 b2_r.epub"));
        // 复审：addedAt UTC 归一化（跨设备时区不偏移）
        const QJsonArray meta = QJsonDocument::fromJson(m.buildBooksJson())
                                    .object()["books"].toArray();
        QCOMPARE(meta.first().toObject()["addedAt"].toString(),
                 QDateTime::fromString("2026-01-01T00:00:00", Qt::ISODate).toUTC().toString(Qt::ISODate));
        // applyBooksJson：本地无内容键匹配的书 → 不建书（建书属导入流程）并 log；
        // 内容键 (title, author, format) 命中 → 元数据可更新（id 不参与匹配，六轮复审）
        m.applyBooksJson("{\"books\":[{\"id\":2,\"title\":\"a\",\"author\":\"作者\","
                         "\"publisher\":\"P\",\"category\":\"C\",\"format\":\"EPUB\","
                         "\"path\":\"books/a.epub\",\"cover\":\"cov\"}]}");
        QCOMPARE(countRows(db, "books"), 1); // 未新增书
        {
            QSqlDatabase seed = seedDb(db);
            QSqlQuery q(seed);
            q.prepare("SELECT title,author,publisher,category,format,cover FROM books WHERE id=1");
            QVERIFY(q.exec() && q.next());
            QCOMPARE(q.value(0).toString(), QString("a"));    // 内容键命中：标题保留
            QCOMPARE(q.value(1).toString(), QString("作者"));
            QCOMPARE(q.value(2).toString(), QString("P"));    // 远端元数据已合并
            QCOMPARE(q.value(3).toString(), QString("C"));
            QCOMPARE(q.value(4).toString(), QString("EPUB"));
            // 七轮复审：cover 不随载荷同步——本机生成路径，采纳端保留本地封面
            QCOMPARE(q.value(5).toString(), QString(""));
        }
        // 七轮复审：载荷不含 cover（本机绝对路径跨设备无意义）
        const QJsonObject metaFirst = QJsonDocument::fromJson(m.buildBooksJson())
                                          .object()["books"].toArray().first().toObject();
        QVERIFY(!metaFirst.contains("cover"));
        // 五轮复审：采纳元数据后 books_fts 同步维护（external-content 无触发器）
        {
            QSqlDatabase seed = seedDb(db);
            QSqlQuery q(seed);
            q.exec("SELECT title,author,publisher FROM books_fts WHERE rowid=1");
            QVERIFY(q.next());
            QCOMPARE(q.value(0).toString(), QString("a"));
            QCOMPARE(q.value(1).toString(), QString("作者"));
            QCOMPARE(q.value(2).toString(), QString("P"));
        }
    }

    // ---- 补充：sync 失败路径——put 失败记日志 ----
    void syncFlowLogsPutFailure() {
        QTemporaryDir dir;
        const QString db = dir.filePath("t.db");
        {
            QSqlDatabase seed = seedDb(db);
            seedBook(seed, 1, "a", 0.5, "2026-08-01T10:00:00");
        }
        MockWebDavClient mock;
        mock.putReturnsFalse = true;
        SyncManager m(db, dir.path());
        SyncManager::Options o; o.settings = false; o.progress = true;
        o.highlights = false; o.books = false;
        m.sync(mock, o);
        QVERIFY(m.log().join('\n').contains("失败 progress.json"));
    }

    // ---- 补充：sync 失败路径——get 失败记日志且不应用 ----
    void syncFlowLogsGetFailure() {
        QTemporaryDir dir;
        const QString db = dir.filePath("t.db");
        {
            QSqlDatabase seed = seedDb(db);
            seedBook(seed, 1, "a", 0.5, "2026-08-01T10:00:00");
        }
        MockWebDavClient mock;
        mock.files["progress.json"] =
            "{\"books\":[{\"bookId\":1,\"progress\":0.9,\"ts\":\"2026-08-02T00:00:00Z\"}]}";
        mock.getReturnsFalse = true; // 远端内容较新 → TakeRemote，但 GET 失败
        SyncManager m(db, dir.path());
        SyncManager::Options o; o.settings = false; o.progress = true;
        o.highlights = false; o.books = false;
        m.sync(mock, o);
        QVERIFY(m.log().join('\n').contains("失败 progress.json"));
        QCOMPARE(progressOf(db, 1).toDouble(), 0.5); // 未应用远端
    }

    // ---- 补充：sync 流程——远端 settings.json 损坏 → 跳过且不空转 ----
    void syncFlowCorruptRemoteSettingsSkips() {
        QTemporaryDir dir;
        QFile f(dir.filePath("settings.json"));
        QVERIFY(f.open(QIODevice::WriteOnly));
        QVERIFY(f.write("{\"theme\":{\"mode\":\"dark\"}}") > 0);
        f.close();
        MockWebDavClient mock;
        mock.files["settings.json"] = "{{{ 截断的"; // 损坏（解析失败）
        mock.mtimes["settings.json"] = QDateTime::currentDateTimeUtc().addSecs(3600); // 若走 mtime 会 TakeRemote
        SyncManager m(dir.filePath("Readdict.db"), dir.path());
        SyncManager::Options o; o.settings = true; o.progress = false;
        o.highlights = false; o.books = false;
        m.sync(mock, o);
        QVERIFY(m.log().join('\n').contains("跳过 settings.json: 远端数据不可解析"));
        QVERIFY(!m.log().join('\n').contains("采用远端"));
        QCOMPARE(readFileBytes(dir.filePath("settings.json")),
                 QByteArray("{\"theme\":{\"mode\":\"dark\"}}")); // 本地未被损坏内容影响
        // 再次同步同样跳过（不空转：不会每轮 TakeRemote 下载后无效果）
        m.sync(mock, o);
        int skipped = 0;
        for (const QString &l : m.log())
            if (l.contains("跳过 settings.json: 远端数据不可解析"))
                ++skipped;
        QCOMPARE(skipped, 2);
    }

    // ---- 补充：highlights note/color 修改经 sync 传播（版本时钟感知编辑） ----
    void highlightsNotePropagatesViaSync() {
        QTemporaryDir dirA, dirB;
        const QString dbA = dirA.filePath("a.db"), dbB = dirB.filePath("b.db");
        const QString seed = "INSERT INTO highlights(id,book_id,chapter,sentence_index,text,"
                             "color,note,created_at) VALUES(1,1,'ch',3,'text','#FFF','',"
                             "'2026-01-01T00:00:00')";
        {
            QSqlDatabase a = seedDb(dbA);
            QSqlQuery qa(a);
            QVERIFY2(qa.exec(seed), qPrintable(qa.lastError().text()));
        }
        {
            QSqlDatabase b = seedDb(dbB);
            QSqlQuery qb(b);
            QVERIFY2(qb.exec(seed), qPrintable(qb.lastError().text()));
        }
        // A 改笔记：updateNote bump created_at（编辑端版本前移到 T）→ 版本时钟感知编辑
        HighlightManager hmA(dbA, "readdict_hl_a");
        hmA.updateNote(1, "新笔记");
        MockWebDavClient mock;
        SyncManager mA(dbA, dirA.path());
        SyncManager::Options o; o.settings = false; o.progress = false;
        o.highlights = true; o.books = false;
        mA.sync(mock, o); // 远端空 → 上传（载荷带新笔记 + 版本 T）
        QVERIFY(mock.files.contains("highlights.json"));
        QVERIFY(QString::fromUtf8(mock.files["highlights.json"]).contains("新笔记"));
        // B 同步 #1：本地 2026-01-01 < T → TakeRemote 合并；合并更新 created_at 取载荷 T
        // （采用端版本 == 载荷版本，绝不再前移）→ B 收到笔记
        SyncManager mB(dbB, dirB.path(), "readdict_sync_b");
        mB.sync(mock, o);
        HighlightManager hmB(dbB, "readdict_hl_b");
        const QVariantList list = hmB.highlightsForBook(1);
        QCOMPARE(list.size(), 1);
        QCOMPARE(list.first().toMap()["note"].toString(), QString("新笔记")); // 笔记已传播
        // B 同步 #2：本地版本 T == 远端 T → Skip（收敛，不重传）
        const int nB = mB.log().size();
        mB.sync(mock, o);
        QVERIFY(mB.log().mid(nB).join('\n').contains("跳过 highlights.json"));
        // A 同步 #2：本地版本 T == 远端 T → Skip（原编辑端不被超越，无循环下载）
        const int nA = mA.log().size();
        mA.sync(mock, o);
        const QStringList addedA = mA.log().mid(nA);
        QVERIFY(addedA.join('\n').contains("跳过 highlights.json"));
        QVERIFY(!addedA.join('\n').contains("采用远端 highlights.json"));
    }

    // ---- 补充：NULL 章/句索引序列化保留 + 去重不失效 ----
    void highlightsNullFieldsRoundtrip() {
        QTemporaryDir dir;
        const QString db = dir.filePath("t.db");
        {
            QSqlDatabase seed = seedDb(db);
            QSqlQuery q(seed);
            // NULL chapter + NULL sentence_index（C7 允许的外部写入形态）
            QVERIFY2(q.exec("INSERT INTO highlights(id,book_id,chapter,sentence_index,text,color,"
                            "note,created_at) VALUES(1,1,NULL,NULL,'t','#FFF','','2026-01-01T00:00:00')"),
                     qPrintable(q.lastError().text()));
        }
        SyncManager m(db, dir.path());
        const QJsonObject first = QJsonDocument::fromJson(m.buildHighlightsJson())
                                      .object()["highlights"].toArray().first().toObject();
        QVERIFY(first["chapter"].isNull());       // JSON null，不压平为 ""
        QVERIFY(first["sentenceIndex"].isNull()); // JSON null，不压平为 0
        // 重放：NULL 元组正确匹配本地 NULL 行 → 不重复插入
        m.applyHighlightsJson(m.buildHighlightsJson());
        QCOMPARE(countRows(db, "highlights"), 1);
    }

    // ---- 补充：books 版本时钟采纳载荷版本（收敛：不因 apply 无版本前进而重复下载） ----
    void syncFlowBooksAdoptsRemoteVersion() {
        QTemporaryDir dir;
        const QString db = dir.filePath("t.db");
        {
            QSqlDatabase seed = seedDb(db);
            seedBook(seed, 1, "a", 0.0, QString()); // added_at 2026-01-01
        }
        MockWebDavClient mock;
        // 远端有本地没有的新书（addedAt 2026-06-01）→ A 版本低于远端
        mock.files["books.json"] =
            "{\"books\":[{\"id\":2,\"title\":\"remote\",\"author\":\"\",\"publisher\":\"\","
            "\"category\":\"\",\"format\":\"EPUB\",\"path\":\"books/r.epub\",\"cover\":\"\","
            "\"addedAt\":\"2026-06-01T00:00:00Z\"}]}";
        SyncManager m(db, dir.path());
        SyncManager::Options o; o.settings = false; o.progress = false;
        o.highlights = false; o.books = true;
        // #1：本地 max(added 01-01, adopted 无效) < 远端 06-01 → TakeRemote → apply(无此书
        // 不写) + adopted 对齐 06-01
        m.sync(mock, o);
        QVERIFY(m.log().join('\n').contains("采用远端 books.json"));
        // #2/#3：本地版本 = max(01-01, adopted 06-01) == 远端 → Skip（不再重复下载）
        m.sync(mock, o);
        const int n = m.log().size();
        m.sync(mock, o);
        QVERIFY(m.log().mid(n).join('\n').contains("跳过 books.json"));
        // KeepLocal 上传后 adopted 对齐本地数据版本（远端回退时不循环）：远端换成更旧内容
        mock.files["books.json"] =
            "{\"books\":[{\"id\":1,\"title\":\"a\",\"author\":\"\",\"publisher\":\"\","
            "\"category\":\"\",\"format\":\"EPUB\",\"path\":\"books/a.epub\",\"cover\":\"\","
            "\"addedAt\":\"2026-01-01T00:00:00Z\"}]}";
        mock.mtimes["books.json"] = QDateTime(QDate(2025, 1, 1), QTime(0, 0, 0), QTimeZone::UTC);
        m.sync(mock, o); // 远端回退到 01-01：adopted 06-01 > 远端 → KeepLocal 上传本地载荷
        QVERIFY(m.log().mid(n).join('\n').contains("保留本地 books.json"));
        const int n2 = m.log().size();
        m.sync(mock, o); // 上传后 adopted := 本地数据 max 01-01 == 远端 → Skip，不循环
        QVERIFY(m.log().mid(n2).join('\n').contains("跳过 books.json"));
    }

    // ---- 补充：highlights 无字段差异时版本单调追赶（避免永 TakeRemote 空转） ----
    void highlightsAdoptsNewerVersionWithoutDiff() {
        QTemporaryDir dir;
        const QString db = dir.filePath("t.db");
        {
            QSqlDatabase seed = seedDb(db);
            seedHighlight(seed, 1, 1, "ch", 3, "text", "2026-01-01T00:00:00");
        }
        SyncManager m(db, dir.path());
        // 双设备独立划线同句：四元组同、color/note 同，但载荷 createdAt 更新 → 采纳版本
        m.applyHighlightsJson("{\"highlights\":[{\"bookId\":1,\"chapter\":\"ch\","
                              "\"sentenceIndex\":3,\"text\":\"text\",\"color\":\"#FFD54F\","
                              "\"note\":\"\",\"createdAt\":\"2026-06-01T00:00:00Z\"}]}");
        QCOMPARE(countRows(db, "highlights"), 1);
        {
            QSqlDatabase seed = seedDb(db);
            QSqlQuery q(seed);
            q.prepare("SELECT created_at FROM highlights WHERE id=1");
            QVERIFY(q.exec() && q.next());
            const QDateTime rowCreated = QDateTime::fromString(q.value(0).toString(), Qt::ISODate);
            QVERIFY(rowCreated.isValid());
            QCOMPARE(rowCreated, QDateTime(QDate(2026, 6, 1), QTime(0, 0, 0), QTimeZone::UTC)); // 版本已追赶
        }
        // 重放同载荷 → 版本已对齐，无更新（幂等）
        m.applyHighlightsJson("{\"highlights\":[{\"bookId\":1,\"chapter\":\"ch\","
                              "\"sentenceIndex\":3,\"text\":\"text\",\"color\":\"#FFD54F\","
                              "\"note\":\"\",\"createdAt\":\"2026-06-01T00:00:00Z\"}]}");
        {
            QSqlDatabase seed = seedDb(db);
            QSqlQuery q(seed);
            q.prepare("SELECT created_at FROM highlights WHERE id=1");
            QVERIFY(q.exec() && q.next());
            QCOMPARE(QDateTime::fromString(q.value(0).toString(), Qt::ISODate),
                     QDateTime(QDate(2026, 6, 1), QTime(0, 0, 0), QTimeZone::UTC));
        }
    }

    // ---- 补充：编辑 bump 毫秒精度（同秒两次编辑版本可区分） ----
    void highlightEditBumpsWithMs() {
        QTemporaryDir dir;
        const QString db = dir.filePath("t.db");
        {
            QSqlDatabase seed = seedDb(db);
            seedHighlight(seed, 1, 1, "ch", 3, "text", "2026-01-01T00:00:00");
        }
        HighlightManager hm(db, "readdict_hl_ms");
        hm.updateNote(1, "n1");
        {
            QSqlDatabase seed = seedDb(db);
            QSqlQuery q(seed);
            q.prepare("SELECT created_at FROM highlights WHERE id=1");
            QVERIFY(q.exec() && q.next());
            const QString t1 = q.value(0).toString();
            QVERIFY(t1.contains('.')); // ISODateWithMs 恒含毫秒字段
            QVERIFY(QDateTime::fromString(t1, Qt::ISODateWithMs).isValid());
        }
        hm.updateColor(1, "#000");
        {
            QSqlDatabase seed = seedDb(db);
            QSqlQuery q(seed);
            q.prepare("SELECT created_at FROM highlights WHERE id=1");
            QVERIFY(q.exec() && q.next());
            QVERIFY(q.value(0).toString().contains('.'));
        }
    }

    // ---- 补充：本地无数据时远端损坏 → 跳过且不空转（新设备） ----
    void syncFlowDownloadsCorruptPayloadSkips() {
        QTemporaryDir dir;
        const QString db = dir.filePath("t.db");
        {
            QSqlDatabase seed = seedDb(db);
            seedBook(seed, 1, "a", 0.0, QString()); // 有书无进度 → 本地无进度数据
        }
        MockWebDavClient mock;
        mock.files["progress.json"] = "{{{ 截断的"; // 损坏
        mock.mtimes["progress.json"] = QDateTime::currentDateTimeUtc();
        SyncManager m(db, dir.path());
        SyncManager::Options o; o.settings = false; o.progress = true;
        o.highlights = false; o.books = false;
        m.sync(mock, o);
        QVERIFY(m.log().join('\n').contains("跳过 progress.json: 远端数据不可解析"));
        QVERIFY(!m.log().join('\n').contains("下载 progress.json")); // 未标下载
        QCOMPARE(progressOf(db, 1).toDouble(), 0.0);
        // 再次同步同样跳过（不空转）
        m.sync(mock, o);
        int skipped = 0;
        for (const QString &l : m.log())
            if (l.contains("跳过 progress.json: 远端数据不可解析"))
                ++skipped;
        QCOMPARE(skipped, 2);
    }

    // ---- 补充：books KeepLocal 上传前合并远端独有书目（数据丢失修复） ----
    void syncFlowBooksKeepLocalPreservesRemote() {
        QTemporaryDir dir;
        const QString db = dir.filePath("t.db");
        {
            QSqlDatabase seed = seedDb(db);
            // B 导入新书（added_at 07-01）；added_at 需改 seedBook 默认，直插 SQL
            QSqlQuery q(seed);
            QVERIFY2(q.exec("INSERT INTO books(id,title,format,path,added_at,progress)"
                            " VALUES(1,'b','EPUB','/lib/books/b.epub','2026-07-01T00:00:00',0.0)"),
                     qPrintable(q.lastError().text()));
        }
        MockWebDavClient mock;
        // 远端：A 的已有书目（id=2，B 本地没有）——标准多设备流程：A 同步后 B 首次同步
        // （adopted=01-01），B 再导入新书后 KeepLocal
        mock.files["books.json"] =
            "{\"books\":[{\"id\":2,\"title\":\"A的书\",\"author\":\"A\",\"publisher\":\"\","
            "\"category\":\"\",\"format\":\"EPUB\",\"path\":\"books/a.epub\",\"cover\":\"\","
            "\"addedAt\":\"2026-01-01T00:00:00Z\"}]}";
        SyncManager m(db, dir.path());
        SyncManager::Options o; o.settings = false; o.progress = false;
        o.highlights = false; o.books = true;
        m.sync(mock, o); // 本地 max(07-01) > 远端 01-01 → KeepLocal
        QVERIFY(m.log().join('\n').contains("保留本地 books.json"));
        // 上传载荷 = 本地书（id=1）+ 远端独有书（id=2）——A 的书目不丢失
        const QJsonArray merged =
            QJsonDocument::fromJson(mock.files["books.json"]).object()["books"].toArray();
        QSet<qint64> ids;
        for (const QJsonValue &v : merged)
            ids.insert(v.toObject()["id"].toVariant().toLongLong());
        QVERIFY(ids.contains(1));
        QVERIFY(ids.contains(2)); // 远端独有书目被并入，未丢失
        QCOMPARE(merged.size(), 2);
    }

    // ---- 补充：settings 空载荷对称处理——远端空本地有内容 → KeepLocal 上传 ----
    void syncFlowEmptyRemoteSettingsKeepsLocal() {
        QTemporaryDir dir;
        QFile f(dir.filePath("settings.json"));
        QVERIFY(f.open(QIODevice::WriteOnly));
        QVERIFY(f.write("{\"theme\":{\"mode\":\"dark\"}}") > 0);
        f.close();
        MockWebDavClient mock;
        mock.files["settings.json"] = "{}"; // 合法空 JSON（无白名单键）
        mock.mtimes["settings.json"] = QDateTime::currentDateTimeUtc().addSecs(3600); // mtime 较新
        SyncManager m(dir.filePath("Readdict.db"), dir.path());
        SyncManager::Options o; o.settings = true; o.progress = false;
        o.highlights = false; o.books = false;
        // 六轮复审：远端空 + 本地有内容 → 内容不等 → 版本压 epoch → KeepLocal 上传
        // （本地设置必须向空远端传播，否则拓扑死锁）；mtime 较新也不能 TakeRemote
        m.sync(mock, o);
        QVERIFY(m.log().join('\n').contains("保留本地 settings.json"));
        QVERIFY(!m.log().join('\n').contains("采用远端 settings.json"));
        QCOMPARE(mock.putNames, QStringList({"settings.json"}));
        QCOMPARE(QJsonDocument::fromJson(mock.files["settings.json"]).object()
                     ["theme"].toObject()["mode"].toString(),
                 QString("dark")); // 空远端已被本地设置填上
        // 再次同步：内容一致 → Skip（收敛）
        m.sync(mock, o);
        QVERIFY(m.log().join('\n').contains("跳过 settings.json"));
        // 两侧都空 → Skip（对称）
        QTemporaryDir dir2;
        QFile f2(dir2.filePath("settings.json"));
        QVERIFY(f2.open(QIODevice::WriteOnly));
        QVERIFY(f2.write("{}") > 0);
        f2.close();
        MockWebDavClient mock2;
        mock2.files["settings.json"] = "{}";
        mock2.mtimes["settings.json"] = QDateTime::currentDateTimeUtc().addSecs(3600);
        SyncManager m2(dir2.filePath("Readdict.db"), dir2.path(), "readdict_sync_2");
        m2.sync(mock2, o);
        QVERIFY(m2.log().join('\n').contains("跳过 settings.json"));
        QVERIFY(mock2.putNames.isEmpty());
    }

    // ---- 补充：books 同 id 不同内容键（六轮复审：内容键匹配，id 不参与） ----
    void syncFlowBooksSameIdDifferentContent() {
        QTemporaryDir dirA, dirB;
        const QString dbA = dirA.filePath("a.db"), dbB = dirB.filePath("b.db");
        {
            QSqlDatabase seed = seedDb(dbA);
            QSqlQuery q(seed);
            // A 的书 X：id=1（两台设备各自首本书都是 id=1）
            QVERIFY2(q.exec("INSERT INTO books(id,title,author,format,path,added_at,progress)"
                            " VALUES(1,'X','甲','EPUB','/lib/books/x.epub',"
                            "'2026-01-01T00:00:00',0.0)"),
                     qPrintable(q.lastError().text()));
            QVERIFY2(q.exec("INSERT INTO books_fts(rowid,title,author,publisher)"
                            " VALUES(1,'X','甲','')"),
                     qPrintable(q.lastError().text()));
        }
        {
            QSqlDatabase seed = seedDb(dbB);
            QSqlQuery q(seed);
            // B 的书 Y：同样 id=1，但内容键不同
            QVERIFY2(q.exec("INSERT INTO books(id,title,author,format,path,added_at,progress)"
                            " VALUES(1,'Y','乙','EPUB','/lib/books/y.epub',"
                            "'2026-07-01T00:00:00',0.0)"),
                     qPrintable(q.lastError().text()));
        }
        MockWebDavClient mock;
        // 远端：A 已同步的 X（id=1，addedAt 01-01）
        mock.files["books.json"] =
            "{\"books\":[{\"id\":1,\"title\":\"X\",\"author\":\"甲\",\"publisher\":\"\","
            "\"category\":\"\",\"format\":\"EPUB\",\"path\":\"books/x.epub\",\"cover\":\"\","
            "\"addedAt\":\"2026-01-01T00:00:00Z\"}]}";
        SyncManager mB(dbB, dirB.path());
        SyncManager::Options o; o.settings = false; o.progress = false;
        o.highlights = false; o.books = true;
        // B（新书 Y，07-01）KeepLocal：内容键去重——X 与 Y 内容键不同 → X 并入不丢失
        mB.sync(mock, o);
        QVERIFY(mB.log().join('\n').contains("保留本地 books.json"));
        const QJsonArray merged =
            QJsonDocument::fromJson(mock.files["books.json"]).object()["books"].toArray();
        QSet<QString> titles;
        for (const QJsonValue &v : merged)
            titles.insert(v.toObject()["title"].toString());
        QVERIFY(titles.contains("Y"));
        QVERIFY(titles.contains("X")); // 同 id 不同内容键：A 的书不被 B 覆盖丢失
        // A 随后同步：下载合并载荷（含 Y）→ applyBooksJson 内容键匹配——Y 与本地 X
        // 内容键不同 → 跳过 + log，绝不按 id=1 覆盖 X 的元数据
        SyncManager mA(dbA, dirA.path(), "readdict_sync_a");
        mA.sync(mock, o);
        {
            QSqlDatabase seed = seedDb(dbA);
            QSqlQuery q(seed);
            q.prepare("SELECT title,author FROM books WHERE id=1");
            QVERIFY(q.exec() && q.next());
            QCOMPARE(q.value(0).toString(), QString("X")); // 未被 Y 覆盖
            QCOMPARE(q.value(1).toString(), QString("甲"));
        }
        QVERIFY(mA.log().join('\n').contains("待书籍同步后注册")); // 未命中跳过已 log
    }
};
QTEST_MAIN(TestSync)
#include "tst_syncmanager.moc"
