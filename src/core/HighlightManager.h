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
    // （键 id/bookId/chapter/sentenceIndex/text/color/note），QML 侧按 map 字段读取。
    Q_INVOKABLE qint64 addHighlight(qint64 bookId, const QString &chapter, int sentenceIndex,
                                    const QString &text, const QString &color, const QString &note = {});
    Q_INVOKABLE void removeHighlight(qint64 id);
    Q_INVOKABLE void updateNote(qint64 id, const QString &note);
    // C7 复审：同句重复划线 → 复用行 id 更新颜色（不产生重复行）
    Q_INVOKABLE void updateColor(qint64 id, const QString &color);
    Q_INVOKABLE QVariantList highlightsForBook(qint64 bookId) const;
signals:
    void highlightsChanged(qint64 bookId);
private:
    QSqlDatabase m_db;
};
