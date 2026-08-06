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
    QTextBlockFormat fmt = cur.blockFormat();
    fmt.setLineHeight(factor * 100.0, QTextBlockFormat::ProportionalHeight);
    // merge 而非 set：只改行距，不覆盖富文本段落自身的其他块属性
    cur.mergeBlockFormat(fmt);
}
