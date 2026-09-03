#pragma once
#include <QObject>
#include <QUrl>

// 本地路径 → file:// URL 的统一转换单例。
//
// 背景：QML 侧多处用 "file://" + path 手工拼接，Windows 盘符路径（F:/...）
// 拼接后 QUrl 把 "F:" 解析为 scheme:port 分隔、"F" 当主机名（且小写化），
// 生成 file://f/Readdict/... 这类坏 URL，图片/PDF 全部加载失败；Unix 路径
// 以 "/" 开头碰巧正确，故 bug 仅在 Windows 爆发。QUrl::fromLocalFile 才是
// 唯一正确入口（处理盘符、反斜杠、中文与空格的百分号转义）。
class FileUrl : public QObject {
    Q_OBJECT
public:
    explicit FileUrl(QObject *parent = nullptr) : QObject(parent) {}
    // 本地绝对路径 → file:/// URL；空串、已是 file:/qrc:/http(s): 等 URL
    // 的输入原样返回（QUrl::fromLocalFile 对含 scheme 的输入会错误重编码）。
    Q_INVOKABLE QUrl fromPath(const QString &path) const;
};
