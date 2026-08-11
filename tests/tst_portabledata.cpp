// 便携数据目录（PortableDataStore）单元测试。
//
// 平台分支全部使用可注入参数（Params 的 applicationDirPath/appDataLocation/
// xdgDataHome/homeDir），不伪造 Q_OS 宏、不修改宿主用户目录；所有目录均落在
// QTemporaryDir 内。唯一接触真实标准路径的断言是 macOS 默认分支与
// QStandardPaths::writableLocation 的只读对照（不写盘）。
#include <QtTest>
#include <QDir>
#include <QFile>
#include <QFileDevice>
#include <QFileInfo>
#include <QStandardPaths>
#include "core/PortableData.h"

namespace {

void writeFile(const QString &path, const QByteArray &content) {
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly)) {
        QFAIL(qPrintable("无法写入 " + path));
        return;
    }
    f.write(content);
}

// 构造一个含完整数据的旧 Qt AppData 目录（settings.json/Readdict.db/books/covers/
// backgrounds/.readdict_sync.json），返回该目录路径。
QString makeLegacyAppData(const QString &root) {
    const QString legacy = root + "/legacy_appdata";
    QDir().mkpath(legacy + "/books");
    QDir().mkpath(legacy + "/covers");
    QDir().mkpath(legacy + "/backgrounds");
    writeFile(legacy + "/settings.json", "{\"theme\":{\"mode\":\"dark\"}}");
    writeFile(legacy + "/Readdict.db", "sqlite-bytes");
    writeFile(legacy + "/books/a.epub", "epub-bytes");
    writeFile(legacy + "/covers/cover_x.png", "png-bytes");
    writeFile(legacy + "/.readdict_sync.json", "{}");
    return legacy;
}

} // namespace

class TestPortableData : public QObject {
    Q_OBJECT
private slots:
    // ---- 路径解析：平台分支用可注入参数（不伪造 Q_OS 宏）----
    void windowsUsesAppDirData() {
        PortableDataStore::Params p;
        p.platform = PortableDataStore::Platform::Windows;
        p.applicationDirPath = "F:/Readdict";
        QCOMPARE(PortableDataStore::resolveDataDir(p), QString("F:/Readdict/data"));
    }

    void macOsUsesAppDataLocation() {
        QTemporaryDir tmp;
        PortableDataStore::Params p;
        p.platform = PortableDataStore::Platform::MacOS;
        p.appDataLocation = tmp.path() + "/Application Support/Readdict";
        QCOMPARE(PortableDataStore::resolveDataDir(p), p.appDataLocation);
    }

    void macOsDefaultsToStandardAppData() {
        // 生产默认分支：appDataLocation 未注入时回退 Qt 标准 AppDataLocation
        // （仅与系统值做只读对照，不写宿主目录）。
        PortableDataStore::Params p;
        p.platform = PortableDataStore::Platform::MacOS;
        QCOMPARE(PortableDataStore::resolveDataDir(p),
                 QStandardPaths::writableLocation(QStandardPaths::AppDataLocation));
    }

    void linuxUsesXdgDataHome() {
        PortableDataStore::Params p;
        p.platform = PortableDataStore::Platform::Linux;
        p.xdgDataHome = "/home/u/.local/share";
        QCOMPARE(PortableDataStore::resolveDataDir(p), QString("/home/u/.local/share/Readdict"));
    }

    void linuxFallsBackToLocalShare() {
        // XDG_DATA_HOME 为空/未设置 → 默认 ~/.local/share/Readdict
        // （homeDir 注入，避免读真实家目录；环境变量显式清空保证确定性）。
        qputenv("XDG_DATA_HOME", "");
        PortableDataStore::Params p;
        p.platform = PortableDataStore::Platform::Linux;
        p.homeDir = "/home/u";
        QCOMPARE(PortableDataStore::resolveDataDir(p), QString("/home/u/.local/share/Readdict"));
        qunsetenv("XDG_DATA_HOME");
    }

    // ---- 目录准备 ----
    void prepareCreatesSubdirs() {
        QTemporaryDir tmp;
        const QString dataDir = tmp.path() + "/data";
        const QString err = PortableDataStore::prepareDataDir(dataDir);
        QVERIFY2(err.isEmpty(), qPrintable(err));
        QVERIFY(QDir(dataDir).exists());
        QVERIFY(QDir(dataDir + "/books").exists());
        QVERIFY(QDir(dataDir + "/covers").exists());
        QVERIFY(QDir(dataDir + "/backgrounds").exists());
    }

    void prepareReusesExistingDirs() {
        QTemporaryDir tmp;
        const QString dataDir = tmp.path() + "/data";
        QVERIFY(QDir().mkpath(dataDir + "/books"));
        writeFile(dataDir + "/books/keep.epub", "x");
        const QString err = PortableDataStore::prepareDataDir(dataDir);
        QVERIFY2(err.isEmpty(), qPrintable(err));
        QVERIFY(QFile::exists(dataDir + "/books/keep.epub")); // 已有内容不被破坏
        QVERIFY(QDir(dataDir + "/covers").exists());          // 缺失子目录补齐
        QVERIFY(QDir(dataDir + "/backgrounds").exists());
    }

    void prepareFailsWhenPathIsFile() {
        QTemporaryDir tmp;
        const QString dataDir = tmp.path() + "/data";
        writeFile(dataDir, "not-a-dir");                      // 目标路径被文件占据
        const QString err = PortableDataStore::prepareDataDir(dataDir);
        QVERIFY(!err.isEmpty());
        QVERIFY(err.contains(dataDir));                       // 错误信息保留实际路径
    }

    void prepareFailsOnUnwritableParent() {
        QTemporaryDir tmp;
        const QString dataDir = tmp.path() + "/data";
        // 父目录只读（0555）：子目录创建必然失败 → 返回错误，不静默改道
        QVERIFY(QFile::setPermissions(tmp.path(),
            QFileDevice::ReadOwner | QFileDevice::ExeOwner
            | QFileDevice::ReadGroup | QFileDevice::ExeGroup
            | QFileDevice::ReadOther | QFileDevice::ExeOther));
        const QString err = PortableDataStore::prepareDataDir(dataDir);
        QVERIFY(!err.isEmpty());
        QVERIFY(err.contains(dataDir));
        // 恢复权限，保证 QTemporaryDir 能清理
        QFile::setPermissions(tmp.path(),
            QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner
            | QFileDevice::ReadGroup | QFileDevice::WriteGroup | QFileDevice::ExeGroup
            | QFileDevice::ReadOther | QFileDevice::WriteOther | QFileDevice::ExeOther);
    }

    // ---- Windows 旧数据迁移 ----
    void migrateCopiesLegacyDataCompletely() {
        QTemporaryDir tmp;
        const QString legacy = makeLegacyAppData(tmp.path());
        const QString dataDir = tmp.path() + "/data";
        const QString err = PortableDataStore::migrateFromLegacy(legacy, dataDir);
        QVERIFY2(err.isEmpty(), qPrintable(err));
        QVERIFY(QFile::exists(dataDir + "/settings.json"));
        QVERIFY(QFile::exists(dataDir + "/Readdict.db"));
        QVERIFY(QFile::exists(dataDir + "/books/a.epub"));
        QVERIFY(QFile::exists(dataDir + "/covers/cover_x.png"));
        QVERIFY(QFile::exists(dataDir + "/backgrounds"));
        QVERIFY(QFile::exists(dataDir + "/.readdict_sync.json")); // 可选文件随迁
        QVERIFY(QFile::exists(dataDir + "/.readdict_migrated"));  // 完成标记
        QVERIFY(!QDir(tmp.path() + "/data.migrating").exists());  // 暂存目录已清理
        // 源数据保留、未修改
        QVERIFY(QFile::exists(legacy + "/settings.json"));
        QVERIFY(QFile::exists(legacy + "/books/a.epub"));
    }

    void migrateSkipsWhenPortableHasData() {
        QTemporaryDir tmp;
        const QString legacy = makeLegacyAppData(tmp.path());
        const QString dataDir = tmp.path() + "/data";
        QVERIFY(QDir().mkpath(dataDir));
        writeFile(dataDir + "/settings.json", "{\"portable\":true}");
        const QString err = PortableDataStore::migrateFromLegacy(legacy, dataDir);
        QVERIFY2(err.isEmpty(), qPrintable(err));           // 跳过不是错误
        QVERIFY(!QFile::exists(dataDir + "/Readdict.db"));  // 旧数据不覆盖便携数据
        QVERIFY(!QFile::exists(dataDir + "/.readdict_migrated"));
        QVERIFY(QFile::exists(legacy + "/Readdict.db"));    // 源仍在
    }

    void migrateFailureLeavesNoMarkerAndSourceIntact() {
        QTemporaryDir tmp;
        const QString legacy = makeLegacyAppData(tmp.path());
        const QString dataDir = tmp.path() + "/data";
        // 让 Readdict.db 不可读 → 暂存复制中途失败
        QFile db(legacy + "/Readdict.db");
        QVERIFY(db.setPermissions(QFileDevice::Permissions())); // 清空全部权限位
        const QString err = PortableDataStore::migrateFromLegacy(legacy, dataDir);
        QVERIFY(!err.isEmpty());
        QVERIFY(!QFile::exists(dataDir + "/.readdict_migrated")); // 部分失败不产生完成标记
        QVERIFY(!QFile::exists(dataDir + "/settings.json"));      // 未合并任何内容
        QVERIFY(!QDir(tmp.path() + "/data.migrating").exists());  // 暂存目录已清理
        QVERIFY(QFile::exists(legacy + "/settings.json"));        // 源数据保留
    }

    void migrateNoLegacyIsNoop() {
        QTemporaryDir tmp;
        const QString err = PortableDataStore::migrateFromLegacy(
            tmp.path() + "/nonexistent", tmp.path() + "/data");
        QVERIFY(err.isEmpty());
        QVERIFY(!QDir(tmp.path() + "/data").exists());
    }

    void migrateEmptyLegacyIsNoop() {
        QTemporaryDir tmp;
        const QString legacy = tmp.path() + "/legacy_appdata";
        QVERIFY(QDir().mkpath(legacy)); // 存在但为空
        const QString dataDir = tmp.path() + "/data";
        const QString err = PortableDataStore::migrateFromLegacy(legacy, dataDir);
        QVERIFY(err.isEmpty());
        QVERIFY(!QDir(dataDir).exists());                         // 无事发生
        QVERIFY(!QDir(tmp.path() + "/data.migrating").exists());
    }

    void migrateEmptySubdirDoesNotBlockMigration() {
        QTemporaryDir tmp;
        const QString legacy = makeLegacyAppData(tmp.path());
        const QString dataDir = tmp.path() + "/data";
        // prepareDataDir 遗留的空子目录不算有效数据，不应阻止迁移
        QVERIFY(QDir().mkpath(dataDir + "/books"));
        QVERIFY(QDir().mkpath(dataDir + "/covers"));
        const QString err = PortableDataStore::migrateFromLegacy(legacy, dataDir);
        QVERIFY2(err.isEmpty(), qPrintable(err));
        QVERIFY(QFile::exists(dataDir + "/settings.json"));
        QVERIFY(QFile::exists(dataDir + "/books/a.epub"));   // 旧数据已并入
        QVERIFY(QFile::exists(dataDir + "/.readdict_migrated"));
    }

    void migrateSkipsWhenPortableHasNonEmptyBooks() {
        QTemporaryDir tmp;
        const QString legacy = makeLegacyAppData(tmp.path());
        const QString dataDir = tmp.path() + "/data";
        QVERIFY(QDir().mkpath(dataDir + "/books"));
        writeFile(dataDir + "/books/existing.epub", "x");    // 非空子目录 = 有效数据
        const QString err = PortableDataStore::migrateFromLegacy(legacy, dataDir);
        QVERIFY2(err.isEmpty(), qPrintable(err));            // 跳过不是错误
        QVERIFY(!QFile::exists(dataDir + "/settings.json")); // 不覆盖便携数据
        QVERIFY(!QFile::exists(dataDir + "/.readdict_migrated"));
        QVERIFY(!QFile::exists(dataDir + "/books/a.epub"));  // 旧书未并入
        QVERIFY(QFile::exists(legacy + "/Readdict.db"));     // 源保留
    }

    void migrateMergeFailureRollsBackAndRetrySucceeds() {
        QTemporaryDir tmp;
        const QString legacy = makeLegacyAppData(tmp.path());
        const QString dataDir = tmp.path() + "/data";
        QVERIFY(QDir().mkpath(dataDir));
        writeFile(dataDir + "/books", "blocker");            // 合并 books 时必然失败
        const QString err = PortableDataStore::migrateFromLegacy(legacy, dataDir);
        QVERIFY(!err.isEmpty());
        QVERIFY(err.contains(QStringLiteral("旧数据合并失败")));
        // 失败清理：本次已合并项回滚，无残留、无标记、暂存已清、源保留
        QVERIFY(!QFile::exists(dataDir + "/settings.json"));
        QVERIFY(!QFile::exists(dataDir + "/Readdict.db"));
        QVERIFY(!QFile::exists(dataDir + "/.readdict_migrated"));
        QVERIFY(!QDir(tmp.path() + "/data.migrating").exists());
        QVERIFY(QFile::exists(legacy + "/Readdict.db"));
        // 移除阻塞后可重试成功（无“已迁移”误判跳过、无残留污染）
        QVERIFY(QFile::remove(dataDir + "/books"));
        const QString retry = PortableDataStore::migrateFromLegacy(legacy, dataDir);
        QVERIFY2(retry.isEmpty(), qPrintable(retry));
        QVERIFY(QFile::exists(dataDir + "/settings.json"));
        QVERIFY(QFile::exists(dataDir + "/books/a.epub"));
        QVERIFY(QFile::exists(dataDir + "/.readdict_migrated"));
    }

    // ---- 权限不足自动提权（Windows 运行时特性；本机覆盖非 Windows 分支与命令构造）----
    void isPermissionErrorTrueForUnwritableParent() {
        QTemporaryDir tmp;
        const QString dataDir = tmp.path() + "/data";
        // 父目录只读 → 创建 dataDir 必然失败，属权限错误
        QVERIFY(QFile::setPermissions(tmp.path(),
            QFileDevice::ReadOwner | QFileDevice::ExeOwner
            | QFileDevice::ReadGroup | QFileDevice::ExeGroup
            | QFileDevice::ReadOther | QFileDevice::ExeOther));
        const QString err = PortableDataStore::prepareDataDir(dataDir);
        QVERIFY(!err.isEmpty());
        QVERIFY2(PortableDataStore::isPermissionError(err, dataDir),
                 qPrintable(QStringLiteral("期望权限错误，实际错误: ") + err));
        // 恢复权限，保证 QTemporaryDir 能清理
        QFile::setPermissions(tmp.path(),
            QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner
            | QFileDevice::ReadGroup | QFileDevice::WriteGroup | QFileDevice::ExeGroup
            | QFileDevice::ReadOther | QFileDevice::WriteOther | QFileDevice::ExeOther);
    }

    void isPermissionErrorTrueForUnwritableExistingDir() {
        QTemporaryDir tmp;
        const QString dataDir = tmp.path() + "/data";
        QVERIFY(QDir().mkpath(dataDir));
        // 目录已存在但只读 → 子目录创建失败属权限错误
        QVERIFY(QFile::setPermissions(dataDir,
            QFileDevice::ReadOwner | QFileDevice::ExeOwner
            | QFileDevice::ReadGroup | QFileDevice::ExeGroup
            | QFileDevice::ReadOther | QFileDevice::ExeOther));
        const QString err = PortableDataStore::prepareDataDir(dataDir);
        QVERIFY(!err.isEmpty());
        QVERIFY2(PortableDataStore::isPermissionError(err, dataDir),
                 qPrintable(QStringLiteral("期望权限错误，实际错误: ") + err));
        QFile::setPermissions(dataDir,
            QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner
            | QFileDevice::ReadGroup | QFileDevice::WriteGroup | QFileDevice::ExeGroup
            | QFileDevice::ReadOther | QFileDevice::WriteOther | QFileDevice::ExeOther);
    }

    void isPermissionErrorFalseForPathIsFile() {
        QTemporaryDir tmp;
        const QString dataDir = tmp.path() + "/data";
        writeFile(dataDir, "not-a-dir");                          // 被文件占据：非权限问题
        const QString err = PortableDataStore::prepareDataDir(dataDir);
        QVERIFY(!err.isEmpty());
        QVERIFY(!PortableDataStore::isPermissionError(err, dataDir));
    }

    void prepareCommandPlainPathUnquoted() {
        const QStringList cmd =
            PortableDataStore::prepareCommand(QStringLiteral("F:/Readdict/data"));
        QCOMPARE(cmd.size(), 2);
        QCOMPARE(cmd.at(0), QStringLiteral("--prepare-data"));
        QCOMPARE(cmd.at(1), QStringLiteral("F:/Readdict/data"));  // 无空白/引号 → 不加引号
    }

    void prepareCommandQuotesPathWithSpaces() {
        const QStringList cmd = PortableDataStore::prepareCommand(
            QStringLiteral("C:/Program Files/Readdict/data"));
        QCOMPARE(cmd.at(1), QStringLiteral("\"C:/Program Files/Readdict/data\""));
    }

    void prepareCommandEscapesEmbeddedQuote() {
        const QStringList cmd = PortableDataStore::prepareCommand(
            QStringLiteral("C:/foo\"bar/data"));
        QCOMPARE(cmd.at(1), QStringLiteral("\"C:/foo\\\"bar/data\""));
    }

    void prepareCommandBackslashOnlyPathStaysUnquoted() {
        const QStringList cmd = PortableDataStore::prepareCommand(
            QStringLiteral("C:\\Readdict\\data\\"));
        // CommandLineToArgvW：无空白/引号时反斜杠原样保留，无需引号即可安全往返
        QCOMPARE(cmd.at(1), QStringLiteral("C:\\Readdict\\data\\"));
    }

    void prepareCommandDoublesTrailingBackslashesWhenQuoted() {
        const QStringList cmd = PortableDataStore::prepareCommand(
            QStringLiteral("C:\\Program Files\\Readdict\\data\\"));
        // 含空白必须加引号；收尾引号前的反斜杠按 CommandLineToArgvW 规则翻倍
        QCOMPARE(cmd.at(1), QStringLiteral("\"C:\\Program Files\\Readdict\\data\\\\\""));
    }

    void elevateNormalPathDoesNotElevate() {
        QTemporaryDir tmp;
        const QString dataDir = tmp.path() + "/data";
        const auto r = PortableDataStore::prepareWithElevation(
            dataDir, QStringLiteral("/nonexistent/Readdict.exe"), false);
        QVERIFY(r.success);
        QVERIFY(!r.elevated);                                     // 普通路径不提权
        QVERIFY(r.error.isEmpty());
        QVERIFY(QDir(dataDir + "/books").exists());
    }

    void elevateNonPermissionErrorDoesNotElevate() {
        QTemporaryDir tmp;
        const QString dataDir = tmp.path() + "/data";
        writeFile(dataDir, "not-a-dir");                          // 非权限错误 → 不提权
        const auto r = PortableDataStore::prepareWithElevation(
            dataDir, QStringLiteral("C:/Readdict/Readdict.exe"), false);
        QVERIFY(!r.success);
        QVERIFY(!r.elevated);
        QVERIFY(r.error.contains(dataDir));
    }

    void elevateNonWindowsReturnsUnsupported() {
        if (PortableDataStore::currentPlatform() == PortableDataStore::Platform::Windows)
            QSKIP("UAC 提权为 Windows 运行时特性，不在本机触发");
        QTemporaryDir tmp;
        const QString dataDir = tmp.path() + "/data";
        QVERIFY(QFile::setPermissions(tmp.path(),
            QFileDevice::ReadOwner | QFileDevice::ExeOwner
            | QFileDevice::ReadGroup | QFileDevice::ExeGroup
            | QFileDevice::ReadOther | QFileDevice::ExeOther));
        const auto r = PortableDataStore::prepareWithElevation(
            dataDir, QStringLiteral("C:/Readdict/Readdict.exe"), false);
        QVERIFY(!r.success);
        QVERIFY(!r.elevated);
        QVERIFY2(r.error.contains(QStringLiteral("不支持自动提权")),
                 qPrintable(QStringLiteral("期望不支持自动提权，实际: ") + r.error));
        QVERIFY(r.error.contains(dataDir));
        QFile::setPermissions(tmp.path(),
            QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner
            | QFileDevice::ReadGroup | QFileDevice::WriteGroup | QFileDevice::ExeGroup
            | QFileDevice::ReadOther | QFileDevice::WriteOther | QFileDevice::ExeOther);
    }

    void elevateAlreadyElevatedDoesNotElevateAgain() {
        if (PortableDataStore::currentPlatform() == PortableDataStore::Platform::Windows)
            QSKIP("UAC 提权为 Windows 运行时特性，不在本机触发");
        QTemporaryDir tmp;
        const QString dataDir = tmp.path() + "/data";
        QVERIFY(QFile::setPermissions(tmp.path(),
            QFileDevice::ReadOwner | QFileDevice::ExeOwner
            | QFileDevice::ReadGroup | QFileDevice::ExeGroup
            | QFileDevice::ReadOther | QFileDevice::ExeOther));
        const auto r = PortableDataStore::prepareWithElevation(
            dataDir, QStringLiteral("C:/Readdict/Readdict.exe"), true);
        QVERIFY(!r.success);
        QVERIFY(!r.elevated);
        QVERIFY2(r.error.contains(QStringLiteral("提权进程")),
                 qPrintable(QStringLiteral("期望拒绝二次提权，实际: ") + r.error));
        QFile::setPermissions(tmp.path(),
            QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner
            | QFileDevice::ReadGroup | QFileDevice::WriteGroup | QFileDevice::ExeGroup
            | QFileDevice::ReadOther | QFileDevice::WriteOther | QFileDevice::ExeOther);
    }

    void ensurePortableDataSucceedsNormalPath() {
        QTemporaryDir tmp;
        const QString legacy = makeLegacyAppData(tmp.path());
        const QString dataDir = tmp.path() + "/data";
        const auto r = PortableDataStore::ensurePortableData(
            legacy, dataDir, QStringLiteral("C:/Readdict/Readdict.exe"), false);
        QVERIFY(r.success);
        QVERIFY(!r.elevated);
        QVERIFY(r.error.isEmpty());
        QVERIFY(QFile::exists(dataDir + "/settings.json"));   // 迁移完成
        QVERIFY(QFile::exists(dataDir + "/books/a.epub"));
        QVERIFY(QFile::exists(dataDir + "/.readdict_migrated"));
        QVERIFY(QDir(dataDir + "/covers").exists());           // 目录准备完成
        QVERIFY(QDir(dataDir + "/backgrounds").exists());
    }

    void elevateReachedWhenMigrateFailsPermission() {
        if (PortableDataStore::currentPlatform() == PortableDataStore::Platform::Windows)
            QSKIP("UAC 提权为 Windows 运行时特性，不在本机触发");
        QTemporaryDir tmp;
        const QString legacy = makeLegacyAppData(tmp.path());
        const QString dataDir = tmp.path() + "/data";
        QVERIFY(QFile::setPermissions(tmp.path(),
            QFileDevice::ReadOwner | QFileDevice::ExeOwner
            | QFileDevice::ReadGroup | QFileDevice::ExeGroup
            | QFileDevice::ReadOther | QFileDevice::ExeOther));
        // 迁移阶段即权限失败（无法创建暂存目录）→ 仍进入提权流程，
        // 而不是在 migrate 一步就中止：非 Windows 返回平台级“不支持自动提权”
        const auto r = PortableDataStore::ensurePortableData(
            legacy, dataDir, QStringLiteral("C:/Readdict/Readdict.exe"), false);
        QVERIFY(!r.success);
        QVERIFY(!r.elevated);
        QVERIFY2(r.error.contains(QStringLiteral("不支持自动提权")),
                 qPrintable(QStringLiteral("期望进入提权流程，实际: ") + r.error));
        QVERIFY(r.error.contains(dataDir));
        QFile::setPermissions(tmp.path(),
            QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner
            | QFileDevice::ReadGroup | QFileDevice::WriteGroup | QFileDevice::ExeGroup
            | QFileDevice::ReadOther | QFileDevice::WriteOther | QFileDevice::ExeOther);
    }

    void migrateFailureNonPermissionDoesNotElevate() {
        if (PortableDataStore::currentPlatform() == PortableDataStore::Platform::Windows)
            QSKIP("UAC 提权为 Windows 运行时特性，不在本机触发");
        QTemporaryDir tmp;
        const QString legacy = makeLegacyAppData(tmp.path());
        const QString dataDir = tmp.path() + "/data";
        QFile db(legacy + "/Readdict.db");
        QVERIFY(db.setPermissions(QFileDevice::Permissions())); // 源不可读：非权限错误
        const auto r = PortableDataStore::ensurePortableData(
            legacy, dataDir, QStringLiteral("C:/Readdict/Readdict.exe"), false);
        QVERIFY(!r.success);
        QVERIFY(!r.elevated);
        QVERIFY2(r.error.contains(QStringLiteral("旧数据迁移失败")),
                 qPrintable(QStringLiteral("期望返回迁移错误，实际: ") + r.error));
        QVERIFY(!r.error.contains(QStringLiteral("不支持自动提权")));
        QVERIFY(r.error.contains(dataDir));
    }

    void helperPreparesDir() {
        QTemporaryDir tmp;
        PortableDataStore::Params p;
        p.platform = PortableDataStore::Platform::Windows;
        p.applicationDirPath = tmp.path();                        // 只接受自身 <appDir>/data
        p.appDataLocation = tmp.path() + "/legacy_appdata";       // 不存在 → 迁移跳过
        const QString dataDir = tmp.path() + "/data";
        QCOMPARE(PortableDataStore::runElevationHelper(
                     { QStringLiteral("--prepare-data"), dataDir }, p), 0);
        QVERIFY(QDir(dataDir + "/books").exists());
        QVERIFY(QDir(dataDir + "/covers").exists());
        QVERIFY(QDir(dataDir + "/backgrounds").exists());
    }

    void helperMigratesLegacyData() {
        QTemporaryDir tmp;
        const QString legacy = makeLegacyAppData(tmp.path());
        PortableDataStore::Params p;
        p.platform = PortableDataStore::Platform::Windows;
        p.applicationDirPath = tmp.path();                        // 只接受自身 <appDir>/data
        p.appDataLocation = legacy;
        const QString dataDir = tmp.path() + "/data";
        QCOMPARE(PortableDataStore::runElevationHelper(
                     { QStringLiteral("--prepare-data"), dataDir }, p), 0);
        QVERIFY(QFile::exists(dataDir + "/settings.json"));
        QVERIFY(QFile::exists(dataDir + "/Readdict.db"));
        QVERIFY(QFile::exists(dataDir + "/books/a.epub"));
        QVERIFY(QFile::exists(dataDir + "/.readdict_migrated"));  // 迁移标记
        QVERIFY(QFile::exists(legacy + "/settings.json"));        // 源数据保留
    }

    void helperRejectsPathOutsideOwnDataDir() {
        QTemporaryDir tmp;
        PortableDataStore::Params p;
        p.platform = PortableDataStore::Platform::Windows;
        p.applicationDirPath = tmp.path();
        // 绝对干净路径但不在本程序目录 data/ 下 → 拒绝（提权进程绝不写入其他位置）
        const QString other = tmp.path() + "/other";
        QCOMPARE(PortableDataStore::runElevationHelper(
                     { QStringLiteral("--prepare-data"), other }, p), 3);
        QVERIFY(!QDir(other).exists());
        const QString sibling = tmp.path() + "/data-extra";
        QCOMPARE(PortableDataStore::runElevationHelper(
                     { QStringLiteral("--prepare-data"), sibling }, p), 3);
        QVERIFY(!QDir(sibling).exists());
    }

    void helperRejectsEmptyApplicationDir() {
        QTemporaryDir tmp;
        PortableDataStore::Params p;
        p.platform = PortableDataStore::Platform::Windows;
        // 无法推导本程序目录 data/ → 拒绝一切路径（防诱导写入）
        const QString dataDir = tmp.path() + "/data";
        QCOMPARE(PortableDataStore::runElevationHelper(
                     { QStringLiteral("--prepare-data"), dataDir }, p), 3);
        QVERIFY(!QDir(dataDir).exists());
    }

    void helperRejectsTraversal() {
        QTemporaryDir tmp;
        PortableDataStore::Params p;
        p.platform = PortableDataStore::Platform::Windows;
        const QString evil = tmp.path() + "/../helper-evil";      // 目录穿越
        QCOMPARE(PortableDataStore::runElevationHelper(
                     { QStringLiteral("--prepare-data"), evil }, p), 3);
        QVERIFY(!QDir(QDir::cleanPath(evil)).exists());
    }

    void helperRejectsRelativePath() {
        PortableDataStore::Params p;
        QCOMPARE(PortableDataStore::runElevationHelper(
                     { QStringLiteral("--prepare-data"), QStringLiteral("data/books") }, p), 3);
    }

    void helperRejectsBadArgs() {
        PortableDataStore::Params p;
        QCOMPARE(PortableDataStore::runElevationHelper({}, p), 2);
        QCOMPARE(PortableDataStore::runElevationHelper(
                     { QStringLiteral("--prepare-data") }, p), 2);
        QCOMPARE(PortableDataStore::runElevationHelper(
                     { QStringLiteral("--prepare-data"), QStringLiteral("/tmp/x"),
                       QStringLiteral("extra") }, p), 2);
        QCOMPARE(PortableDataStore::runElevationHelper(
                     { QStringLiteral("--some-other-flag"), QStringLiteral("/tmp/x") }, p), 2);
    }
};

QTEST_MAIN(TestPortableData)
#include "tst_portabledata.moc"
