#pragma once
#include <QString>

// 应用日志文件化：qInstallMessageHandler 把 qInfo/qWarning 等写入
// <数据目录>/logs/readdict-YYYY-MM-DD.log（按天分文件，同时保留 stderr）。
// 安装时清理 7 天前的旧日志。
namespace FileLogger {
void install(const QString &dataDir);
}
