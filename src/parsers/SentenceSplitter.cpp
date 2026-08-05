#include "SentenceSplitter.h"

namespace {

// 缩写保护：判断 text[i]（应为 '.'）属于缩写的一部分而不应断句。
// (1) 句点后紧跟字母/数字（U.S.A 内部点、3.14、e.g. 内部点）
// (2) 句点前是 1~2 个字母的短词（Dr.、Mr.、U.S.A. 的末点；"world."、"two." 等正常句尾不受影响）
bool isAbbreviationDot(const QString &text, int i) {
    if (i + 1 < text.size()) {
        const QChar next = text.at(i + 1);
        if (next.isLetter() || next.isDigit())
            return true;
    }
    int len = 0;
    for (int j = i - 1; j >= 0 && text.at(j).isLetter(); --j) {
        if (++len > 2)
            return false;
    }
    return len >= 1;
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
        const bool isTerminator = c == u'。' || c == u'？' || c == u'！' || c == '?' || c == '!' || c == '.';
        if (isTerminator) {
            if (c == '.' && isAbbreviationDot(text, i)) {
                cur.append(c); // 缩写：并入当前句
                continue;
            }
            cur.append(c);
            i = consumeWhitespace(text, i, cur); // 句尾空白并入本句
            out.append(cur);
            cur.clear();
            continue;
        }
        if (c == '\n' && i + 1 < n && data[i + 1] == '\n') {
            // 段落边界（连续换行）：换行内容并入前一句后断句，不单独成句
            while (i < n && data[i] == '\n')
                cur.append(data[i++]);
            --i;
            if (!cur.trimmed().isEmpty())
                out.append(cur);
            cur.clear();
            continue;
        }
        cur.append(c); // 普通字符与单换行并入当前句
    }
    if (!cur.trimmed().isEmpty())
        out.append(cur);
    return out;
}
