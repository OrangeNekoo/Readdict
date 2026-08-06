// D1：WebDavClient（协议子集）— 本地 QTcpServer mock 验证 PROPFIND/MKCOL/PUT/GET/DELETE
#include <QtTest>
#include <QTcpServer>
#include <QTcpSocket>
#include <QHash>
#include <QTimeZone>
#include "WebDavClient.h"

// 每个连接处理一个完整请求：收齐 header + Content-Length 对齐 body 后按方法回固定响应，
// 然后主动关闭连接（避免 keep-alive 状态机复杂化）。记录全部请求供断言。
struct MockRequest {
    QByteArray method, path, body, auth;
};

class MockDav : public QTcpServer {
    Q_OBJECT
public:
    QList<MockRequest> requests;
    // MKCOL 响应状态：默认 405（目录已存在）；用例可改 201 Created 锁定创建成功路径
    QByteArray mkcolStatus = "405 Method Not Allowed";

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
            return; // body 未收齐，等下一次 readyRead

        MockRequest mr;
        const QList<QByteArray> head = req.left(hdrEnd).split(' ');
        mr.method = head.value(0);
        mr.path = head.value(1);
        mr.body = req.mid(hdrEnd + 4);
        for (const QByteArray &line : req.left(hdrEnd).split('\n')) {
            const QByteArray l = line.trimmed();
            if (l.toLower().startsWith("authorization:"))
                mr.auth = l.mid(14).trimmed();
        }
        requests.append(mr);

        const QByteArray body = responseBody(mr);
        const QByteArray resp = "HTTP/1.1 " + statusLine(mr) + "\r\n"
            "Content-Type: application/xml\r\n"
            "Content-Length: " + QByteArray::number(body.size()) + "\r\n"
            "Connection: close\r\n\r\n" + body;
        s->write(resp);
        s->flush();
        s->disconnectFromHost();
    }

    // getlastmodified 用 RFC 1123（RFC 4918 规定的 DAV:getlastmodified 格式）；
    // notes.txt 故意用 RFC3339、my%20file.json 用 percent-encoded href、subdir/ 尾斜杠、
    // a%2Fb.json 的 %2F 编码斜杠（核心保证：先按字面 '/' 切分再 percent-decode，%2F 不误切）、
    // settings.json 的 404 propstat（Apache mod_dav 对集合即发，空 prop 不得覆盖 200 值）
    QByteArray responseBody(const MockRequest &mr) {
        if (mr.method == "PROPFIND")
            return "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
                   "<d:multistatus xmlns:d=\"DAV:\">"
                   "<d:response><d:href>/sync/settings.json</d:href>"
                   "<d:propstat><d:prop>"
                   "<d:getlastmodified>Tue, 04 Aug 2026 00:00:00 GMT</d:getlastmodified>"
                   "<d:getcontentlength>12</d:getcontentlength>"
                   "</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>"
                   "<d:propstat><d:prop>"
                   "<d:getlastmodified/>"
                   "<d:getcontentlength/>"
                   "</d:prop><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat></d:response>"
                   "<d:response><d:href>/sync/notes.txt</d:href>"
                   "<d:propstat><d:prop>"
                   "<d:getlastmodified>2026-08-05T10:30:00Z</d:getlastmodified>"
                   "<d:getcontentlength>7</d:getcontentlength>"
                   "</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>"
                   "<d:response><d:href>/sync/my%20file.json</d:href>"
                   "<d:propstat><d:prop>"
                   "<d:getcontentlength>9</d:getcontentlength>"
                   "</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>"
                   "<d:response><d:href>/sync/a%2Fb.json</d:href>"
                   "<d:propstat><d:prop>"
                   "<d:getcontentlength>8</d:getcontentlength>"
                   "</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>"
                   "<d:response><d:href>/sync/subdir/</d:href>"
                   "<d:propstat><d:prop>"
                   "<d:getcontentlength>0</d:getcontentlength>"
                   "</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>"
                   "</d:multistatus>";
        if (mr.method == "GET" && mr.path.endsWith("missing.json"))
            return "Not Found";
        return "hello";
    }

    QByteArray statusLine(const MockRequest &mr) {
        if (mr.method == "PROPFIND")
            return "207 Multi-Status";
        // MKCOL：默认目录已存在（405）——验证 put() 的 MKCOL 兜底不阻断 PUT；
        // 用例可改 mkcolStatus 为 "201 Created" 锁定创建成功路径
        if (mr.method == "MKCOL")
            return mkcolStatus;
        if (mr.method == "GET" && mr.path.endsWith("missing.json"))
            return "404 Not Found";
        return "200 OK";
    }
};

class TestWebDav : public QObject {
    Q_OBJECT
private slots:
    // put：MKCOL 兜底 + PUT，baseUrl 无尾斜杠自动补全，Basic Auth 正确
    void putMkcolThenPut() {
        MockDav server;
        QVERIFY(server.listen(QHostAddress::LocalHost, 0));
        WebDavClient c("http://127.0.0.1:" + QString::number(server.serverPort()) + "/sync", "u", "p");
        QVERIFY(c.put("settings.json", QByteArray("hello")));
        QVERIFY(c.lastError().isEmpty());
        QCOMPARE(server.requests.size(), 2); // MKCOL + PUT
        QCOMPARE(server.requests[0].method, QByteArray("MKCOL"));
        QCOMPARE(server.requests[0].path, QByteArray("/sync/"));
        QCOMPARE(server.requests[1].method, QByteArray("PUT"));
        QCOMPARE(server.requests[1].path, QByteArray("/sync/settings.json"));
        QCOMPARE(server.requests[1].body, QByteArray("hello"));
        QCOMPARE(server.requests[1].auth, QByteArray("Basic dTpw")); // base64("u:p")
    }

    // get：GET 返回 body
    void getReturnsBody() {
        MockDav server;
        QVERIFY(server.listen(QHostAddress::LocalHost, 0));
        WebDavClient c("http://127.0.0.1:" + QString::number(server.serverPort()) + "/sync", "u", "p");
        QCOMPARE(c.get("settings.json"), QByteArray("hello"));
        QVERIFY(c.lastError().isEmpty());
        QCOMPARE(server.requests.last().method, QByteArray("GET"));
        QCOMPARE(server.requests.last().path, QByteArray("/sync/settings.json"));
    }

    // get 404：lastError 置位
    void getMissingSetsError() {
        MockDav server;
        QVERIFY(server.listen(QHostAddress::LocalHost, 0));
        WebDavClient c("http://127.0.0.1:" + QString::number(server.serverPort()) + "/sync", "u", "p");
        c.get("missing.json");
        QVERIFY(!c.lastError().isEmpty());
    }

    // list：PROPFIND depth 1 → 解析 multistatus（href/getcontentlength/getlastmodified），
    // 含 RFC1123+GMT、RFC3339 兜底、percent-decode、%2F 不误切、404 propstat 不覆盖 200 值、
    // 子目录（尾斜杠）过滤
    void listParsesMultistatus() {
        MockDav server;
        QVERIFY(server.listen(QHostAddress::LocalHost, 0));
        WebDavClient c("http://127.0.0.1:" + QString::number(server.serverPort()) + "/sync", "u", "p");
        const auto res = c.list();
        QCOMPARE(res.size(), 4); // settings.json + notes.txt + my file.json + a/b.json（subdir/ 被滤）
        QVERIFY(res[0].modified.isValid()); // 404 propstat 的空值不得覆盖 200 值
        QCOMPARE(res[0].name, QString("settings.json"));
        QCOMPARE(res[0].size, 12);
        QCOMPARE(res[0].modified.toUTC(),
                 QDateTime(QDate(2026, 8, 4), QTime(0, 0, 0), QTimeZone::UTC));
        QVERIFY(res[1].modified.isValid()); // RFC3339 兜底
        QCOMPARE(res[1].name, QString("notes.txt"));
        QCOMPARE(res[1].size, 7);
        QCOMPARE(res[1].modified.toUTC(),
                 QDateTime(QDate(2026, 8, 5), QTime(10, 30, 0), QTimeZone::UTC));
        QCOMPARE(res[2].name, QString("my file.json")); // percent-decode
        QCOMPARE(res[2].size, 9);
        QCOMPARE(res[3].name, QString("a/b.json")); // %2F 先按字面 '/' 切分再解码，不误切
        QCOMPARE(res[3].size, 8);
        QCOMPARE(server.requests.last().method, QByteArray("PROPFIND"));
        QCOMPARE(server.requests.last().path, QByteArray("/sync/"));
    }

    // MKCOL 回 405（目录已存在）：MKCOL 兜底不阻断 PUT，put() 以 PUT 结果为准
    void putMkcol405FallsThroughToPut() {
        MockDav server;
        QVERIFY(server.listen(QHostAddress::LocalHost, 0));
        WebDavClient c("http://127.0.0.1:" + QString::number(server.serverPort()) + "/sync", "u", "p");
        QVERIFY(c.put("settings.json", QByteArray("hello")));
        QVERIFY(c.lastError().isEmpty());
        QCOMPARE(server.requests.size(), 2);
        QCOMPARE(server.requests[0].method, QByteArray("MKCOL"));
        QCOMPARE(server.requests[0].path, QByteArray("/sync/"));
        QCOMPARE(server.requests[1].method, QByteArray("PUT"));
        QCOMPARE(server.requests[1].body, QByteArray("hello"));
    }

    // MKCOL 回 201（目录创建成功）：与 405 等价——put() 忽略 MKCOL 响应，PUT 照发
    void putMkcol201CreatesDir() {
        MockDav server;
        server.mkcolStatus = "201 Created";
        QVERIFY(server.listen(QHostAddress::LocalHost, 0));
        WebDavClient c("http://127.0.0.1:" + QString::number(server.serverPort()) + "/sync", "u", "p");
        QVERIFY(c.put("settings.json", QByteArray("hello")));
        QVERIFY(c.lastError().isEmpty());
        QCOMPARE(server.requests.size(), 2);
        QCOMPARE(server.requests[0].method, QByteArray("MKCOL"));
        QCOMPARE(server.requests[0].path, QByteArray("/sync/"));
        QCOMPARE(server.requests[1].method, QByteArray("PUT"));
        QCOMPARE(server.requests[1].body, QByteArray("hello"));
    }

    // remove：DELETE 目标路径
    void removeSendsDelete() {
        MockDav server;
        QVERIFY(server.listen(QHostAddress::LocalHost, 0));
        WebDavClient c("http://127.0.0.1:" + QString::number(server.serverPort()) + "/sync", "u", "p");
        QVERIFY(c.remove("settings.json"));
        QVERIFY(c.lastError().isEmpty());
        QCOMPARE(server.requests.last().method, QByteArray("DELETE"));
        QCOMPARE(server.requests.last().path, QByteArray("/sync/settings.json"));
    }
};
QTEST_MAIN(TestWebDav)
#include "tst_webdav.moc"
