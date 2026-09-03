#pragma once
#include <QObject>
#include <QSqlDatabase>
#include <QVariantList>
#include <QVariantMap>

class HighlightManager : public QObject {
    Q_OBJECT
public:
    explicit HighlightManager(const QString &dbPath, const QString &connection = {}, QObject *parent = nullptr);
    // C7：全部 Q_INVOKABLE 供 QML 直接调用；highlightsForBook 返回 QVariantList<QVariantMap>
    // （键 id/bookId/chapter/sentenceIndex/text/color/note/chapterIndex/selStart/selLength），
    // QML 侧按 map 字段读取。selStart/selLength：选区在段内纯文本坐标的字符区间
    // （v4 起），负值 = 未提供（整句粒度，旧行为）；默认参数保持旧调用兼容。
    Q_INVOKABLE qint64 addHighlight(qint64 bookId, const QString &chapter, int sentenceIndex,
                                    const QString &text, const QString &color, const QString &note = {},
                                    int chapterIndex = 0, int selStart = -1, int selLength = -1);
    Q_INVOKABLE void removeHighlight(qint64 id);
    Q_INVOKABLE void updateNote(qint64 id, const QString &note);
    // C7 复审：同句重复划线 → 复用行 id 更新颜色（不产生重复行）
    Q_INVOKABLE void updateColor(qint64 id, const QString &color);
    // L5（P0#6）：旧库 chapter_index=0 的行按章节标题回填 1 起索引（仅触碰未赋值行，
    // 幂等：已回填/新写入的行不再改写）
    Q_INVOKABLE void backfillChapterIndexes(qint64 bookId, const QVariantList &titles);
    Q_INVOKABLE QVariantList highlightsForBook(qint64 bookId) const;
signals:
    void highlightsChanged(qint64 bookId);
private:
    QSqlDatabase m_db;
};
