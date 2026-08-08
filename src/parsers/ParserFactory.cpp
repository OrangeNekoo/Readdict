#include "ParserFactory.h"
#include "TextParser.h"
#include "EpubParser.h"
#include "Fb2Parser.h"
#include "MobiParser.h"

DocumentModel ParserFactory::parse(const QString &filePath, const QString &format, QString *error) {
    if (format == "TXT" || format == "MD") {
        TextParser p;
        const DocumentModel m = p.parse(filePath);
        if (error) *error = p.lastError();
        return m;
    }
    if (format == "EPUB") {
        EpubParser p;
        const DocumentModel m = p.parse(filePath);
        if (error) *error = p.lastError();
        return m;
    }
    if (format == "FB2") {
        Fb2Parser p;
        const DocumentModel m = p.parse(filePath);
        if (error) *error = p.lastError();
        return m;
    }
    if (format == "MOBI" || format == "AZW3") {
        MobiParser p;
        const DocumentModel m = p.parse(filePath);
        if (error) *error = p.lastError();
        return m;
    }
    if (error) *error = QStringLiteral("不支持的文件格式: %1").arg(format);
    return {};
}
