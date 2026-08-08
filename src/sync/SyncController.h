#pragma once
#include "SyncManager.h"
#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>

class SettingsStore;

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
    // L2（P0#2）：注入应用级 SettingsStore 单例——转发给 SyncManager（合并写盘经单例），
    // 并供 doSync/定时器读取 webdav 配置；未注入时各处临时构造兜底（测试旧夹具）。
    void setSettingsStore(SettingsStore *s);
    // L3（P0#3）：注入书体注册钩子——转发给 SyncManager（下载落盘后经导入管线注册）
    void setAdoptHandler(std::function<QString(const QString &)> h);
    QStringList log() const { return m_log; }
private:
    QString settingsPath() const;   // db 同目录 settings.json（与 SyncManager::settingsPath 同源）
    void doSync(const SyncManager::Options &opts);
    QString m_dbPath;
    SyncManager m_mgr;
    QTimer m_timer;
    bool m_running = false;
    QStringList m_log;
    SettingsStore *m_store = nullptr; // L2：注入的设置单例（非拥有，main.cpp 持有）
signals:
    void runningChanged();
    void logChanged();
    void finished(bool ok, const QString &error);
    // L8（P1#18）：转发 SyncManager::syncApplied——本次同步成功应用远端数据
    // （进度/划线/书目/书体注册）；main.cpp 据此刷新 Books 单例，ReaderPage 重载划线
    void dataApplied();
};
