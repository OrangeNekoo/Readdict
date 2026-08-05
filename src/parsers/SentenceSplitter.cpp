#include "SentenceSplitter.h"

#include <QSet>

namespace {

bool isSentenceEnd(QChar c) {
    return c == u'。' || c == u'？' || c == u'！' || c == '?' || c == '!' || c == '.';
}

// 常见英文缩写白名单（小写比较；含内部点如 U.S./U.S.A.）
bool isKnownAbbreviation(const QString &token) {
    static const QSet<QString> kAbbr = {
        QStringLiteral("dr"), QStringLiteral("mr"), QStringLiteral("mrs"),
        QStringLiteral("ms"), QStringLiteral("st"), QStringLiteral("mt"),
        QStringLiteral("prof"), QStringLiteral("jr"), QStringLiteral("sr"),
        QStringLiteral("u.s"), QStringLiteral("u.s.a"), QStringLiteral("u.k"),
        QStringLiteral("e.g"), QStringLiteral("i.e"), QStringLiteral("etc"),
    };
    return kAbbr.contains(token.toLower());
}

// 提取句点前的单词（含内部点，如 "U.S.A"），用于白名单匹配；限制回扫长度避免退化
QString tokenBefore(const QString &text, int i) {
    QString token;
    for (int j = i - 1; j >= 0 && token.size() < 32; --j) {
        const QChar ch = text.at(j);
        if (ch.isLetter()) {
            token.prepend(ch);
        } else if (ch == '.' && j + 1 < i && text.at(j + 1).isLetter()) {
            token.prepend(ch); // 内部点：后随字母才并入（U.S.A 的中间点）
        } else {
            break;
        }
    }
    return token;
}

// 缩写保护：判断 text[i]（应为 '.'）属于缩写的一部分而不应断句
bool isAbbreviationDot(const QString &text, int i) {
    // (1) 句点后紧跟字母/数字（U.S.A 内部点、3.14、e.g 首点）
    if (i + 1 < text.size()) {
        const QChar next = text.at(i + 1);
        if (next.isLetter() || next.isDigit())
            return true;
    }
    // (2) 白名单：句点前的单词（含内部点）为常见缩写（Dr.、U.S.A. 末点等）
    return isKnownAbbreviation(tokenBefore(text, i));
}

// 断句符后的空白（含换行）并入已结束的句子，避免下一句以空白开头
int consumeWhitespace(const QString &text, int i, QString &cur) {
    while (i + 1 < text.size() && text.at(i + 1).isSpace())
        cur.append(text.at(++i));
    return i;
}

} // namespace

QVector<QString> SentenceSplitter::split(const QString &text) {
    QVector<QString> out;
    QString cur;
    const QChar *data = text.constData();
    const int n = text.size();
    for (int i = 0; i < n; ++i) {
        const QChar c = data[i];
        if (isSentenceEnd(c)) {
            if (c == '.') {
                // 省略号：连续句点不断句
                if ((i + 1 < n && data[i + 1] == '.') || (i > 0 && data[i - 1] == '.')) {
                    cur.append(c);
                    continue;
                }
                if (isAbbreviationDot(text, i)) {
                    cur.append(c); // 缩写：并入当前句
                    continue;
                }
            }
            // 连续标点（？！、!? 等）只断一次：后续断句符并入本句
            while (i < n && isSentenceEnd(data[i]))
                cur.append(data[i++]);
            --i;
            i = consumeWhitespace(text, i, cur); // 句尾空白并入本句
            out.append(cur);
            cur.clear();
            continue;
        }
        if (c == '\n' || c == '\r') {
            // 单个换行（含 \r\n）并入当前句；连续换行（含仅空格/制表符的空白行）为段落边界，
            // 并入前一句后断句，不单独成句
            const int unit = (c == '\r' && i + 1 < n && data[i + 1] == '\n') ? 2 : 1;
            int probe = i + unit;
            while (probe < n && (data[probe] == ' ' || data[probe] == '\t'))
                ++probe; // 空白行的空格/制表符填充不算内容
            if (probe < n && (data[probe] == '\n' || data[probe] == '\r')) {
                while (i < n) {
                    const QChar ch = data[i];
                    if (ch == '\n' || ch == '\r' || ch == ' ' || ch == '\t') {
                        cur.append(ch);
                        ++i;
                    } else {
                        break;
                    }
                }
                --i;
                if (!cur.trimmed().isEmpty())
                    out.append(cur);
                cur.clear();
                continue;
            }
            cur.append(c);
            continue;
        }
        cur.append(c); // 普通字符并入当前句
    }
    if (!cur.trimmed().isEmpty())
        out.append(cur);
    return out;
}
