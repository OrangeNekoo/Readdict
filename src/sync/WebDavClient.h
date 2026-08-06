#pragma once
#include <QString>
#include <QByteArray>
#include <QVector>
#include <QDateTime>
#include <QNetworkRequest>
#include <QNetworkAccessManager>

// D1：自实现 WebDAV 协议子集（PROPFIND/MKCOL/PUT/GET/DELETE），不引第三方库。
struct DavEntry {
    QString name;
    qint64 size = 0;
    QDateTime modified;
};

class WebDavClient {
public:
    WebDavClient(const QString &baseUrl, const QString &user, const QString &password);
    bool put(const QString &name, const QByteArray &data);      // PUT + MKCOL 兜底
    QByteArray get(const QString &name);                        // GET
    bool remove(const QString &name);                           // DELETE
    QVector<DavEntry> list();                                   // PROPFIND depth 1
    QString lastError() const { return m_error; }
private:
    QNetworkRequest makeRequest(const QString &name, const QByteArray &method);
    QNetworkAccessManager m_nam;
    QString m_base, m_user, m_pass, m_error;
};
