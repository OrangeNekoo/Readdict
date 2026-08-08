// Fb2Parser.cpp — FB2 解析器
// FB2（FictionBook 2.0）是单个 XML 文件：description（元数据）+ body（正文）
// + binary（图片 base64）。QXmlStreamReader 前向流式，且 <image> 可能在
// <binary> 之前被引用，故对同一份字节做两遍解析：第一遍收元数据与 binary，
// 第二遍按 section 分章。
// 标签/属性一律按本地名匹配（r.name()/a.name() 不含命名空间前缀），
// 兼容 <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
// 与 <image l:href>（xlink 前缀）等写法。
#include "Fb2Parser.h"
#include "SentenceSplitter.h"

#include <QByteArray>
#include <QCryptographicHash>
#include <QFile>
#include <QFileInfo>
#include <QXmlStreamReader>
#include <QXmlStreamAttributes>

namespace {

// 空段落（无文本且无图片）不进入章节（与 EpubParser 一致）
bool isEmptyParagraph(const Paragraph &p) {
    return p.imagePath.isEmpty() && p.text.trimmed().isEmpty();
}

// 单条 binary 上限（base64 原文大小；解码后约 3/4。与 EpubParser 的 zip 条目
// 上限同取舍，防恶意/损坏文件撑爆内存）
constexpr qint64 kMaxBinarySize = 64LL * 1024 * 1024;

// 段落内保留的内联标签（其余元素忽略标签、字符文本照收）
bool isInlineTag(const QString &tag) {
    return tag == QLatin1String("b") || tag == QLatin1String("i")
        || tag == QLatin1String("strong") || tag == QLatin1String("em");
}

// binary content-type → 解出图片文件的扩展名（未知类型不补扩展名）
QString extensionForType(const QString &contentType) {
    if (contentType == QLatin1String("image/png")) return QStringLiteral(".png");
    if (contentType == QLatin1String("image/jpeg")) return QStringLiteral(".jpg");
    if (contentType == QLatin1String("image/gif")) return QStringLiteral(".gif");
    if (contentType == QLatin1String("image/svg+xml")) return QStringLiteral(".svg");
    return QString();
}

} // namespace

DocumentModel Fb2Parser::parse(const QString &fb2Path) {
    DocumentModel m;
    m_error.clear();
    m_binaries.clear();
    m_binaryTypes.clear();
    m_imgNames.clear();
    QFile f(fb2Path);
    if (!f.open(QIODevice::ReadOnly)) {
        m_error = QStringLiteral("文件无法打开: %1").arg(fb2Path);
        return m;
    }
    const QByteArray data = f.readAll();
    if (data.isEmpty()) return m;

    // 第一遍：元数据 + binary（图片 base64）。同时是整份文档的良构校验：
    // QXmlStreamReader 对错配结束标签等错误会以"幻影"结束标签形式放行当前
    // 消费循环、随后置 hasError，故此处一旦有错直接返回空模型（正文遍只在
    // 良构文档上运行）
    QXmlStreamReader meta(data);
    while (!meta.atEnd() && !meta.hasError()) {
        meta.readNext();
        if (!meta.isStartElement()) continue;
        const QString tag = meta.name().toString();
        if (tag == QLatin1String("description")) {
            readMetadata(meta, &m);
        } else if (tag == QLatin1String("binary")) {
            const QString id = meta.attributes().value("id").toString();
            if (!id.isEmpty()) {
                // content-type 用于给解出的图片文件补扩展名
                m_binaryTypes.insert(id,
                    meta.attributes().value("content-type").toString());
                const QByteArray b64 = meta.readElementText().toUtf8();
                if (!b64.isEmpty() && b64.size() <= kMaxBinarySize)
                    m_binaries.insert(id, b64);
                else if (b64.size() > kMaxBinarySize)
                    qWarning("Fb2Parser: binary %s 超过大小上限，跳过",
                             qUtf8Printable(id));
            }
        }
    }
    if (meta.hasError()) {
        qWarning("Fb2Parser: %s 的 XML 解析失败：%s",
                 qUtf8Printable(fb2Path), qUtf8Printable(meta.errorString()));
        m_error = QStringLiteral("FB2 XML 解析失败：%1").arg(meta.errorString());
        // 出错必须返回完全空的模型：DocumentModel::empty() 只查 chapters，
        // 若此时 title/author 已填充会与"出错返回空模型"语义矛盾
        return DocumentModel{};
    }
    if (m.title.isEmpty()) m.title = QFileInfo(fb2Path).completeBaseName();

    // 第二遍：正文（只取第一个 body——主正文；notes 等附属 body 跳过）
    QXmlStreamReader body(data);
    while (!body.atEnd() && !body.hasError()) {
        body.readNext();
        if (!body.isStartElement() || body.name() != QLatin1String("body"))
            continue;
        m_imgDir = QDir(QDir::temp().filePath(QStringLiteral("Readdict-")
            + QString::fromLatin1(QCryptographicHash::hash(
                fb2Path.toUtf8(), QCryptographicHash::Md5).toHex().left(16))));
        m_imgDir.mkpath(".");
        while (!body.atEnd() && (body.readNext() != QXmlStreamReader::EndElement
               || body.name() != QLatin1String("body"))) {
            if (body.isStartElement() && body.name() == QLatin1String("section")) {
                Chapter ch;
                parseSection(body, ch);
                if (!ch.paragraphs.isEmpty()) m.chapters.append(ch);
            }
        }
        break;
    }

    // 每段预分句（与 TextParser/EpubParser 一致）
    for (Chapter &c : m.chapters)
        for (Paragraph &p : c.paragraphs)
            p.sentences = SentenceSplitter::split(p.text);
    return m;
}

void Fb2Parser::readMetadata(QXmlStreamReader &r, DocumentModel *m) {
    // 位于 <description> 起始；消费到 </description>
    while (!r.atEnd() && (r.readNext() != QXmlStreamReader::EndElement
           || r.name() != QLatin1String("description"))) {
        if (!r.isStartElement()) continue;
        const QString tag = r.name().toString();
        if (tag == QLatin1String("title-info")) {
            while (!r.atEnd() && (r.readNext() != QXmlStreamReader::EndElement
                   || r.name() != QLatin1String("title-info"))) {
                if (!r.isStartElement()) continue;
                const QString t = r.name().toString();
                if (t == QLatin1String("book-title") && m->title.isEmpty())
                    m->title = r.readElementText().trimmed();
                else if (t == QLatin1String("author") && m->author.isEmpty())
                    m->author = readAuthor(r);
                else
                    skipElement(r);
            }
        } else {
            skipElement(r);
        }
    }
}

QString Fb2Parser::readAuthor(QXmlStreamReader &r) {
    // 位于 <author> 起始；消费到 </author>。拼接顺序 first+middle+last
    // （与 EpubParser fixture 的 "作者甲" 约定一致，无分隔符）
    QString first, middle, last;
    while (!r.atEnd() && (r.readNext() != QXmlStreamReader::EndElement
           || r.name() != QLatin1String("author"))) {
        if (!r.isStartElement()) continue;
        const QString tag = r.name().toString();
        if (tag == QLatin1String("first-name"))
            first = r.readElementText().trimmed();
        else if (tag == QLatin1String("middle-name"))
            middle = r.readElementText().trimmed();
        else if (tag == QLatin1String("last-name"))
            last = r.readElementText().trimmed();
        else
            skipElement(r);
    }
    return first + middle + last;
}

void Fb2Parser::parseSection(QXmlStreamReader &r, Chapter &ch) {
    // 位于 <section> 起始；消费到 </section>。嵌套 <section> 递归并入本章，
    // 其标题作为 level=1 标题段落（html 带 <h1> 包裹，与 EpubParser 的
    // flush 一致）；首个 section 标题只进 Chapter.title。
    bool haveTitle = false;
    while (!r.atEnd() && (r.readNext() != QXmlStreamReader::EndElement
           || r.name() != QLatin1String("section"))) {
        if (!r.isStartElement()) continue;
        const QString tag = r.name().toString();
        if (tag == QLatin1String("title")) {
            const QString t = readTitleText(r);
            if (!haveTitle && ch.title.isEmpty()) {
                ch.title = t;
                haveTitle = true;
            } else if (!t.isEmpty()) {
                Paragraph h;
                h.text = t;
                h.level = 1;
                h.html = QStringLiteral("<h1>") + t.toHtmlEscaped()
                       + QStringLiteral("</h1>");
                ch.paragraphs.append(h);
            }
        } else if (tag == QLatin1String("section")) {
            parseSection(r, ch);
        } else if (tag == QLatin1String("p")) {
            Paragraph p;
            parseParagraph(r, p);
            if (!isEmptyParagraph(p)) ch.paragraphs.append(p);
        } else {
            skipElement(r);
        }
    }
}

QString Fb2Parser::readTitleText(QXmlStreamReader &r) {
    // 位于 <title> 起始；消费到 </title>。收集所有字符数据（含 <p> 与内联
    // 标签内文本），空白归一化后作为章标题
    QString text;
    while (!r.atEnd() && (r.readNext() != QXmlStreamReader::EndElement
           || r.name() != QLatin1String("title"))) {
        if (r.isCharacters()) text += r.text();
    }
    return text.simplified();
}

void Fb2Parser::parseParagraph(QXmlStreamReader &r, Paragraph &p) {
    // 位于 <p> 起始；消费到 </p>。Characters 双写：text 收原文、html 收转义；
    // 内联标签（b/i/strong/em）原样保留在 html；<image> 解出图片；
    // 其余元素忽略标签本身，其字符数据由循环继续收集（文本不丢）
    while (!r.atEnd() && (r.readNext() != QXmlStreamReader::EndElement
           || r.name() != QLatin1String("p"))) {
        if (r.isCharacters()) {
            const QString t = r.text().toString();
            p.text += t;
            p.html += t.toHtmlEscaped();
        } else if (r.isStartElement()) {
            const QString tag = r.name().toString();
            if (tag == QLatin1String("image")) {
                // 属性按本地名匹配：<image l:href="#id"/>（xlink 前缀）
                QString href;
                const QXmlStreamAttributes attrs = r.attributes();
                for (const QXmlStreamAttribute &a : attrs) {
                    if (a.name() == QLatin1String("href")) {
                        href = a.value().toString();
                        break;
                    }
                }
                if (!href.startsWith(QLatin1Char('#'))) {
                    qWarning("Fb2Parser: 图片引用非 #id 形式 %s，跳过",
                             qUtf8Printable(href));
                    continue;
                }
                const QString id = href.mid(1);
                // 防路径穿越：binary id 直接用作缓存文件名，QDir::filePath 不
                // 去除 .. 与路径分隔符，恶意 id（如 "../../evil"）会把 base64
                // 写到缓存目录之外。拒绝含 /、\、.. 的 id，整体跳过该图片
                if (id.isEmpty() || id.contains(QLatin1Char('/'))
                    || id.contains(QLatin1Char('\\'))
                    || id.contains(QStringLiteral(".."))) {
                    qWarning("Fb2Parser: 非法图片引用 #%s，跳过", qUtf8Printable(id));
                    continue;
                }
                const auto it = m_binaries.constFind(id);
                if (it == m_binaries.constEnd()) {
                    qWarning("Fb2Parser: 图片引用无对应 binary #%s",
                             qUtf8Printable(id));
                    continue;
                }
                const QByteArray imgData = QByteArray::fromBase64(it.value());
                if (imgData.isEmpty()) {
                    qWarning("Fb2Parser: binary #%s base64 解码为空", qUtf8Printable(id));
                    continue;
                }
                // 命名依赖 binary id + content-type 扩展名（同名冲突加 id md5
                // 前缀），与解析次序无关，保证多次解析同一书得到相同文件名；
                // 已存在的文件直接复用
                QString name = id;
                const auto t = m_binaryTypes.constFind(id);
                if (t != m_binaryTypes.constEnd())
                    name += extensionForType(t.value());
                if (name.isEmpty()) name = QStringLiteral("img");
                if (m_imgNames.contains(name)) {
                    const QString digest = QString::fromLatin1(
                        QCryptographicHash::hash(id.toUtf8(), QCryptographicHash::Md5)
                            .toHex().left(8));
                    name = digest + QLatin1Char('_') + name;
                } else {
                    m_imgNames.insert(name);
                }
                const QString local = m_imgDir.filePath(name);
                if (!QFile::exists(local)) {
                    QFile out(local);
                    if (!out.open(QIODevice::WriteOnly)) {
                        qWarning("Fb2Parser: 写入图片缓存失败 %s", qUtf8Printable(local));
                        continue;
                    }
                    out.write(imgData);
                    out.close();
                }
                p.imagePath = local;
                p.html += QStringLiteral("<img src=\"") + local.toHtmlEscaped()
                        + QStringLiteral("\">");
            } else if (isInlineTag(tag)) {
                p.html += '<' + tag + '>';
            }
            // 其余元素：忽略标签，字符文本由后续 Characters 收集
        } else if (r.isEndElement()) {
            // p 的结束标签已被循环条件消费，此处只可能是内联标签闭合
            const QString tag = r.name().toString();
            if (isInlineTag(tag)) p.html += QStringLiteral("</") + tag + '>';
        }
    }
}

void Fb2Parser::skipElement(QXmlStreamReader &r) {
    // 位于某起始元素；消费到其匹配结束标签（含嵌套元素）
    int depth = 1;
    while (depth > 0 && !r.atEnd()) {
        r.readNext();
        if (r.isStartElement()) ++depth;
        else if (r.isEndElement()) --depth;
    }
}
