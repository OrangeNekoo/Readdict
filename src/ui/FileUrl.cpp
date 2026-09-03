#include "FileUrl.h"

QUrl FileUrl::fromPath(const QString &path) const {
    if (path.isEmpty())
        return QUrl();
    // 已是完整 URL（file:/、http:、qrc: 等带 scheme）的原样保留；判定与
    // QUrl 一致：scheme 为字母开头 + 字母数字/+-.。Windows 盘符 "F:/x" 同形，
    // 但单字母 scheme 均为保留盘符、无真实 URL 使用，按本地路径处理。
    const int colon = path.indexOf(':');
    if (colon > 1) {
        const QString scheme = path.left(colon);
        const QChar *u = scheme.constData();
        const int len = scheme.length();
        bool isScheme = u[0].isLetter();
        for (int i = 1; isScheme && i < len; ++i)
            isScheme = u[i].isLetterOrNumber() || u[i] == '+' || u[i] == '-' || u[i] == '.';
        if (isScheme)
            return QUrl(path);
    }
    return QUrl::fromLocalFile(path);
}
