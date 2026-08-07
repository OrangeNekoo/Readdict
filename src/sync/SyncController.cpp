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
        SettingsStore st(settingsPath());
        SyncManager::Options opts;
        opts.settings = st.value(QStringLiteral("webdav/syncSettings")).toBool(true);
        opts.progress = st.value(QStringLiteral("webdav/syncProgress")).toBool(true);
        opts.highlights = st.value(QStringLiteral("webdav/syncHighlights")).toBool(false);
        opts.books = st.value(QStringLiteral("webdav/syncBooks")).toBool(false);
        doSync(opts);
    });
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

    SettingsStore st(settingsPath());
    WebDavClient client(st.value(QStringLiteral("webdav/url")).toString(),
                        st.value(QStringLiteral("webdav/user")).toString(),
                        st.value(QStringLiteral("webdav/password")).toString());
    // 同步阻塞（QEventLoop 网络）；完成与否由日志判定（SyncManager 无返回值）
    m_mgr.sync(client, opts);
    m_log = m_mgr.log();
    emit logChanged();

    // 失败判定：SyncManager 失败路径统一 log "… 失败 <name>: <error>"
    // （见 syncOne），成功/跳过路径无"失败"字样。收集失败行作为 error 文本。
    QStringList failed;
    for (const QString &line : m_log)
        if (line.contains(QStringLiteral("失败")))
            failed.append(line);
    const QString error = failed.join(QLatin1Char('\n'));

    m_running = false;
    emit runningChanged();
    emit finished(failed.isEmpty(), error);
}
