// D1：WebDavClient（协议子集）— 本地 QTcpServer mock 验证 PROPFIND/MKCOL/PUT/GET/DELETE
#include <QtTest>
#include <QTcpServer>
#include <QTcpSocket>
#include <QHash>
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

    // getlastmodified 用 RFC 1123（RFC 4918 规定的 DAV:getlastmodified 格式）
    static QByteArray responseBody(const MockRequest &mr) {
        if (mr.method == "PROPFIND")
            return "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
                   "<d:multistatus xmlns:d=\"DAV:\">"
                   "<d:response><d:href>/sync/settings.json</d:href>"
                   "<d:propstat><d:prop>"
                   "<d:getlastmodified>Tue, 04 Aug 2026 00:00:00 GMT</d:getlastmodified>"
                   "<d:getcontentlength>12</d:getcontentlength>"
                   "</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>"
                   "</d:response></d:multistatus>";
        if (mr.method == "GET" && mr.path.endsWith("missing.json"))
            return "Not Found";
        return "hello";
    }

    static QByteArray statusLine(const MockRequest &mr) {
        if (mr.method == "PROPFIND")
            return "207 Multi-Status";
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

    // list：PROPFIND depth 1 → 解析 multistatus（href/getcontentlength/getlastmodified）
    void listParsesMultistatus() {
        MockDav server;
        QVERIFY(server.listen(QHostAddress::LocalHost, 0));
        WebDavClient c("http://127.0.0.1:" + QString::number(server.serverPort()) + "/sync", "u", "p");
        const auto res = c.list();
        QCOMPARE(res.size(), 1);
        QCOMPARE(res[0].name, QString("settings.json"));
        QCOMPARE(res[0].size, 12);
        QCOMPARE(res[0].modified.toUTC(),
                 QDateTime(QDate(2026, 8, 4), QTime(0, 0, 0), Qt::UTC));
        QCOMPARE(server.requests.last().method, QByteArray("PROPFIND"));
        QCOMPARE(server.requests.last().path, QByteArray("/sync/"));
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
