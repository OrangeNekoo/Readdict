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

class SettingsStore;

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
    // apply* 返回 false = 写库/写盘失败（syncOne 据此 log 失败并跳过 adopted 推进，避免
    // 元数据丢失后不再重试）
    bool applySettingsJson(const QByteArray &data);
    bool applyProgressJson(const QByteArray &data);
    bool applyHighlightsJson(const QByteArray &data);
    bool applyBooksJson(const QByteArray &data);
    // L2（P0#2）：注入应用级 SettingsStore 单例——applySettingsJson 合并结果经单例
    // setRoot 原子落盘并刷新内存；未注入（纯单元测试夹具）时原子直写文件兜底。
    void setSettingsStore(SettingsStore *s) { m_settings = s; }
    Conflict resolveConflict(const QDateTime &local, const QDateTime &remote) const;
    struct Options { bool settings = false, progress = true, highlights = false, books = false; };
    void sync(WebDavClient &client, const Options &opts);
    QStringList log() const { return m_log; }
private:
    void log(const QString &line);                       // 时间 + 动作 + 文件名
    QString settingsPath() const;                        // db 同目录 settings.json
    QVector<QPair<qint64, double>> progressPairs() const; // books 表 progress>0 的书
    // 通用单项同步：按 远端有无 × 本地有无 分派；两边都有时先做内容相等检查
    // （sameAsLocal，settings 用：内容一致即 Skip，mtime 时钟不再导致循环），再按版本比较裁决。
    // remoteVersionOf（内容类项目 progress/highlights/books）：从远端载荷提取内容版本
    // （max ts），与本地内容版本比较——同钟收敛（Skip 可达、不重复下载）；settings 缺省
    // 用 DavEntry::modified（文件 mtime，本地侧截断到秒级对齐，见 sync()）。
    // uploadWith（books 用）：KeepLocal 上传前把远端载荷中本地缺失的条目并入载荷——
    // 否则无条件 PUT 本地方集会整体覆盖远端书目（标准多设备流程的数据丢失，见报告）。
    void syncOne(WebDavClient &client, const QVector<DavEntry> &remote, const QString &name,
                 const std::function<QByteArray()> &build,
                 const std::function<bool(const QByteArray &)> &apply,
                 const QDateTime &localVersion, bool hasLocalData,
                 const std::function<QDateTime(const QByteArray &)> &remoteVersionOf = {},
                 const std::function<bool(const QByteArray &)> &sameAsLocal = {},
                 // 采纳钩子（books 用）：TakeRemote/下载/KeepLocal 上传成功后，把已确认的
                 // 载荷版本记入同步状态（adopted = 载荷 max addedAt），本地版本时钟随之
                 // 追赶——否则版本低于远端的设备每次 TakeRemote 下载后 apply 无版本前进，
                 // 重复下载永不 Skip
                 const std::function<void(const QByteArray &)> &onAdopt = {},
                 const std::function<QByteArray(const QByteArray &)> &uploadWith = {});
    void syncBookBodies(WebDavClient &client, const QVector<DavEntry> &remote);
    // ---- 同步状态（libraryDir/.readdict_sync.json）：记录已采纳的远端版本 ----
    QString syncStatePath() const;
    QDateTime adoptedVersion(const QString &item) const;
    bool setAdoptedVersion(const QString &item, const QDateTime &v);
    QString m_dbPath, m_libraryDir;
    QSqlDatabase m_db;
    QStringList m_log;
    SettingsStore *m_settings = nullptr; // L2：注入的设置单例（非拥有，main.cpp 持有）
};
