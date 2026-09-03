#include "FileLogger.h"

#include <QDate>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QMutex>
#include <QTextStream>
#include <cstdio>

namespace {

QMutex g_mutex;
QString g_logDir;
constexpr int kRetentionDays = 7;

const char *typeTag(QtMsgType type) {
    switch (type) {
    case QtDebugMsg:    return "DEBUG";
    case QtInfoMsg:     return "INFO";
    case QtWarningMsg:  return "WARN";
    case QtCriticalMsg: return "ERROR";
    case QtFatalMsg:    return "FATAL";
    }
    return "INFO";
}

void fileMessageHandler(QtMsgType type, const QMessageLogContext &context, const QString &msg) {
    QMutexLocker lock(&g_mutex);
    const QString line = QStringLiteral("%1 [%2] %3 (%4:%5)\n")
        .arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd hh:mm:ss.zzz")))
        .arg(typeTag(type), msg,
             context.file ? QString::fromLatin1(context.file) : QStringLiteral("-"))
        .arg(context.line);
    const QByteArray utf8 = line.toUtf8();

    // 未安装完成（数据目录未知）或写文件失败时，仅走 stderr
    if (!g_logDir.isEmpty()) {
        QFile f(g_logDir + QStringLiteral("/readdict-")
                + QDate::currentDate().toString(QStringLiteral("yyyy-MM-dd")) + QStringLiteral(".log"));
        if (f.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
            f.write(utf8);
        }
    }
    std::fwrite(utf8.constData(), 1, size_t(utf8.size()), stderr);
    std::fflush(stderr);
}

void removeExpiredLogs(const QString &logDir) {
    const QDateTime cutoff = QDateTime::currentDateTime().addDays(-kRetentionDays);
    const QFileInfoList entries = QDir(logDir).entryInfoList(
        {QStringLiteral("*.log")}, QDir::Files, QDir::Name);
    for (const QFileInfo &fi : entries) {
        if (fi.lastModified() < cutoff) QFile::remove(fi.absoluteFilePath());
    }
}

} // namespace

void FileLogger::install(const QString &dataDir) {
    QMutexLocker lock(&g_mutex);
    g_logDir = dataDir + QStringLiteral("/logs");
    QDir().mkpath(g_logDir);
    removeExpiredLogs(g_logDir);
    qInstallMessageHandler(fileMessageHandler);
}
