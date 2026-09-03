// MobiParser.cpp — MOBI/AZW3 解析器（libmobi）
// 实际 libmobi API（vendored 0.8.x，与任务简报的函数名不同）：
//   - mobi_init() / mobi_free(m)                 —— 无 mobi_decode_outbuffer，
//     解压在 mobi_parse_rawml 内部（mobi_get_rawml → mobi_decompress_content）
//   - mobi_load_filename(m, path)                —— 返回 MOBI_RET；无
//     mobi_get_last_error()，错误码自行映射（MOBI_FILE_NOT_FOUND 等）
//   - mobi_is_encrypted(m)                       —— rh->encryption_type 1/2 判定
//   - mobi_meta_get_title/author(m)              —— EXTH 标题/作者
//   - mobi_init_rawml(m) / mobi_parse_rawml(rawml, m) / mobi_free_rawml()
//     —— 重建 rawml->markup（HTML 链表）/ rawml->resources（图片等）；KF8 自动
//     识别（use_kf8 默认），KF7/KF8 走同一流程
//   - 无 mobi_markup_get_* 迭代器：直接遍历 MOBIPart 链表
//   - 图片引用：libmobi 重建 HTML 时把 recindex/kindle:embed 链接重写为
//     src="resource%05u.ext"（u = 资源 part->uid），故按同名落盘即可映射
#include "MobiParser.h"
#include "SentenceSplitter.h"

#include <mobi.h>

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QCryptographicHash>
#include <QRegularExpression>

namespace {

// 空段落（无文本且无图片）不进入章节（与 EpubParser/Fb2Parser 一致）
bool isEmptyParagraph(const Paragraph &p) {
    return p.imagePath.isEmpty() && p.text.trimmed().isEmpty();
}

// 解码 MOBI HTML 常见实体：toHtmlEscaped 的 5 个 + 常用排版实体 + 数值实体。
// 未知实体保留字面（保证正文不截断，同 EpubParser 取舍）。
QString decodeEntities(QString s) {
    s.replace(QStringLiteral("&lt;"), QStringLiteral("<"))
     .replace(QStringLiteral("&gt;"), QStringLiteral(">"))
     .replace(QStringLiteral("&quot;"), QStringLiteral("\""))
     .replace(QStringLiteral("&#39;"), QStringLiteral("'"))
     .replace(QStringLiteral("&nbsp;"), QStringLiteral(" "))
     .replace(QStringLiteral("&mdash;"), QStringLiteral("—"))
     .replace(QStringLiteral("&ndash;"), QStringLiteral("–"))
     .replace(QStringLiteral("&hellip;"), QStringLiteral("…"))
     .replace(QStringLiteral("&lsquo;"), QStringLiteral("‘"))
     .replace(QStringLiteral("&rsquo;"), QStringLiteral("’"))
     .replace(QStringLiteral("&ldquo;"), QStringLiteral("“"))
     .replace(QStringLiteral("&rdquo;"), QStringLiteral("”"))
     .replace(QStringLiteral("&laquo;"), QStringLiteral("«"))
     .replace(QStringLiteral("&raquo;"), QStringLiteral("»"))
     .replace(QStringLiteral("&copy;"), QStringLiteral("©"))
     .replace(QStringLiteral("&reg;"), QStringLiteral("®"))
     .replace(QStringLiteral("&trade;"), QStringLiteral("™"))
     .replace(QStringLiteral("&bull;"), QStringLiteral("•"))
     .replace(QStringLiteral("&amp;"), QStringLiteral("&"));
    static const QRegularExpression numRe(QStringLiteral("&#(x[0-9a-fA-F]+|[0-9]+);"));
    int searchFrom = 0;
    QRegularExpressionMatch m;
    while ((m = numRe.match(s, searchFrom)).hasMatch()) {
        const QString digits = m.captured(1);
        bool ok = false;
        const char32_t cp = digits.startsWith(QLatin1Char('x'))
            ? char32_t(digits.mid(1).toUInt(&ok, 16))
            : char32_t(digits.toUInt(&ok, 10));
        if (ok && cp <= 0x10FFFF) {
            s.replace(m.capturedStart(), m.capturedLength(),
                      QString::fromUcs4(&cp, 1));
            searchFrom = m.capturedStart() + 1;
        } else {
            searchFrom = m.capturedEnd(); // 非法数值实体保留字面
        }
    }
    return s;
}

// libmobi 资源类型 → 文件扩展名（仅图片；字体/音频/OPF/NCX 不导出）
QString extensionForType(MOBIFiletype type) {
    switch (type) {
    case T_JPG: return QStringLiteral("jpg");
    case T_GIF: return QStringLiteral("gif");
    case T_PNG: return QStringLiteral("png");
    case T_BMP: return QStringLiteral("bmp");
    default: return {};
    }
}

// MOBI_RET → 中文错误（libmobi 无错误字符串导出，自行映射）
QString mobiErrorMessage(MOBI_RET ret) {
    switch (ret) {
    case MOBI_FILE_NOT_FOUND: return QStringLiteral("文件不存在");
    case MOBI_FILE_ENCRYPTED: return QStringLiteral("该文件受 DRM 保护（已加密），无法解析");
    case MOBI_FILE_UNSUPPORTED: return QStringLiteral("不是受支持的 MOBI/AZW3 文件");
    case MOBI_DATA_CORRUPT: return QStringLiteral("MOBI 文件数据损坏");
    case MOBI_PARAM_ERR: return QStringLiteral("MOBI 文件参数错误");
    case MOBI_MALLOC_FAILED: return QStringLiteral("内存分配失败");
    case MOBI_INIT_FAILED: return QStringLiteral("MOBI 初始化失败");
    default:
        return QStringLiteral("MOBI 解析失败（libmobi 错误码 %1）").arg(int(ret));
    }
}

bool isBlockTag(const QString &tag) {
    return tag == QLatin1String("p") || tag == QLatin1String("li")
        || tag == QLatin1String("div")
        || (tag.size() == 2 && tag.at(0) == QLatin1Char('h')
            && tag.at(1) >= QLatin1Char('1') && tag.at(1) <= QLatin1Char('6'));
}

bool isHeadingTag(const QString &tag) {
    return tag.size() == 2 && tag.at(0) == QLatin1Char('h')
        && tag.at(1) >= QLatin1Char('1') && tag.at(1) <= QLatin1Char('6');
}

// 段落内保留的内联标签（其余元素忽略标签、字符文本照收）
bool isInlineTag(const QString &tag) {
    return tag == QLatin1String("b") || tag == QLatin1String("i")
        || tag == QLatin1String("em") || tag == QLatin1String("strong");
}

} // namespace

DocumentModel MobiParser::parse(const QString &mobiPath) {
    DocumentModel model;
    m_error.clear();
    if (!QFileInfo::exists(mobiPath)) {
        m_error = QStringLiteral("文件不存在: %1").arg(mobiPath);
        return model;
    }

    MOBIData *m = mobi_init();
    if (m == nullptr) {
        m_error = QStringLiteral("内存分配失败");
        return model;
    }
    const MOBI_RET loadRet = mobi_load_filename(m, mobiPath.toLocal8Bit().constData());
    // 加密优先判定：libmobi 对部分异常文件也可能加载成功，但 rh 已带
    // encryption_type；零字节/垃圾文件则走 loadRet 错误分支
    if (loadRet != MOBI_SUCCESS || mobi_is_encrypted(m)) {
        m_error = mobi_is_encrypted(m)
            ? QStringLiteral("该文件受 DRM 保护（已加密），无法解析")
            : mobiErrorMessage(loadRet);
        mobi_free(m);
        return model;
    }
    if (!mobi_is_mobipocket(m)) {
        m_error = QStringLiteral("不是受支持的 MOBI/AZW3 文件");
        mobi_free(m);
        return model;
    }

    char *titleC = mobi_meta_get_title(m);
    char *authorC = mobi_meta_get_author(m);
    char *publisherC = mobi_meta_get_publisher(m);
    model.title = titleC ? QString::fromUtf8(titleC) : QString();
    model.author = authorC ? QString::fromUtf8(authorC) : QString();
    model.publisher = publisherC ? QString::fromUtf8(publisherC) : QString();
    free(titleC);
    free(authorC);
    free(publisherC);
    if (model.title.isEmpty())
        model.title = QFileInfo(mobiPath).completeBaseName();

    MOBIRawml *rawml = mobi_init_rawml(m);
    if (rawml == nullptr) {
        m_error = QStringLiteral("MOBI rawml 初始化失败");
        mobi_free(m);
        return model;
    }
    const MOBI_RET parseRet = mobi_parse_rawml(rawml, m);
    if (parseRet != MOBI_SUCCESS) {
        m_error = mobiErrorMessage(parseRet);
        mobi_free_rawml(rawml);
        mobi_free(m);
        return model;
    }

    // 图片缓存目录按书唯一（与 EpubParser/Fb2Parser 同模式）；libmobi 重建
    // HTML 时图片引用已重写为 src="resourceNNNNN.ext"，按 uid 落盘即可对上
    const QDir imgDir(QDir::temp().filePath(QStringLiteral("Readdict-mobi-")
        + QString::fromLatin1(QCryptographicHash::hash(
            mobiPath.toUtf8(), QCryptographicHash::Md5).toHex().left(16))));
    imgDir.mkpath(".");
    QHash<quint64, const MOBIPart *> resByUid;
    for (const MOBIPart *part = rawml->resources; part; part = part->next)
        resByUid.insert(part->uid, part);

    // ---- 章节/段落切分状态机（对拼接后的 markup HTML 单遍扫描） ----
    QVector<Chapter> chapters;
    Chapter curChapter;
    Paragraph curPara;
    bool inBlock = false;
    QHash<QString, QString> imgCache; // "resourceNNNNN.ext" → 本地路径

    const auto wrapAndAppendPara = [&]() {
        // 标题段与 TextParser 一致：html 带 <hN> 包裹
        if (curPara.level > 0 && !curPara.html.isEmpty()) {
            const QString lvl = QString::number(curPara.level);
            curPara.html = "<h" + lvl + '>' + curPara.html + "</h" + lvl + '>';
        }
        if (!isEmptyParagraph(curPara))
            curChapter.paragraphs.append(curPara);
        curPara = Paragraph();
        inBlock = false;
    };
    const auto closeChapter = [&]() {
        if (curChapter.paragraphs.isEmpty() && curChapter.title.isEmpty())
            return; // 空章（文件头、连续标题等）不产出
        if (curChapter.title.isEmpty())
            curChapter.title = QStringLiteral("第%1章").arg(chapters.size() + 1);
        chapters.append(curChapter);
        curChapter = Chapter();
    };

    static const QRegularExpression tagRe(QStringLiteral("<(/)?([a-zA-Z0-9:]+)([^>]*)>"));
    static const QRegularExpression srcRe(QStringLiteral("src=[\"']?([^\"'\\s>]+)"));
    static const QRegularExpression resNameRe(QStringLiteral("^resource(\\d+)\\."));

    bool sawHtml = false; // 是否处理过任何 HTML part（Print Replica 等为 T_PDF/T_BREAK）
    for (const MOBIPart *part = rawml->markup; part; part = part->next) {
        if (part->type != T_HTML || part->data == nullptr || part->size == 0)
            continue;
        sawHtml = true;
        const QString html = QString::fromUtf8(
            reinterpret_cast<const char *>(part->data), int(part->size));
        QRegularExpressionMatchIterator it = tagRe.globalMatch(html);
        int pos = 0;
        while (it.hasNext()) {
            const QRegularExpressionMatch match = it.next();
            const QString text = html.mid(pos, match.capturedStart() - pos);
            pos = match.capturedEnd();
            const bool closing = !match.captured(1).isEmpty();
            const QString tag = match.captured(2).toLower();
            if (!text.isEmpty() && inBlock) {
                curPara.html += text;
                curPara.text += decodeEntities(text);
            }
            if (closing) {
                if (isBlockTag(tag)) {
                    if (isHeadingTag(tag) && curPara.level <= 2) {
                        // h1/h2 闭合：收尾旧章，标题段作为新章首段
                        const QString headingText = curPara.text.trimmed();
                        closeChapter();
                        curChapter.title = headingText;
                        wrapAndAppendPara();
                    } else {
                        wrapAndAppendPara();
                    }
                } else if (inBlock && isInlineTag(tag)) {
                    curPara.html += "</" + tag + '>';
                }
                continue;
            }
            if (isBlockTag(tag)) {
                wrapAndAppendPara(); // 上一个块结束，新块开始
                curPara.level = isHeadingTag(tag) ? tag.at(1).digitValue() : 0;
                inBlock = true;
                continue;
            }
            if (tag == QLatin1String("img")) {
                const QRegularExpressionMatch sm = srcRe.match(match.captured(3));
                if (sm.hasMatch()) {
                    const QString src = decodeEntities(sm.captured(1));
                    QString local = imgCache.value(src);
                    if (local.isEmpty() && !imgCache.contains(src)) {
                        // 把 resourceNNNNN.ext 映射到 resources 链表里的 part
                        const QRegularExpressionMatch rm = resNameRe.match(src);
                        if (rm.hasMatch()) {
                            const auto rp = resByUid.constFind(rm.captured(1).toULongLong());
                            if (rp != resByUid.constEnd()) {
                                const QString ext = extensionForType(rp.value()->type);
                                if (!ext.isEmpty() && rp.value()->size > 0) {
                                    const QString path = imgDir.filePath(src);
                                    if (!QFile::exists(path)) {
                                        QFile f(path);
                                        if (f.open(QIODevice::WriteOnly)) {
                                            f.write(reinterpret_cast<const char *>(rp.value()->data),
                                                    qint64(rp.value()->size));
                                            f.close();
                                        }
                                    }
                                    local = path;
                                }
                            }
                        }
                        imgCache.insert(src, local);
                    }
                    if (!local.isEmpty()) {
                        if (!inBlock)
                            wrapAndAppendPara(); // 块外图片自成段落
                        curPara.imagePath = local;
                        curPara.html += QStringLiteral("<img src=\"")
                            + local.toHtmlEscaped() + "\">";
                    }
                    // 未映射（非 resourceNNNNN 形式或资源缺失）的图片 v1 跳过
                }
                continue;
            }
            if (tag == QLatin1String("br")) {
                // <br>（含 <br/>）在段落内输出换行：html 保留结构、text 供分句
                if (inBlock) {
                    curPara.html += QStringLiteral("<br>");
                    curPara.text += QLatin1Char('\n');
                }
                continue;
            }
            if (inBlock && isInlineTag(tag))
                curPara.html += '<' + tag + '>';
        }
        if (pos < html.size()) {
            const QString tail = html.mid(pos);
            if (!tail.isEmpty() && inBlock) {
                curPara.html += tail;
                curPara.text += decodeEntities(tail);
            }
        }
    }
    wrapAndAppendPara();
    closeChapter();

    if (!sawHtml) {
        // Print Replica（AZW4，markup 为 T_PDF）等无 HTML 正文的类型：
        // 返回空模型并给出明确错误，而非静默成功
        mobi_free_rawml(rawml);
        mobi_free(m);
        m_error = QStringLiteral("未解析到正文（不支持的 MOBI 类型）");
        return model;
    }

    mobi_free_rawml(rawml);
    mobi_free(m);

    model.chapters = chapters;
    // 每段预分句
    for (Chapter &c : model.chapters)
        for (Paragraph &p : c.paragraphs)
            p.sentences = SentenceSplitter::split(p.text);
    return model;
}

// 轻量元数据读取（任务4）：只 mobi_init/load + EXTH 读取，不跑 rawml 重建与
// 正文分章——BookImporter 注册时以最小开销取 title/author/publisher。
// 元数据语义与 parse() 一致（mobi_meta_get_title/author/publisher）；加载失败
// 返回空模型，调用方按"元数据缺失"处理，不阻断入库。
DocumentModel MobiParser::readMetadataOnly(const QString &mobiPath) {
    DocumentModel model;
    m_error.clear();
    if (!QFileInfo::exists(mobiPath)) {
        m_error = QStringLiteral("文件不存在: %1").arg(mobiPath);
        return model;
    }

    MOBIData *m = mobi_init();
    if (m == nullptr) {
        m_error = QStringLiteral("内存分配失败");
        return model;
    }
    const MOBI_RET loadRet = mobi_load_filename(m, mobiPath.toLocal8Bit().constData());
    if (loadRet != MOBI_SUCCESS || mobi_is_encrypted(m)) {
        m_error = mobi_is_encrypted(m)
            ? QStringLiteral("该文件受 DRM 保护（已加密），无法解析")
            : mobiErrorMessage(loadRet);
        mobi_free(m);
        return model;
    }
    if (!mobi_is_mobipocket(m)) {
        m_error = QStringLiteral("不是受支持的 MOBI/AZW3 文件");
        mobi_free(m);
        return model;
    }

    char *titleC = mobi_meta_get_title(m);
    char *authorC = mobi_meta_get_author(m);
    char *publisherC = mobi_meta_get_publisher(m);
    model.title = titleC ? QString::fromUtf8(titleC) : QString();
    model.author = authorC ? QString::fromUtf8(authorC) : QString();
    model.publisher = publisherC ? QString::fromUtf8(publisherC) : QString();
    free(titleC);
    free(authorC);
    free(publisherC);
    if (model.title.isEmpty())
        model.title = QFileInfo(mobiPath).completeBaseName();
    mobi_free(m);
    return model;
}
