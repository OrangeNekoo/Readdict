#include "ParserFactory.h"
#include "TextParser.h"
#include "EpubParser.h"
#include "Fb2Parser.h"
#include "MobiParser.h"

DocumentModel ParserFactory::parse(const QString &filePath, const QString &format) {
    if (format == "TXT" || format == "MD") return TextParser().parse(filePath);
    if (format == "EPUB") return EpubParser().parse(filePath);
    if (format == "FB2") return Fb2Parser().parse(filePath);
    if (format == "MOBI" || format == "AZW3") return MobiParser().parse(filePath);
    return {};
}
