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
    virtual ~WebDavClient() = default;
    // D2：方法抽成 virtual——tst_syncmanager 以内存 MockWebDavClient 覆盖，
    // 使 SyncManager 的 sync 全流程可在无网络下测试（虚接口方案，见 task-D2-report.md）。
    virtual bool put(const QString &name, const QByteArray &data);      // PUT + MKCOL 兜底
    virtual QByteArray get(const QString &name);                        // GET
    virtual bool remove(const QString &name);                           // DELETE
    virtual QVector<DavEntry> list();                                   // PROPFIND depth 1
    virtual QString lastError() const { return m_error; }
private:
    QNetworkRequest makeRequest(const QString &name, const QByteArray &method);
    QNetworkAccessManager m_nam;
    QString m_base, m_user, m_pass, m_error;
};
