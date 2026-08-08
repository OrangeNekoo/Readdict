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
        // 等章节布局收敛：loadChapter 后 contentHeight 首趟可能仍是旧章残留值
        //（Repeater 布局在事件循环 polish 阶段才更新，直接读会算错 maxY——
        // 内容变矮时 Flickable 会把 contentY 钳回）。轮询到高度连续两次采样
        // 一致（50ms 间隔）且 > 视口高为止。
        function waitContentSettled(cv) {
            var last = -1
            var stable = 0
            var t0 = new Date().getTime()
            while (new Date().getTime() - t0 < 5000) {
                var h = cv.contentHeight
                if (Math.abs(h - last) < 0.5) stable++
                else stable = 0
                if (stable >= 2 && h > cv.height) return true
                last = h
                wait(50)
            }
            return cv.contentHeight > cv.height
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
            // 首页 ←/↑ 不越界（autoPrevChapter 首章兜底不换，contentY 保持 0）
            cv.contentY = 0
            cv.handleKey(Qt.Key_Left, Qt.NoModifier)
            cv.handleKey(Qt.Key_Up, Qt.NoModifier)
            wait(450)
            verify(cv.contentY === 0, "paged 首页 ←/↑ 应兜底不换，实际 " + cv.contentY)
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

        // E4 复审：paged 模式 ← 章首回上一章——pagePrev 在 contentY=0 时不再死键，
        // 转 requestPrevChapter → ReaderPage.autoPrevChapter（与 pageNext 章末翻章对称）；
        // 首章章首 ← 由 autoPrevChapter 兜底不换。
        function test_pagedPrevChapterAtChapterStart() {
            var book = findBook("multibook")
            verify(book !== null, "multibook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            page.pageMode = "paged"
            var titles = Books.chapterTitles(book.id)
            verify(titles.length >= 3, "multibook 应有 3 章，实际 " + titles.length)
            Books.currentChapter = 1
            page.loadChapter(1)
            tryVerify(function () { return cv.contentHeight > cv.height }, 3000,
                      "章 1 内容高度应就绪（contentHeight=" + cv.contentHeight + "）")
            cv.contentY = 0
            wait(50)
            // 章首 ← → 上一章（旧实现 contentY=0 直接 return，← 为死键）
            cv.handleKey(Qt.Key_Left, Qt.NoModifier)
            tryVerify(function () { return Books.currentChapter === 0 }, 3000,
                      "paged 章首 ← 应回上一章，实际 currentChapter=" + Books.currentChapter)
            // 首章章首 ← 兜底不换（autoPrevChapter 边界）
            cv.handleKey(Qt.Key_Left, Qt.NoModifier)
            wait(100)
            compare(Books.currentChapter, 0, "paged 首章章首 ← 应兜底不换")
            h.stack.destroy()
        }

        // E4 复审：键盘按住自动重复（isAutoRepeat，30-60Hz）不连翻多章——scroll 模式
        // ←/→ 与 paged 模式章末翻章只响应首次按下；内容位移（翻页）重复无害。
        function test_autoRepeatThrottlesChapterChange() {
            var book = findBook("multibook")
            verify(book !== null, "multibook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            // scroll 模式：章 0 按住 →（autoRepeat）不应翻章；正常按下才翻
            Books.currentChapter = 0
            page.loadChapter(0)
            wait(100)
            cv.handleKey(Qt.Key_Right, Qt.NoModifier, true)
            wait(100)
            compare(Books.currentChapter, 0, "scroll 按住 → 自动重复不应翻章")
            cv.handleKey(Qt.Key_Right, Qt.NoModifier, false)
            tryVerify(function () { return Books.currentChapter === 1 }, 3000,
                      "scroll 正常按下 → 应翻章，实际 currentChapter=" + Books.currentChapter)
            // paged 模式：章 1 翻到章末最后一页——逐页按 →（pageNext 动画路径，
            // 每按等 450ms 动画收敛；不用直设 contentY=maxY：连续 loadChapter 后
            // Flickable 内部状态会把直设的非页边界值在下一帧重置回 0，动画路径免疫）
            page.pageMode = "paged"
            page.loadChapter(1)
            verify(waitContentSettled(cv),
                   "章 1 内容高度应就绪并收敛（contentHeight=" + cv.contentHeight + "）")
            var maxY = Math.max(0, cv.contentHeight - cv.height)
            var guard = 0
            while (guard++ < 10) {
                cv.handleKey(Qt.Key_Right, Qt.NoModifier)
                wait(450)
                if (cv.contentY >= maxY - 2) break
            }
            verify(cv.contentY >= maxY - 2,
                   "pageNext 应推进到章末最后一页（contentY=" + cv.contentY + "，maxY=" + maxY + "）")
            // 章末按住 →（autoRepeat）不应翻章；正常按下才翻
            cv.handleKey(Qt.Key_Right, Qt.NoModifier, true)
            wait(100)
            compare(Books.currentChapter, 1, "paged 章末按住 → 自动重复不应翻章")
            cv.handleKey(Qt.Key_Right, Qt.NoModifier, false)
            tryVerify(function () { return Books.currentChapter === 2 }, 3000,
                      "paged 章末正常按下 → 应翻章，实际 currentChapter=" + Books.currentChapter)
            h.stack.destroy()
        }

        // E4 复审：paged 模式滚轮吸附——滚轮滚动改变 contentY 但不触发 movementEnded，
        // 靠 onContentYChanged 的 snapTimer（200ms 收敛）补吸附到最近页边界；
        // snapToPage 内部有 ttsActive/恢复窗口门控（此处 ttsActive=false 且恢复已关）。
        function test_pagedWheelSnapToPageBoundary() {
            var book = findBook("longbook")
            verify(book !== null, "longbook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            page.pageMode = "paged"
            tryVerify(function () { return cv.contentHeight > cv.height * 2 }, 3000,
                      "longbook 内容应远超视口")
            var pageH = cv.height
            cv.contentY = 0
            wait(50)
            // 模拟滚轮：contentY 落到非页边界（pageH*0.5+10 → 最近页边界 pageH）
            cv.contentY = pageH * 0.5 + 10
            tryVerify(function () { return Math.abs(cv.contentY - pageH) < 4 }, 3000,
                      "contentY 收敛后应吸附到最近页边界（期望 " + pageH
                      + "，实际 " + cv.contentY + "）")
            h.stack.destroy()
        }

        // E4 复审：动画互斥——pageAnim 启动前先停 followAnim（两动画驱动同一
        // contentY，并发会让目标互相覆盖）；followAnim 由 TTS 跟随/搜索跳转驱动。
        function test_pageAnimStopsFollowAnim() {
            var book = findBook("longbook")
            verify(book !== null, "longbook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            page.pageMode = "paged"
            tryVerify(function () { return cv.contentHeight > cv.height * 2 }, 3000,
                      "longbook 内容应远超视口")
            cv.contentY = 0
            // 启动 followAnim（TTS 跟随路径；段 50 的 y 远超视口 1/3，目标非 0 不会瞬停）
            cv.followSentence(50)
            verify(cv.followAnimation.running === true, "followAnim 应已启动")
            // 键盘翻页启动 pageAnim → followAnim 必须先停（互斥断言）
            cv.handleKey(Qt.Key_Right, Qt.NoModifier)
            verify(cv.pageAnimation.running === true, "pageAnim 应运行")
            verify(cv.followAnimation.running === false,
                   "pageAnim 启动前 followAnim 应被停止")
            wait(450)
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
