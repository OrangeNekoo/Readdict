#include <QtTest>
#include <QSignalSpy>
#include <memory>
#include "core/HighlightManager.h"

class TestHighlights : public QObject {
    Q_OBJECT
private slots:
    // QWARN duplicate connection name 'readdict_main' 已知良性（A3 同因），未改 DatabaseManager
    void init() { m_h.reset(new HighlightManager(":memory:")); }
    void addsAndLists() {
        m_h->addHighlight(1, "第一章", 3, "这是高亮文本", "#FFD54F", "笔记内容");
        const auto list = m_h->highlightsForBook(1);
        QCOMPARE(list.size(), 1);
        QCOMPARE(list[0].text, QString("这是高亮文本"));
        QCOMPARE(list[0].note, QString("笔记内容"));
    }
    void removes() {
        const qint64 id = m_h->addHighlight(1, "ch", 0, "t", "#FFF", "");
        m_h->removeHighlight(id);
        QCOMPARE(m_h->highlightsForBook(1).size(), 0);
    }
    void updatesNote() {
        const qint64 id = m_h->addHighlight(1, "ch", 0, "t", "#FFF", "旧笔记");
        m_h->updateNote(id, "新笔记");
        const auto list = m_h->highlightsForBook(1);
        QCOMPARE(list.size(), 1);
        QCOMPARE(list[0].note, QString("新笔记"));
        QCOMPARE(list[0].text, QString("t")); // 仅改 note，其余字段不变
    }
    void emitsChangedOnEveryWrite() {
        QSignalSpy spy(m_h.get(), &HighlightManager::highlightsChanged);
        const qint64 id = m_h->addHighlight(1, "ch", 0, "t", "#FFF");
        m_h->updateNote(id, "n");
        m_h->removeHighlight(id);
        QCOMPARE(spy.count(), 3);
        QCOMPARE(spy.at(0).at(0).toLongLong(), 1);
        QCOMPARE(spy.at(1).at(0).toLongLong(), 1);
        QCOMPARE(spy.at(2).at(0).toLongLong(), 1);
    }
    void booksAreIsolated() {
        m_h->addHighlight(1, "ch", 0, "a", "#FFF", "");
        m_h->addHighlight(2, "ch", 1, "b", "#FF0", "");
        const auto list = m_h->highlightsForBook(1);
        QCOMPARE(list.size(), 1);
        QCOMPARE(list[0].text, QString("a"));
        QCOMPARE(m_h->highlightsForBook(2).size(), 1);
    }
private:
    std::unique_ptr<HighlightManager> m_h;
};
QTEST_MAIN(TestHighlights)
#include "tst_highlights.moc"
