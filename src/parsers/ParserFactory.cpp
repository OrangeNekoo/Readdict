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

DocumentModel ParserFactory::readMetadata(const QString &filePath, const QString &format) {
    if (format == "EPUB") {
        EpubParser p;
        return p.readMetadata(filePath);
    }
    if (format == "FB2") {
        Fb2Parser p;
        return p.readMetadataOnly(filePath);
    }
    if (format == "MOBI" || format == "AZW3") {
        MobiParser p;
        return p.readMetadataOnly(filePath);
    }
    // TXT/MD/PDF/未知：无元数据来源，返回空模型（标题回退文件名、作者/出版社空）
    return {};
}
