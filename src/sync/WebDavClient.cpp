#include "WebDavClient.h"
#include <QNetworkReply>
#include <QEventLoop>
#include <QObject>
#include <QUrl>
#include <QXmlStreamReader>

namespace {

// Qt 6.11 的 RFC 2822 解析只接受 ±HHMM 数字时区，命名时区（GMT 等）一律返回 Invalid；
// 而 WebDAV 服务器按 RFC 1123 发 "… GMT"。先归一化命名时区再解析。
QDateTime parseDavTime(const QString &text)
{
    QString s = text.trimmed();
    static const QHash<QString, QString> zones = {
        {QStringLiteral("GMT"), QStringLiteral("+0000")},
        {QStringLiteral("UT"),  QStringLiteral("+0000")},
        {QStringLiteral("UTC"), QStringLiteral("+0000")},
        {QStringLiteral("EST"), QStringLiteral("-0500")},
        {QStringLiteral("EDT"), QStringLiteral("-0400")},
        {QStringLiteral("CST"), QStringLiteral("-0600")},
        {QStringLiteral("CDT"), QStringLiteral("-0500")},
        {QStringLiteral("MST"), QStringLiteral("-0700")},
        {QStringLiteral("MDT"), QStringLiteral("-0600")},
        {QStringLiteral("PST"), QStringLiteral("-0800")},
        {QStringLiteral("PDT"), QStringLiteral("-0700")},
    };
    const int sp = s.lastIndexOf(' ');
    if (sp > 0) {
        const auto it = zones.constFind(s.mid(sp + 1));
        if (it != zones.cend())
            s = s.left(sp + 1) + it.value();
    }
    QDateTime dt = QDateTime::fromString(s, Qt::RFC2822Date);
    if (dt.isValid())
        return dt;
    // 兜底 RFC3339/ISO8601：部分服务器发 "2026-08-04T00:00:00Z"（含 Z 后缀）
    return QDateTime::fromString(s, Qt::ISODate);
}

} // namespace


WebDavClient::WebDavClient(const QString &baseUrl, const QString &user, const QString &password)
    : m_base(baseUrl), m_user(user), m_pass(password)
{
    if (!m_base.endsWith('/'))
        m_base += '/';
}

QNetworkRequest WebDavClient::makeRequest(const QString &name, const QByteArray &method)
{
    QNetworkRequest req(QUrl(m_base + name));
    req.setRawHeader("Authorization", "Basic " + (m_user + ":" + m_pass).toUtf8().toBase64());
    if (method == "PROPFIND")
        req.setRawHeader("Depth", "1");
    // 简报错误处理：10s 传输超时；超时后 reply 以 OperationCanceledError 结束
    req.setTransferTimeout(10000);
    return req;
}

bool WebDavClient::put(const QString &name, const QByteArray &data)
{
    QEventLoop loop;
    // MKCOL 兜底：201 创建成功 / 405 已存在均视为目录就绪，其余失败不阻断 PUT
    // （PUT 的结果才是 put() 的判定依据）
    // 注意：2 参形式的第二参是 verb（data 走默认 nullptr）——
    // 传空 QByteArray() 会发出空方法，必须显式传动词
    QNetworkReply *mk = m_nam.sendCustomRequest(makeRequest("", "MKCOL"), QByteArray("MKCOL"));
    QObject::connect(mk, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    loop.exec();
    mk->deleteLater();

    QNetworkReply *r = m_nam.put(makeRequest(name, "PUT"), data);
    QObject::connect(r, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    loop.exec();
    const bool ok = r->error() == QNetworkReply::NoError;
    m_error = ok ? QString() : r->errorString();
    r->deleteLater();
    return ok;
}

QByteArray WebDavClient::get(const QString &name)
{
    QNetworkReply *r = m_nam.get(makeRequest(name, "GET"));
    QEventLoop loop;
    QObject::connect(r, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    loop.exec();
    const QByteArray body = r->readAll();
    m_error = r->error() == QNetworkReply::NoError ? QString() : r->errorString();
    r->deleteLater();
    return body;
}

bool WebDavClient::remove(const QString &name)
{
    QNetworkReply *r = m_nam.sendCustomRequest(makeRequest(name, "DELETE"), QByteArray("DELETE"));
    QEventLoop loop;
    QObject::connect(r, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    loop.exec();
    const bool ok = r->error() == QNetworkReply::NoError;
    m_error = ok ? QString() : r->errorString();
    r->deleteLater();
    return ok;
}

QVector<DavEntry> WebDavClient::list()
{
    QVector<DavEntry> out;
    QNetworkReply *r = m_nam.sendCustomRequest(makeRequest("", "PROPFIND"), QByteArray("PROPFIND"));
    QEventLoop loop;
    QObject::connect(r, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    loop.exec();
    if (r->error() != QNetworkReply::NoError) {
        m_error = r->errorString();
        r->deleteLater();
        return out;
    }
    m_error.clear();

    // 解析 multistatus（RFC 4918）：校验 DAV: 命名空间；宽松服务器可能省略命名空间
    // 声明（namespaceUri() 为空），一并接受——真机联调遇空列表优先排查响应结构
    auto davElement = [](const QXmlStreamReader &x) {
        return x.namespaceUri().isEmpty() || x.namespaceUri() == QStringLiteral("DAV:");
    };
    QXmlStreamReader xml(r->readAll());
    while (!xml.atEnd()) {
        xml.readNext();
        if (!xml.isStartElement() || !davElement(xml) || xml.name() != QStringLiteral("response"))
            continue;
        DavEntry e;
        QString hrefText;
        while (!xml.atEnd()) {
            xml.readNext();
            if (xml.isEndElement() && xml.name() == QStringLiteral("response"))
                break;
            if (!xml.isStartElement() || !davElement(xml))
                continue;
            if (xml.name() == QStringLiteral("href")) {
                hrefText = xml.readElementText();
                // 先取末段再 percent-decode：%2F 编码的斜杠属于文件名本身（RFC 3986 段内编码）；
                // Qt 6.11 的 fromPercentEncoding 直接返回 QString，无需再包 fromUtf8
                e.name = QUrl::fromPercentEncoding(hrefText.section('/', -1).toUtf8());
            }
            else if (xml.name() == QStringLiteral("getcontentlength"))
                e.size = xml.readElementText().trimmed().toLongLong();
            else if (xml.name() == QStringLiteral("getlastmodified"))
                e.modified = parseDavTime(xml.readElementText());
        }
        // 集合自身与子目录（href 尾斜杠）不属于文件：跳过（当前同步模型只同步文件）
        if (!e.name.isEmpty() && !hrefText.endsWith('/'))
            out.append(e);
    }
    r->deleteLater();
    return out;
}
