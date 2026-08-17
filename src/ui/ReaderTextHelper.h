#pragma once
#include <QObject>
#include <QStringList>
#include <QVariantList>

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
    // 返回同一 TextEdit 实际布局产生的行边界，坐标相对 TextEdit 左上角。
    // 每项为 {top: real, bottom: real}，QML 用它在真实行边界分页。
    Q_INVOKABLE QVariantList lineBreaks(QQuickItem *edit) const;
    // 桥接既有 SentenceSplitter：不复制/改写其缩写、标点或空白规则，
    // 仅过滤 trim 后为空的片段并转为 QStringList 供 QML 使用。
    Q_INVOKABLE QStringList splitSentences(const QString &text) const;
};
