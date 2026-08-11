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
};

QTEST_MAIN(TestPortableData)
#include "tst_portabledata.moc"
