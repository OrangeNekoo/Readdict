#include <QtTest>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFontDatabase>
#include <QSet>
#include <QSignalSpy>
#include <QTemporaryDir>
#include "core/BookManager.h"
#include "core/SearchEngine.h"
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
    void removeBookWithFilesDeletesDbAndFiles() {
        // B1：删书+删文件——DB 行、书文件、真实封面（cover_ 前缀）一并删除且发 booksChanged
        const QString bookFile = m_tmp->path() + "/books/delete_me.txt";
        const QString coverFile = m_tmp->path() + "/covers/cover_abc.png";
        QVERIFY(QDir().mkpath(QFileInfo(bookFile).absolutePath()));
        QVERIFY(QDir().mkpath(QFileInfo(coverFile).absolutePath()));
        QFile bf(bookFile); QVERIFY(bf.open(QIODevice::WriteOnly)); bf.write("待删内容"); bf.close();
        QFile cf(coverFile); QVERIFY(cf.open(QIODevice::WriteOnly)); cf.write("PNG"); cf.close();
        const qint64 id = m_mgr->addBook(Book{-1, "删书测试", "作者", "社", "", "TXT", bookFile, coverFile, 0.0});
        QVERIFY(id > 0);
        QSignalSpy spy(m_mgr.get(), &BookManager::booksChanged);
        m_mgr->removeBookWithFiles(id, true);
        QCOMPARE(m_mgr->bookById(id).id, -1);          // DB 行已删
        QCOMPARE(m_mgr->search("删书测试").size(), 0); // FTS 索引同步清理
        QVERIFY(!QFile::exists(bookFile));             // 书文件已删
        QVERIFY(!QFile::exists(coverFile));            // 真实封面已删
        QCOMPARE(spy.count(), 1);                      // 书架刷新信号
    }
    void removeBookWithFilesKeepsPlaceholderCover() {
        // B1：占位封面（<hash6>.png，非 cover_ 前缀）按书名哈希共享——删书不删文件
        const QString placeholder = m_tmp->path() + "/covers/abc123.png";
        QVERIFY(QDir().mkpath(QFileInfo(placeholder).absolutePath()));
        QFile pf(placeholder); QVERIFY(pf.open(QIODevice::WriteOnly)); pf.write("PNG"); pf.close();
        const qint64 id = m_mgr->addBook(Book{-1, "共享封面书", "作者", "社", "", "TXT",
                                              m_tmp->path() + "/x.txt", placeholder, 0.0});
        QVERIFY(id > 0);
        m_mgr->removeBookWithFiles(id, true);
        QCOMPARE(m_mgr->bookById(id).id, -1);
        QVERIFY(QFile::exists(placeholder)); // 共享占位封面保留
    }
    void updateCoverUpdatesAndSignals() {
        // B1：updateCover 更新 cover 字段并发出 booksChanged
        QSignalSpy spy(m_mgr.get(), &BookManager::booksChanged);
        m_mgr->updateCover(1, "/tmp/new_cover.png");
        QCOMPARE(m_mgr->bookById(1).cover, QString("/tmp/new_cover.png"));
        QCOMPARE(spy.count(), 1);
    }
    void removeBookClearsFulltextIndex() {
        // C8：removeBook 应同步清理 SearchEngine 的 fts_content 行（表存在时）。
        // 独立文件库 + 独立连接名（init 的 readdict_main 已被 :memory: 占用）。
        QTemporaryDir tmp;
        const QString db = tmp.path() + "/t.db";
        {
            SearchEngine se(db);
            se.indexBook(1, "第一章", {"魔女现身。"});
            QCOMPARE(se.searchAll("魔女").size(), 1);
        }
        BookManager mgr(db, "readdict_fts_test");
        mgr.addBook(Book{-1, "书", "作者", "社", "类", "TXT", "/tmp/x.txt", QString(), 0.0});
        mgr.removeBook(1);
        SearchEngine se2(db);
        QVERIFY(se2.searchAll("魔女").isEmpty());
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
    void statsAggregatesAndGroupsByCategory() {
        // D4：聚合查询——COUNT/SUM/AVG 与分类 GROUP BY；read_seconds 来自 B10 计时累加
        m_mgr->addReadSeconds(1, 3600); // 红楼梦 +1 小时
        m_mgr->addReadSeconds(1, 1800); // 红楼梦 +30 分
        m_mgr->addReadSeconds(2, 600);  // 三体 +10 分
        m_mgr->setProgress(1, 0.25);    // 红楼梦 25%，三体 50%（init 注入）
        const QVariantMap stats = m_mgr->stats();
        QCOMPARE(stats.value("totalBooks").toLongLong(), 2);
        QCOMPARE(stats.value("totalReadSeconds").toLongLong(), 6000); // 3600+1800+600
        QCOMPARE(stats.value("totalProgress").toDouble(), 0.375);     // (0.25+0.5)/2
        const QVariantList byCat = stats.value("byCategory").toList();
        QCOMPARE(byCat.size(), 2);
        QCOMPARE(byCat.at(0).toMap().value("name").toString(), QString("古典"));
        QCOMPARE(byCat.at(0).toMap().value("count").toLongLong(), 1);
        QCOMPARE(byCat.at(1).toMap().value("name").toString(), QString("科幻"));
        QCOMPARE(byCat.at(1).toMap().value("count").toLongLong(), 1);
    }
    void statsEmptyLibraryIsZeroed() {
        // D4：空库（0 书）不崩——COUNT=0、SUM/AVG 为 NULL 时 COALESCE 归零、byCategory 为空
        BookManager empty(":memory:", "readdict_stats_empty");
        const QVariantMap stats = empty.stats();
        QCOMPARE(stats.value("totalBooks").toLongLong(), 0);
        QCOMPARE(stats.value("totalReadSeconds").toLongLong(), 0);
        QCOMPARE(stats.value("totalProgress").toDouble(), 0.0);
        QVERIFY(stats.value("byCategory").toList().isEmpty());
    }
    void statsIncludesUncategorizedBooks() {
        // D4：未分类书（category=''）计入 byCategory（name 为空串），计数与 totalBooks 对齐
        m_mgr->addBook(Book{-1, "无分类书", "某作者", "某社", "", "TXT", "/tmp/nocat.txt", QString(), 0.0});
        const QVariantMap stats = m_mgr->stats();
        QCOMPARE(stats.value("totalBooks").toLongLong(), 3);
        const QVariantList byCat = stats.value("byCategory").toList();
        QCOMPARE(byCat.size(), 3); // 古典、科幻、空分类
        QCOMPARE(byCat.at(0).toMap().value("name").toString(), QString()); // '' 排最前
        QCOMPARE(byCat.at(0).toMap().value("count").toLongLong(), 1);
    }
    void stopTrackingWithoutStartIsNoop() {
        m_mgr->stopTracking(); // 未 start 时调用无副作用（不崩溃、不写负数）
        QCOMPARE(m_mgr->bookById(1).readSeconds, 0);
        m_mgr->stopTracking();
        QCOMPARE(m_mgr->bookById(1).readSeconds, 0);
    }
    void dedupesDuplicateTxtChapterTitles() {
        // C7b：TXT 重复 h2 标题 → chapterTitles 兜底为 "第N章"，标题全唯一；
        // loadChapter 标题与 chapterTitles 同源（划线键 "章节标题|句索引" 才能对上）
        const qint64 id = m_mgr->addBook(Book{-1, "dup", "作者", "出版社", "", "TXT",
            QStringLiteral(EPUB_FIXTURES_DIR) + "/dup-titles.txt", QString(), 0.0});
        const QVariantList titles = m_mgr->chapterTitles(id);
        QCOMPARE(titles.size(), 4);
        QCOMPARE(titles.at(0).toString(), QString("dup-titles")); // 首章 = 文件名（唯一）
        QCOMPARE(titles.at(1).toString(), QString("第一章"));      // 首个 h2 保留
        // 重复 h2 章兜底为序号章名，且不与既有标题冲突
        QSet<QString> seen;
        for (const QVariant &t : titles) {
            const QString s = t.toString();
            QVERIFY2(!s.isEmpty(), qPrintable("标题不应为空：" + s));
            QVERIFY2(!seen.contains(s), qPrintable("标题应唯一，重复：" + s));
            seen.insert(s);
        }
        for (int i = 0; i < titles.size(); ++i)
            QCOMPARE(m_mgr->loadChapter(id, i).toMap().value("title").toString(),
                     titles.at(i).toString());
    }
    void fallbackForEmptyFb2Titles() {
        // C7b：FB2 无 <title> 的 section → 空标题兜底为 "第N章"（对齐 EPUB/MOBI 行为）
        const qint64 id = m_mgr->addBook(Book{-1, "empty", "作者", "出版社", "", "FB2",
            QStringLiteral(EPUB_FIXTURES_DIR) + "/empty-title.fb2", QString(), 0.0});
        const QVariantList titles = m_mgr->chapterTitles(id);
        QCOMPARE(titles.size(), 3);
        QCOMPARE(titles.at(0).toString(), QString("第1章"));
        QCOMPARE(titles.at(1).toString(), QString("第2章"));
        QCOMPARE(titles.at(2).toString(), QString("第3章"));
        for (int i = 0; i < titles.size(); ++i)
            QCOMPARE(m_mgr->loadChapter(id, i).toMap().value("title").toString(),
                     titles.at(i).toString());
    }
    void resolvesAllBundledFonts() {
        // D4：加载 bundled 字体后，resolveFontFamily 应把 4 个存储 token 映射到实际字族：
        // 宋体/黑体走英文族名回退链、HW 变体命中独立字族、得意黑映射 Smiley Sans。
        // 测试 cwd 为 build/tests（ctest 默认），../../fronts 即仓库字体目录；
        // 从仓库根手动运行则 fronts/ 命中（双候选互备）。
        const QStringList rels = {
            QStringLiteral("02_SourceHanSans-VF/02_SourceHanSans-VF/Variable/SourceHanSans-VF.otf.ttc"),
            QStringLiteral("02_SourceHanSans-VF/02_SourceHanSans-VF/Variable/SourceHanSansHW-VF.otf.ttc"),
            QStringLiteral("02_SourceHanSerif-VF/02_SourceHanSerif-VF/Variable/SourceHanSerif-VF.otf.ttc"),
            QStringLiteral("smiley-sans-v2.0.1/SmileySans-Oblique.otf"),
        };
        QString base = QDir::current().filePath(QStringLiteral("fronts"));
        if (!QDir(base).exists()) base = QDir::current().filePath(QStringLiteral("../../fronts"));
        if (!QDir(base).exists())
            QSKIP("未找到仓库 fronts 字体目录（cwd=" + QDir::current().path().toUtf8() + "），跳过字体映射验证");
        int loaded = 0;
        for (const QString &rel : rels) {
            if (QFontDatabase::addApplicationFont(base + "/" + rel) >= 0)
                ++loaded;
        }
        if (loaded < 4)
            QSKIP("bundled 字体加载不完整，跳过字体映射验证");
        // 4 族实际字族名都应在（CoreText 只暴露英文族名）
        QVERIFY(QFontDatabase::hasFamily(QStringLiteral("Source Han Serif VF")));
        QVERIFY(QFontDatabase::hasFamily(QStringLiteral("Source Han Sans VF")));
        QVERIFY(QFontDatabase::hasFamily(QStringLiteral("Source Han Sans HW VF")));
        QVERIFY(QFontDatabase::hasFamily(QStringLiteral("Smiley Sans")));
        // 中文族名可能直接命中（系统已装同名族）——命中时返回首选值，否则回退英文族名
        const QString serif = QFontDatabase::hasFamily(QStringLiteral("思源宋体 VF"))
            ? QStringLiteral("思源宋体 VF") : QStringLiteral("Source Han Serif VF");
        const QString sans = QFontDatabase::hasFamily(QStringLiteral("思源黑体 VF"))
            ? QStringLiteral("思源黑体 VF") : QStringLiteral("Source Han Sans VF");
        const QString smiley = QFontDatabase::hasFamily(QStringLiteral("得意黑"))
            ? QStringLiteral("得意黑") : QStringLiteral("Smiley Sans");
        QCOMPARE(m_mgr->resolveFontFamily(QStringLiteral("思源宋体 VF")), serif);
        QCOMPARE(m_mgr->resolveFontFamily(QStringLiteral("思源黑体 VF")), sans);
        // HW 变体：独立字族优先于通用无衬线链（旧实现会静默回退成非 HW 黑体）
        QCOMPARE(m_mgr->resolveFontFamily(QStringLiteral("SourceHanSansHW-VF")),
                 QStringLiteral("Source Han Sans HW VF"));
        QCOMPARE(m_mgr->resolveFontFamily(QStringLiteral("得意黑")), smiley);
    }
private:
    std::unique_ptr<QTemporaryDir> m_tmp;
    std::unique_ptr<SettingsStore> m_settings;
    std::unique_ptr<BookManager> m_mgr;
};
QTEST_MAIN(TestBookManager)
#include "tst_bookmanager.moc"
