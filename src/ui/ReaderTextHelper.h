#pragma once
#include <QObject>
class QQuickItem;

// C7：Qt 6.7+ 的 Text 移除了 selectByMouse/selectedText 等选择 API（deprecated 后删除），
// 段落改用只读 TextEdit 渲染；但 TextEdit 没有 lineHeight 属性（Text 独有），行距
// 无法从 QML 直接设置。本助手把行距因子经 QTextBlockFormat::setLineHeight 施加到
// TextEdit 的富文本文档上，与 Text.lineHeight 语义一致（ProportionalHeight = factor*100%）。
class ReaderTextHelper : public QObject {
    Q_OBJECT
public:
    explicit ReaderTextHelper(QObject *parent = nullptr) : QObject(parent) {}
    Q_INVOKABLE void applyLineSpacing(QQuickItem *edit, double factor);
};
