#pragma once
#include "DocumentModel.h"
#include <QString>

class ParserFactory {
public:
    // error（可选出参）：解析失败原因（具体解析器 lastError 透传）；成功为空串
    static DocumentModel parse(const QString &filePath, const QString &format, QString *error = nullptr);
};
