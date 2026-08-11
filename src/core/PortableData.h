#pragma once
#include <QString>
#include <QStringList>

// 便携数据目录边界（全应用唯一的平台路径判断点）。
//
// 职责（设计文档 docs/superpowers/specs/2026-08-11-portable-data-design.md）：
//  1. 解析数据根目录 dataDir：
//       Windows → <程序目录>/data/（基于 applicationDirPath，不依赖 CWD）；
//       macOS   → Qt 标准 AppDataLocation（~/.app 包外、根 /Library 外）；
//       Linux   → $XDG_DATA_HOME/Readdict（变量为空时 ~/.local/share/Readdict）。
//  2. 准备 dataDir/books/covers/backgrounds；失败保留错误信息与实际路径，
//     禁止静默改写到另一个目录。
//  3. Windows 旧 Qt AppData → 便携目录迁移：临时目录 data.migrating + 完成标记
//     .readdict_migrated；源数据保留，已有便携数据不覆盖，部分失败不产生标记。
//
// 除本类外，业务类（SettingsStore/BookManager/BookImporter/HighlightManager/
// SearchEngine/SyncController）一律只接收解析后的 dataDir，不做平台判断。
// 平台分支全部经 Params 注入：测试注入 QTemporaryDir 路径即可覆盖各平台规则，
// 不伪造 Q_OS 宏、不触碰宿主用户目录。
class PortableDataStore {
public:
    enum class Platform { Windows, MacOS, Linux };

    // 解析参数：生产代码从 QCoreApplication/QStandardPaths/环境变量填充；
    // 测试注入临时路径。留空字段走生产默认值。
    struct Params {
        Platform platform = currentPlatform();
        QString applicationDirPath;  // Windows：可执行文件所在目录
        QString appDataLocation;     // macOS：QStandardPaths::AppDataLocation 值
        QString xdgDataHome;         // Linux：$XDG_DATA_HOME（空 → 默认 ~/.local/share）
        QString homeDir;             // Linux 默认兜底用家目录（空 → QDir::homePath）
    };

    // 当前宿主平台（本类内唯一使用 Q_OS 宏的位置）
    static Platform currentPlatform();
    // 解析数据根目录。纯函数：不创建目录、不写盘。
    static QString resolveDataDir(const Params &p);
    // 创建 dataDir 及 books/covers/backgrounds。返回空串=成功；
    // 否则为含实际路径的可读错误（不可写/创建失败均在此返回）。
    static QString prepareDataDir(const QString &dataDir);
    // Windows 旧数据迁移：legacyAppData 有数据且 dataDir 无有效数据时，把
    // settings.json/Readdict.db/books/covers/backgrounds/.readdict_sync.json/
    // .readdict_index_fail.json 复制到 dataDir（先完整暂存到 data.migrating，
    // 成功后再合并并写 .readdict_migrated 标记）。返回空串=成功或无需迁移；
    // 否则为可读错误。源目录保留、不修改。macOS/Linux 传空 legacyAppData 即跳过。
    static QString migrateFromLegacy(const QString &legacyAppData, const QString &dataDir);

    static QString settingsFileName() { return QStringLiteral("settings.json"); }
    static QString dbFileName() { return QStringLiteral("Readdict.db"); }

private:
    static QStringList subDirs();              // books/covers/backgrounds
    static QStringList legacyOptionalFiles();  // .readdict_sync.json/.readdict_index_fail.json
    static QString migrationMarker();          // .readdict_migrated
    static bool portableHasData(const QString &dataDir);
};
