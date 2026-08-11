#include "PortableData.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QIODevice>
#include <QStandardPaths>

namespace {

// 递归复制 src → dst（合并语义：目标已存在则先移除再复制）。返回空串=成功。
QString copyRecursively(const QString &src, const QString &dst) {
    const QFileInfo si(src);
    if (si.isDir()) {
        if (!QDir().mkpath(dst))
            return QStringLiteral("无法创建目录: %1").arg(dst);
        const QStringList entries = QDir(src).entryList(
            QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot | QDir::Hidden);
        for (const QString &e : entries) {
            const QString err = copyRecursively(src + QLatin1Char('/') + e,
                                                dst + QLatin1Char('/') + e);
            if (!err.isEmpty())
                return err;
        }
        return {};
    }
    if (QFile::exists(dst) && !QFile::remove(dst))
        return QStringLiteral("无法覆盖目标文件: %1").arg(dst);
    if (!QFile::copy(src, dst))
        return QStringLiteral("无法复制 %1 → %2").arg(src, dst);
    return {};
}

} // namespace

PortableDataStore::Platform PortableDataStore::currentPlatform() {
#if defined(Q_OS_WIN)
    return Platform::Windows;
#elif defined(Q_OS_MACOS)
    return Platform::MacOS;
#else
    return Platform::Linux;
#endif
}

QString PortableDataStore::resolveDataDir(const PortableDataStore::Params &p) {
    switch (p.platform) {
    case Platform::Windows: {
        if (p.applicationDirPath.isEmpty())
            return {};
        return QDir::cleanPath(p.applicationDirPath + QStringLiteral("/data"));
    }
    case Platform::MacOS:
        if (!p.appDataLocation.isEmpty())
            return p.appDataLocation;
        return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    case Platform::Linux: {
        QString base = p.xdgDataHome;
        if (base.isEmpty())
            base = qEnvironmentVariable("XDG_DATA_HOME");
        if (base.isEmpty())
            base = (p.homeDir.isEmpty() ? QDir::homePath() : p.homeDir)
                   + QStringLiteral("/.local/share");
        return QDir::cleanPath(base + QStringLiteral("/Readdict"));
    }
    }
    return {}; // 不可达（编译器需要）
}

QString PortableDataStore::prepareDataDir(const QString &dataDir) {
    if (!QDir().mkpath(dataDir))
        return QStringLiteral("无法创建数据目录: %1").arg(dataDir);
    QDir root(dataDir);
    const QStringList subs = subDirs();
    for (const QString &sub : subs) {
        if (!root.mkpath(sub))
            return QStringLiteral("无法创建数据子目录: %1").arg(root.filePath(sub));
    }
    return {};
}

QString PortableDataStore::migrateFromLegacy(const QString &legacyAppData, const QString &dataDir) {
    if (legacyAppData.isEmpty())
        return {}; // macOS/Linux：新旧路径相同，不迁移
    const QDir legacy(legacyAppData);
    if (!legacy.exists())
        return {}; // 无旧目录
    if (portableHasData(dataDir))
        return {}; // 便携目录已有有效数据 → 不覆盖

    // 收集旧目录中实际存在的可迁移内容
    QStringList sources;
    const QStringList files = { settingsFileName(), dbFileName() };
    for (const QString &f : files) {
        if (QFileInfo::exists(legacy.filePath(f)))
            sources << f;
    }
    for (const QString &d : subDirs()) {
        if (QDir(legacy.filePath(d)).exists())
            sources << d;
    }
    for (const QString &f : legacyOptionalFiles()) {
        if (QFileInfo::exists(legacy.filePath(f)))
            sources << f;
    }
    if (sources.isEmpty())
        return {}; // 旧目录无任何可迁移内容

    // 临时目录 + 完成标记：先完整复制到 <data 父目录>/data.migrating/
    const QString staging =
        QFileInfo(dataDir).dir().filePath(QStringLiteral("data.migrating"));
    QDir(staging).removeRecursively(); // 清理上次失败残留（仅固定名 staging）
    if (!QDir().mkpath(staging))
        return QStringLiteral("无法创建迁移暂存目录: %1").arg(staging);
    for (const QString &name : sources) {
        const QString err = copyRecursively(legacy.filePath(name),
                                            staging + QLatin1Char('/') + name);
        if (!err.isEmpty()) {
            QDir(staging).removeRecursively();
            return QStringLiteral("旧数据迁移失败（%1）: %2").arg(name, err);
        }
    }

    // 必需内容全部复制成功 → 合并到 dataDir
    if (!QDir().mkpath(dataDir)) {
        QDir(staging).removeRecursively();
        return QStringLiteral("无法创建数据目录: %1").arg(dataDir);
    }
    for (const QString &name : sources) {
        const QString err = copyRecursively(staging + QLatin1Char('/') + name,
                                            dataDir + QLatin1Char('/') + name);
        if (!err.isEmpty()) {
            QDir(staging).removeRecursively();
            return QStringLiteral("旧数据合并失败（%1）: %2").arg(name, err);
        }
    }
    QDir(staging).removeRecursively(); // 合并完成，清理暂存

    // 写入迁移标记
    QFile marker(dataDir + QLatin1Char('/') + migrationMarker());
    if (!marker.open(QIODevice::WriteOnly))
        return QStringLiteral("无法写入迁移标记: %1").arg(marker.fileName());
    marker.close();
    return {};
}

bool PortableDataStore::portableHasData(const QString &dataDir) {
    if (QFile::exists(dataDir + QLatin1Char('/') + migrationMarker()))
        return true; // 已完成迁移
    const QDir d(dataDir);
    if (!d.exists())
        return false;
    const QStringList files = { settingsFileName(), dbFileName() };
    for (const QString &f : files) {
        if (QFile::exists(d.filePath(f)))
            return true;
    }
    for (const QString &sub : subDirs()) {
        if (d.exists(sub))
            return true;
    }
    return false;
}

QStringList PortableDataStore::subDirs() {
    return { QStringLiteral("books"), QStringLiteral("covers"), QStringLiteral("backgrounds") };
}

QStringList PortableDataStore::legacyOptionalFiles() {
    return { QStringLiteral(".readdict_sync.json"), QStringLiteral(".readdict_index_fail.json") };
}

QString PortableDataStore::migrationMarker() {
    return QStringLiteral(".readdict_migrated");
}
