import QtQuick
import QtQuick.Pdf
import QtTest
import Readdict.Backend
import Readdict.Test 1.0

// 冒烟测试：真实 UI 组件可在测试进程中加载（Loader + qrc 资源路径，
// 单例由 tst_qmlmain.cpp 注册）。
Item {
    id: root
    width: 1100; height: 720
    Component {
        id: shelfComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/ShelfPage.qml" }
    }
    Component {
        id: cardComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/BookCard.qml" }
    }
    Component {
        id: readerComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml" }
    }
    Component {
        id: contentComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/ReaderContent.qml" }
    }
    Component {
        id: controlsComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/ReaderControls.qml" }
    }
    Component {
        id: pdfReaderComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/PdfReaderPage.qml" }
    }
    TestCase {
        name: "PdfReaderSmoke"
        function test_pdfReaderLoads() {
            var loader = pdfReaderComp.createObject(root)
            verify(loader.item !== null, "PdfReaderPage 应能加载（QtQuick.Pdf import + PdfScrollablePageView 编译检查）")
            loader.destroy()
        }
        // 真实 PDF 加载验证：TestEnv.pdfSource 为空（未设 READDICT_REAL_PDF）时跳过；
        // 否则加载真实文件并等待 PdfDocument Ready，确认 QtPdf 渲染管线可用
        function test_pdfLoadsRealSource() {
            var src = TestEnv.pdfSource
            if (src.length === 0)
                skip("未设置 READDICT_REAL_PDF，跳过真实 PDF 加载验证")
            var loader = pdfReaderComp.createObject(root)
            var page = loader.item
            verify(page !== null, "PdfReaderPage 应能加载")
            page.book = { id: 999001, title: "真实PDF", path: src }
            var doc = page.pdfDocument
            verify(doc !== null, "PdfReaderPage 应暴露 pdfDocument")
            tryVerify(function () { return doc.status === PdfDocument.Ready }, 15000,
                      "真实 PDF 应加载为 Ready，实际 " + doc.status)
            verify(doc.pageCount > 0, "加载的 PDF 应有页数")
            // 30MB 大 PDF 首帧渲染可能仍在进行：等渲染完成再销毁，避免 QtPdfQuick 拆除竞态崩溃
            tryVerify(function () { return page.pdfView.status === Image.Ready }, 15000,
                      "首页渲染应完成，实际 " + page.pdfView.status)
            loader.destroy()
        }
        // B10：PDF 进度恢复——Ready 后应先 goToPage(保存页)，且 Ready 时的
        // 首次 currentPageChanged(0) 不得覆盖保存值（restoreDone 标志门控写入）
        function test_pdfRestoresPage() {
            var src = TestEnv.pdfSource
            if (src.length === 0)
                skip("未设置 READDICT_REAL_PDF，跳过 PDF 进度恢复验证")
            var id = 999002 // 独立 bookId，避免与 test_pdfLoadsRealSource 的 999001 互相污染
            Settings.setValue("progress/pdf_" + id, 3)
            var loader = pdfReaderComp.createObject(root)
            var page = loader.item
            page.book = { id: id, title: "真实PDF", path: src }
            tryVerify(function () { return page.pdfDocument.status === PdfDocument.Ready }, 15000,
                      "真实 PDF 应加载为 Ready")
            tryVerify(function () { return page.pdfView.currentPage === 3 }, 5000,
                      "恢复后应定位到保存页 3，实际 " + page.pdfView.currentPage)
            compare(Number(Settings.value("progress/pdf_" + id)), 3,
                    "恢复页不应被 Ready 时的初始页 0 覆盖")
            tryVerify(function () { return page.pdfView.status === Image.Ready }, 15000,
                      "恢复页渲染应完成再销毁，实际 " + page.pdfView.status)
            loader.destroy()
        }
    }
    TestCase {
        name: "ShelfSmoke"
        function test_shelfLoads() {
            var loader = shelfComp.createObject(root)
            verify(loader.item !== null, "ShelfPage 应能加载")
            loader.destroy()
        }
    }
    TestCase {
        name: "CardSmoke"
        function test_cardLoads() {
            var loader = cardComp.createObject(root)
            verify(loader.item !== null, "BookCard 应能加载（含右键菜单与分类 Dialog 编译检查）")
            loader.item.book = { id: 1, title: "测试书", cover: "", progress: 0.5 }
            loader.destroy()
        }
    }
    TestCase {
        name: "ReaderSmoke"
        function test_readerLoads() {
            var loader = readerComp.createObject(root)
            verify(loader.item !== null, "ReaderPage 应能加载（含控制栏/目录 Dialog 编译检查）")
            loader.destroy()
        }
        // 本文件在 tst_e2e.qml 之后执行（文件名字典序），此时书库已有导入的 TXT 书；
        // B10 新增的 EPUB/长文本书导入会改变 booksModel 首位，故按 format 显式找 TXT
        function test_loadChapter() {
            var book = null
            for (let b of Books.booksModel)
                if ((b.format || "").toUpperCase() === "TXT") { book = b; break }
            if (!book)
                skip("书库无 TXT 书，跳过章节加载验证")
            var loader = readerComp.createObject(root)
            var page = loader.item
            verify(page !== null, "ReaderPage 应能加载")
            page.book = book
            page.loadChapter(0)
            verify(page.chapter !== null && page.chapter.paragraphs !== undefined,
                   "loadChapter 应返回带 paragraphs 的章节对象")
            verify(page.chapter.paragraphs.length > 0, "TXT 首章应有段落")
            compare(page.chapter.title, page.book.title, "TXT 首章标题应为书名")
            loader.destroy()
        }
    }
    TestCase {
        name: "ContentSmoke"
        // 直接实例化 ReaderContent：运行期验证段落委托（Text 与图片分支）不报错、
        // 排版参数生效、内容高度随段落增长
        function test_rendersParagraphs() {
            var loader = contentComp.createObject(root)
            loader.width = 800
            loader.height = 600
            var c = loader.item
            verify(c !== null, "ReaderContent 应能加载")
            c.typography = { fontFamily: "Source Han Sans VF", fontSize: 18, lineHeight: 1.6,
                             align: "left", pageWidth: "normal" }
            c.chapter = { title: "测试章", paragraphs: [
                { text: "正文段", html: "<p>正文段</p>", level: 0, imagePath: "" },
                { text: "", html: "", level: 0, imagePath: "/nonexistent/b8.png" },
                { text: "前文 图 后文", html: "<p>前文 <img src=\"/nonexistent/b8.png\"> 后文</p>", level: 0, imagePath: "/nonexistent/b8.png" },
                { text: "标题", html: "<h2>标题</h2>", level: 2, imagePath: "" }
            ]}
            wait(50)
            // Flickable 会把声明子项重挂到 contentItem；Repeater 在 positioner（Column）内
            // 又会把委托重挂到 Column，故 col.children[0..3] 依次是 4 个段落委托
            var col = c.contentItem.children[0]        // Column
            var dPure = col.children[1]                // 纯图段委托
            var dMixed = col.children[2]               // 混合段委托
            verify(dPure !== undefined && dPure.pureImage === true,
                   "纯图段应走 Image 分支（pureImage=true）")
            verify(dMixed !== undefined && dMixed.pureImage === false,
                   "混合段应走 Text 分支（html 含 img 之外的正文）")
            var mixedTxt = dMixed.children[0]          // 委托内 Text
            verify(mixedTxt.text.indexOf("前文") >= 0 && mixedTxt.text.indexOf("<img") >= 0
                   && mixedTxt.text.indexOf("file://") >= 0,
                   "混合段 Text 应保留正文、行内图且 src 补 file://，实际 " + mixedTxt.text)
            // 隐式高度依赖布局 polish，轮询等待而非一次性 wait
            tryVerify(function () { return c.contentHeight > 0 }, 2000,
                      "内容高度应随段落增长，实际 " + c.contentHeight)
            // 页宽三档 + 对齐切换应无运行时错误且宽度变化生效
            c.typography = { fontFamily: "Source Han Sans VF", fontSize: 20, lineHeight: 1.8,
                             align: "center", pageWidth: "wide" }
            tryVerify(function () { return c.contentHeight > 0 }, 2000,
                      "切换排版后内容高度仍应大于 0")
            loader.destroy()
        }
    }
    TestCase {
        name: "ControlsSmoke"
        // 锁定字号按钮接线（回归：A+ 曾误调 fontSize 属性的自动变更信号导致只减不增）
        function test_fontButtons() {
            var loader = controlsComp.createObject(root)
            var ctl = loader.item
            verify(ctl !== null, "ReaderControls 应能加载")
            ctl.fontSize = 18
            var got = -1
            ctl.changeFontSize.connect(function (s) { got = s })
            // RowLayout 子项顺序：0上一章 1目录 2spacer 3A− 4字号label 5A+ 6背景 7对齐 8页宽 9下一章
            var layout = ctl.children[1]
            var btnAplus = layout.children[5]
            btnAplus.clicked()
            compare(got, 19, "A+ 应发 changeFontSize(fontSize+1)")
            layout.children[3].clicked()
            compare(got, 17, "A− 应发 changeFontSize(fontSize-1)")
            loader.destroy()
        }
    }
    TestCase {
        name: "ReaderRestore"
        // B10：进度恢复与阅读计时端到端冒烟——真实 ReaderPage 组件生命周期
        // （onCompleted 恢复章节/滚动/计时，onDestruction 保存滚动/结算计时）。
        // 多章节 EPUB fixture（sample.epub，2 章）验证章节恢复；长文本书验证滚动恢复。
        function initTestCase() {
            if (TestEnv.epubFixture.length > 0)
                Importer.doImport(TestEnv.epubFixture)
            if (TestEnv.longSource.length > 0)
                Importer.doImport(TestEnv.longSource)
        }
        function findBook(fmt, titlePart) {
            for (let b of Books.booksModel)
                if ((b.format || "").toUpperCase() === fmt && (titlePart === "" || b.title.indexOf(titlePart) >= 0))
                    return b
            return null
        }
        // 打开阅读页（模拟生产 StackView.push(…, {book})）：setSource 初始属性在
        // onCompleted 前应用，保证章节加载/滚动恢复/计时都在 book 就绪后执行
        function openReader(book) {
            var loader = readerComp.createObject(root)
            loader.setSource("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: book })
            var page = loader.item
            verify(page !== null, "ReaderPage 应能加载")
            return loader
        }
        function test_chapterRestore() {
            var book = findBook("EPUB", "")
            if (!book) skip("未导入 EPUB fixture")
            // 打开 → 翻到第 2 章 → 销毁（模拟退出）→ 重开应恢复到第 2 章
            var loader = openReader(book)
            var page = loader.item
            tryVerify(function () { return page.chapter.paragraphs && page.chapter.paragraphs.length > 0 }, 5000,
                      "打开应加载章节")
            page.loadChapter(1)
            compare(page.chapter.title, "第二章", "翻到第二章")
            loader.destroy()
            wait(100) // QML destroy() 延迟到事件循环：等 onDestruction 的保存先落地
            var loader2 = openReader(book)
            var page2 = loader2.item
            tryVerify(function () { return page2.chapter.paragraphs && page2.chapter.paragraphs.length > 0 }, 5000,
                      "重开应加载章节")
            compare(page2.chapter.title, "第二章", "重开应恢复到第二章")
            loader2.destroy()
        }
        // 书架进度百分比联动：loadChapter 换章后 books.progress = 章节数/总章节数
        function test_progressPercent() {
            var book = findBook("EPUB", "")
            if (!book) skip("未导入 EPUB fixture")
            Books.loadChapter(book.id, 1)
            var cur = findBook("EPUB", "")
            verify(cur !== null && Math.abs(cur.progress - 1.0) < 0.01,
                   "第 2 章 / 共 2 章 进度应为 1.0，实际 " + (cur ? cur.progress : "?"))
            Books.loadChapter(book.id, 0)
            cur = findBook("EPUB", "")
            verify(cur !== null && Math.abs(cur.progress - 0.5) < 0.01,
                   "第 1 章 / 共 2 章 进度应为 0.5，实际 " + (cur ? cur.progress : "?"))
        }
        function test_scrollRestore() {
            var book = findBook("TXT", "longbook")
            if (!book) skip("未导入长文本书")
            var loader = openReader(book)
            var page = loader.item
            tryVerify(function () { return page.contentView.contentHeight > 2000 }, 5000,
                      "长文本书内容高度应远大于视口")
            page.contentView.contentY = 400
            var savedY = page.contentView.contentY
            verify(savedY > 300, "滚动值应生效，实际 " + savedY)
            loader.destroy() // onDestruction 保存 scroll_<bookId>
            wait(100) // 等延迟销毁完成、滚动位置写入 settings.json
            var loader2 = openReader(book)
            var page2 = loader2.item
            tryVerify(function () {
                return Math.abs(page2.contentView.contentY - savedY) < 1
            }, 5000, "重开应恢复到保存的滚动位置 " + savedY + "，实际 " + page2.contentView.contentY)
            loader2.destroy()
        }
        // 阅读计时：打开页面 mock 阅读 1.2 秒，销毁后 read_seconds 应增加（后端 QElapsedTimer 实测）
        function test_readSeconds() {
            var book = findBook("TXT", "longbook")
            if (!book) skip("未导入长文本书")
            var before = book.readSeconds
            var loader = openReader(book)
            wait(1200)
            loader.destroy() // onDestruction → stopTracking 结算
            wait(100) // 等延迟销毁完成、read_seconds 写入数据库
            var after = 0
            for (let b of Books.booksModel)
                if (b.id === book.id) { after = b.readSeconds; break }
            verify(after >= before + 1, "阅读 1.2 秒后 read_seconds 应至少 +1，实际增加 " + (after - before))
        }
        // 真实书验证（READDICT_REAL_EPUB 门控，未设置跳过）：导入 → 翻到第 3 章 → 重开断言恢复
        function test_realEpubChapterRestore() {
            var src = TestEnv.realEpubSource
            if (src.length === 0)
                skip("未设置 READDICT_REAL_EPUB，跳过真实书恢复验证")
            Importer.doImport(src)
            var book = findBook("EPUB", "从零")
            if (!book) skip("真实 EPUB 未导入")
            var loader = openReader(book)
            var page = loader.item
            tryVerify(function () { return page.chapter.paragraphs && page.chapter.paragraphs.length > 0 }, 8000,
                      "真实 EPUB 应能打开并加载章节")
            page.loadChapter(2) // 第 3 章（索引 2）
            var t3 = page.chapter.title
            verify(t3.length > 0, "第 3 章应有标题")
            loader.destroy()
            var loader2 = openReader(book)
            var page2 = loader2.item
            tryVerify(function () { return page2.chapter.paragraphs && page2.chapter.paragraphs.length > 0 }, 8000,
                      "重开应加载章节")
            compare(page2.chapter.title, t3, "重开应恢复到第 3 章（" + t3 + "）")
            loader2.destroy()
        }
    }
}
