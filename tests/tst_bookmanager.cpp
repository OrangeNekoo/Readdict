#include <QtTest>
#include <QSignalSpy>
#include <QTemporaryDir>
#include "core/BookManager.h"
#include "core/SettingsStore.h"

class TestBookManager : public QObject {
    Q_OBJECT
private slots:
    void init() {
        m_tmp.reset(new QTemporaryDir);
        m_settings.reset(new SettingsStore(m_tmp->path() + "/settings.json"));
        m_mgr.reset(new BookManager(":memory:"));
        m_mgr->setSettingsStore(m_settings.get());
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
    void positionRoundTrip() {
        // B10：savePosition 同时持久化章节索引与章内滚动偏移，恢复接口按键读回
        m_mgr->savePosition(1, 2, 123.5);
        QCOMPARE(m_mgr->lastChapter(1), 2);
        QCOMPARE(m_mgr->lastScrollY(1), 123.5);
    }
    void positionDefaultsZero() {
        // B10：无进度记录时恢复值应为 0（章节 0 / 顶部）
        QCOMPARE(m_mgr->lastChapter(2), 0);
        QCOMPARE(m_mgr->lastScrollY(2), 0.0);
    }
    void loadChapterUpdatesProgressPercent() {
        // B10：换章时 books.progress 更新为 章节数/总章节数，并刷新 last_read_at
        m_mgr->addBook(Book{-1, "fixture", "作者", "出版社", "", "EPUB",
                            QStringLiteral(EPUB_FIXTURES_DIR) + "/sample.epub", QString(), 0.0});
        const qint64 id = 3; // init 已添加 id 1、2
        QVERIFY(!m_mgr->loadChapter(id, 1).toMap().isEmpty());
        QCOMPARE(m_mgr->bookById(id).progress, 1.0); // 第 2 章 / 共 2 章
        QVERIFY(!m_mgr->bookById(id).lastReadAt.isEmpty());
        m_mgr->loadChapter(id, 0);
        QCOMPARE(m_mgr->bookById(id).progress, 0.5); // 第 1 章 / 共 2 章
    }
    void readingTimerAccumulates() {
        // B10：startTracking 后实测 elapsed，stopTracking 结算到 read_seconds（mock 计时）
        m_mgr->startTracking(1);
        QTest::qWait(1100);
        m_mgr->stopTracking();
        QVERIFY2(m_mgr->bookById(1).readSeconds >= 1,
                 qPrintable(QStringLiteral("阅读约 1.1 秒应累加至少 1 秒，实际 %1")
                                .arg(m_mgr->bookById(1).readSeconds)));
    }
    void stopTrackingWithoutStartIsNoop() {
        m_mgr->stopTracking(); // 未 start 时调用无副作用（不崩溃、不写负数）
        QCOMPARE(m_mgr->bookById(1).readSeconds, 0);
        m_mgr->stopTracking();
        QCOMPARE(m_mgr->bookById(1).readSeconds, 0);
    }
private:
    std::unique_ptr<QTemporaryDir> m_tmp;
    std::unique_ptr<SettingsStore> m_settings;
    std::unique_ptr<BookManager> m_mgr;
};
QTEST_MAIN(TestBookManager)
#include "tst_bookmanager.moc"
