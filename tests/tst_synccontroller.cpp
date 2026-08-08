// D3：SyncController 集成测试——真实 SyncController + 真实 WebDavClient 走本地
// QTcpServer mock（D1 mock 模式）。验证：
//   1. 成功路径（空远端 + 本地有数据）：finished(true, "") 到达、日志透出
//      （上传 settings.json / progress.json）、running 复位、请求确实发出；
//   2. 不可达服务器（连接拒绝）：finished(false, error) 到达、日志含失败行、不崩溃；
//   3. setAutoSync 开关与空选项 run 不崩溃（防重入）。
#include <QtTest>
#include <QTcpServer>
#include <QTcpSocket>
#include <QHash>
#include <QSqlQuery>
#include <QSqlError>
#include <QTemporaryDir>
#include <QSignalSpy>
#include "core/DatabaseManager.h"
#include "core/SettingsStore.h"
#include "SyncController.h"

// 空远端 mock：PROPFIND → 空 multistatus（首次同步=远端无文件），
// MKCOL/PUT → 201 Created（目录就绪 + 上传成功），GET → 404。
class EmptyDav : public QTcpServer {
    Q_OBJECT
public:
    QList<QByteArray> methods;
protected:
    void incomingConnection(qintptr fd) override {
        QTcpSocket *s = new QTcpSocket(this);
        s->setSocketDescriptor(fd);
        m_buf[s] = QByteArray();
        connect(s, &QTcpSocket::readyRead, this, [this, s] { onReadyRead(s); });
        connect(s, &QTcpSocket::disconnected, s, &QObject::deleteLater);
        connect(s, &QTcpSocket::disconnected, this, [this, s] { m_buf.remove(s); });
    }
private:
    QHash<QTcpSocket *, QByteArray> m_buf;
    void onReadyRead(QTcpSocket *s) {
        QByteArray &req = m_buf[s];
        req += s->readAll();
        const int hdrEnd = req.indexOf("\r\n\r\n");
        if (hdrEnd < 0)
            return;
        int contentLength = 0;
        for (const QByteArray &line : req.left(hdrEnd).split('\n')) {
            const QByteArray l = line.trimmed().toLower();
            if (l.startsWith("content-length:"))
                contentLength = l.mid(15).trimmed().toInt();
        }
        if (req.size() < hdrEnd + 4 + contentLength)
            return;
        methods.append(req.left(hdrEnd).split(' ').value(0));
        QByteArray status = "201 Created";
        QByteArray body;
        if (req.left(hdrEnd).startsWith("PROPFIND")) {
            status = "207 Multi-Status";
            body = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
                   "<d:multistatus xmlns:d=\"DAV:\"></d:multistatus>";
        }
        const QByteArray resp = "HTTP/1.1 " + status + "\r\n"
            "Content-Type: application/xml\r\n"
            "Content-Length: " + QByteArray::number(body.size()) + "\r\n"
            "Connection: close\r\n\r\n" + body;
        s->write(resp);
        s->flush();
        s->disconnectFromHost();
    }
};

// L8（P1#18）：带数据的远端 mock——PROPFIND 列出 progress.json（mtime 较新），
// GET 返回载荷——驱动 SyncController 的 TakeRemote 应用路径（dataApplied 转发）
class ProgressDav : public QTcpServer {
    Q_OBJECT
protected:
    void incomingConnection(qintptr fd) override {
        QTcpSocket *s = new QTcpSocket(this);
        s->setSocketDescriptor(fd);
        m_buf[s] = QByteArray();
        connect(s, &QTcpSocket::readyRead, this, [this, s] { onReadyRead(s); });
        connect(s, &QTcpSocket::disconnected, s, &QObject::deleteLater);
        connect(s, &QTcpSocket::disconnected, this, [this, s] { m_buf.remove(s); });
    }
private:
    QHash<QTcpSocket *, QByteArray> m_buf;
    // 载荷版本 2026-08-02（晚于本地 08-01）→ TakeRemote 应用。
    // char 数组（非指针）：QByteArrayLiteral 需字面量数组推导长度
    static constexpr char kPayload[] =
        "{\"books\":[{\"bookId\":1,\"progress\":0.9,\"ts\":\"2026-08-02T00:00:00Z\"}]}";
    void onReadyRead(QTcpSocket *s) {
        QByteArray &req = m_buf[s];
        req += s->readAll();
        const int hdrEnd = req.indexOf("\r\n\r\n");
        if (hdrEnd < 0)
            return;
        int contentLength = 0;
        for (const QByteArray &line : req.left(hdrEnd).split('\n')) {
            const QByteArray l = line.trimmed().toLower();
            if (l.startsWith("content-length:"))
                contentLength = l.mid(15).trimmed().toInt();
        }
        if (req.size() < hdrEnd + 4 + contentLength)
            return;
        QByteArray status = "201 Created"; // MKCOL/PUT
        QByteArray body;
        if (req.left(hdrEnd).startsWith("PROPFIND")) {
            status = "207 Multi-Status";
            body = QByteArrayLiteral("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
                   "<d:multistatus xmlns:d=\"DAV:\">"
                   "<d:response><d:href>/dav/progress.json</d:href>"
                   "<d:propstat><d:prop>"
                   "<d:getlastmodified>2026-08-02T00:00:00Z</d:getlastmodified>"
                   "<d:getcontentlength>71</d:getcontentlength>"
                   "</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>"
                   "</d:response></d:multistatus>");
        } else if (req.left(hdrEnd).startsWith("GET")) {
            status = "200 OK";
            body = QByteArrayLiteral(kPayload);
        }
        const QByteArray resp = "HTTP/1.1 " + status + "\r\n"
            "Content-Type: application/json\r\n"
            "Content-Length: " + QByteArray::number(body.size()) + "\r\n"
            "Connection: close\r\n\r\n" + body;
        s->write(resp);
        s->flush();
        s->disconnectFromHost();
    }
};

class TestSyncController : public QObject {
    Q_OBJECT
private slots:
    // 成功路径：空远端（首次同步）→ 本地有数据项全部上传，finished(true) 到达
    void syncsToLocalMockServer() {
        EmptyDav server;
        QVERIFY2(server.listen(QHostAddress::LocalHost, 0), "mock 服务器应能监听");
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        // 造库：schema + 一条有进度的书（progress 同步项有数据 → 上传 progress.json）
        {
            DatabaseManager dbm(dir.path() + "/t.db", QStringLiteral("synccontroller_test"));
            QSqlQuery q(dbm.database());
            QVERIFY2(q.exec("INSERT INTO books(title,author,format,path,progress,read_seconds,last_read_at,added_at) "
                            "VALUES('测试书','作者','TXT','/tmp/t.txt',0.5,120,"
                            "'2026-08-07T10:00:00Z','2026-08-07T09:00:00Z')"),
                     q.lastError().text().toUtf8());
        }
        SettingsStore st(dir.path() + "/settings.json");
        st.setValue("webdav/url",
                    QStringLiteral("http://127.0.0.1:%1/dav/").arg(server.serverPort()));
        st.setValue("webdav/user", "u");
        st.setValue("webdav/password", "p");
        st.save();

        SyncController ctl(dir.path() + "/t.db", dir.path(), QStringLiteral("synccontroller_conn") + QTest::currentTestFunction());
        bool got = false, ok = false;
        QString err;
        QObject::connect(&ctl, &SyncController::finished,
                         [&](bool o, const QString &e) { got = true; ok = o; err = e; });
        ctl.run(true, true, false, false);

        QVERIFY2(got, "finished 信号应到达（run 同步阻塞）");
        QVERIFY2(ok, ("成功路径 finished 应为 true，error=" + err).toUtf8());
        QVERIFY2(!ctl.running(), "同步结束后 running 应为 false");
        const QString logText = ctl.log().join(QLatin1Char('\n'));
        QVERIFY2(logText.contains(QStringLiteral("上传 settings.json")),
                 ("日志应含 settings 上传，实际:\n" + logText).toUtf8());
        QVERIFY2(logText.contains(QStringLiteral("上传 progress.json")),
                 ("日志应含 progress 上传，实际:\n" + logText).toUtf8());
        QVERIFY2(server.methods.contains("PROPFIND"), "应先 PROPFIND 列表远端");
        QVERIFY2(server.methods.contains("PUT"), "本地有数据应 PUT 上传");
    }

    // 错误配置（不可达服务器）：finished(false, error) 到达、日志含失败行、不崩溃
    void unreachableServerFailsGracefully() {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        SettingsStore st(dir.path() + "/settings.json");
        st.setValue("webdav/url", "http://127.0.0.1:1/dav/"); // port 1：连接拒绝
        st.save();
        DatabaseManager dbm(dir.path() + "/t.db", QStringLiteral("synccontroller_test2"));
        SyncController ctl(dir.path() + "/t.db", dir.path(), QStringLiteral("synccontroller_conn") + QTest::currentTestFunction());

        bool got = false, ok = true;
        QString err;
        QObject::connect(&ctl, &SyncController::finished,
                         [&](bool o, const QString &e) { got = true; ok = o; err = e; });
        ctl.run(true, false, false, false);

        QVERIFY2(got, "finished 信号应到达");
        QVERIFY2(!ok, "不可达服务器应判定失败");
        QVERIFY2(!err.isEmpty(), "失败应带 error 文本");
        const QString logText = ctl.log().join(QLatin1Char('\n'));
        QVERIFY2(logText.contains(QStringLiteral("失败")),
                 ("日志应含失败行，实际:\n" + logText).toUtf8());
        QVERIFY2(!ctl.running(), "同步结束后 running 应为 false");
    }

    // setAutoSync 开关：只启停定时器，不崩溃
    void autoSyncToggleIsSafe() {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        DatabaseManager dbm(dir.path() + "/t.db", QStringLiteral("synccontroller_test3"));
        SyncController ctl(dir.path() + "/t.db", dir.path(), QStringLiteral("synccontroller_conn") + QTest::currentTestFunction());
        ctl.setAutoSync(true);
        ctl.setAutoSync(false);
        ctl.setAutoSync(true);
        ctl.setAutoSync(false);
        QVERIFY(true);
    }

    // 全项关闭的空转 run：finished(true) 且不崩溃（m_running 门控）
    void noopRunSucceeds() {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        DatabaseManager dbm(dir.path() + "/t.db", QStringLiteral("synccontroller_test4"));
        SettingsStore st(dir.path() + "/settings.json");
        st.setValue("webdav/url", "");
        st.save();
        SyncController ctl(dir.path() + "/t.db", dir.path(), QStringLiteral("synccontroller_conn") + QTest::currentTestFunction());
        bool got = false, ok = false;
        QObject::connect(&ctl, &SyncController::finished,
                         [&](bool o, const QString &) { got = true; ok = o; });
        ctl.run(false, false, false, false); // 无勾选项：空转成功
        QVERIFY2(got, "finished 信号应到达");
        QVERIFY2(ok, "无勾选项应判定成功（无失败行）");
        QVERIFY2(!ctl.running(), "同步结束后 running 应为 false");
    }

    // D3 复审回归：历史失败不得污染本次判定——先不可达失败，再本地 mock 成功，
    // 第二次 finished 必须为 (true, "")（SyncManager::sync 开始清空 m_log）
    void staleFailureDoesNotPoisonNextRun() {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString conn = QStringLiteral("synccontroller_conn") + QTest::currentTestFunction();
        DatabaseManager dbm(dir.path() + "/t.db", QStringLiteral("synccontroller_dbm") + QTest::currentTestFunction());
        SettingsStore st(dir.path() + "/settings.json");
        SyncController ctl(dir.path() + "/t.db", dir.path(), conn);

        // 第一次：不可达服务器 → 失败
        st.setValue("webdav/url", "http://127.0.0.1:1/dav/");
        st.save();
        bool got = false, ok = true;
        QString err;
        QObject::connect(&ctl, &SyncController::finished,
                         [&](bool o, const QString &e) { got = true; ok = o; err = e; });
        ctl.run(true, false, false, false);
        QVERIFY2(got && !ok, "第一次（不可达）应失败");

        // 第二次：本地 mock → 成功；不得受第一次失败行影响
        EmptyDav server;
        QVERIFY2(server.listen(QHostAddress::LocalHost, 0), "mock 服务器应能监听");
        st.setValue("webdav/url",
                    QStringLiteral("http://127.0.0.1:%1/dav/").arg(server.serverPort()));
        st.save();
        got = false; ok = false; err.clear();
        ctl.run(true, false, false, false);
        QVERIFY2(got, "第二次 finished 应到达");
        QVERIFY2(ok, ("后续成功同步不应被历史失败污染，error=" + err).toUtf8());
        QVERIFY2(err.isEmpty(), "成功同步 error 应为空");
        QVERIFY2(!ctl.running(), "同步结束后 running 应为 false");
    }

    // D3 复审回归：books 信息行可含书名/文件名里的"失败"字（如《失败的逻辑》），
    // 不得误判为同步失败——失败判定只看时间戳后紧跟"失败"的消息
    void bookTitleContainingFailureWordStillSucceeds() {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        // 真实书籍文件（文件名含"失败"）
        const QString bookPath = dir.filePath("失败的逻辑.txt");
        QFile bookFile(bookPath);
        QVERIFY(bookFile.open(QIODevice::WriteOnly));
        bookFile.write("内容");
        bookFile.close();
        {
            DatabaseManager dbm(dir.path() + "/t.db",
                                QStringLiteral("synccontroller_dbm") + QTest::currentTestFunction());
            QSqlQuery q(dbm.database());
            QVERIFY2(q.exec("INSERT INTO books(title,format,path,added_at) "
                            "VALUES('失败的逻辑','TXT','" + bookPath + "','2026-08-07T09:00:00Z')"),
                     q.lastError().text().toUtf8());
        }
        EmptyDav server;
        QVERIFY2(server.listen(QHostAddress::LocalHost, 0), "mock 服务器应能监听");
        SettingsStore st(dir.path() + "/settings.json");
        st.setValue("webdav/url",
                    QStringLiteral("http://127.0.0.1:%1/dav/").arg(server.serverPort()));
        st.save();
        SyncController ctl(dir.path() + "/t.db", dir.path(),
                           QStringLiteral("synccontroller_conn") + QTest::currentTestFunction());

        bool got = false, ok = false;
        QString err;
        QObject::connect(&ctl, &SyncController::finished,
                         [&](bool o, const QString &e) { got = true; ok = o; err = e; });
        ctl.run(false, false, false, true); // 仅 books 同步（含文件体上传）

        QVERIFY2(got, "finished 信号应到达");
        QVERIFY2(ok, ("书名/文件名含'失败'的成功同步应判定成功，error=" + err).toUtf8());
        QVERIFY2(err.isEmpty(), "成功同步 error 应为空");
        const QString logText = ctl.log().join(QLatin1Char('\n'));
        QVERIFY2(logText.contains(QStringLiteral("失败的逻辑")),
                 ("日志应含书籍文件上传行，实际:\n" + logText).toUtf8());
        QVERIFY2(!ctl.running(), "同步结束后 running 应为 false");
    }

    // L8（P1#18）：TakeRemote 成功应用远端数据 → SyncController::dataApplied 转发到达，
    // finished(true)；数据确实落库（SyncManager::syncApplied → dataApplied 接线回归）
    void appliedDataEmitsDataApplied() {
        ProgressDav server;
        QVERIFY2(server.listen(QHostAddress::LocalHost, 0), "mock 服务器应能监听");
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString conn = QStringLiteral("synccontroller_conn") + QTest::currentTestFunction();
        {
            DatabaseManager dbm(dir.path() + "/t.db", conn);
            QSqlQuery q(dbm.database());
            QVERIFY2(q.exec("INSERT INTO books(title,format,path,progress,last_read_at,added_at) "
                            "VALUES('测试书','TXT','/tmp/t.txt',0.5,"
                            "'2026-08-01T10:00:00Z','2026-08-01T09:00:00Z')"),
                     q.lastError().text().toUtf8());
        }
        SettingsStore st(dir.path() + "/settings.json");
        st.setValue("webdav/url",
                    QStringLiteral("http://127.0.0.1:%1/dav/").arg(server.serverPort()));
        st.save();
        SyncController ctl(dir.path() + "/t.db", dir.path(), conn);
        QSignalSpy dataSpy(&ctl, &SyncController::dataApplied);
        bool got = false, ok = false;
        QObject::connect(&ctl, &SyncController::finished,
                         [&](bool o, const QString &) { got = true; ok = o; });
        ctl.run(false, true, false, false); // 仅 progress
        QVERIFY2(got, "finished 信号应到达");
        QVERIFY2(ok, "远端应用成功应判定成功");
        QCOMPARE(dataSpy.count(), 1); // syncApplied 已转发为 dataApplied
        // 数据确实落库：SyncManager 构造时同名 addDatabase 移除了种子 dbm 的连接，
        // 用独立验证连接（tst_syncmanager 的 progressOf 同模式）
        QSqlDatabase v = QSqlDatabase::addDatabase("QSQLITE", "synccontroller_verify");
        v.setDatabaseName(dir.path() + "/t.db");
        QVERIFY(v.open());
        QSqlQuery q(v);
        q.prepare("SELECT progress FROM books WHERE id=1");
        QVERIFY(q.exec() && q.next());
        QCOMPARE(q.value(0).toDouble(), 0.9); // 远端进度已应用
        v = QSqlDatabase(); // 先释放句柄再移除连接，避免 "still in use" 告警
        QSqlDatabase::removeDatabase("synccontroller_verify");
    }
};

QTEST_MAIN(TestSyncController)
#include "tst_synccontroller.moc"
