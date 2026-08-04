#include <QtTest>
#include <QSignalSpy>
#include "core/BookManager.h"

class TestBookManager : public QObject {
    Q_OBJECT
private slots:
    void init() {
        m_mgr.reset(new BookManager(":memory:"));
        // 简报原文用聚合初始化 {"红楼梦", ...}，但 Book.id 是首位成员，
        // const char* -> qint64 无法编译；改为显式构造，语义不变（cover 空串）。
        m_mgr->addBook(Book{-1, "红楼梦", "曹雪芹", "人民文学出版社", "古典", "TXT", "/tmp/hlm.txt", QString(), 0.0});
        m_mgr->addBook(Book{-1, "三体", "刘慈欣", "重庆出版社", "科幻", "EPUB", "/tmp/santi.epub", QString(), 0.5});
    }
    void listsBooksRecentFirst() {
        // 控制者裁定：默认排序 added_at DESC, id DESC（最近添加在前，id 兜底保证稳定），
        // 三体后添加，故 books[0] 是三体。
        const auto books = m_mgr->books();
        QCOMPARE(books.size(), 2);
        QCOMPARE(books[0].title, QString("三体"));
    }
    void sortsByAuthor() {
        m_mgr->setSort(SortField::Author);
        QCOMPARE(m_mgr->books()[0].author, QString("刘慈欣")); // 刘 < 曹
    }
    void filtersByCategory() {
        m_mgr->setFilter("科幻");
        const auto books = m_mgr->books();
        QCOMPARE(books.size(), 1);
        QCOMPARE(books[0].title, QString("三体"));
    }
    void searchesByTitle() {
        QCOMPARE(m_mgr->search("三体").size(), 1);
        QCOMPARE(m_mgr->search("红楼").size(), 1);
    }
    void updatesProgressPersists() {
        m_mgr->setProgress(1, 0.8);
        QCOMPARE(m_mgr->bookById(1).progress, 0.8);
    }
    void categoryCrud() {
        m_mgr->addCategory("历史");
        QVERIFY(m_mgr->categories().contains("历史"));
        m_mgr->removeCategory("历史");
        QVERIFY(!m_mgr->categories().contains("历史"));
    }
    void deletesBook() {
        m_mgr->removeBook(1);
        QCOMPARE(m_mgr->books().size(), 1);
        QCOMPARE(m_mgr->search("红楼梦").size(), 0); // FTS 索引同步清理
    }
    void searchesTitleContainingQuote() {
        // 复审修复：MATCH 中未转义的 '"' 会截断字符串导致 exec 失败静默返回空，剔除后仍应命中。
        m_mgr->addBook(Book{-1, "测试\"引号", "某作者", "其他", "其他", "EPUB", "/tmp/quote.epub", QString(), 0.0});
        QCOMPARE(m_mgr->search("引号\"").size(), 1);
    }
private:
    std::unique_ptr<BookManager> m_mgr;
};
QTEST_MAIN(TestBookManager)
#include "tst_bookmanager.moc"
