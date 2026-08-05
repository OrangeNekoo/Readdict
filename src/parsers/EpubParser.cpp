// EpubParser.cpp — EPUB 解析器
// 管线：container.xml → rootfile → content.opf（title/creator/manifest/spine）
// → 按 spine 顺序逐章 XHTML → normalizeXhtml → 按 <p>/<h*>/<li> 切分段落。
// 图片 <img src> 从 zip 解出二进制，缓存到 QDir::temp() 下按书唯一的子目录
// （Readdict-<epub 路径 md5>），Paragraph.imagePath 指向解出文件。
#include "EpubParser.h"
#include "SentenceSplitter.h"

#include <unzip.h>   // minizip（third_party/zlib/contrib/minizip，B1 引入）

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QCryptographicHash>
#include <QRegularExpression>
#include <QUrl>
#include <QXmlStreamReader>
#include <utility>

namespace {

// ---- 小工具 ----

// 归一化 html 中的实体仅来自 toHtmlEscaped：&amp; &lt; &gt; &quot; &#39;
// （数值实体在 XML 解析时已被解码）。还原顺序：&amp; 最后。
QString decodeEntities(QString s) {
    return s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"")
            .replace("&#39;", "'").replace("&amp;", "&");
}

// 去掉轻量 html 标签取纯文本
QString stripTags(QString s) {
    static const QRegularExpression tagRe("<[^>]*>");
    return decodeEntities(s.replace(tagRe, QString()));
}

// 解析 zip 内相对路径（href 相对条目所在目录），支持 ./ 与 ../；href 可能含
// 百分号编码、#fragment、?query。先按编码态剥离 #/?（%23/%3F 是字面量，不算
// 分隔符），再百分号解码。返回 zip 内条目路径；无法解析时返回空。
QString resolveEntry(const QString &href, const QString &baseEntry) {
    QString rel = href; // 编码态处理，见上
    const int frag = rel.indexOf('#');
    if (frag >= 0) rel.truncate(frag);
    const int query = rel.indexOf('?');
    if (query >= 0) rel.truncate(query);
    rel = QUrl::fromPercentEncoding(rel.toUtf8());
    rel.replace('\\', '/');
    if (rel.isEmpty() || rel.contains("://") || rel.startsWith("data:"))
        return {};
    if (rel.startsWith('/')) rel.remove(0, 1); // 以 / 开头视为相对 zip 根
    QString base = baseEntry;
    const int slash = base.lastIndexOf('/');
    if (slash >= 0) base.truncate(slash + 1); // 保留目录部分（含尾部 '/'）
    QStringList parts = (base + rel).split('/');
    QStringList out;
    for (const QString &p : std::as_const(parts)) {
        if (p.isEmpty() || p == ".")
            continue;
        if (p == "..") {
            if (!out.isEmpty()) out.removeLast();
            continue;
        }
        out.append(p);
    }
    return out.join('/');
}

// 解析 container.xml，取 rootfile full-path（优先 media-type 为 oebps-package+xml 者）
QString containerRootfile(const QByteArray &xml) {
    QXmlStreamReader r(xml);
    QString fallback;
    while (!r.atEnd()) {
        r.readNext();
        if (!r.isStartElement() || r.name().toString() != QLatin1String("rootfile"))
            continue;
        const QString full = r.attributes().value("full-path").toString();
        const QString mt = r.attributes().value("media-type").toString();
        if (full.isEmpty())
            continue;
        if (mt == QLatin1String("application/oebps-package+xml"))
            return full;
        if (fallback.isEmpty())
            fallback = full;
    }
    return fallback;
}

// OPF 解析结果：书名/作者、manifest id→(href, media-type)、spine idref 顺序
struct OpfInfo {
    QString title, author;
    QHash<QString, QPair<QString, QString>> itemById; // id → (href, media-type)
    QStringList spineIds;
};

// 解析 content.opf（标签名去前缀匹配，兼容 dc:title 等命名空间写法）
bool parseOpf(const QByteArray &xml, OpfInfo *out) {
    QXmlStreamReader r(xml);
    while (!r.atEnd()) {
        r.readNext();
        if (!r.isStartElement())
            continue;
        QString tag = r.name().toString();
        const int colon = tag.indexOf(':');
        if (colon >= 0) tag.remove(0, colon + 1);
        if (tag == QLatin1String("title") && out->title.isEmpty()) {
            out->title = r.readElementText().trimmed();
        } else if (tag == QLatin1String("creator") && out->author.isEmpty()) {
            out->author = r.readElementText().trimmed();
        } else if (tag == QLatin1String("item")) {
            const QString id = r.attributes().value("id").toString();
            const QString href = r.attributes().value("href").toString();
            const QString mt = r.attributes().value("media-type").toString();
            if (!id.isEmpty() && !href.isEmpty())
                out->itemById.insert(id, qMakePair(href, mt));
        } else if (tag == QLatin1String("itemref")) {
            const QString idref = r.attributes().value("idref").toString();
            if (!idref.isEmpty())
                out->spineIds.append(idref);
        }
    }
    return !out->spineIds.isEmpty();
}

// 从归一化 html 提取首个 h1-h3 文本（章节标题兜底，<title> 缺失时用）
QString firstHeading(const QString &html) {
    static const QRegularExpression hRe("<h[123][^>]*>(.*?)</h[123]>",
                                        QRegularExpression::DotMatchesEverythingOption);
    const QRegularExpressionMatch m = hRe.match(html);
    return m.hasMatch() ? stripTags(m.captured(1)).trimmed() : QString();
}

// 空段落（无文本且无图片）不进入章节
bool isEmptyParagraph(const Paragraph &p) {
    return p.imagePath.isEmpty() && p.text.trimmed().isEmpty();
}

// 单条 zip 条目大小上限（章节/图片均远小于此；与 TextParser 的读取取舍一致，
// 防恶意/损坏压缩包撑爆内存）
constexpr qint64 kMaxZipEntrySize = 64LL * 1024 * 1024;

// HTML 命名实体解析器：XML 只预定义 amp/lt/gt/quot/apos，XHTML 里常见的
// &nbsp;/&mdash;/&hellip; 等未声明实体若不解析，QXmlStreamReader 直接报错、
// 实体之后正文静默截断。映射常见 HTML 4 命名实体为对应码点。
class HtmlEntityResolver : public QXmlStreamEntityResolver {
public:
    QString resolveUndeclaredEntity(const QString &name) override {
        static const QHash<QString, QChar> kEntities = {
            {QStringLiteral("nbsp"), QChar(0x00A0)},
            {QStringLiteral("mdash"), QChar(0x2014)},
            {QStringLiteral("ndash"), QChar(0x2013)},
            {QStringLiteral("hellip"), QChar(0x2026)},
            {QStringLiteral("lsquo"), QChar(0x2018)},
            {QStringLiteral("rsquo"), QChar(0x2019)},
            {QStringLiteral("ldquo"), QChar(0x201C)},
            {QStringLiteral("rdquo"), QChar(0x201D)},
            {QStringLiteral("sbquo"), QChar(0x201A)},
            {QStringLiteral("bdquo"), QChar(0x201E)},
            {QStringLiteral("copy"), QChar(0x00A9)},
            {QStringLiteral("reg"), QChar(0x00AE)},
            {QStringLiteral("trade"), QChar(0x2122)},
            {QStringLiteral("middot"), QChar(0x00B7)},
            {QStringLiteral("bull"), QChar(0x2022)},
            {QStringLiteral("laquo"), QChar(0x00AB)},
            {QStringLiteral("raquo"), QChar(0x00BB)},
            {QStringLiteral("times"), QChar(0x00D7)},
            {QStringLiteral("divide"), QChar(0x00F7)},
            {QStringLiteral("plusmn"), QChar(0x00B1)},
            {QStringLiteral("deg"), QChar(0x00B0)},
            {QStringLiteral("pound"), QChar(0x00A3)},
            {QStringLiteral("yen"), QChar(0x00A5)},
            {QStringLiteral("euro"), QChar(0x20AC)},
            {QStringLiteral("frac12"), QChar(0x00BD)},
            {QStringLiteral("frac14"), QChar(0x00BC)},
            {QStringLiteral("frac34"), QChar(0x00BE)},
            {QStringLiteral("dagger"), QChar(0x2020)},
            {QStringLiteral("permil"), QChar(0x2030)},
            // Latin-1 补充常见重音字符
            {QStringLiteral("agrave"), QChar(0x00E0)},
            {QStringLiteral("aacute"), QChar(0x00E1)},
            {QStringLiteral("acirc"), QChar(0x00E2)},
            {QStringLiteral("atilde"), QChar(0x00E3)},
            {QStringLiteral("auml"), QChar(0x00E4)},
            {QStringLiteral("aring"), QChar(0x00E5)},
            {QStringLiteral("ccedil"), QChar(0x00E7)},
            {QStringLiteral("egrave"), QChar(0x00E8)},
            {QStringLiteral("eacute"), QChar(0x00E9)},
            {QStringLiteral("ecirc"), QChar(0x00EA)},
            {QStringLiteral("euml"), QChar(0x00EB)},
            {QStringLiteral("igrave"), QChar(0x00EC)},
            {QStringLiteral("iacute"), QChar(0x00ED)},
            {QStringLiteral("icirc"), QChar(0x00EE)},
            {QStringLiteral("iuml"), QChar(0x00EF)},
            {QStringLiteral("ntilde"), QChar(0x00F1)},
            {QStringLiteral("ograve"), QChar(0x00F2)},
            {QStringLiteral("oacute"), QChar(0x00F3)},
            {QStringLiteral("ocirc"), QChar(0x00F4)},
            {QStringLiteral("otilde"), QChar(0x00F5)},
            {QStringLiteral("ouml"), QChar(0x00F6)},
            {QStringLiteral("ugrave"), QChar(0x00F9)},
            {QStringLiteral("uacute"), QChar(0x00FA)},
            {QStringLiteral("ucirc"), QChar(0x00FB)},
            {QStringLiteral("uuml"), QChar(0x00FC)},
            {QStringLiteral("yacute"), QChar(0x00FD)},
            {QStringLiteral("yuml"), QChar(0x00FF)},
        };
        const auto it = kEntities.constFind(name);
        return it != kEntities.constEnd() ? QString(it.value()) : QString();
    }
};

} // namespace

// ---- EpubParser ----

QByteArray EpubParser::readZipEntry(const QString &zipPath, const QString &entry) const {
    unzFile zip = unzOpen64(zipPath.toUtf8().constData());
    if (!zip) return {};
    QByteArray out;
    // 先精确匹配，再大小写不敏感兜底（真实书条目名大小写偶有出入）
    int rc = unzLocateFile(zip, entry.toUtf8().constData(), 1);
    if (rc != UNZ_OK) rc = unzLocateFile(zip, entry.toUtf8().constData(), 2);
    if (rc == UNZ_OK) {
        if (unzOpenCurrentFile(zip) == UNZ_OK) {
            char buf[4096];
            int n;
            while ((n = unzReadCurrentFile(zip, buf, sizeof(buf))) > 0) {
                out.append(buf, n);
                if (out.size() > kMaxZipEntrySize) {
                    qWarning("EpubParser: 条目 %s 超过 %lld MB，跳过",
                             qUtf8Printable(entry),
                             static_cast<long long>(kMaxZipEntrySize / (1024 * 1024)));
                    out.clear();
                    break;
                }
            }
            unzCloseCurrentFile(zip);
        }
    }
    unzClose(zip);
    return out;
}

QString EpubParser::normalizeXhtml(const QByteArray &xhtml, QString *title) const {
    QString html;
    HtmlEntityResolver resolver;
    QXmlStreamReader r(xhtml);
    r.setEntityResolver(&resolver);
    bool inBody = false;
    const auto keepOpen = [](const QString &tag) {
        return tag == QLatin1String("p") || tag == QLatin1String("h1")
            || tag == QLatin1String("h2") || tag == QLatin1String("h3")
            || tag == QLatin1String("b") || tag == QLatin1String("i")
            || tag == QLatin1String("em") || tag == QLatin1String("strong")
            || tag == QLatin1String("li") || tag == QLatin1String("ul")
            || tag == QLatin1String("ol");
    };
    const auto keepClose = [&](const QString &tag) {
        return keepOpen(tag) && tag != QLatin1String("img");
    };
    while (!r.atEnd()) {
        r.readNext();
        if (r.isStartElement()) {
            const QString tag = r.name().toString();
            // <head><title> 在 body 之前出现，须在 inBody 判断前捕获
            if (tag == QLatin1String("title") && title && title->isEmpty()) {
                *title = r.readElementText();
                continue;
            }
            if (tag == QLatin1String("body")) { inBody = true; continue; }
            if (!inBody) continue;
            if (keepOpen(tag)) {
                html += '<' + tag + '>';
            } else if (tag == QLatin1String("img")) {
                // 保留 src（属性值已被 XML 解码），供段落拆分时提取
                const QString src = r.attributes().value("src").toString();
                html += QStringLiteral("<img src=\"") + src.toHtmlEscaped() + "\">";
            }
        } else if (r.isEndElement()) {
            const QString tag = r.name().toString();
            if (tag == QLatin1String("body")) { inBody = false; continue; }
            if (keepClose(tag)) html += "</" + tag + '>';
        } else if (r.isCharacters() && inBody) {
            html += r.text().toString().toHtmlEscaped();
        }
    }
    if (r.hasError()) {
        qWarning("EpubParser: XHTML 解析错误（第 %lld 字符处中断，已解析部分保留）: %s",
                 static_cast<long long>(r.characterOffset()),
                 qUtf8Printable(r.errorString()));
    }
    return html;
}

QString EpubParser::extractImage(const QString &zipPath, const QString &entry,
                                 const QDir &dir, QHash<QString, QString> *cache) const {
    const auto it = cache->constFind(entry);
    if (it != cache->constEnd())
        return it.value();
    const QByteArray data = readZipEntry(zipPath, entry);
    if (data.isEmpty())
        return {};
    QString name = entry.mid(entry.lastIndexOf('/') + 1);
    if (name.isEmpty()) name = QStringLiteral("img");
    if (dir.exists(name)) {
        // 与其他条目同名冲突（不同目录同名图片）：加条目路径 md5 前缀，确定性命名
        const QString digest = QString::fromLatin1(
            QCryptographicHash::hash(entry.toUtf8(), QCryptographicHash::Md5)
                .toHex().left(8));
        name = digest + QLatin1Char('_') + name;
    }
    QFile f(dir.filePath(name));
    if (!f.open(QIODevice::WriteOnly)) {
        qWarning("EpubParser: 写入图片缓存失败 %s", qUtf8Printable(dir.filePath(name)));
        return {};
    }
    f.write(data);
    f.close();
    const QString path = dir.filePath(name);
    cache->insert(entry, path);
    return path;
}

// 把一章的归一化 html 切成段落；<img src> 从 zip 解出并写入本地缓存，
// imagePath 指向解出文件，html 内 img 的 src 一并替换为本地路径。
void EpubParser::splitParagraphs(const QString &html, const QString &zipPath,
                                 const QString &chapterEntry, const QDir &imgDir,
                                 QHash<QString, QString> *imgCache,
                                 QVector<Paragraph> *out) const {
    Paragraph cur;
    bool inBlock = false; // 处于 <p>/<h*>/<li> 之内
    static const QRegularExpression tagRe("<(/)?([a-z0-9]+)([^>]*)>");
    QRegularExpressionMatchIterator it = tagRe.globalMatch(html);
    int pos = 0;
    const auto flush = [&]() {
        // 标题段与 TextParser 一致：html 带 <hN> 包裹
        if (cur.level > 0 && !cur.html.isEmpty()) {
            const QString lvl = QString::number(cur.level);
            cur.html = "<h" + lvl + '>' + cur.html + "</h" + lvl + '>';
        }
        if (!isEmptyParagraph(cur)) out->append(cur);
        cur = Paragraph();
        inBlock = false;
    };
    while (it.hasNext()) {
        const QRegularExpressionMatch m = it.next();
        const QString text = html.mid(pos, m.capturedStart() - pos); // 标签间文本（已转义）
        pos = m.capturedEnd();
        const bool closing = !m.captured(1).isEmpty();
        const QString tag = m.captured(2);
        if (!text.isEmpty() && inBlock) {
            cur.html += text;
            cur.text += decodeEntities(text);
        }
        if (closing) {
            if (tag == "p" || tag == "h1" || tag == "h2" || tag == "h3" || tag == "li")
                flush();
            // b/i/em/strong 等内联闭合标签保留在 html 中
            else if (inBlock && (tag == "b" || tag == "i" || tag == "em" || tag == "strong"))
                cur.html += "</" + tag + '>';
            continue;
        }
        if (tag == "p" || tag == "h1" || tag == "h2" || tag == "h3" || tag == "li") {
            flush(); // 上一个块结束，新块开始
            cur.level = tag.startsWith('h') ? tag.mid(1).toInt() : 0;
            inBlock = true;
            continue;
        }
        if (tag == "img") {
            static const QRegularExpression srcRe("src=\"([^\"]*)\"");
            const QRegularExpressionMatch sm = srcRe.match(m.captured(3));
            if (!sm.hasMatch()) continue;
            // normalize 时 src 被 toHtmlEscaped 二次转义，先还原再解析条目
            const QString entry = resolveEntry(decodeEntities(sm.captured(1)), chapterEntry);
            if (entry.isEmpty()) {
                qWarning("EpubParser: 无法解析图片引用 %s", qUtf8Printable(sm.captured(1)));
                continue;
            }
            const QString local = extractImage(zipPath, entry, imgDir, imgCache);
            if (local.isEmpty()) {
                qWarning("EpubParser: 图片解出失败 %s（zip 内无此条目）", qUtf8Printable(entry));
                continue;
            }
            if (!inBlock) flush(); // 块外图片自成段落
            cur.imagePath = local;
            cur.html += QStringLiteral("<img src=\"") + local.toHtmlEscaped() + "\">";
            continue;
        }
        // 内联保留标签（b/i/em/strong）；ul/ol 块标签在段落层丢弃（li 已自成段落）
        if (inBlock && (tag == "b" || tag == "i" || tag == "em" || tag == "strong"))
            cur.html += '<' + tag + '>';
    }
    if (pos < html.size()) {
        const QString tail = html.mid(pos);
        if (!tail.isEmpty() && inBlock) {
            cur.html += tail;
            cur.text += decodeEntities(tail);
        }
    }
    flush();
}

DocumentModel EpubParser::parse(const QString &epubPath) {
    DocumentModel m;
    if (!QFileInfo::exists(epubPath)) return m;
    // 1) container.xml → rootfile 路径
    const QByteArray container = readZipEntry(epubPath, "META-INF/container.xml");
    if (container.isEmpty()) {
        qWarning("EpubParser: %s 中缺少 META-INF/container.xml", qUtf8Printable(epubPath));
        return m;
    }
    const QString opfEntry = containerRootfile(container);
    if (opfEntry.isEmpty()) return m;
    // 2) content.opf → 元数据 / manifest / spine
    const QByteArray opf = readZipEntry(epubPath, opfEntry);
    if (opf.isEmpty()) return m;
    OpfInfo info;
    if (!parseOpf(opf, &info)) {
        qWarning("EpubParser: %s 的 OPF 缺少 spine", qUtf8Printable(opfEntry));
        return m;
    }
    m.title = info.title;
    m.author = info.author;
    if (m.title.isEmpty()) m.title = QFileInfo(epubPath).completeBaseName();
    // 3) 按 spine 顺序逐章解析；图片缓存目录按书唯一（epub 路径 md5）
    const QDir imgDir(QDir::temp().filePath(QStringLiteral("Readdict-") + QString::fromLatin1(
        QCryptographicHash::hash(epubPath.toUtf8(), QCryptographicHash::Md5)
            .toHex().left(16))));
    imgDir.mkpath(".");
    QHash<QString, QString> imgCache;
    int chapterNo = 0;
    for (const QString &idref : std::as_const(info.spineIds)) {
        const auto it = info.itemById.constFind(idref);
        if (it == info.itemById.constEnd()) {
            qWarning("EpubParser: spine 引用未在 manifest 中 %s", qUtf8Printable(idref));
            continue;
        }
        const QString mediaType = it.value().second;
        if (mediaType.startsWith("image/") || mediaType == "application/x-dtbncx+xml")
            continue; // 封面图片/NCX 等非内容条目
        const QString entry = resolveEntry(it.value().first, opfEntry);
        if (entry.isEmpty()) continue;
        const QByteArray xhtml = readZipEntry(epubPath, entry);
        if (xhtml.isEmpty()) {
            qWarning("EpubParser: 章节文件缺失 %s", qUtf8Printable(entry));
            continue;
        }
        QString chTitle;
        const QString html = normalizeXhtml(xhtml, &chTitle);
        if (chTitle.isEmpty()) chTitle = firstHeading(html);
        if (chTitle.isEmpty()) chTitle = QStringLiteral("第%1章").arg(chapterNo + 1);
        Chapter ch;
        ch.title = chTitle;
        splitParagraphs(html, epubPath, entry, imgDir, &imgCache, &ch.paragraphs);
        if (ch.paragraphs.isEmpty()) continue; // 封面等空章节跳过
        m.chapters.append(ch);
        ++chapterNo;
    }
    // 4) 每段预分句
    for (Chapter &c : m.chapters)
        for (Paragraph &p : c.paragraphs)
            p.sentences = SentenceSplitter::split(p.text);
    return m;
}
