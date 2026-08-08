import QtQuick
import QtQuick.Controls
import QtTest
import Readdict.Backend
import Readdict.Test 1.0

// E4：方向键翻页 + 横向翻页模式冒烟。
// 方向键：scroll 模式 ↑↓/PageUp/PageDown 滚动一视口页、←/→ 翻章（边界不越）；
// paged 模式四向 + PageUp/PageDown 按视口高度整页翻动（←/→ 翻页而非翻章）。
// 键盘注入：直接调用 contentView.handleKey（Keys.onPressed 委托同一函数——
// quicktest harness 无法可靠合成键盘事件，同 C7 选择注入取舍；Keys 接线是
// 一行委托，由评审核对）。
// 动画收敛：翻页动画 300ms，每次按键后 wait(450) 等动画完全结束再断言/再按
//（tryVerify 会在动画中途通过，紧接着的按键会基于中途位置计算页号 → 误判，
// 故统一用 wait 收敛而非 tryVerify 中途值）。
// 结构约定（同 tst_readerpage）：根为带尺寸的 Item，ReaderPage 经 StackView
// push（生产路径）；用 TestEnv.longSource（300 段单章，内容远高于视口，
// 可滚动多页）与 TestEnv.multiSource（3 章，可翻章）验证。
Item {
    id: root
    width: 1100; height: 720

    TestCase {
        name: "ArrowKeyPagingSmoke"

        function initTestCase() {
            if (Books.booksModel.length === 0)
                for (let f of TestEnv.sourceFiles) Importer.doImport(f)
            Importer.doImport(TestEnv.longSource)
            Importer.doImport(TestEnv.multiSource)
            // 翻页方式默认竖滚（避免上一用例残留 paged 污染本用例）
            Settings.setValue("reading/pageMode", "scroll")
        }
        function cleanupTestCase() {
            Settings.setValue("reading/pageMode", "scroll")
            // 清理本文件导入的长书：tst_highlightsui 的 findTxtBook() 取最新 TXT
            //（booksModel added_at DESC），且 loadChapter 持久化 progress/<bookId>，
            // 不删会让后续用例拿到 longbook/multibook 并打开错误章节（全量回归失败源）
            for (let b of Books.booksModel)
                if (b.title === "longbook" || b.title === "multibook")
                    Books.removeBookWithFiles(b.id, true)
        }
        function findBook(title) {
            for (let b of Books.booksModel)
                if (b.title === title) return b
            return null
        }
        function openPage(book) {
            var stack = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; StackView { anchors.fill: parent; }", root)
            verify(stack !== null, "测试 StackView 应能创建")
            stack.push("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: book })
            var page = stack.currentItem
            verify(page !== null, "ReaderPage 应被 push 进 StackView")
            tryVerify(function () {
                return page.chapter && page.chapter.paragraphs
                    && page.chapter.paragraphs.length > 0
            }, 3000, "打开书后应加载章节段落")
            // E4：取消滚动恢复——恢复 Timer（200ms 收敛后 applyRestore）会在翻页
            // 动画中途把 contentY 拽回保存位置，干扰方向键/翻页断言；本用例
            // 从 0 起翻，显式关闭恢复（restoreScrollY=-1 + restorePending=false，
            // applyRestore 对非 pending 直接 return）。
            page.contentView.restoreScrollY = -1
            page.contentView.restorePending = false
            return { stack: stack, page: page }
        }

        // scroll 模式：↓ 滚动一视口页（contentY += 视口高），↑ 回退；PageDown/PageUp 同语义
        function test_arrowScrollsViewportPage() {
            var book = findBook("longbook")
            verify(book !== null, "longbook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            tryVerify(function () { return cv.contentHeight > cv.height * 2 }, 3000,
                      "longbook 内容应远超视口（contentHeight=" + cv.contentHeight
                      + "，height=" + cv.height + "）")
            var pageH = cv.height
            cv.contentY = 0
            // ↓ 翻一视口页（动画 300ms → wait 收敛）
            cv.handleKey(Qt.Key_Down, Qt.NoModifier)
            wait(450)
            verify(Math.abs(cv.contentY - pageH) < 4,
                   "↓ 应滚动一视口页，实际 contentY=" + cv.contentY + "（期望 " + pageH + "）")
            // PageDown 同语义（再翻一页）
            cv.handleKey(Qt.Key_PageDown, Qt.NoModifier)
            wait(450)
            verify(Math.abs(cv.contentY - 2 * pageH) < 4,
                   "PageDown 应再滚动一视口页，实际 contentY=" + cv.contentY)
            // ↑ 回退一页（回到上一页起点）
            cv.handleKey(Qt.Key_Up, Qt.NoModifier)
            wait(450)
            verify(Math.abs(cv.contentY - pageH) < 4,
                   "↑ 应回退一视口页，实际 contentY=" + cv.contentY)
            // 首页边界：回退到 0 后继续 ↑ 不越界
            cv.contentY = 0
            cv.handleKey(Qt.Key_Up, Qt.NoModifier)
            wait(450)
            verify(cv.contentY === 0, "首页 ↑ 应钳制在 0，实际 " + cv.contentY)
            h.stack.destroy()
        }

        // scroll 模式：→ 翻下一章、← 翻上一章；边界（首章 ← / 末章 →）不越
        function test_arrowSwitchesChapters() {
            var book = findBook("multibook")
            verify(book !== null, "multibook 应已导入")
            var h = openPage(book)
            var page = h.page
            var titles = Books.chapterTitles(book.id)
            verify(titles.length >= 3, "multibook 应有 3 章，实际 " + titles.length)
            Books.currentChapter = 0
            page.loadChapter(0)
            wait(100)
            // → 下一章
            page.contentView.handleKey(Qt.Key_Right, Qt.NoModifier)
            tryVerify(function () { return Books.currentChapter === 1 }, 3000,
                      "→ 应翻到下一章，实际 currentChapter=" + Books.currentChapter)
            // ← 回上一章
            page.contentView.handleKey(Qt.Key_Left, Qt.NoModifier)
            tryVerify(function () { return Books.currentChapter === 0 }, 3000,
                      "← 应翻回上一章，实际 currentChapter=" + Books.currentChapter)
            // 首章 ← 不越界（loadChapter(-1) 钳制到 0）
            page.contentView.handleKey(Qt.Key_Left, Qt.NoModifier)
            wait(100)
            compare(Books.currentChapter, 0, "首章 ← 应钳制在 0")
            // 末章 → 不越界（autoNextChapter 末章兜底）
            page.loadChapter(titles.length - 1)
            wait(100)
            page.contentView.handleKey(Qt.Key_Right, Qt.NoModifier)
            wait(100)
            compare(Books.currentChapter, titles.length - 1, "末章 → 应钳制在末章")
            h.stack.destroy()
        }
    }

    TestCase {
        name: "PagedModeSmoke"

        function initTestCase() {
            if (Books.booksModel.length === 0)
                for (let f of TestEnv.sourceFiles) Importer.doImport(f)
            Importer.doImport(TestEnv.longSource)
            Importer.doImport(TestEnv.multiSource)
            Settings.setValue("reading/pageMode", "scroll")
        }
        function cleanupTestCase() {
            Settings.setValue("reading/pageMode", "scroll")
            // 同 ArrowKeyPagingSmoke：清理本文件导入的长书，避免污染后续用例
            //（findTxtBook 取最新 TXT + progress 持久化影响打开章节）
            for (let b of Books.booksModel)
                if (b.title === "longbook" || b.title === "multibook")
                    Books.removeBookWithFiles(b.id, true)
        }
        function findBook(title) {
            for (let b of Books.booksModel)
                if (b.title === title) return b
            return null
        }
        function openPage(book) {
            var stack = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; StackView { anchors.fill: parent; }", root)
            verify(stack !== null, "测试 StackView 应能创建")
            stack.push("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: book })
            var page = stack.currentItem
            verify(page !== null, "ReaderPage 应被 push 进 StackView")
            tryVerify(function () {
                return page.chapter && page.chapter.paragraphs
                    && page.chapter.paragraphs.length > 0
            }, 3000, "打开书后应加载章节段落")
            // E4：取消滚动恢复（同 ArrowKeyPagingSmoke.openPage，避免恢复 Timer
            // 在翻页动画中途拽回 contentY）
            page.contentView.restoreScrollY = -1
            page.contentView.restorePending = false
            return { stack: stack, page: page }
        }

        // 横翻：→/↓ 整页前进（contentY 到视口高度的整数倍页边界）、←/↑ 回退
        function test_pagedModeTurnsPages() {
            var book = findBook("longbook")
            verify(book !== null, "longbook 应已导入")
            var h = openPage(book)
            var page = h.page
            page.pageMode = "paged"
            var cv = page.contentView
            compare(cv.pageMode, "paged", "pageMode 应注入 ReaderContent")
            tryVerify(function () { return cv.contentHeight > cv.height * 2 }, 3000,
                      "longbook 内容应远超视口")
            cv.contentY = 0
            var pageH = cv.height
            // → 翻到第 1 页边界（≈ 1 × 视口高）
            cv.handleKey(Qt.Key_Right, Qt.NoModifier)
            wait(450)
            verify(Math.abs(cv.contentY - pageH) < 4,
                   "paged → 应定位到第 1 页边界，实际 contentY=" + cv.contentY
                   + "（页高 " + pageH + "）")
            // ↓ 同语义 → 第 2 页边界
            cv.handleKey(Qt.Key_Down, Qt.NoModifier)
            wait(450)
            verify(Math.abs(cv.contentY - 2 * pageH) < 4,
                   "paged ↓ 应定位到第 2 页边界，实际 contentY=" + cv.contentY)
            // ← 回退 → 第 1 页边界
            cv.handleKey(Qt.Key_Left, Qt.NoModifier)
            wait(450)
            verify(Math.abs(cv.contentY - pageH) < 4,
                   "paged ← 应回退到第 1 页边界，实际 contentY=" + cv.contentY)
            // 首页 ←/↑ 不越界
            cv.contentY = 0
            cv.handleKey(Qt.Key_Left, Qt.NoModifier)
            cv.handleKey(Qt.Key_Up, Qt.NoModifier)
            wait(450)
            verify(cv.contentY === 0, "paged 首页 ←/↑ 应钳制在 0，实际 " + cv.contentY)
            h.stack.destroy()
        }

        // 横翻：章末页再 → 翻过章末进入下一章（真实书籍语义）；末章 → 不越
        function test_pagedModeLastPageAdvancesChapter() {
            var book = findBook("multibook")
            verify(book !== null, "multibook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            page.pageMode = "paged"
            var titles = Books.chapterTitles(book.id)
            Books.currentChapter = 0
            page.loadChapter(0)
            // 等新章内容高度就绪（loadChapter 后布局异步，直接读 contentHeight 可能为 0）
            tryVerify(function () { return cv.contentHeight > cv.height }, 3000,
                      "章 0 内容高度应就绪（contentHeight=" + cv.contentHeight + "）")
            // 直接定位到章末（contentY = maxY），再 → 应翻章而非停在章末
            var maxY = cv.contentHeight - cv.height
            cv.contentY = maxY
            wait(50)
            cv.handleKey(Qt.Key_Right, Qt.NoModifier)
            tryVerify(function () { return Books.currentChapter === 1 }, 3000,
                      "paged 章末再 → 应进入下一章，实际 currentChapter=" + Books.currentChapter)
            // 末章章末 → 不越（autoNextChapter 兜底）
            page.loadChapter(titles.length - 1)
            tryVerify(function () { return cv.contentHeight > cv.height }, 3000,
                      "末章内容高度应就绪")
            maxY = cv.contentHeight - cv.height
            cv.contentY = Math.max(0, maxY)
            wait(50)
            cv.handleKey(Qt.Key_Right, Qt.NoModifier)
            wait(100)
            compare(Books.currentChapter, titles.length - 1, "paged 末章章末 → 应钳制在末章")
            h.stack.destroy()
        }

        // 模式持久化：设置页写 reading/pageMode → 重开 ReaderPage 生效
        function test_pagedModePersists() {
            Settings.setValue("reading/pageMode", "paged")
            var book = findBook("longbook")
            verify(book !== null, "longbook 应已导入")
            var h = openPage(book)
            var page = h.page
            compare(page.pageMode, "paged", "重开阅读页应读取 reading/pageMode=paged")
            compare(page.contentView.pageMode, "paged", "content 应继承 paged 模式")
            h.stack.destroy()
            Settings.setValue("reading/pageMode", "scroll")
            // 改回 scroll 重开 → 竖滚
            var h2 = openPage(book)
            compare(h2.page.pageMode, "scroll", "改回 scroll 后重开应生效")
            h2.stack.destroy()
        }

        // 设置页入口：翻页方式单选切换 → reading/pageMode 持久化 + 恢复选中。
        // 程序化 checked=true / toggle() 不触发 onToggled（Qt 6.11 实测，同背景
        // 模式单选取舍）→ 用 mouseClick 模拟真实点击驱动写入。
        function test_settingsPageModeEntry() {
            var loader = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; Loader { source: \"qrc:/qt/qml/Readdict/ui/qml/SettingsPage.qml\"; }", root)
            verify(loader.item !== null, "SettingsPage 应能加载")
            loader.width = 1100; loader.height = 720
            var sp = loader.item
            verify(sp.pageModeScrollRadio !== undefined && sp.pageModePagedRadio !== undefined,
                   "设置页应暴露翻页方式单选句柄")
            // 初始：默认 scroll 选中
            verify(sp.pageModeScrollRadio.checked, "默认应选中连续滚动")
            // 滚动到翻页方式单选可见（mouseClick 要求目标在窗口内，同背景单选先例）
            var fl = sp.settingsScroll.contentItem
            fl.contentY = Math.max(0, sp.pageModePagedRadio.mapToItem(fl, 0, 0).y - 80)
            wait(100)
            // 切整页翻动 → 写 reading/pageMode=paged
            mouseClick(sp.pageModePagedRadio, sp.pageModePagedRadio.width / 2,
                       sp.pageModePagedRadio.height / 2)
            compare(String(Settings.value("reading/pageMode")), "paged",
                    "点整页翻动应写 reading/pageMode=paged")
            // 切回连续滚动
            mouseClick(sp.pageModeScrollRadio, sp.pageModeScrollRadio.width / 2,
                       sp.pageModeScrollRadio.height / 2)
            compare(String(Settings.value("reading/pageMode")), "scroll",
                    "点连续滚动应写 reading/pageMode=scroll")
            // 恢复 paged 后重载设置页 → 选中态恢复
            Settings.setValue("reading/pageMode", "paged")
            var loader2 = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; Loader { source: \"qrc:/qt/qml/Readdict/ui/qml/SettingsPage.qml\"; }", root)
            loader2.width = 1100; loader2.height = 720
            verify(loader2.item.pageModePagedRadio.checked,
                   "reading/pageMode=paged 时重载设置页应选中整页翻动")
            loader2.destroy()
            loader.destroy()
            Settings.setValue("reading/pageMode", "scroll")
        }
    }
}
