// TextParser.cpp — TXT/Markdown 解析器
// 编码处理：BOM 优先；无 BOM 时严格尝试 UTF-8，出现替换字符（U+FFFD）则回退 GB18030。
// Qt 6 不内置 GB18030 codec（QTextCodec 仅经 Qt5Compat 提供且不含 GB18030），
// 故 GB18030 解码按平台实现：macOS/Linux 走系统 iconv，Windows 走 MultiByteToWideChar。
#include "TextParser.h"
#include "SentenceSplitter.h"

#include <QFile>
#include <QFileInfo>
#include <QStringDecoder>
#include <QRegularExpression>

#if defined(Q_OS_WIN)
#  include <windows.h>
#else
#  include <iconv.h>
#endif

// Qt5Compat 提供 QTextCodec 时优先尝试（Qt 6 内置 codec 不含 GB18030，通常返回 nullptr）
#if defined(__has_include)
#  if __has_include(<QTextCodec>)
#    define TEXT_PARSER_HAS_QTEXTCODEC 1
#  endif
#endif
#ifdef TEXT_PARSER_HAS_QTEXTCODEC
#  include <QTextCodec>
#endif

namespace {

// 跨平台 GB18030 → QString。
// 先尝试 QTextCodec::codecForName("GB18030")（Qt5Compat 提供时可用）；Qt 6 内置 codec
// 不含 GB18030（返回 nullptr），故实际路径为平台原生转换。
QString decodeGb18030(const QByteArray &data) {
#ifdef TEXT_PARSER_HAS_QTEXTCODEC
    if (QTextCodec *gb = QTextCodec::codecForName("GB18030"))
        return gb->toUnicode(data);
#endif
#if defined(Q_OS_WIN)
    // 先按 CP_UTF8 严格探测（数据实际为 UTF-8 时直接解码），失败则按 ANSI 代码页
    // （简体中文系统为 936/GBK，GB18030 的实用子集）。
    int len = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                  data.constData(), data.size(), nullptr, 0);
    UINT cp = CP_UTF8;
    if (len <= 0) {
        len = MultiByteToWideChar(CP_ACP, 0, data.constData(), data.size(), nullptr, 0);
        cp = CP_ACP;
    }
    if (len <= 0) return QString::fromUtf8(data);
    QVector<wchar_t> buf(len);
    MultiByteToWideChar(cp, 0, data.constData(), data.size(), buf.data(), len);
    return QString::fromWCharArray(buf.constData(), len);
#else
    // macOS / Linux：系统自带 iconv（GB18030 → UTF-8，最多 1:4 字节膨胀）
    iconv_t cd = iconv_open("UTF-8", "GB18030");
    if (cd == reinterpret_cast<iconv_t>(-1)) return QString::fromUtf8(data);
    QByteArray out(data.size() * 4 + 8, Qt::Uninitialized);
    char *inp = const_cast<char *>(data.constData());
    size_t inLeft = static_cast<size_t>(data.size());
    char *outp = out.data();
    size_t outLeft = static_cast<size_t>(out.size());
    const size_t rc = iconv(cd, &inp, &inLeft, &outp, &outLeft);
    iconv_close(cd);
    if (rc == static_cast<size_t>(-1)) {
        // 无效字节序列：回退 UTF-8（含替换字符）并记录
        qWarning("TextParser: GB18030 解码失败（无效字节），回退 UTF-8");
        return QString::fromUtf8(data);
    }
    out.truncate(static_cast<int>(out.size() - outLeft));
    return QString::fromUtf8(out);
#endif
}

} // namespace

QString TextParser::detectAndRead(const QString &filePath, QString *error) {
    if (!QFileInfo::exists(filePath)) {
        if (error) *error = QStringLiteral("文件不存在: %1").arg(filePath);
        return {};
    }
    QFile f(filePath);
    if (!f.open(QIODevice::ReadOnly)) {
        if (error) *error = QStringLiteral("文件无法打开: %1").arg(filePath);
        return {};
    }
    const QByteArray data = f.readAll();
    QString text;
    // BOM 检测
    if (data.startsWith("\xEF\xBB\xBF")) {
        text = QString::fromUtf8(data.mid(3));
    } else if (data.startsWith("\xFF\xFE") || data.startsWith("\xFE\xFF")) {
        // QStringDecoder::Utf16 依据 BOM 判定端序并吞掉 BOM（Qt 6 原生，替代 QTextCodec）
        QStringDecoder dec(QStringConverter::Utf16);
        text = dec.decode(data);
    } else {
        // 启发式：尝试 UTF-8 严格解码，失败则 GB18030
        QString utf8 = QString::fromUtf8(data);
        if (utf8.contains(QChar::ReplacementCharacter)) {
            text = decodeGb18030(data);
        } else {
            text = utf8;
        }
    }
    return text;
}

QString TextParser::mdToHtml(const QString &line) {
    QString s = line.toHtmlEscaped();
    static const QRegularExpression bold(R"(\*\*(.+?)\*\*)");
    static const QRegularExpression italic(R"(\*(.+?)\*)");
    s.replace(bold, "<b>\\1</b>").replace(italic, "<i>\\1</i>");
    return s;
}

DocumentModel TextParser::parse(const QString &filePath) {
    DocumentModel m;
    m_error.clear();
    const QString text = detectAndRead(filePath, &m_error);
    if (text.isEmpty()) return m;
    const QStringList lines = text.split('\n');
    Chapter ch; ch.title = m.title = QFileInfo(filePath).completeBaseName();
    Paragraph cur;
    bool inPre = false;
    for (const QString &raw : lines) {
        const QString line = raw.trimmed();
        if (line.startsWith("# ") || line.startsWith("## ") || line.startsWith("### ")) {
            // 新章节（## 及以上）或新标题段落
            if (!cur.text.isEmpty()) { cur.html = mdToHtml(cur.text); ch.paragraphs.append(cur); cur = Paragraph(); }
            const int level = line.count('#');
            Paragraph h; h.text = line.mid(level + 1); h.level = level;
            h.html = QString("<h%1>%2</h%1>").arg(level).arg(h.text.toHtmlEscaped());
            ch.paragraphs.append(h);
        } else if (line.isEmpty()) {
            if (!cur.text.isEmpty()) { cur.html = mdToHtml(cur.text); ch.paragraphs.append(cur); cur = Paragraph(); }
        } else if (line.startsWith("```")) {
            inPre = !inPre;
        } else {
            if (!cur.text.isEmpty()) cur.text += "\n";
            cur.text += line;
            if (!inPre && !cur.html.isEmpty()) cur.html += " ";
            cur.html = mdToHtml(cur.text);
        }
    }
    if (!cur.text.isEmpty()) ch.paragraphs.append(cur);
    // 按 h2 拆多章：第一处 h2 前的段落归第一章，之后每个 h2 开新章
    DocumentModel out; out.title = m.title;
    Chapter curCh; curCh.title = ch.title;
    for (const Paragraph &p : ch.paragraphs) {
        if (p.level >= 2 && !curCh.paragraphs.isEmpty()) { out.chapters.append(curCh); curCh = Chapter{p.text}; }
        curCh.paragraphs.append(p);
    }
    out.chapters.append(curCh);
    // 对每个段落预分句
    for (Chapter &c : out.chapters)
        for (Paragraph &p : c.paragraphs)
            p.sentences = SentenceSplitter::split(p.text);
    return out;
}
