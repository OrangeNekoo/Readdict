import QtQuick
import QtQuick.Controls
import QtTest
import Readdict.Backend
import Readdict.Test 1.0

// E4：方向键翻页 + 真正横向分页模式冒烟（任务3）。
// 方向键：scroll 模式 ↑↓/PageUp/PageDown 滚动一视口页、←/→ 翻章（边界不越）；
// paged 模式四向 + PageUp/PageDown 按页宽横向整页翻动（←/→ 翻页而非翻章）——
// 页面沿 x 轴排列：contentWidth > width、翻页改变 contentX、contentY 恒 0 不承担
// 分页职责；pageModel 由稳定单向估算（字符串长度/段落边界/视口几何）生成，无振荡。
// 键盘注入：多数用例直接调用 contentView.handleKey（Keys.onPressed 委托同一函数，
// 状态机单元级驱动）；任务2 起 test_activeFocusAndProductionKeys 用 QtTest keyClick
// 真实按键走生产 Keys.onPressed → handleKey 链路（先断言 content 持有 activeFocus），
// 两者互补，交互证据不依赖单一函数调用。
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

        // 任务2（生产键盘焦点链路）：不调 handleKey 注入，真实按键经 QtTest keyClick
        // 走生产 Keys.onPressed → handleKey 路径。前提是 push 后 ReaderContent 持有
        // activeFocus（页面 focus:true + Flickable focus:true + StackView 激活后
        // forceActiveFocus）——先断言焦点再断言按键行为。
        function test_activeFocusAndProductionKeys() {
            var book = findBook("longbook")
            verify(book !== null, "longbook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            tryVerify(function () { return cv.activeFocus === true }, 3000,
                      "push 后 ReaderContent 应持有 activeFocus")
            tryVerify(function () { return cv.contentHeight > cv.height * 2 }, 3000,
                      "longbook 内容应远超视口")
            cv.contentY = 0
            var pageH = cv.height
            // 真实 ↓ 键 → 滚动一视口页（生产 Keys 路径）
            keyClick(Qt.Key_Down)
            wait(450)
            verify(Math.abs(cv.contentY - pageH) < 4,
                   "真实 ↓ 键应滚动一视口页，实际 contentY=" + cv.contentY + "（期望 " + pageH + "）")
            // 真实 ↑ 键 → 回退到顶部
            keyClick(Qt.Key_Up)
            wait(450)
            verify(Math.abs(cv.contentY) < 4,
                   "真实 ↑ 键应回退到顶部，实际 contentY=" + cv.contentY)
            h.stack.destroy()

            // 生产 Keys 路径翻章：multibook ←/→
            var mb = findBook("multibook")
            verify(mb !== null, "multibook 应已导入")
            var h2 = openPage(mb)
            var titles = Books.chapterTitles(mb.id)
            verify(titles.length >= 3, "multibook 应有 3 章，实际 " + titles.length)
            Books.currentChapter = 0
            h2.page.loadChapter(0)
            wait(100)
            tryVerify(function () { return h2.page.contentView.activeFocus === true }, 3000,
                      "第二次 push 的 content 也应持有 activeFocus")
            keyClick(Qt.Key_Right)
            tryVerify(function () { return Books.currentChapter === 1 }, 3000,
                      "真实 → 键应翻到下一章，实际 currentChapter=" + Books.currentChapter)
            keyClick(Qt.Key_Left)
            tryVerify(function () { return Books.currentChapter === 0 }, 3000,
                      "真实 ← 键应翻回上一章，实际 currentChapter=" + Books.currentChapter)
            h2.stack.destroy()
        }

        // 任务2（拖动阈值）：正文真实拖拽滚动（按下+位移超阈值+松开）不应误触发
        // 唤出（TapHandler DragThreshold 手势策略）；同时锁定正文拖动本身可用。
        function test_realDragScrollDoesNotSummon() {
            var book = findBook("longbook")
            verify(book !== null, "longbook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            page.controlsHideDelay = 100000
            page.controlsVisible = false
            page.sheetOpen = false
            wait(50)
            tryVerify(function () { return cv.contentHeight > cv.height * 2 }, 3000,
                      "longbook 内容应远超视口")
            cv.contentY = 0
            // 正文列左侧留白（x=5）向上拖 160px：位移远超 DragThreshold → Flickable 拖动。
            // mouseDrag 分步移动（每步超过拖拽阈值），合成拖动比手写 mouseMove 稳定。
            mouseDrag(cv, 5, 250, 0, -160, Qt.LeftButton, Qt.NoModifier, 50)
            tryVerify(function () { return cv.contentY > 100 }, 3000,
                      "正文拖动应滚动（拖动未被点击桥接拦截），实际 contentY=" + cv.contentY)
            verify(!page.sheetOpen, "拖动超过阈值不应误触发唤出")
            h.stack.destroy()
        }

        // 任务2：不把"调用函数"作为唯一交互证据——上方真实点击/按键用例已锁定
        // 生产链路；此处仅作为翻章语义对照（→ 翻章、← 回章、边界钳制）保留注入版。
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
        // 任务3：等页面模型就绪——pageModel 由稳定单向估算（字符串长度/段落边界/
        // 视口几何）同步生成，不依赖 delegate 异步高度反馈 → pageCount 一经生成即
        // 收敛不振荡（此前两次方案因动态高度测量振荡回滚）。只需等页面 Repeater
        // 委托数与 pageCount 同步（Repeater 布局在事件循环 polish 阶段落地）。
        function waitPagesSettled(cv) {
            var last = -1
            var stable = 0
            var t0 = new Date().getTime()
            while (new Date().getTime() - t0 < 5000) {
                var pc = cv.pageCount
                var synced = pc > 0 && cv.pageRepeater.count === pc
                if (synced) {
                    if (Math.abs(pc - last) < 0.5) stable++
                    else stable = 0
                    if (stable >= 2) return true
                } else {
                    stable = 0
                }
                last = pc
                wait(50)
            }
            return false
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

        // 任务3：真正横向分页——页面沿 x 轴排列：contentWidth > width、左右/上下键
        // 翻页改变 contentX（页宽粒度）、contentY 恒 0（不承担分页职责）、
        // contentHeight <= height；pageCount 稳定无振荡；首页 ←/↑ 兜底不换章。
        function test_pagedContentIsHorizontal() {
            var book = findBook("longbook")
            verify(book !== null, "longbook 应已导入")
            var h = openPage(book)
            var page = h.page
            page.pageMode = "paged"
            var cv = page.contentView
            compare(cv.pageMode, "paged", "pageMode 应注入 ReaderContent")
            verify(waitPagesSettled(cv),
                   "页面模型应就绪并稳定：5s 内未证明同步（pageCount=" + cv.pageCount
                   + "，页面委托=" + cv.pageRepeater.count + "）")
            var w = cv.width
            verify(w > 0, "视口宽应 > 0，实际 " + w)
            verify(cv.contentWidth > w,
                   "paged contentWidth 应大于视口宽（实际 " + cv.contentWidth + " ≤ " + w + "）")
            verify(cv.contentHeight <= cv.height + 0.5,
                   "paged contentHeight 应不超过视口高（实际 " + cv.contentHeight
                   + "，视口 " + cv.height + "）")
            verify(cv.pageCount >= 2, "longbook 应至少 2 页，实际 " + cv.pageCount)
            // pageCount 稳定：连续采样不变（无振荡）
            var pc1 = cv.pageCount
            wait(300)
            compare(cv.pageCount, pc1, "pageCount 不应振荡（" + pc1 + " → " + cv.pageCount + "）")
            cv.contentX = 0
            var y0 = cv.contentY
            // → 翻到第 1 页边界（1 × 页宽）
            cv.handleKey(Qt.Key_Right, Qt.NoModifier)
            wait(450)
            verify(Math.abs(cv.contentX - w) < 4,
                   "paged → 应定位到第 1 页（contentX=" + cv.contentX + "，期望 " + w + "）")
            compare(cv.contentY, y0, "paged 翻页 contentY 应保持不变")
            // ↓ 同语义 → 第 2 页
            cv.handleKey(Qt.Key_Down, Qt.NoModifier)
            wait(450)
            verify(Math.abs(cv.contentX - 2 * w) < 4,
                   "paged ↓ 应定位到第 2 页（contentX=" + cv.contentX + "，期望 " + 2 * w + "）")
            compare(cv.contentY, y0, "paged ↓ 翻页 contentY 应保持不变")
            // ← 回退 → 第 1 页
            cv.handleKey(Qt.Key_Left, Qt.NoModifier)
            wait(450)
            verify(Math.abs(cv.contentX - w) < 4,
                   "paged ← 应回退到第 1 页（contentX=" + cv.contentX + "）")
            // 首页 ←/↑ 不越界（autoPrevChapter 首章兜底不换，contentX 保持 0）
            cv.contentX = 0
            cv.handleKey(Qt.Key_Left, Qt.NoModifier)
            cv.handleKey(Qt.Key_Up, Qt.NoModifier)
            wait(450)
            verify(cv.contentX === 0, "paged 首页 ←/↑ 应兜底不换，实际 " + cv.contentX)
            compare(cv.contentY, 0, "paged 首页 contentY 应恒 0")
            h.stack.destroy()
        }

        // 横翻：章末页再 → 翻过章末进入下一章（真实书籍语义）；末章 → 不越
        function test_pagedLastPageAdvancesChapter() {
            var book = findBook("multibook")
            verify(book !== null, "multibook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            page.pageMode = "paged"
            var titles = Books.chapterTitles(book.id)
            Books.currentChapter = 0
            page.loadChapter(0)
            // 等章 0 页面模型就绪（pageModel 同步估算，Repeater 布局异步落地）
            verify(waitPagesSettled(cv),
                   "章 0 页面模型应就绪（pageCount=" + cv.pageCount + "）")
            // 直接定位到章末（contentX = (页数-1)×页宽），再 → 应翻章而非停在末页
            cv.contentX = (cv.pageCount - 1) * cv.width
            wait(50)
            cv.handleKey(Qt.Key_Right, Qt.NoModifier)
            tryVerify(function () { return Books.currentChapter === 1 }, 3000,
                      "paged 章末再 → 应进入下一章，实际 currentChapter=" + Books.currentChapter)
            // 末章章末 → 不越（autoNextChapter 兜底）
            page.loadChapter(titles.length - 1)
            verify(waitPagesSettled(cv),
                   "末章页面模型应就绪（pageCount=" + cv.pageCount + "）")
            cv.contentX = (cv.pageCount - 1) * cv.width
            wait(50)
            cv.handleKey(Qt.Key_Right, Qt.NoModifier)
            wait(100)
            compare(Books.currentChapter, titles.length - 1, "paged 末章章末 → 应钳制在末章")
            h.stack.destroy()
        }

        // E4 复审：paged 模式 ← 章首回上一章——pagePrev 在 contentX=0 时不再死键，
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
            verify(waitPagesSettled(cv),
                   "章 1 页面模型应就绪（pageCount=" + cv.pageCount + "）")
            cv.contentX = 0
            wait(50)
            // 章首 ← → 上一章（旧实现 contentX 无横向语义，← 为死键）
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
            // paged 模式：翻到末页——逐页按 →（pageNext 动画路径，每按等 450ms 收敛）。
            // 用章 0（100 段 ≈ 3 页）：章 1 仅 60 段，字符估算下恰为 1 页，末页即首页，
            // 逐页循环第一按就会误触发翻章（估算语义下章 1 无"末页停留"可测）。
            page.pageMode = "paged"
            page.loadChapter(0)
            verify(waitPagesSettled(cv),
                   "章 0 页面模型应就绪并稳定（pageCount=" + cv.pageCount + "）")
            cv.contentX = 0
            var maxX = (cv.pageCount - 1) * cv.width
            var guard = 0
            while (guard++ < 10) {
                cv.handleKey(Qt.Key_Right, Qt.NoModifier)
                wait(450)
                if (cv.contentX >= maxX - 2) break
            }
            verify(cv.contentX >= maxX - 2,
                   "pageNext 应推进到末页（contentX=" + cv.contentX + "，maxX=" + maxX + "）")
            // 章末按住 →（autoRepeat）不应翻章；正常按下才翻
            cv.handleKey(Qt.Key_Right, Qt.NoModifier, true)
            wait(100)
            compare(Books.currentChapter, 0, "paged 章末按住 → 自动重复不应翻章")
            cv.handleKey(Qt.Key_Right, Qt.NoModifier, false)
            tryVerify(function () { return Books.currentChapter === 1 }, 3000,
                      "paged 章末正常按下 → 应翻章，实际 currentChapter=" + Books.currentChapter)
            h.stack.destroy()
        }

        // E4 复审：paged 模式横向吸附——拖拽/滚轮改变 contentX 后收敛吸附到最近页边界
        //（onContentXChanged → snapTimer(200ms) → snapToPage；ttsActive/恢复窗口内跳过，
        // 此处 ttsActive=false 且恢复已关）。
        function test_pagedWheelSnapToPageBoundary() {
            var book = findBook("longbook")
            verify(book !== null, "longbook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            page.pageMode = "paged"
            verify(waitPagesSettled(cv),
                   "页面模型应就绪并稳定（pageCount=" + cv.pageCount + "）")
            var w = cv.width
            cv.contentX = 0
            wait(50)
            // 模拟滚轮：contentX 落到非页边界（w*0.5+10 → 最近页边界 w）
            cv.contentX = w * 0.5 + 10
            tryVerify(function () { return Math.abs(cv.contentX - w) < 4 }, 3000,
                      "contentX 收敛后应吸附到最近页边界（期望 " + w
                      + "，实际 " + cv.contentX + "）")
            h.stack.destroy()
        }

        // E4 复审：动画互斥——goToPage（paged 翻页与 TTS 跟随共用 pageAnimX，驱动
        // contentX）启动前先停 followAnim（scroll 模式 TTS 跟随/搜索跳转驱动 contentY，
        // 双动画同向并发会让目标互相覆盖；paged 下 followAnim 由 goToPage 显式停止）。
        function test_pageAnimStopsFollowAnim() {
            var book = findBook("longbook")
            verify(book !== null, "longbook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            page.pageMode = "paged"
            verify(waitPagesSettled(cv),
                   "页面模型应就绪并稳定（pageCount=" + cv.pageCount + "）")
            cv.contentX = 0
            // 启动 TTS 跟随：末句所在段落位于末页（页数 ≥ 2 → 目标页 ≠ 0，动画不会瞬停）
            cv.followSentence(cv.totalSentences - 1)
            verify(cv.pageAnimationX.running === true, "paged 跟随应驱动 pageAnimX")
            // 键盘翻页启动 pageAnimX → followAnim 必须先停（互斥断言）
            cv.handleKey(Qt.Key_Right, Qt.NoModifier)
            verify(cv.pageAnimationX.running === true, "翻页应驱动 pageAnimX")
            verify(cv.followAnimation.running === false,
                   "pageAnimX 启动前 followAnim 应被停止")
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

        // 设置页入口（U5：翻页方式迁入 SettingsBackgroundPage 子页）：KdRadioGrid
        // 单选切换 → reading/pageMode 持久化 + 恢复选中。selectValue() 与单元格点击
        // 同路径（MouseArea.onClicked → selectValue）；恢复走 currentValue 赋值不触发
        // selected（不写 Settings，同背景模式单选取舍）。
        function test_settingsPageModeEntry() {
            var loader = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; Loader { source: \"qrc:/qt/qml/Readdict/ui/qml/SettingsBackgroundPage.qml\"; }", root)
            verify(loader.item !== null, "SettingsBackgroundPage 应能加载")
            loader.width = 1100; loader.height = 720
            var sp = loader.item
            verify(sp.pageModeGrid !== undefined, "背景子页应暴露翻页方式 KdRadioGrid 句柄")
            // 初始：默认 scroll 选中
            compare(sp.pageModeGrid.currentValue, "scroll", "默认应选中连续滚动")
            // 切整页翻动 → 写 reading/pageMode=paged
            sp.pageModeGrid.selectValue("paged")
            compare(String(Settings.value("reading/pageMode")), "paged",
                    "选整页翻动应写 reading/pageMode=paged")
            // 切回连续滚动
            sp.pageModeGrid.selectValue("scroll")
            compare(String(Settings.value("reading/pageMode")), "scroll",
                    "选连续滚动应写 reading/pageMode=scroll")
            // 恢复 paged 后重载子页 → 选中态恢复
            Settings.setValue("reading/pageMode", "paged")
            var loader2 = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; Loader { source: \"qrc:/qt/qml/Readdict/ui/qml/SettingsBackgroundPage.qml\"; }", root)
            loader2.width = 1100; loader2.height = 720
            compare(loader2.item.pageModeGrid.currentValue, "paged",
                    "reading/pageMode=paged 时重载子页应选中整页翻动")
            loader2.destroy()
            loader.destroy()
            Settings.setValue("reading/pageMode", "scroll")
        }
    }
}
