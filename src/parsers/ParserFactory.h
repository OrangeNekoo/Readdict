#pragma once
#include "DocumentModel.h"
#include <QString>

class ParserFactory {
public:
    static DocumentModel parse(const QString &filePath, const QString &format);
};
