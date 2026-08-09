#include <QtTest>
#include "core/SearchEngine.h"

// C8：FTS5 全文搜索。
// 覆盖简报步骤 1 的两个基准用例（indexesAndFinds / noHitsWhenAbsent），
// 以及扩展边界：引号/元字符清理（A3 先例防 FTS 语法错误）、跨书 searchAll、
// removeBook 清理、snippet 上下文、空查询、ASCII 前缀、重复索引替换。
// L9：游标式 indexBook 已删，索引入口统一为 rebuildBook（整书单事务）。
class TestSearch : public QObject {
    Q_OBJECT
private slots:
    void init() { m_s.reset(new SearchEngine(":memory:")); }

    void indexesAndFinds() {
        m_s->rebuildBook(1, chapters({QStringLiteral("第一章"), {"这是第一段内容。", "包含关键词的段落。"}}));
        const auto hits = m_s->search(1, "关键词");
        QCOMPARE(hits.size(), 1);
        QCOMPARE(hits[0].paragraphIndex, 1);
        QCOMPARE(hits[0].chapterIndex, 0);
    }

    void noHitsWhenAbsent() {
        m_s->rebuildBook(1, chapters({QStringLiteral("ch"), {"普通文本。"}}));
        QVERIFY(m_s->search(1, "不存在的词").isEmpty());
    }

    void quoteStripped() {
        // A3 先例：MATCH 中未转义的 '"' 会截断语法导致静默失败；剔除后仍应命中
        m_s->rebuildBook(1, chapters({QStringLiteral("ch"), {"引号测试文本。"}}));
        QCOMPARE(m_s->search(1, "\"测试").size(), 1);
    }

    void metaCharsStripped() {
        // FTS5 元字符（* ( ) { } : ^）同样会破坏 MATCH 语法，剔除后仍应命中
        m_s->rebuildBook(1, chapters({QStringLiteral("ch"), {"元字符测试文本。"}}));
        QCOMPARE(m_s->search(1, "测试*").size(), 1);
        QCOMPARE(m_s->search(1, "(测试)").size(), 1);
    }

    void searchAllAcrossBooks() {
        m_s->rebuildBook(1, chapters({QStringLiteral("第一章"), {"魔女现身于森林。"}}));
        m_s->rebuildBook(2, chapters({QStringLiteral("第二章"), {"贤者与魔女交谈。"}}));
        const auto hits = m_s->searchAll("魔女");
        QCOMPARE(hits.size(), 2);
        QSet<qint64> books;
        for (const auto &h : hits) books.insert(h.bookId);
        QVERIFY(books.contains(1) && books.contains(2));
    }

    void removeBookClears() {
        m_s->rebuildBook(1, chapters({QStringLiteral("ch"), {"删除后不应再命中。"}}));
        m_s->removeBook(1);
        QVERIFY(m_s->search(1, "删除").isEmpty());
        QVERIFY(m_s->searchAll("删除").isEmpty());
        // 删除后新书独立索引，章节索引从第 0 章开始
        m_s->rebuildBook(2, chapters({QStringLiteral("ch"), {"新书内容。"}}));
        const auto hits = m_s->search(2, "新书");
        QCOMPARE(hits.size(), 1);
        QCOMPARE(hits[0].chapterIndex, 0);
    }

    void snippetHasContext() {
        // 命中词前 22 字 / 后 22 字：snippet 应含命中词、前后 20 字窗口、两端省略号
        const QString text = QStringLiteral(
            "甲乙丙丁戊己庚辛壬癸子丑寅卯辰巳午未申酉戌亥关键词甲乙丙丁戊己庚辛壬癸子丑寅卯辰巳午未申酉戌亥");
        m_s->rebuildBook(1, chapters({QStringLiteral("ch"), {text}}));
        const auto hits = m_s->search(1, "关键词");
        QCOMPARE(hits.size(), 1);
        QVERIFY(hits[0].snippet.contains("关键词"));
        QVERIFY(hits[0].snippet.startsWith("…"));
        QVERIFY(hits[0].snippet.endsWith("…"));
    }

    void emptyQuery() {
        m_s->rebuildBook(1, chapters({QStringLiteral("ch"), {"任意内容。"}}));
        QVERIFY(m_s->search(1, "").isEmpty());
        QVERIFY(m_s->search(1, "\"").isEmpty());
        QVERIFY(m_s->searchAll("").isEmpty());
    }

    void asciiPrefix() {
        m_s->rebuildBook(1, chapters({QStringLiteral("ch"), {"The quick brown fox."}}));
        QCOMPARE(m_s->search(1, "quick").size(), 1);
        QCOMPARE(m_s->search(1, "qui").size(), 1);   // 前缀命中
        QVERIFY(m_s->search(1, "zebra").isEmpty());
    }

    void reindexReplaces() {
        // 整书重建：旧内容全部清除，新内容写入，不残留旧章节
        m_s->rebuildBook(1, chapters({QStringLiteral("第一章"), {"旧内容甲。"}}));
        m_s->rebuildBook(1, chapters({QStringLiteral("第一章"), {"新内容乙。"}}));
        QVERIFY(m_s->search(1, "旧内容").isEmpty());
        QCOMPARE(m_s->search(1, "新内容").size(), 1);
    }

    void multiChapterAccumulates() {
        // 多章整书索引：各章槽位独立，章节索引按列表序（回归：曾整书
        // DELETE 导致只留最后一章）
        m_s->rebuildBook(1, {qMakePair(QStringLiteral("第一章"), QStringList{"第一章有魔女。"}),
                             qMakePair(QStringLiteral("第二章"), QStringList{"第二章有贤者。"})});
        QCOMPARE(m_s->search(1, "魔女")[0].chapterIndex, 0);
        QCOMPARE(m_s->search(1, "贤者")[0].chapterIndex, 1);
        QCOMPARE(m_s->searchAll("魔女").size(), 1);
        QCOMPARE(m_s->searchAll("贤者").size(), 1);
    }

    void rebuildBookReplacesWholeBook() {
        // 原子整书重建（单事务）：旧章节全部清除、新章节按列表序写入；
        // 二次重建同样原子替换，已重建章节不受部分影响
        m_s->rebuildBook(1, {qMakePair(QStringLiteral("第一章"), QStringList{"旧章内容。"}),
                             qMakePair(QStringLiteral("第二章"), QStringList{"旧二章内容。"})});
        QVector<QPair<QString, QStringList>> chapters2;
        chapters2.append(qMakePair(QStringLiteral("新一章"), QStringList{"新内容甲。"}));
        chapters2.append(qMakePair(QStringLiteral("新二章"), QStringList{"新内容乙。"}));
        m_s->rebuildBook(1, chapters2);
        QVERIFY(m_s->search(1, "旧章").isEmpty());
        QVERIFY(m_s->search(1, "旧二章").isEmpty());
        QCOMPARE(m_s->search(1, "新内容甲")[0].chapterIndex, 0);
        QCOMPARE(m_s->search(1, "新内容乙")[0].chapterIndex, 1);
        QCOMPARE(m_s->searchAll("新内容乙").size(), 1);  // 重建的章节不受影响
    }

private:
    static QVector<QPair<QString, QStringList>>
    chapters(const QPair<QString, QStringList> &c) { return {c}; }
    std::unique_ptr<SearchEngine> m_s;
};
QTEST_MAIN(TestSearch)
#include "tst_search.moc"
