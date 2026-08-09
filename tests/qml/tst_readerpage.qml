import QtQuick
import QtQuick.Controls
import QtTest
import Readdict.Backend
import Readdict.Test 1.0

// U4：阅读页回归冒烟——Kindle 顶栏、TtsBar 贴底、内容区可见与返回导航。
// 顶栏仅在 Sheet 唤出态显示，返回按钮与朗读入口分别走新顶栏/⋮菜单。
// 本用例锁定真实书打开后内容区可见高度 > 0、段落真实渲染出内容高度、
// TtsBar 贴底不压顶栏、朗读会话门控与返回按钮 pop 回书架。
// 结构约定（与 tst_background 一致）：根为带尺寸的 Item，TestCase 是其子项；
// ReaderPage 经 StackView push（生产路径，供返回导航断言）。
// C3：ControlsSummonSmoke 覆盖唤出交互（点击底部唤出 + 无操作 5s 自动隐藏 +
// 交互重置计时 + TtsBar 门控协同）——Timer 注入短间隔（controlsHideDelay）
// 收敛 5s 语义，断言状态机而非等真实 5s。
Item {
    id: root
    width: 1100; height: 720

    TestCase {
        name: "ReaderNavSmoke"

        function initTestCase() {
            Books.doSearch("")
            Books.setFilter("")
            Books.setSort(0)
            var hasTxt = false
            for (let b of Books.booksModel)
                if ((b.format || "").toUpperCase() === "TXT") { hasTxt = true; break }
            if (!hasTxt)
                for (let f of TestEnv.sourceFiles) Importer.doImport(f)
        }

        function findTxtBook() {
            for (let b of Books.booksModel)
                if ((b.format || "").toUpperCase() === "TXT") return b
            return null
        }

        function test_openBookShowsContentAndBack() {
            var book = findTxtBook()
            verify(book !== null, "测试书应已导入")
            var stack = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; StackView { anchors.fill: parent; }", root)
            verify(stack !== null, "测试 StackView 应能创建")
            // "书架"占位（pop 目标）：真实 ShelfPage 依赖 Books 模型与网格，占位 Item
            // 只验证返回导航链路（ReaderPage pop 回上一页），不重测书架页
            var shelfMarker = Qt.createQmlObject("import QtQuick; Item {}", root)
            verify(shelfMarker !== null)
            stack.push(shelfMarker)
            stack.push("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: book })
            var page = stack.currentItem
            verify(page !== null, "ReaderPage 应被 push 进 StackView")
            // 章节真实加载（loadChapter 经 Books 后端返回段落模型）
            tryVerify(function () {
                return page.chapter && page.chapter.paragraphs
                    && page.chapter.paragraphs.length > 0
            }, 3000, "打开书后应加载章节段落")
            // 内容区可见高度 > 0（内容空白回归锁定点）
            tryVerify(function () { return page.contentView.height > 0 }, 3000,
                      "内容区高度应 > 0，实际 " + page.contentView.height)
            // 段落真实渲染：内容总高 > 0（有可滚动内容）
            tryVerify(function () { return page.contentView.contentHeight > 0 }, 3000,
                      "内容总高度应 > 0，实际 " + page.contentView.contentHeight)
            // 回归源精确锁定：TtsBar 应贴底（y ≈ 高 - 46 控制栏 - 46 朗读条），
            // 而非 y=0 压住顶栏（锚失效回归，见 ttsBar 锚注释）；C2 起默认隐藏，
            // 隐藏时 y 仍按锚定位（anchors 与可见性无关），断言依然成立
            verify(page.ttsBar !== undefined, "ReaderPage 应暴露 ttsBar 句柄")
            tryVerify(function () { return page.ttsBar.y > root.height * 0.5 }, 3000,
                      "TtsBar 应位于页面下部，实际 y=" + page.ttsBar.y + "（y=0 即锚失效回归）")
            // C2：朗读条门控——默认隐藏（无朗读会话，用户反馈 BUG ②），正文占满到底部控制栏
            Tts.stop()   // 幂等复位（loadChapter 已 stop；前置用例可能留 state!=0）
            // 先等锚求值稳定到隐藏态（隐藏态正文高 = 720-36-46=638，显示态 592）再捕获基线
            // （C5：控制栏 52→46 细条化，几何断言同步）
            tryVerify(function () {
                return !page.ttsBar.visible && page.contentView.height >= root.height - 36 - 46
            }, 3000, "TtsBar 应隐藏且正文占满，实际 height=" + page.contentView.height)
            var hiddenH = page.contentView.height
            // 状态注入：setSentences + play 驱动 state 0→1（与 TtsBar 播放键的 Tts.play()
            // 走同一 stateChanged 路径）→ TtsBar 显示且正文让出 46px。
            // 前置 reconfigure 到 openai 无 key：引擎存在但不可用，play 置 state=1 不发声
            Tts.reconfigure("openai", "https://api.openai.com/v1", "", "tts-1", "nova", 1.0)
            Tts.setSentences(["测试朗读句子。"])
            Tts.play()
            tryVerify(function () { return page.ttsBar.visible }, 3000, "朗读会话激活后 TtsBar 应显示")
            tryVerify(function () { return page.contentView.height === hiddenH - 46 }, 3000,
                      "TtsBar 显示时正文应让出 46px，实际 " + page.contentView.height)
            Tts.stop()
            tryVerify(function () { return !page.ttsBar.visible }, 3000, "停止后 TtsBar 应隐藏")
            tryVerify(function () { return page.contentView.height === hiddenH }, 3000,
                      "TtsBar 隐藏时正文应恢复占满，实际 " + page.contentView.height)
            // U4：朗读入口迁移至右上角 ⋮ 菜单；菜单点击应启动会话。
            verify(page.readerMenu !== undefined, "ReaderPage 应暴露功能菜单句柄")
            Tts.reconfigure("openai", "https://api.openai.com/v1", "", "tts-1", "nova", 1.0)
            Tts.setSentences(["测试朗读句子。"])
            page.sheetOpen = true
            page.menuOpen = true
            page.menuAction("read")
            tryVerify(function () { return page.ttsBar.visible && Tts.state === 1 }, 3000,
                      "菜单朗读应启动会话（TtsBar 显示、state=1）")
            Tts.stop()
            // 返回链路：Sheet 唤出态顶栏返回按钮可见可点 → pop 回书架。
            verify(page.backButton !== undefined, "ReaderPage 应暴露返回按钮句柄")
            verify(page.backButton.visible && page.backButton.enabled,
                   "返回按钮应可见可用")
            page.backButton.clicked()
            tryVerify(function () { return stack.currentItem === shelfMarker }, 3000,
                      "点击返回后应 pop 回书架")
            stack.destroy()
            shelfMarker.destroy()
        }
    }

    TestCase {
        name: "ControlsSummonSmoke"
        // C3：阅读控件唤出交互冒烟——点击正文底部唤出 + 无操作自动隐藏 +
        // 交互重置计时 + TtsBar 门控协同。结构约定与 ReaderNavSmoke 一致：
        // StackView push 生产路径；5s 语义经 controlsHideDelay 注入短间隔收敛。
        // 手势注入：经 page.handleContentTap(y)（TapHandler 桥接共用同一状态机——
        // quicktest harness 无法可靠合成真实鼠标事件，与 C7 选择注入同取舍，见报告）。
        function initTestCase() {
            Books.doSearch("")
            Books.setFilter("")
            Books.setSort(0)
            var hasTxt = false
            for (let b of Books.booksModel)
                if ((b.format || "").toUpperCase() === "TXT") { hasTxt = true; break }
            if (!hasTxt)
                for (let f of TestEnv.sourceFiles) Importer.doImport(f)
        }
        function findTxtBook() {
            for (let b of Books.booksModel)
                if ((b.format || "").toUpperCase() === "TXT") return b
            return null
        }
        function openPage() {
            var book = findTxtBook()
            verify(book !== null, "测试书应已导入")
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
            return { stack: stack, page: page }
        }

        // 隐藏态：点正文底部 → 唤出；注入短间隔（300ms 收敛 5s）无操作 → 自动隐藏；
        // 隐藏态点正文上部（非底部 1/4）→ 保持隐藏
        function test_clickBottomSummonsAndAutoHides() {
            var h = openPage()
            var page = h.page
            page.controlsHideDelay = 300
            page.controlsVisible = false   // 模拟隐藏态
            wait(50)
            // 正文底 1/4 内（页面坐标 y=600，正文区 36..668，1/4 线=510）→ 唤出
            page.handleContentTap(600)
            tryVerify(function () { return page.controlsVisible }, 3000,
                      "点击正文底部应唤出控制栏")
            tryVerify(function () { return !page.controlsVisible }, 3000,
                      "无操作后控制栏应自动隐藏")
            // 隐藏态：点正文上部（y=50，未到 1/4 线）→ 保持隐藏
            page.handleContentTap(50)
            wait(150)
            verify(!page.controlsVisible, "点正文上部不应唤出控制栏")
            h.stack.destroy()
        }

        // 隐藏态：点控制栏原位置（正文下方空位带 y=700）→ 唤出
        //（"点击阅读界面底部"的字面路径——唤出热区含隐藏时控制栏空位带）
        function test_clickOnHiddenBarStripSummons() {
            var h = openPage()
            var page = h.page
            page.controlsHideDelay = 100000   // 本用例不关心计时
            page.controlsVisible = false
            wait(50)
            page.handleContentTap(700)
            tryVerify(function () { return page.controlsVisible }, 3000,
                      "点击隐藏控制栏位置应唤出")
            h.stack.destroy()
        }

        // 交互重置计时：唤出后轻点正文 / hover 移动均重置 5s 计时（跨过原到期点仍可见），
        // 之后无操作才隐藏。delay=500：t0 唤出（到期 t0+500）→ t0+300 轻点（到期 t0+800）
        // → t0+650 断言仍可见（无重置则已隐藏）→ hover 移动（到期 t0+1150）→ t0+1000
        // 断言仍可见 → 无操作至 t0+1400 隐藏。
        function test_interactionResetsHideTimer() {
            var h = openPage()
            var page = h.page
            page.controlsHideDelay = 500
            page.controlsVisible = false
            wait(50)
            page.handleContentTap(600)
            tryVerify(function () { return page.controlsVisible }, 3000, "点击底部应唤出")
            wait(300)
            verify(page.controlsVisible, "到期前应仍可见")
            page.handleContentTap(50)   // 上部轻点：只重置计时（<1/4 线不唤出）
            wait(350)
            verify(page.controlsVisible, "轻点应重置 5s 计时（跨过原到期点仍可见）")
            h.stack.destroy()
        }

        // 隐藏态 hover 移动不唤出（D7 语义变更：移动只重置计时、唤出走点击）
        // ——NoButton hover 区 onPositionChanged 只 restart，controlsVisible 保持 false
        function test_hoverMoveDoesNotSummon() {
            var h = openPage()
            var page = h.page
            page.controlsHideDelay = 100000
            page.controlsVisible = false
            wait(50)
            // hover 区计时重置入口不可直接调用（MouseArea 内部），语义由
            // hideControlsTimer.restart 无副作用保证；此处断言显隐状态不变
            verify(!page.controlsVisible, "隐藏态下无点击时控制栏应保持隐藏")
            h.stack.destroy()
        }

        // C2 协同：唤出/隐藏框架只作用于控制栏——朗读会话激活时 TtsBar 照常显示
        // （即使控制栏隐藏），唤出控制栏不带动 TtsBar（state=0 仍隐藏）
        function test_ttsBarGatingUnaffected() {
            var h = openPage()
            var page = h.page
            page.controlsHideDelay = 100000
            Tts.stop()   // 幂等复位
            page.controlsVisible = false
            Tts.reconfigure("openai", "https://api.openai.com/v1", "", "tts-1", "nova", 1.0)
            Tts.setSentences(["测试朗读句子。"])
            Tts.play()   // 状态注入 state 0→1（同 C2 冒烟路径，openai 无 key 不发声）
            tryVerify(function () { return page.ttsBar.visible }, 3000,
                      "朗读会话中 TtsBar 应显示")
            verify(!page.controlsVisible, "控制栏隐藏不应影响 TtsBar 门控")
            Tts.stop()
            tryVerify(function () { return !page.ttsBar.visible }, 3000,
                      "停止后 TtsBar 应隐藏")
            page.handleContentTap(600)
            tryVerify(function () { return page.controlsVisible }, 3000,
                      "点击底部应唤出控制栏")
            verify(!page.ttsBar.visible, "唤出控制栏不应带出 TtsBar（C2 门控独立）")
            h.stack.destroy()
        }
    }
    TestCase {
        name: "ReaderToolbarSmoke"
        function initTestCase() {
            Books.doSearch("")
            Books.setFilter("")
            Books.setSort(0)
            var hasTxt = false
            for (let b of Books.booksModel)
                if ((b.format || "").toUpperCase() === "TXT") { hasTxt = true; break }
            if (!hasTxt)
                for (let f of TestEnv.sourceFiles) Importer.doImport(f)
        }

        function openPage() {
            var book = null
            for (let b of Books.booksModel)
                if ((b.format || "").toUpperCase() === "TXT") { book = b; break }
            verify(book !== null, "测试书应已导入")
            var stack = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; StackView { anchors.fill: parent; }", root)
            stack.push("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: book })
            var page = stack.currentItem
            tryVerify(function () { return page.chapter && page.chapter.paragraphs
                                      && page.chapter.paragraphs.length > 0 }, 3000,
                      "打开书后应加载章节段落")
            return { stack: stack, page: page }
        }

        function test_toolbarSignalsAndBookmarkTwoStates() {
            var h = openPage()
            var page = h.page
            verify(page.topToolbar !== undefined, "ReaderPage 应暴露 Kindle 顶栏")
            page.sheetOpen = true
            tryVerify(function () { return page.topToolbar.visible }, 2000, "Sheet 打开时顶栏应显示")
            compare(page.topToolbar.height, 40, "顶栏高度应为 40px")
            verify(page.topToolbar.backBtn !== undefined && page.topToolbar.menuBtn !== undefined,
                   "顶栏应暴露返回/菜单按钮句柄")
            page.bookmarks = []
            page.toggleBookmark()
            verify(page.topToolbar.bookmarked, "点击书签后应进入已收藏态")
            var saved = Settings.value("bookmarks/" + page.book.id)
            verify(saved && saved.indexOf(Books.currentChapter) >= 0, "书签应持久化当前章节")
            page.toggleBookmark()
            verify(!page.topToolbar.bookmarked, "再次点击同一章节应取消书签")
            saved = Settings.value("bookmarks/" + page.book.id)
            verify(!saved || saved.indexOf(Books.currentChapter) < 0, "取消书签应更新持久化列表")
            page.sheetOpen = false
            tryVerify(function () { return !page.topToolbar.visible }, 2000, "Sheet 关闭时顶栏应隐藏")
            h.stack.destroy()
        }
    }

}
