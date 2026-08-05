#pragma once
#include "DocumentModel.h"
#include <QString>

class TextParser {
public:
    DocumentModel parse(const QString &filePath);
private:
    static QString detectAndRead(const QString &filePath);
    static QString mdToHtml(const QString &line);
};
