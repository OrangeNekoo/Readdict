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

    // ---- Windows 权限不足自动提权（最小权限 helper，见设计文档“权限处理”）----

    // prepareWithElevation 的结果。
    struct ElevationResult {
        bool elevated = false;  // 本次调用是否发起了 UAC 提权
        bool success = false;   // 调用后 dataDir 可用（无需提权即已可用，或提权后复检通过）
        QString error;          // 失败原因（success 时为空）
    };

    // prepareDataDir 的错误是否疑似权限不足（提权决策依据）：匹配已知权限措辞，
    // 否则检查 dataDir/父目录实际可写性。
    static bool isPermissionError(const QString &error, const QString &dataDir);

    // 构造 Windows 提权 helper 的命令行参数（仅接受目标目录，不接受任意命令）：
    // 返回 { "--prepare-data", <按 CommandLineToArgvW 规则转义的路径> }。
    static QStringList prepareCommand(const QString &dataDir);

    // 一次性完成 旧数据迁移 + 目录准备（含提权），main 启动唯一入口：
    // 1) 先以普通权限整体尝试（migrateFromLegacy → prepareDataDir），成功即返回；
    // 2) 失败且疑似权限不足且 !alreadyElevated 时，Windows 以 ShellExecuteExW 的
    //    verb `runas` 调起自身 helper（executablePath --prepare-data <dataDir>），
    //    helper 内部自行 迁移+准备（其 legacy 由其启动参数解析），等待退出并检查
    //    API 返回与退出码，随后普通进程复检 迁移+准备 均成立才算成功；
    // 3) 非权限错误直接返回原错误（提权无意义）；macOS/Linux 返回明确的
    //    “不支持自动提权”错误，绝不调用 sudo/root；helper 模式绝不再次提权。
    static ElevationResult ensurePortableData(const QString &legacyAppData,
                                              const QString &dataDir,
                                              const QString &executablePath,
                                              bool alreadyElevated);

    // 仅“目录准备”语义的提权入口（旧接口，等价于 ensurePortableData 传空 legacy）：
    // 先以普通权限 prepareDataDir；仅当失败疑似权限不足且 !alreadyElevated 时提权。
    // macOS/Linux 返回明确的“不支持自动提权”错误，绝不调用 sudo/root。
    static ElevationResult prepareWithElevation(const QString &dataDir,
                                                const QString &executablePath,
                                                bool alreadyElevated);

    // Windows 提权 helper 专用入口：参数固定为 { "--prepare-data", <path> } 时执行
    // 旧数据迁移 + 目录准备并返回退出码（0=成功；1=准备/迁移失败；2=参数形态错误；
    // 3=路径被拒绝）。安全边界：<path> 必须等于 cleanPath(applicationDirPath/data)
    // （Windows 便携目录唯一形态）——提权进程绝不接受任意绝对路径，防诱导写入。
    // 不启动 GUI、不注册 QML 单例、绝不再次提权（防 UAC 递归）。
    // Params 供测试注入（生产传启动时解析的 dp，Windows legacy 用 appDataLocation）。
    static int runElevationHelper(const QStringList &args, const Params &p);

#if defined(Q_OS_WIN)
    // 当前进程是否已以管理员权限运行（仅 Windows 定义；用于防二次 UAC 递归）。
    static bool isRunningElevated();
#endif

    static QString settingsFileName() { return QStringLiteral("settings.json"); }
    static QString dbFileName() { return QStringLiteral("Readdict.db"); }

private:
    // 便携目录存在性探测结果：None=无有效数据；Present=已有有效数据（迁移跳过）；
    // LinkRejected=目录内存在链接类条目（符号链接/重解析点），fail-closed 拒绝迁移。
    enum class DataPresence { None, Present, LinkRejected };

    static QStringList subDirs();              // books/covers/backgrounds
    static QStringList legacyOptionalFiles();  // .readdict_sync.json/.readdict_index_fail.json
    static QString migrationMarker();          // .readdict_migrated
    static DataPresence portableHasData(const QString &dataDir);
};
