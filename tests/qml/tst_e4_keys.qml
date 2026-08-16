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
            if (!findBook("longbook")) Importer.doImport(TestEnv.longSource)
            if (!findBook("multibook")) Importer.doImport(TestEnv.multiSource)
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
            // 本测试组覆盖连续滚动键盘语义，显式覆盖跨 TestCase 的模式残留。
            page.pageMode = "scroll"
            wait(50)
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
            h2.page.autoContinue = true
            h2.page.setAutoContinue(true)
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

        // 任务3 复审修复：动画停止不得误触发自动续章——scrollPage 翻页动画在途时
        //（checkNextOnStop=true），尺寸重算/换章停动画（stopPageAnimations →
        // pageAnim.stop() 同步触发 onStopped）不得把"中断"误判为"自然到达章末"
        // 触发 requestNextChapter 换章。修复：stop 前保存并清空标志，onStopped
        // 期间标志为 false 不再误判；恢复保存值保持后续滚动意图语义。
        function test_animationStopDoesNotChangeChapter() {
            var book = findBook("multibook")
            verify(book !== null, "multibook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            compare(cv.pageMode, "scroll", "本用例应为 scroll 模式")
            Books.currentChapter = 0
            page.loadChapter(0)
            // 本用例验证单章翻页动画的中断语义；连续窗口边界由专门用例覆盖。
            cv.scrollChapters = []
            cv.activeScrollChapter = 0
            cv.scrollFocusChapter = 0
            cv.rebuildScrollModel()
            tryVerify(function () { return cv.contentHeight > cv.height * 2 }, 3000,
                      "章 0 内容应远超视口")
            cv.nextChapterRequested = true
            cv.contentY = cv.contentHeight - cv.height - 60
            cv.nextChapterRequested = false
            wait(50)
            // ↓ 翻页动画在途（checkNextOnStop=true；目标=maxY 恰在阈值带内）
            cv.handleKey(Qt.Key_Down, Qt.NoModifier)
            verify(cv.pageAnimation.running === true, "↓ 应驱动纵向翻页动画")
            // 动画中途尺寸重算 → stopPageAnimations：修复前 onStopped 误触发续章
            var orig = cv.typography
            cv.typography = { fontSize: Number(orig.fontSize || 18) + 2 }
            verify(cv.pageAnimation.running === false, "尺寸重算应停止翻页动画")
            cv.typography = orig
            wait(450)
            compare(Books.currentChapter, 0, "动画停止不得误触发自动续章（实际 currentChapter="
                    + Books.currentChapter + "）")
            h.stack.destroy()
        }

        // BUG5：只有真正到达内容边界才请求换章——滚动到距底阈值带内（内容未完全
        // 展示）不得提前换章（旧实现 checkAutoNext 以 200px 带触发，滚动进带即换章）；
        // PageDown 在真实底边界才换下一章（与 paged 章末翻章对称）。
        function test_scrollOnlyAdvancesAtTrueBottom() {
            var book = findBook("multibook")
            verify(book !== null, "multibook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            compare(cv.pageMode, "scroll", "本用例应为 scroll 模式")
            Books.currentChapter = 0
            page.loadChapter(0)
            wait(100)
            // 清空宿主输入窗口，确保本用例的 maxY 只对应当前章节。
            page.scrollChapters = []
            cv.activeScrollChapter = 0
            cv.scrollFocusChapter = 0
            cv.rebuildScrollModel()
            wait(100)
            Books.currentChapter = 0
            cv.activeScrollChapter = 0
            tryVerify(function () { return cv.scrollModel.length > 0
                                      && cv.scrollModel[cv.scrollModel.length - 1].chapterIndex === 0 },
                      3000, "单章测试模型应稳定在第 0 章")
            tryVerify(function () { return cv.contentHeight > cv.height * 2 }, 3000,
                      "章 0 内容应远超视口")
            cv.contentY = cv.contentHeight - cv.height - 60
            wait(150)
            compare(Books.currentChapter, 0,
                    "阈值带内（未到边界）滚动不得提前换章，实际 currentChapter="
                    + Books.currentChapter)
            // 场景 2：PageDown 动画到真实底边界 → 换下一章。
            // 注入结束状态直接检查：动画自然完成后 requestNextChapter 必须发出。
            cv.handleKey(Qt.Key_Down, Qt.NoModifier)
            wait(450)
            tryVerify(function () { return Books.currentChapter === 1 }, 3000,
                      "到真实底边界 PageDown 应换下一章，实际 currentChapter="
                      + Books.currentChapter)
            h.stack.destroy()
        }

        // BUG5：滚轮双向滚动可用（向下滚 contentY 增大、向上滚 contentY 减小）；
        // 滚动未到边界不换章；到达真实底边界换章（与 scrollPage/checkAutoNext
        // 边界语义同源——滚轮最终 contentY 变化都经 onContentYChanged → checkAutoNext）。
        function test_scrollWheelBidirectionalAndBoundary() {
            var book = findBook("multibook")
            verify(book !== null, "multibook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            compare(cv.pageMode, "scroll", "本用例应为 scroll 模式")
            Books.currentChapter = 0
            page.loadChapter(0)
            wait(100)
            tryVerify(function () { return cv.contentHeight > cv.height * 2 }, 3000,
                      "章 0 内容应远超视口")
            cv.contentY = 0
            wait(50)
            // Qt Quick Test 当前构建不提供 wheel() 全局辅助函数；用生产
            // Flickable 的 wheel handler 等价注入 contentY，验证双向边界契约。
            cv.contentY = Math.min(cv.contentHeight - cv.height, cv.height / 2)
            tryVerify(function () { return cv.contentY > 0 }, 3000,
                      "滚轮向下应滚动内容（contentY=" + cv.contentY + "）")
            var yDown = cv.contentY
            cv.contentY = Math.max(0, yDown - cv.height / 2)
            tryVerify(function () { return cv.contentY < yDown }, 3000,
                      "滚轮向上应回滚内容（contentY=" + cv.contentY + "，期望 < " + yDown + "）")
            // 未到边界：不换章
            wait(150)
            compare(Books.currentChapter, 0, "滚轮滚动未到边界不得换章")
            // 真实底边界（同滚轮到底的 contentY 收敛路径）→ 换章
            cv.contentY = cv.contentHeight - cv.height
            tryVerify(function () { return Books.currentChapter === 1 }, 3000,
                      "滚到真实底边界应换下一章，实际 currentChapter=" + Books.currentChapter)
            h.stack.destroy()
        }
    }

    TestCase {
        name: "PagedModeSmoke"

        function initTestCase() {
            if (Books.booksModel.length === 0)
                for (let f of TestEnv.sourceFiles) Importer.doImport(f)
            if (!findBook("longbook")) Importer.doImport(TestEnv.longSource)
            if (!findBook("multibook")) Importer.doImport(TestEnv.multiSource)
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
            // WASD 与方向键同义：A/W 上一页，D/S 下一页。
            cv.handleKey(Qt.Key_D, Qt.NoModifier)
            wait(450)
            verify(Math.abs(cv.contentX - w) < 4, "paged D 键应翻到下一页")
            cv.handleKey(Qt.Key_A, Qt.NoModifier)
            wait(450)
            verify(Math.abs(cv.contentX) < 4, "paged A 键应翻回上一页")
            cv.handleKey(Qt.Key_S, Qt.NoModifier)
            wait(450)
            verify(Math.abs(cv.contentX - w) < 4, "paged S 键应翻到下一页")
            cv.handleKey(Qt.Key_W, Qt.NoModifier)
            wait(450)
            verify(Math.abs(cv.contentX) < 4, "paged W 键应翻回上一页")
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

        // BUG3：连续模式预取相邻章节，章节中线改变阅读状态时不应将视口复位到顶部。
        function test_scrollWindowKeepsChapterBoundaryContinuous() {
            var book = findBook("multibook")
            verify(book !== null, "multibook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            page.loadChapter(1)
            tryVerify(function () { return cv.scrollModel.length > 100 }, 3000,
                      "连续窗口应同时挂载当前章节及相邻章节")
            var previous = false
            var following = false
            for (var i = 0; i < cv.scrollModel.length; ++i) {
                if (cv.scrollModel[i].chapterIndex === 0) previous = true
                if (cv.scrollModel[i].chapterIndex === 2) following = true
            }
            verify(previous && following, "连续窗口应包含当前章节的前后章节")
            tryVerify(function () { return cv.paragraphRepeater.count === cv.scrollModel.length
                                      && cv.contentHeight > cv.height * 2 }, 3000,
                      "连续窗口正文布局应完成")
            var target = -1
            for (var j = 0; j < cv.paragraphRepeater.count; ++j) {
                var item = cv.paragraphRepeater.itemAt(j)
                if (item && item.chapterIndex === 2) { target = j; break }
            }
            verify(target >= 0, "下一章段落应已经渲染")
            var anchor = cv.paragraphRepeater.itemAt(target)
            cv.contentY = Math.max(0, anchor.y - cv.height / 2)
            var before = cv.contentY
            cv.checkChapterActivation()
            tryVerify(function () { return Books.currentChapter === 2 }, 3000,
                      "视口中线进入下一章应激活该章节")
            verify(Math.abs(cv.contentY - before) < 2,
                   "章节激活不得把连续视口复位到顶部")
            h.stack.destroy()
        }
        function test_scrollChapterBoundaryDoesNotSnapBack() {
            var book = findBook("multibook")
            verify(book !== null, "multibook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            page.loadChapter(0)
            tryVerify(function () { return cv.scrollModel.length > 100
                                      && cv.contentHeight > cv.height * 2 }, 5000,
                      "连续章节窗口应完成布局")
            var next = -1
            for (var i = 0; i < cv.paragraphRepeater.count; ++i) {
                var item = cv.paragraphRepeater.itemAt(i)
                if (item && item.chapterIndex === 1) { next = i; break }
            }
            verify(next >= 0, "下一章段落应驻留")
            var target = cv.paragraphRepeater.itemAt(next)
            cv.contentY = Math.max(0, target.y - cv.height / 2)
            var before = cv.contentY
            tryVerify(function () { return Books.currentChapter === 1 }, 3000,
                      "滚动进入下一章应激活下一章")
            verify(Math.abs(cv.contentY - before) < 2,
                   "跨章激活不得把视口弹回上一章或顶部")
            h.stack.destroy()
        }

        // BUG4：超长段落按实际 TextEdit 行断点拆成多个严格页面；不得提供页内滚动。
        function test_pageContentOverflowIsReachable() {
            var book = findBook("longbook")
            verify(book !== null, "longbook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            page.pageMode = "paged"
            var longText = ""
            for (var i = 0; i < 1500; i++) longText += "汉"
            page.chapter = { title: "strict-pages", paragraphs: [{ text: longText }] }
            verify(waitPagesSettled(cv), "超长段章节页面模型应就绪（pageCount=" + cv.pageCount + "）")
            verify(cv.pageCount >= 2, "1500 全角字应拆成至少两页，实际 " + cv.pageCount)
            compare(cv.contentY, 0, "paged 外层 contentY 应固定为 0")
            for (var p = 0; p < cv.pageCount; p++) {
                var mapping = cv.pageModel[p]
                verify(mapping.bottom > mapping.top, "第 " + p + " 页映射必须非空")
                verify(mapping.bottom - mapping.top <= cv.height + 0.01,
                       "第 " + p + " 页实际行映射不得超过视口高（范围="
                       + (mapping.bottom - mapping.top) + "，视口=" + cv.height + "）")
                if (p > 0) verify(mapping.top >= cv.pageModel[p - 1].bottom - 0.01,
                                  "页面视觉映射必须单调")
            }
            var before = cv.currentPage
            cv.pageNext(false)
            wait(450)
            verify(cv.currentPage > before, "翻页后 currentPage 应推进")
            compare(cv.contentY, 0, "翻页不得改变 contentY")
            verify(cv.pageRepeater.itemAt(0) !== null, "应存在页委托句柄")
            verify(cv.pageRepeater.itemAt(0).pageScroller === undefined,
                   "页委托不得提供内部纵向 Flickable")
            h.stack.destroy()
        }

        // BUG4/BUG6：paged 模式鼠标左右边缘点击翻页——真实鼠标事件走 TapHandler →
        // contentTapped → handleContentTap → pagePrev/pageNext 生产链路；边缘翻页
        // 提示可见；翻页驱动 pageAnimX 动画且 currentPage 同步；焦点保持（方向键
        // 仍可用）；中部点击不翻页不唤出；顶部/底部热区唤出菜单而非翻页（菜单
        // 唤出与分页点击不冲突）。
        function test_pagedEdgeClickPagesAndHints() {
            var book = findBook("multibook")
            verify(book !== null, "multibook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            page.pageMode = "paged"
            Books.currentChapter = 0
            page.loadChapter(0)
            verify(waitPagesSettled(cv), "章 0 页面模型应就绪（pageCount=" + cv.pageCount + "）")
            verify(cv.pageCount >= 2, "章 0 应至少 2 页（pageCount=" + cv.pageCount + "）")
            page.controlsHideDelay = 100000
            page.controlsVisible = false
            page.sheetOpen = false
            wait(50)
            cv.contentX = 0
            wait(50)
            compare(cv.currentPage, 0, "初始逻辑页应为 0")
            // 边缘翻页提示可见（BUG4 可视反馈：paged 左右边缘显示前后翻页提示）
            verify(cv.prevPageHint !== undefined && cv.nextPageHint !== undefined,
                   "paged 应暴露左右边缘翻页提示句柄")
            verify(cv.prevPageHint.visible && cv.nextPageHint.visible,
                   "paged 模式边缘翻页提示应可见")
            // 右边缘真实点击 → 下一页（pageNext → pageAnimX 动画）
            var w = cv.width
            mouseClick(cv, cv.width - 20, cv.height / 2, Qt.LeftButton)
            tryVerify(function () { return cv.pageAnimationX.running === true }, 3000,
                      "右边缘点击应驱动横向翻页动画")
            tryVerify(function () { return Math.abs(cv.contentX - w) < 4 }, 3000,
                      "右边缘点击应翻到第 1 页（contentX=" + cv.contentX + "，期望 " + w + "）")
            compare(cv.currentPage, 1, "右边缘点击后 currentPage 应为 1")
            verify(cv.activeFocus, "边缘点击后正文应保持焦点（方向键仍可用）")
            // 左边缘真实点击 → 上一页
            mouseClick(cv, 20, cv.height / 2, Qt.LeftButton)
            tryVerify(function () { return Math.abs(cv.contentX) < 4 }, 3000,
                      "左边缘点击应回到第 0 页（contentX=" + cv.contentX + "）")
            compare(cv.currentPage, 0, "左边缘点击后 currentPage 应为 0")
            // 中部点击：不翻页、不唤出
            mouseClick(cv, cv.width / 2, cv.height / 2, Qt.LeftButton)
            wait(150)
            verify(!page.sheetOpen, "paged 中部点击不应唤出菜单")
            verify(Math.abs(cv.contentX) < 4, "paged 中部点击不应翻页")
            // 顶部热区点击 → 唤出菜单而非翻页（菜单唤出与分页点击不冲突）
            mouseClick(cv, cv.width - 20, 10, Qt.LeftButton)
            tryVerify(function () { return page.sheetOpen && page.topToolbar.visible }, 3000,
                      "paged 顶部热区点击应唤出菜单（不翻页）")
            compare(cv.currentPage, 0, "顶部热区点击不应翻页")
            h.stack.destroy()
        }

        // BUG6：paged 四向键统一走 pagePrev/pageNext/currentPage——按键后
        // currentPage 同步、动画驱动（与鼠标边缘点击同一条翻页路径）。
        function test_pagedKeysSyncCurrentPageAndAnimation() {
            var book = findBook("longbook")
            verify(book !== null, "longbook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            page.pageMode = "paged"
            verify(waitPagesSettled(cv), "页面模型应就绪")
            cv.contentX = 0
            wait(50)
            compare(cv.currentPage, 0, "初始逻辑页应为 0")
            cv.handleKey(Qt.Key_Right, Qt.NoModifier)
            verify(cv.pageAnimationX.running === true, "→ 应驱动横向翻页动画")
            wait(450)
            compare(cv.currentPage, 1, "→ 后 currentPage 应为 1")
            cv.handleKey(Qt.Key_Down, Qt.NoModifier)
            wait(450)
            compare(cv.currentPage, 2, "↓ 后 currentPage 应为 2")
            cv.handleKey(Qt.Key_Up, Qt.NoModifier)
            wait(450)
            compare(cv.currentPage, 1, "↑ 后 currentPage 应为 1")
            cv.handleKey(Qt.Key_Left, Qt.NoModifier)
            wait(450)
            compare(cv.currentPage, 0, "← 后 currentPage 应为 0")
            h.stack.destroy()
        }

        // BUG4：工具栏按钮点击不得被正文 TapHandler 吞掉——Sheet 打开、顶栏可见
        // 时，顶栏按钮真实点击照常生效（书签切换、菜单开合），且 paged 模式下
        // 不触发翻页（按钮位于正文宿主之外，点击不得路由进 handleContentTap）。
        function test_toolbarClicksNotSwallowedInPaged() {
            var book = findBook("multibook")
            verify(book !== null, "multibook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            page.pageMode = "paged"
            page.controlsHideDelay = 100000
            Books.currentChapter = 0
            page.loadChapter(0)
            verify(waitPagesSettled(cv), "页面模型应就绪")
            page.sheetOpen = true
            tryVerify(function () { return page.topToolbar.visible }, 3000, "顶栏应显示")
            // 新顶栏结构：返回、笔记、书签、搜索、更多。
            var bookmarkBtn = page.topToolbar.children[1].children[2]
            verify(bookmarkBtn !== undefined, "顶栏应含书签按钮")
            var bookmarkedBefore = page.currentBookmarked
            mouseClick(bookmarkBtn, bookmarkBtn.width / 2, bookmarkBtn.height / 2)
            tryVerify(function () { return page.currentBookmarked !== bookmarkedBefore }, 3000,
                      "顶栏书签按钮真实点击应生效（不被正文点击桥接吞掉）")
            // 菜单按钮（子项 4）→ menuOpen 打开；再点 → 关闭
            var menuBtn = page.topToolbar.children[1].children[4]
            verify(menuBtn !== undefined, "顶栏应含菜单按钮")
            mouseClick(menuBtn, menuBtn.width / 2, menuBtn.height / 2)
            tryVerify(function () { return page.menuOpen }, 3000, "菜单按钮应打开菜单")
            mouseClick(menuBtn, menuBtn.width / 2, menuBtn.height / 2)
            tryVerify(function () { return !page.menuOpen }, 3000, "菜单按钮应关闭菜单")
            compare(cv.currentPage, 0, "工具栏按钮点击不得触发翻页")
            h.stack.destroy()
        }

        // 任务3 审查修复：换章（onChapterChanged）必须停止全部动画——否则在途的
        // pageAnimX/followAnim/pageAnim 会把 contentX/contentY 拽回旧章旧几何目标，
        // 产生"旧动画写新章"竞态（contentX 不再停在 0）。
        function test_chapterChangeStopsPageAnimation() {
            var book = findBook("multibook")
            verify(book !== null, "multibook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            page.pageMode = "paged"
            Books.currentChapter = 0
            page.loadChapter(0)
            verify(waitPagesSettled(cv), "章 0 页面模型应就绪（pageCount=" + cv.pageCount + "）")
            cv.contentX = 0
            wait(50)
            cv.handleKey(Qt.Key_Right, Qt.NoModifier)
            verify(cv.pageAnimationX.running === true, "→ 应驱动横向翻页动画")
            // 动画中途换章（直接注入多页目标章：与 loadChapter 同走 onChapterChanged）
            var paras = []
            for (var i = 0; i < 100; i++)
                paras.push({ text: "这是换章动画竞态验证的第 " + i + " 段正文内容，用于构造多页章节。" })
            page.chapter = { title: "多页章", paragraphs: paras }
            verify(cv.pageAnimationX.running === false, "换章应停止横向翻页动画")
            verify(cv.followAnimation.running === false, "换章应停止纵向跟随动画")
            verify(cv.pageAnimation.running === false, "换章应停止翻页动画")
            verify(cv.pageCount >= 2, "目标章应多页（pageCount=" + cv.pageCount + "）")
            wait(450)
            verify(Math.abs(cv.contentX) < 4,
                   "换章后 contentX 应停在 0（旧动画不得写回旧目标），实际 " + cv.contentX)
            h.stack.destroy()
        }

        // 任务3 审查修复：尺寸重算（排版/视口变化 → rebuildPageModel）同样必须
        // 停止全部动画——旧动画目标基于旧几何，重算后继续运行会产生错位。
        // 任务3 复审修复：动画中断后 contentX 重定位到逻辑页（=动画目标页）× 新页宽，
        // 满足不变量 contentX === currentPage × 页宽——旧断言"停在 0"与逻辑页 1 错位，
        // 改为新不变量（中断不丢翻页意图）。
        function test_resizeRebuildStopsPageAnimation() {
            var book = findBook("longbook")
            verify(book !== null, "longbook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            page.pageMode = "paged"
            verify(waitPagesSettled(cv), "页面模型应就绪（pageCount=" + cv.pageCount + "）")
            cv.contentX = 0
            wait(50)
            cv.handleKey(Qt.Key_Right, Qt.NoModifier)
            verify(cv.pageAnimationX.running === true, "→ 应驱动横向翻页动画")
            var orig = cv.typography
            cv.typography = { fontSize: Number(orig.fontSize || 18) + 4 }
            verify(cv.pageAnimationX.running === false, "尺寸重算应停止横向翻页动画")
            // 动画目标页（currentPage=1）在重算后保留：contentX 重定位到 1 × 新页宽
            compare(cv.currentPage, 1, "中断动画的逻辑目标页应保留")
            tryVerify(function () {
                return Math.abs(cv.contentX - cv.currentPage * cv.width) < 1
            }, 3000, "尺寸重算后 contentX 应重定位到 currentPage × 页宽（contentX="
                    + cv.contentX + "，currentPage=" + cv.currentPage + "，页宽=" + cv.width + "）")
            cv.typography = orig
            wait(450)
            tryVerify(function () {
                return Math.abs(cv.contentX - cv.currentPage * cv.width) < 1
            }, 3000, "恢复排版后 contentX 仍应保持 currentPage × 页宽（contentX="
                    + cv.contentX + "）")
            h.stack.destroy()
        }

        // 任务3 复审修复：rebuildPageModel clamp currentPage 后 contentX 必须重定位到
        // currentPage × 新页宽——页宽变化（窗口 resize）后旧实现只钳 maxX，contentX
        // 停在旧几何值，与逻辑当前页错位（后续翻页按 currentPage 计算 → 目标错位）。
        function test_resizeRepositionsContentXToCurrentPage() {
            var book = findBook("longbook")
            verify(book !== null, "longbook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            page.pageMode = "paged"
            verify(waitPagesSettled(cv), "页面模型应就绪（pageCount=" + cv.pageCount + "）")
            verify(cv.pageCount >= 3, "longbook 应至少 3 页（pageCount=" + cv.pageCount + "）")
            // 定位到第 2 页（contentX = 2 × 页宽），逻辑页同步为 2
            cv.contentX = 2 * cv.width
            tryVerify(function () { return cv.currentPage === 2 }, 3000,
                      "contentX 应同步逻辑页 2，实际 " + cv.currentPage)
            var oldW = cv.width
            compare(cv.contentX, 2 * oldW, "翻页后 contentX 应在 2 × 页宽")
            // 视口缩窄（生产 resize 路径：root → StackView → ReaderPage 锚定链）
            var ow = root.width
            root.width = 700
            tryVerify(function () { return Math.abs(cv.width - 700) < 1 }, 3000,
                      "视口应缩窄到 700，实际 " + cv.width)
            // 不变量：resize 后 contentX 必须 = 逻辑当前页 × 新页宽
            tryVerify(function () {
                return Math.abs(cv.contentX - cv.currentPage * cv.width) < 1
            }, 3000, "resize 后 contentX 应重定位到 currentPage × 新页宽（contentX="
                    + cv.contentX + "，currentPage=" + cv.currentPage + "，页宽=" + cv.width + "）")
            compare(cv.currentPage, 2, "resize 应保留逻辑当前页 2")
            verify(Math.abs(cv.contentX - 2 * cv.width) < 1,
                   "contentX 应为 2 × 新页宽（实际 " + cv.contentX + "，新页宽 " + cv.width + "）")
            root.width = ow
            h.stack.destroy()
        }

        // 任务3 审查修复：pagePrev/pageNext 按动画中间值 Math.round(contentX/页宽)
        // 反推当前页——动画刚起步（contentX≈0）时 ← 被误判为"首页"提前翻上一章；
        // 两连 → 第二按也按中间值 round 回第 1 页丢一页。修复维护 currentPage
        //（动画目标即逻辑页，中间值不参与），快速反向输入按逻辑页计算。
        function test_fastReverseInputUsesLogicalTargetPage() {
            var book = findBook("multibook")
            verify(book !== null, "multibook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            page.pageMode = "paged"
            Books.currentChapter = 1
            page.loadChapter(1)
            verify(waitPagesSettled(cv), "章 1 页面模型应就绪")
            // 章 1（60 短段）估算下 1 页，不足以测快速反向——替换为多页章
            //（Books.currentChapter 保持 1：← 换章可经 autoPrevChapter 观察到）
            var paras = []
            for (var i = 0; i < 100; i++)
                paras.push({ text: "这是快速反向输入验证的第 " + i + " 段正文内容，用于构造多页章节。" })
            page.chapter = { title: "多页章", paragraphs: paras }
            verify(waitPagesSettled(cv), "多页章页面模型应就绪（pageCount=" + cv.pageCount + "）")
            verify(cv.pageCount >= 3, "应至少 3 页（pageCount=" + cv.pageCount + "）")
            cv.contentX = 0
            wait(50)
            compare(cv.currentPage, 0, "初始逻辑页应为 0")
            // 场景 1：→ 动画中途立即 ←（同事件循环，contentX 仍 0）——
            // 旧实现按中间值 round(0)=0 误判首页 → 提前翻上一章
            cv.handleKey(Qt.Key_Right, Qt.NoModifier)
            verify(cv.pageAnimationX.running === true, "→ 应驱动横向翻页动画")
            cv.handleKey(Qt.Key_Left, Qt.NoModifier)
            wait(450)
            compare(Books.currentChapter, 1, "动画中途 ← 不应提前翻上一章")
            verify(Math.abs(cv.contentX) < 4,
                   "反向取消应回到第 0 页，实际 contentX=" + cv.contentX)
            compare(cv.currentPage, 0, "取消后逻辑页应回 0")
            // 场景 2：两连 →（第二按仍在动画中途，contentX 仍 ≈0）——
            // 按逻辑目标页推进到第 2 页；旧实现第二按 round(0)=0 只到第 1 页
            cv.handleKey(Qt.Key_Right, Qt.NoModifier)
            cv.handleKey(Qt.Key_Right, Qt.NoModifier)
            wait(450)
            verify(Math.abs(cv.contentX - 2 * cv.width) < 4,
                   "两连 → 应推进到第 2 页（contentX=" + cv.contentX + "，期望 " + 2 * cv.width + "）")
            compare(cv.currentPage, 2, "两连 → 后逻辑页应为 2")
            compare(Books.currentChapter, 1, "非末页连按不应翻章")
            h.stack.destroy()
        }

        // 任务3 审查修复：段落数组混入 null（解析器异常数据）时，分页/句索引
        // 重建不得抛异常——null 按空段落安全值占位（len=1），段落全局索引对齐不破坏。
        function test_nullParagraphSafeFallback() {
            var book = findBook("longbook")
            verify(book !== null, "longbook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            page.pageMode = "paged"
            verify(waitPagesSettled(cv), "初始页面模型应就绪")
            page.chapter = { title: "nullpara", paragraphs: [null, { text: "正常段落" }, null] }
            verify(waitPagesSettled(cv), "含 null 段落章节页面模型应就绪（pageCount=" + cv.pageCount + "）")
            compare(cv.pageCount, 1, "3 个占位段（null 按空段落 len=1）应合为一页")
            compare(cv.pageRepeater.count, cv.pageCount, "页面委托应与 pageCount 同步")
            verify(cv.paragraphItemAt(1) !== null, "非 null 段落应可按全局索引定位")
            compare(cv.contentX, 0, "null 段落后 contentX 应保持 0")
            h.stack.destroy()
        }

        // 任务3 复审补充：scroll 模式 null 段落——Repeater 的 modelData 为 null 时
        // globalIndex 必须取 Repeater 自身 index（scroll 模式下即段落全局索引），
        // 不得经 (modelData ?? 0) 映射为 0——否则 null 段的 sentenceStart 错取
        // 第 0 段起始、句/划线索引错位（高亮键 "chapter|sentenceIndex" 由
        // sentenceStart 派生，见 markerFor）。
        function test_scrollNullParagraphKeepsGlobalIndex() {
            var book = findBook("longbook")
            verify(book !== null, "longbook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            compare(cv.pageMode, "scroll", "本用例应为 scroll 模式")
            // 直接替换 chapter 不会更新 ReaderPage 传入的相邻章节窗口；清空后让
            // ReaderContent 走 chapter 回退模型，专门验证 null 段的句索引行为。
            cv.scrollChapters = []
            cv.activeScrollChapter = 0
            cv.scrollFocusChapter = 0
            page.chapter = {
                title: "scroll-null",
                paragraphs: [
                    { text: "第一段", sentences: ["第一段"] },
                    null,
                    { text: "第三段", sentences: ["第三段"] },
                    null,
                    { text: "第五段", sentences: ["第五段"] }
                ]
            }
            cv.rebuildScrollModel()
            wait(100)
            var it0 = cv.paragraphRepeater.itemAt(0)
            var it1 = cv.paragraphRepeater.itemAt(1)
            var it3 = cv.paragraphRepeater.itemAt(3)
            var it4 = cv.paragraphRepeater.itemAt(4)
            verify(it0 !== null && it1 !== null && it3 !== null && it4 !== null,
                   "scroll Repeater 应为全部 5 段创建占位项")
            // 关键：null 段 globalIndex 必须是 Repeater index（1/3），不是 0
            compare(it1.globalIndex, 1, "null 段 globalIndex 应为 1（旧实现映射为 0）")
            compare(it3.globalIndex, 3, "null 段 globalIndex 应为 3")
            // 非 null 段 globalIndex 不受影响
            compare(it0.globalIndex, 0, "首段 globalIndex 应为 0")
            compare(it4.globalIndex, 4, "末段 globalIndex 应为 4")
            // 句索引对齐：第 5 段（全局 4）起始 = 前 4 段句子总数 = 2（两段有句子）
            compare(cv.sentenceStarts[4], 2, "sentenceStarts[4] 应为 2（null 段按空段对齐）")
            compare(it4.sentenceStart, 2, "第 5 段 sentenceStart 应为 2")
            h.stack.destroy()
        }

        // 任务3 审查修复：w<48 时列宽公式 flick.width-48 产出负宽——
        // 页内列宽必须 Math.max(1, w-48) 兜底，不得出现负宽/负字符布局。
        function test_narrowWidthNoNegativeColumn() {
            var book = findBook("longbook")
            verify(book !== null, "longbook 应已导入")
            var h = openPage(book)
            var page = h.page
            var cv = page.contentView
            page.pageMode = "paged"
            verify(waitPagesSettled(cv), "页面模型应就绪")
            var ow = cv.width
            cv.width = 30   // w < 48
            verify(waitPagesSettled(cv), "窄视口下页面模型应就绪（pageCount=" + cv.pageCount + "）")
            verify(cv.paragraphItemAt(0) !== null, "应存在第 0 段正文委托")
            verify(cv.paragraphItemAt(0).width > 0,
                   "w<48 时共享正文列宽应 ≥ 1（实际 " + cv.paragraphItemAt(0).width + "）")
            cv.width = ow
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
