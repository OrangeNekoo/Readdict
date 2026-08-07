#pragma once
#include "SyncManager.h"
#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>

// D3：SyncController——QObject 薄封装，把 SyncManager 的同步流程接到 QML
// （qmlRegisterSingletonInstance 注册为 Readdict.Backend.Sync 单例）。
// 职责：读 SettingsStore 的 webdav 分区（url/user/password）构造 WebDavClient →
// SyncManager::sync 执行 → 更新 running/log 属性 → 发 finished(ok, error)。
//
// 已知取舍（设计文档已定）：SyncManager::sync 是同步阻塞（QEventLoop 网络），
// run() 会短暂卡住 UI 线程——同步由用户手动触发或每 30 分钟一次，频率低，
// 简报无异步要求，故保持同步实现（卡顿时长受 WebDavClient 10s 传输超时约束）。
class SyncController : public QObject {
    Q_OBJECT
public:
    // connection：SQLite 连接名，透传给 SyncManager（默认 readdict_sync，与各应用
    // 单例连接隔离）；测试注入独立名避免跨用例 addDatabase 重名告警（D2 同模式）。
    explicit SyncController(const QString &dbPath, const QString &libraryDir,
                            const QString &connection = QStringLiteral("readdict_sync"),
                            QObject *parent = nullptr);
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(QStringList log READ log NOTIFY logChanged)
    Q_INVOKABLE void run(bool settings, bool progress, bool highlights, bool books);
    Q_INVOKABLE void setAutoSync(bool enabled);   // 每 30 分钟一次，默认关
    bool running() const { return m_running; }
    QStringList log() const { return m_log; }
private:
    QString settingsPath() const;   // db 同目录 settings.json（与 SyncManager::settingsPath 同源）
    void doSync(const SyncManager::Options &opts);
    QString m_dbPath;
    SyncManager m_mgr;
    QTimer m_timer;
    bool m_running = false;
    QStringList m_log;
signals:
    void runningChanged();
    void logChanged();
    void finished(bool ok, const QString &error);
};
