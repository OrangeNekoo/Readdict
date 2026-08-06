#pragma once
#include <QObject>
#include <QSqlDatabase>
#include <QVector>

struct Highlight { qint64 id=-1, bookId=0; QString chapter, text, color, note; int sentenceIndex=-1; };

class HighlightManager : public QObject {
    Q_OBJECT
public:
    explicit HighlightManager(const QString &dbPath, const QString &connection = {}, QObject *parent = nullptr);
    qint64 addHighlight(qint64 bookId, const QString &chapter, int sentenceIndex,
                        const QString &text, const QString &color, const QString &note = {});
    void removeHighlight(qint64 id);
    void updateNote(qint64 id, const QString &note);
    QVector<Highlight> highlightsForBook(qint64 bookId) const;
signals:
    void highlightsChanged(qint64 bookId);
private:
    QSqlDatabase m_db;
};
