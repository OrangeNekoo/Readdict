#pragma once
#include "WebDavClient.h"
#include <QDateTime>
#include <QJsonArray>
#include <QJsonObject>
#include <QPair>
#include <QSqlDatabase>
#include <QString>
#include <QStringList>
#include <QVector>
#include <functional>

// D2：同步数据打包、合并与冲突解决。
// 职责：把本地数据（设置/进度/划线/书籍元数据）打包为 JSON 上传 WebDAV，下载远端
// JSON 合并回本地；按 mtime 冲突解决（KeepLocal/TakeRemote/Skip）。日志存内存供
// SyncPage 展示（m_log）。
//
// 关键决策（详见 task-D2-report.md）：
// - 单连接 readdict_sync 直连 SQL：与 main 的单例连接（readdict_main/readdict_highlights）
//   隔离（同名 addDatabase 会移除旧连接）；单连接保证 :memory: 库数据共享（多连接下
//   :memory: 是彼此独立的私有库）。
// - 本地版本 mtime：settings 用 settings.json 文件 mtime（简报"本地文件 QFileInfo::lastModified"）；
//   progress/highlights/books 用各自数据的最新时间戳（last_read_at/created_at/added_at）。
// - 载荷 ts 统一 UTC 序列化（ISODate + Z），跨设备时区不偏移。
// - 远端文件命名：settings.json / progress.json / highlights.json / books.json；
//   书籍文件体 b<id>_<basename>（扁平命名，list() 是 depth 1，子目录不可见）。
class SyncManager {
public:
    enum Conflict { KeepLocal, TakeRemote, Skip };
    // connection：SQLite 连接名，默认 readdict_sync；测试可注入避免全局连接名冲突。
    explicit SyncManager(const QString &dbPath, const QString &libraryDir,
                         const QString &connection = QStringLiteral("readdict_sync"));
    QByteArray buildSettingsJson() const;
    QByteArray buildProgressJson(const QVector<QPair<qint64, double>> &progress) const;
    QByteArray buildHighlightsJson() const;
    QByteArray buildBooksJson() const;
    void applySettingsJson(const QByteArray &data);
    void applyProgressJson(const QByteArray &data);
    void applyHighlightsJson(const QByteArray &data);
    void applyBooksJson(const QByteArray &data);
    Conflict resolveConflict(const QDateTime &local, const QDateTime &remote) const;
    struct Options { bool settings = false, progress = true, highlights = false, books = false; };
    void sync(WebDavClient &client, const Options &opts);
    QStringList log() const { return m_log; }
private:
    void log(const QString &line);                       // 时间 + 动作 + 文件名
    QString settingsPath() const;                        // db 同目录 settings.json
    QVector<QPair<qint64, double>> progressPairs() const; // books 表 progress>0 的书
    // 通用单项同步：按 远端有无 × 本地有无 × mtime 冲突 四分支推进（见 sync 注释）
    void syncOne(WebDavClient &client, const QVector<DavEntry> &remote, const QString &name,
                 const std::function<QByteArray()> &build,
                 const std::function<void(const QByteArray &)> &apply,
                 const QDateTime &localVersion, bool hasLocalData);
    void syncBookBodies(WebDavClient &client, const QVector<DavEntry> &remote);
    QString m_dbPath, m_libraryDir;
    QSqlDatabase m_db;
    QStringList m_log;
};
