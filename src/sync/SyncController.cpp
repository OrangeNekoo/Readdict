#include "SyncController.h"
#include "../core/SettingsStore.h"
#include "WebDavClient.h"
#include <QDir>
#include <QFileInfo>

SyncController::SyncController(const QString &dbPath, const QString &libraryDir,
                               const QString &connection, QObject *parent)
    : QObject(parent), m_dbPath(dbPath), m_mgr(dbPath, libraryDir, connection) {
    // 自动同步：每 30 分钟一次，勾选项从 SettingsStore 读（与手动同步同一套配置键）。
    // 定时器默认不启动（setAutoSync(false) 即默认状态；main.cpp 按
    // settings.json 的 webdav/autoSync 恢复上次选择）。
    m_timer.setInterval(30 * 60 * 1000);
    connect(&m_timer, &QTimer::timeout, this, [this] {
        SettingsStore *st = m_store;
        SettingsStore fallback(settingsPath());   // 仅未注入时（测试旧夹具）
        if (!st) st = &fallback;
        SyncManager::Options opts;
        opts.settings = st->value(QStringLiteral("webdav/syncSettings")).toBool(true);
        opts.progress = st->value(QStringLiteral("webdav/syncProgress")).toBool(true);
        opts.highlights = st->value(QStringLiteral("webdav/syncHighlights")).toBool(false);
        opts.books = st->value(QStringLiteral("webdav/syncBooks")).toBool(false);
        doSync(opts);
    });
    // L8（P1#18）：转发 SyncManager::syncApplied → dataApplied（main.cpp 据此刷新
    // Books 单例，ReaderPage 重载划线）
    connect(&m_mgr, &SyncManager::syncApplied, this, &SyncController::dataApplied);
}

QString SyncController::settingsPath() const {
    // settings.json 与 db 同目录（生产即 AppDataLocation）；测试注入临时目录时
    // 同样指向测试的 settings.json，避免硬编码 AppDataLocation 污染真实配置。
    return QFileInfo(m_dbPath).absoluteDir().filePath(QStringLiteral("settings.json"));
}

void SyncController::run(bool settings, bool progress, bool highlights, bool books) {
    SyncManager::Options opts;
    opts.settings = settings;
    opts.progress = progress;
    opts.highlights = highlights;
    opts.books = books;
    doSync(opts);
}

void SyncController::setSettingsStore(SettingsStore *s) {
    m_store = s;
    m_mgr.setSettingsStore(s);
}

void SyncController::setAdoptHandler(std::function<QString(const QString &)> h) {
    m_mgr.setAdoptHandler(std::move(h));
}

void SyncController::setAutoSync(bool enabled) {
    if (enabled)
        m_timer.start();
    else
        m_timer.stop();
}

void SyncController::doSync(const SyncManager::Options &opts) {
    if (m_running) return; // 同步中忽略重复触发（手动连点 / 定时器撞车）
    m_running = true;
    emit runningChanged();

    SettingsStore *st = m_store;
    SettingsStore fallback(settingsPath());   // 仅未注入时（测试旧夹具）
    if (!st) st = &fallback;
    WebDavClient client(st->value(QStringLiteral("webdav/url")).toString(),
                        st->value(QStringLiteral("webdav/user")).toString(),
                        st->value(QStringLiteral("webdav/password")).toString());
    // 同步阻塞（QEventLoop 网络）；L8（P1#12）：成败由结构化 Result 判定——
    // 失败路径在 SyncManager 内统一记入 Result.failures（与日志失败行同源），
    // 不再按日志字符串匹配判败（书名含"失败"字样的误判与信息行漏判一并根除）
    const SyncManager::Result r = m_mgr.sync(client, opts);
    m_log = m_mgr.log();
    emit logChanged();

    m_running = false;
    emit runningChanged();
    emit finished(r.ok, r.failures.join(QLatin1Char('\n')));
}
