#include "ReaderTextHelper.h"

#include <QMetaObject>
#include <QMetaProperty>
#include <QObject>
#include <QQuickItem>
#include <QQuickTextDocument>
#include <QVariant>
#include <QTextBlockFormat>
#include <QTextCursor>
#include <QTextDocument>

namespace {
// QQuickTextEdit 是 Qt 6.11 的 private 类（无公共头文件），但其 textDocument
// Q_PROPERTY 存在；经 meta-object 读取 QQuickTextDocument*（公共类）。
QQuickTextDocument *textDocumentOf(QQuickItem *edit) {
    if (!edit) return nullptr;
    const QMetaObject *mo = edit->metaObject();
    const int idx = mo->indexOfProperty("textDocument");
    if (idx < 0) return nullptr;
    const QVariant v = mo->property(idx).read(edit);
    return qobject_cast<QQuickTextDocument *>(v.value<QObject *>());
}
} // namespace

void ReaderTextHelper::applyLineSpacing(QQuickItem *edit, double factor) {
    QQuickTextDocument *qdoc = textDocumentOf(edit);
    if (!qdoc) return;
    QTextDocument *doc = qdoc->textDocument();
    if (!doc) return;
    if (factor <= 0.0) factor = 1.6;
    QTextCursor cur(doc);
    cur.select(QTextCursor::Document);
    // 用默认构造的 QTextBlockFormat（不带任何块属性）而非 cur.blockFormat()：
    // select(Document) 后光标停在文档末尾，blockFormat() 返回**末段**整块格式
    // （对齐/边距/缩进/标题属性），以其为 merge 基础会把末段格式污染到全章段落
    // （如居中诗行章节整章被改对齐）。默认构造 + 只设行距 → merge 仅施加行距。
    QTextBlockFormat fmt;
    fmt.setLineHeight(factor * 100.0, QTextBlockFormat::ProportionalHeight);
    // merge 而非 set：只改行距，不覆盖富文本段落自身的其他块属性
    cur.mergeBlockFormat(fmt);
}
