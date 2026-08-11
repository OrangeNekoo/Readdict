#include "PortableData.h"
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QIODevice>
#include <QStandardPaths>

#include <cerrno>

#if defined(Q_OS_WIN)
#include <windows.h>
#include <shellapi.h>
#endif

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

// 删除单个条目（文件或目录树），供迁移合并失败回滚使用。
void removeEntry(const QString &path) {
    const QFileInfo fi(path);
    if (fi.isDir())
        QDir(path).removeRecursively();
    else if (fi.exists())
        QFile::remove(path);
}

// errno 是否为权限类错误（QDir::mkpath/QFileSystemEngine 失败后 errno 保真：
// Windows ACL 拒绝映射为 EACCES，POSIX 为 EACCES/EPERM/EROFS）。
bool isPermissionErrno(int err) {
    return err == EACCES || err == EPERM || err == EROFS;
}

// 目录可写性兜底判断：dataDir 已存在但不可写，或父目录存在但不可写（无法创建）。
bool pathLooksUnwritable(const QString &dataDir) {
    const QFileInfo dir(dataDir);
    if (dir.exists())
        return !dir.isWritable();
    const QFileInfo parent(QFileInfo(dataDir).absolutePath());
    return parent.exists() && !parent.isWritable();
}

// 按 CommandLineToArgvW 规则转义命令行参数：含空白/引号（或为空）时加引号，
// 引号前的反斜杠翻倍，收尾引号前的反斜杠同样翻倍。Windows UTF-16 路径安全。
QString quoteWindowsArgument(const QString &arg) {
    bool needQuote = arg.isEmpty();
    for (const QChar c : arg) {
        if (c.isSpace() || c == QLatin1Char('"')) {
            needQuote = true;
            break;
        }
    }
    if (!needQuote)
        return arg;
    QString out;
    out.reserve(arg.size() + 8);
    out += QLatin1Char('"');
    int backslashes = 0;
    for (const QChar c : arg) {
        if (c == QLatin1Char('\\')) {
            ++backslashes;
        } else if (c == QLatin1Char('"')) {
            out.append(QString(backslashes * 2 + 1, QLatin1Char('\\')));
            out.append(QLatin1Char('"'));
            backslashes = 0;
        } else {
            out.append(QString(backslashes, QLatin1Char('\\')));
            out.append(c);
            backslashes = 0;
        }
    }
    out.append(QString(backslashes * 2, QLatin1Char('\\')));
    out.append(QLatin1Char('"'));
    return out;
}

#if defined(Q_OS_WIN)
// 将 Windows 错误码转成可读文本（用于 ShellExecuteExW 失败诊断）。
QString windowsErrorText(DWORD code) {
    wchar_t *buf = nullptr;
    const DWORD n = FormatMessageW(
        FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM
            | FORMAT_MESSAGE_IGNORE_INSERTS,
        nullptr, code, 0, reinterpret_cast<wchar_t *>(&buf), 0, nullptr);
    QString text;
    if (n > 0 && buf) {
        text = QString::fromWCharArray(buf, int(n)).trimmed();
        LocalFree(buf);
    }
    return text.isEmpty() ? QStringLiteral("错误码 %1").arg(code) : text;
}

// Windows 提权路径：ShellExecuteExW verb `runas` 调起自身 helper
// （executablePath --prepare-data <dataDir>）。helper 内部自行 迁移+准备；
// 本函数只负责启动、有界等待与退出码检查，成功后由 ensurePortableData 复检。
// 仅当 迁移/准备 失败疑似权限不足且非提权进程时由 ensurePortableData 调用。
PortableDataStore::ElevationResult elevateViaUac(const QString &dataDir,
                                                 const QString &executablePath) {
    PortableDataStore::ElevationResult result;
    const QString params =
        PortableDataStore::prepareCommand(dataDir).join(QLatin1Char(' '));

    SHELLEXECUTEINFOW sei{};
    sei.cbSize = sizeof(SHELLEXECUTEINFOW);
    sei.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_FLAG_NO_UI;
    sei.lpVerb = L"runas";
    sei.lpFile = reinterpret_cast<LPCWSTR>(executablePath.utf16());
    sei.lpParameters = reinterpret_cast<LPCWSTR>(params.utf16());
    sei.nShow = SW_HIDE;

    // UAC 失败/取消（ERROR_CANCELLED）在此返回可读错误，不进入等待。
    if (!ShellExecuteExW(&sei)) {
        const DWORD code = GetLastError();
        result.elevated = false;
        result.success = false;
        result.error = code == ERROR_CANCELLED
            ? QStringLiteral("用户取消了 UAC 提权，数据目录准备失败: %1").arg(dataDir)
            : QStringLiteral("无法启动提权 helper（%1）: %2")
                  .arg(windowsErrorText(code), dataDir);
        return result;
    }

    result.elevated = true;
    DWORD exitCode = 0;
    if (!sei.hProcess) {
        result.success = false;
        result.error = QStringLiteral("提权 helper 启动后未返回进程句柄: %1").arg(dataDir);
        return result;
    }
    // 等待 helper 退出（helper 只做目录/迁移、无事件循环，正常必然快速退出；
    // 保留 INFINITE 但必须检查 API 返回，等待失败不得以未知状态继续）。
    const DWORD waitResult = WaitForSingleObject(sei.hProcess, INFINITE);
    if (waitResult != WAIT_OBJECT_0) {
        const DWORD code = GetLastError();
        result.success = false;
        result.error = QStringLiteral("等待提权 helper 退出失败（%1）: %2")
            .arg(waitResult == WAIT_FAILED ? windowsErrorText(code)
                 : QStringLiteral("未获得对象信号，状态 %1").arg(waitResult),
                 dataDir);
        CloseHandle(sei.hProcess);
        return result;
    }
    if (!GetExitCodeProcess(sei.hProcess, &exitCode)) {
        const DWORD code = GetLastError();
        result.success = false;
        result.error = QStringLiteral("读取提权 helper 退出码失败（%1）: %2")
            .arg(windowsErrorText(code), dataDir);
        CloseHandle(sei.hProcess);
        return result;
    }
    CloseHandle(sei.hProcess);

    // helper 退出码 1=准备/迁移失败、2=参数形态错误、3=路径被拒绝，统一报可读错误。
    if (exitCode != 0) {
        result.success = false;
        result.error = QStringLiteral("提权 helper 执行失败（退出码 %1）: %2")
                           .arg(exitCode).arg(dataDir);
        return result;
    }
    result.success = true;
    return result;
}
#endif // Q_OS_WIN

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
    if (!QDir().mkpath(dataDir)) {
        const bool perm = isPermissionErrno(errno) || pathLooksUnwritable(dataDir);
        return QStringLiteral("无法创建数据目录: %1%2")
            .arg(dataDir, perm ? QStringLiteral("（权限不足）") : QString());
    }
    QDir root(dataDir);
    const QStringList subs = subDirs();
    for (const QString &sub : subs) {
        if (!root.mkpath(sub)) {
            const bool perm = isPermissionErrno(errno) || pathLooksUnwritable(dataDir);
            return QStringLiteral("无法创建数据子目录: %1%2")
                .arg(root.filePath(sub), perm ? QStringLiteral("（权限不足）") : QString());
        }
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

    // 必需内容全部复制成功 → 合并到 dataDir。任一项失败回滚本次已合并项：
    // dataDir 回到“无有效数据”状态，保证可重试（无残留污染、不产生完成标记）。
    if (!QDir().mkpath(dataDir)) {
        QDir(staging).removeRecursively();
        return QStringLiteral("无法创建数据目录: %1").arg(dataDir);
    }
    QStringList merged;
    for (const QString &name : sources) {
        const QString err = copyRecursively(staging + QLatin1Char('/') + name,
                                            dataDir + QLatin1Char('/') + name);
        if (!err.isEmpty()) {
            for (const QString &done : merged)
                removeEntry(dataDir + QLatin1Char('/') + done);
            QDir(staging).removeRecursively();
            return QStringLiteral("旧数据合并失败（%1）: %2").arg(name, err);
        }
        merged << name;
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
    // 只认有效数据：空子目录（目录准备遗留）不算，否则会阻止后续迁移
    for (const QString &sub : subDirs()) {
        const QDir sd(d.filePath(sub));
        if (sd.exists()
            && !sd.entryList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden).isEmpty())
            return true;
    }
    return false;
}

bool PortableDataStore::isPermissionError(const QString &error, const QString &dataDir) {
    // 1) 消息明确带权限措辞（prepareDataDir 在 errno EACCES/目录不可写时追加“权限不足”）
    if (error.contains(QStringLiteral("权限不足"))
        || error.contains(QLatin1String("permission denied"), Qt::CaseInsensitive)
        || error.contains(QLatin1String("access is denied"), Qt::CaseInsensitive))
        return true;
    // 2) 兜底：目录已存在但不可写，或父目录存在但不可写（无法创建）
    return pathLooksUnwritable(dataDir);
}

QStringList PortableDataStore::prepareCommand(const QString &dataDir) {
    // 只构造固定形态 { "--prepare-data", <转义路径> }，不接受任意命令。
    return { QStringLiteral("--prepare-data"), quoteWindowsArgument(dataDir) };
}

PortableDataStore::ElevationResult PortableDataStore::ensurePortableData(
    const QString &legacyAppData, const QString &dataDir,
    const QString &executablePath, bool alreadyElevated) {
    ElevationResult result;

    // 1. 普通权限整体尝试：旧数据迁移 + 目录准备一次完成。
    //    （迁移失败不再单独致命：权限不足时可经提权 helper 重跑。）
    QString err = migrateFromLegacy(legacyAppData, dataDir);
    if (err.isEmpty())
        err = prepareDataDir(dataDir);
    if (err.isEmpty()) {
        result.elevated = false;
        result.success = true;
        return result;
    }

    // 2. 非权限错误（如路径被文件占据、源数据不可读）直接失败，提权无意义。
    if (!isPermissionError(err, dataDir)) {
        result.elevated = false;
        result.success = false;
        result.error = err;
        return result;
    }

    // 3. 防 UAC 递归：已在提权进程中不再二次提权。
    //    （helper 模式 runElevationHelper 绝不调用本函数，此处为双保险。）
    if (alreadyElevated) {
        result.elevated = false;
        result.success = false;
        result.error = QStringLiteral("数据目录权限不足且已处于提权进程，放弃二次提权: %1")
                           .arg(dataDir);
        return result;
    }

#if defined(Q_OS_WIN)
    // 4. 提权 helper 内部自行 迁移+准备（其 legacy 由其启动参数解析）。
    result = elevateViaUac(dataDir, executablePath);
    if (!result.success)
        return result;

    // 5. 复检：提权后 迁移+准备 都必须成立才 success（helper 已完成则此处均为
    //    幂等空操作——迁移见 .readdict_migrated/有效数据即跳过，准备见目录已存在）。
    err = migrateFromLegacy(legacyAppData, dataDir);
    if (err.isEmpty())
        err = prepareDataDir(dataDir);
    if (!err.isEmpty()) {
        result.elevated = true;
        result.success = false;
        result.error = QStringLiteral("提权后数据目录仍不可用: %1（%2）").arg(dataDir, err);
    }
    return result;
#else
    // macOS/Linux：不自动提权（不调 sudo/root），返回明确错误由调用方停止启动。
    result.elevated = false;
    result.success = false;
    result.error = QStringLiteral("当前平台不支持自动提权，数据目录权限不足: %1").arg(dataDir);
    return result;
#endif
}

PortableDataStore::ElevationResult PortableDataStore::prepareWithElevation(
    const QString &dataDir, const QString &executablePath, bool alreadyElevated) {
    // 仅“目录准备”语义的旧接口：等价于 ensurePortableData 传空 legacy
    // （普通路径无旧数据可迁移，migrateFromLegacy 为空操作）。
    return ensurePortableData(QString(), dataDir, executablePath, alreadyElevated);
}

int PortableDataStore::runElevationHelper(const QStringList &args, const Params &p) {
    // 仅接受固定形态：--prepare-data <路径>。不接受任何其他命令。
    if (args.size() != 2 || args.at(0) != QStringLiteral("--prepare-data"))
        return 2;
    const QString dataDir = args.at(1);
    // 路径穿越防护：必须是 cleanPath 后的绝对路径（拒绝 .. 穿越/相对路径/脏路径）。
    const QString clean = QDir::cleanPath(dataDir);
    if (clean.isEmpty() || !QDir::isAbsolutePath(clean) || clean != dataDir)
        return 3;
    // 安全边界：只接受本程序目录下的 data/（Windows 便携目录唯一形态）。任意其他
    // 绝对路径一律拒绝——提权进程绝不被诱导在管理员权限下写入任意位置。
    const QString expected = p.applicationDirPath.isEmpty()
        ? QString() : QDir::cleanPath(p.applicationDirPath + QStringLiteral("/data"));
    if (expected.isEmpty() || clean != expected)
        return 3;
    // Windows 旧数据迁移（提权后一并完成）；macOS/Linux 传空 legacyAppData 即跳过。
    const QString legacy =
        p.platform == Platform::Windows ? p.appDataLocation : QString();
    const QString migrateErr = migrateFromLegacy(legacy, clean);
    if (!migrateErr.isEmpty()) {
        qCritical().noquote() << "提权 helper: 旧数据迁移失败:" << migrateErr;
        return 1;
    }
    const QString prepareErr = prepareDataDir(clean);
    if (!prepareErr.isEmpty()) {
        qCritical().noquote() << "提权 helper: 数据目录准备失败:" << prepareErr;
        return 1;
    }
    return 0;
}

#if defined(Q_OS_WIN)
bool PortableDataStore::isRunningElevated() {
    HANDLE token = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token))
        return false;
    TOKEN_ELEVATION elev{};
    DWORD size = 0;
    const BOOL ok = GetTokenInformation(token, TokenElevation, &elev, sizeof(elev), &size);
    CloseHandle(token);
    return ok && elev.TokenIsElevated != 0;
}
#endif

QStringList PortableDataStore::subDirs() {
    return { QStringLiteral("books"), QStringLiteral("covers"), QStringLiteral("backgrounds") };
}

QStringList PortableDataStore::legacyOptionalFiles() {
    return { QStringLiteral(".readdict_sync.json"), QStringLiteral(".readdict_index_fail.json") };
}

QString PortableDataStore::migrationMarker() {
    return QStringLiteral(".readdict_migrated");
}
