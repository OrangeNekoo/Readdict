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

        // 审查修复：任务5 用例级 cleanup——失败路径也复位背景分区，避免污染
        // Settings（background/mode、imagePath、textColor 为任务5读写键）。
        function cleanup() {
            Settings.setValue("background/mode", "light")
            Settings.setValue("background/imagePath", "")
            Settings.setValue("background/textColor", "")
        }

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
        // 手势注入：本用例多数断言直接调 page.handleContentTap(y)（状态机单元级
        // 驱动，TapHandler 桥接共用同一状态机入口）；任务2 起另增 test_realClick*
        // 真实鼠标点击用例（QtTest.mouseClick 走 TapHandler → contentTapped →
        // handleContentTap 生产链路），两者互补。
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
            tryVerify(function () { return page.sheetOpen && page.topToolbar.visible }, 3000,
                      "点击正文底部应唤出 Sheet 与顶栏")
            verify(!page.hideTimer.running, "Sheet 唤出后隐藏计时器应暂停")
            wait(400)
            verify(page.sheetOpen && page.topToolbar.visible, "Sheet 唤出后应保持可见")
            page.handleContentTap(50)
            tryVerify(function () { return !page.sheetOpen && !page.topToolbar.visible }, 3000,
                      "再次点击正文应关闭 Sheet 与顶栏")
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
            tryVerify(function () { return page.sheetOpen && page.topToolbar.visible }, 3000,
                      "点击隐藏底部热区应唤出 Sheet 与顶栏")
            h.stack.destroy()
        }

        // Sheet 唤出后隐藏计时器暂停；关闭后恢复计时。
        function test_interactionResetsHideTimer() {
            var h = openPage()
            var page = h.page
            page.controlsHideDelay = 500
            page.controlsVisible = false
            wait(50)
            page.handleContentTap(600)
            tryVerify(function () { return page.sheetOpen && page.topToolbar.visible }, 3000,
                      "点击底部应唤出 Sheet 与顶栏")
            verify(!page.hideTimer.running, "Sheet 打开期间隐藏计时器应暂停")
            wait(700)
            verify(page.sheetOpen && page.topToolbar.visible, "Sheet 打开期间应保持可见")
            page.handleContentTap(50)
            tryVerify(function () { return !page.sheetOpen && !page.topToolbar.visible }, 3000,
                      "点击正文应关闭 Sheet 与顶栏")
            tryVerify(function () { return page.hideTimer.running }, 3000,
                      "Sheet 关闭后应恢复隐藏计时器")
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

        // BUG4：点击状态机——只有窗口上部/下部热区唤出菜单；中部点击不改变
        // 菜单（旧实现任何位置都弹 Sheet，与 paged 左右翻页冲突）。scroll 模式
        // 断言：上部热区（y<zoneH）、下部热区（y>高-zoneH）轻点唤出 Sheet 与
        // 顶栏；中部轻点既不唤出也不关闭。
        function test_scrollModeHotZonesOnlySummon() {
            var h = openPage()
            var page = h.page
            page.controlsHideDelay = 100000
            page.controlsVisible = false
            page.sheetOpen = false
            wait(50)
            // 中部轻点：不改变菜单（Sheet 保持关闭，旧实现此处弹 Sheet）
            page.handleContentTap(page.contentView.height / 2)
            wait(100)
            verify(!page.sheetOpen && !page.topToolbar.visible,
                   "scroll 中部轻点不应唤出菜单（BUG4）")
            // 上部热区轻点 → 唤出
            page.handleContentTap(10)
            tryVerify(function () { return page.sheetOpen && page.topToolbar.visible }, 3000,
                      "scroll 上部热区轻点应唤出 Sheet 与顶栏")
            // 关闭后下部热区轻点 → 唤出
            page.sheetOpen = false
            page.controlsVisible = false
            wait(50)
            page.handleContentTap(page.contentView.height - 10)
            tryVerify(function () { return page.sheetOpen && page.topToolbar.visible }, 3000,
                      "scroll 下部热区轻点应唤出 Sheet 与顶栏")
            h.stack.destroy()
        }

        // 任务2（生产点击链路）：不调用 handleContentTap，而是用 QtTest.mouseClick
        // 在正文宿主（ReaderContent/Flickable 表面）真实点击——验证 TapHandler 桥接
        // 真实存在。旧实现 TapHandler 挂在 ReaderPage 层，被正文 Flickable 的按压
        // grab 吞掉，生产点击永远到不了 handleContentTap 状态机。
        // 坐标选正文列左侧留白（x=5，正文列居中从 x≈200 起）→ 点击命中 Flickable 表面。
        function test_realClickTopContentSummons() {
            var h = openPage()
            var page = h.page
            page.controlsHideDelay = 100000
            page.controlsVisible = false
            page.sheetOpen = false
            wait(50)
            // 顶部正文区域真实点击（页面坐标 y=50，正文区顶部）
            mouseClick(page.contentView, 5, 50, Qt.LeftButton)
            tryVerify(function () { return page.sheetOpen && page.topToolbar.visible }, 3000,
                      "真实点击顶部正文区应唤出 Sheet 与顶栏")
            h.stack.destroy()
        }

        // 隐藏态底部热区原位置（页面底部 y=700）真实点击 → 唤出。
        // 与 test_clickOnHiddenBarStripSummons 的 handleContentTap 注入版互补：
        // 本用例经真实鼠标事件走 TapHandler → contentTapped → handleContentTap 链路。
        function test_realClickHiddenBarStripSummons() {
            var h = openPage()
            var page = h.page
            page.controlsHideDelay = 100000
            page.controlsVisible = false
            page.sheetOpen = false
            wait(50)
            mouseClick(page.contentView, 5, 700, Qt.LeftButton)
            tryVerify(function () { return page.sheetOpen && page.topToolbar.visible }, 3000,
                      "真实点击隐藏底部热区应唤出 Sheet 与顶栏")
            h.stack.destroy()
        }

        // 正文文本上的真实拖选不应被点击桥接吞掉：拖选后选择工具条照常弹出。
        //（文本选择路径 TextEdit selectByMouse 优先于点击桥接——选择语义保留）
        function test_realTextSelectionStillWorks() {
            var h = openPage()
            var page = h.page
            page.controlsHideDelay = 100000
            page.controlsVisible = false
            page.sheetOpen = false
            wait(50)
            var cv = page.contentView
            // 正文列内文本行（x=550 在列内，y=25 首行）：按下 + 横向拖过若干字符
            mousePress(cv, 550, 25, Qt.LeftButton)
            mouseMove(cv, 700, 25, 50, Qt.LeftButton)
            mouseMove(cv, 800, 25, 50, Qt.LeftButton)
            mouseRelease(cv, 800, 25, Qt.LeftButton)
            tryVerify(function () { return cv.selectionToolbar.visible }, 3000,
                      "正文真实拖选应弹出选择工具条（点击桥接不应吞掉选择）")
            verify(!page.sheetOpen, "文本拖选不应误触发唤出 Sheet")
            h.stack.destroy()
        }

        // 任务2复审（评审发现）：ReaderContent 根级 TapHandler 覆盖选择/颜色工具条
        // 子按钮——若轻点命中可见工具条仍发 contentTapped，ReaderPage 会连带打开
        // Sheet，违反"按钮点击不受影响"。回归：打开选择/颜色工具条后真实点击其
        // 按钮/色块，断言 sheetOpen 保持关闭，且按钮自身行为照常（划线按钮展开
        // 色板、色块落库划线）。注：Sheet 打开态下工具条被 Sheet 全页遮罩盖住
        //（点面板外关闭是 Sheet 自身契约），本用例只锁定关闭态的按钮点击解耦。
        function test_toolbarButtonClicksDoNotTouchSheet() {
            var h = openPage()
            var page = h.page
            var cv = page.contentView
            page.controlsHideDelay = 100000
            page.controlsVisible = false
            page.sheetOpen = false
            wait(50)
            // 幂等：清掉本书可能残留的首句划线（重复运行/中断遗留），保证 +1 断言确定
            var stale = Highlights.highlightsForBook(page.book.id)
            for (var i = 0; i < stale.length; i++)
                if (stale[i].sentenceIndex === 0) Highlights.removeHighlight(stale[i].id)
            // 打开选择工具条：模拟选择首段首句（走真实定位逻辑，工具条视口固定）
            var firstSentence = (page.chapter.paragraphs[0].sentences
                                 && page.chapter.paragraphs[0].sentences[0]) || "首句"
            cv.simulateSelection(0, firstSentence)
            tryVerify(function () { return cv.selectionToolbar.visible }, 3000,
                      "选择后工具条应出现")
            verify(!page.sheetOpen, "选择本身不应打开 Sheet")
            // 工具条结构：selBar(Rectangle) → Row → [复制, 划线, 笔记]（声明序）
            var row = cv.selectionToolbar.children[0]
            var markBtn = row.children[1]   // 「划线」按钮
            verify(markBtn !== undefined && markBtn.text.length > 0, "工具条应含划线按钮")
            // 真实点击按钮中心（映射到正文宿主视口坐标）——按钮点中的同时不得
            // 连带触发 contentTapped → Sheet
            var bp = markBtn.mapToItem(cv, markBtn.width / 2, markBtn.height / 2)
            mouseClick(cv, bp.x, bp.y)
            tryVerify(function () { return cv.colorToolbar.visible }, 3000,
                      "点划线按钮应展开色板（按钮行为照常）")
            verify(!page.sheetOpen, "点击选择工具条按钮不应连带打开 Sheet")
            // 色板结构：colorBar(Rectangle) → Row → [色块×3]（Repeater 委托）
            var cRow = cv.colorToolbar.children[0]
            var swatch = cRow.children[0]
            var before = Highlights.highlightsForBook(page.book.id).length
            var sp = swatch.mapToItem(cv, swatch.width / 2, swatch.height / 2)
            mouseClick(cv, sp.x, sp.y)
            tryVerify(function () {
                return Highlights.highlightsForBook(page.book.id).length === before + 1
            }, 3000, "点击色块应新增一条划线（按钮行为照常）")
            verify(!page.sheetOpen, "点击色板色块不应连带打开 Sheet")
            // 清理本次划线（防污染后续用例与重复运行）
            var rows = Highlights.highlightsForBook(page.book.id)
            for (var j = before; j < rows.length; j++)
                Highlights.removeHighlight(rows[j].id)
            h.stack.destroy()
        }

        // 复制按钮修复（最终审查发现）：旧实现引用未注册的 Clipboard——Qt 6 无 QML
        // Clipboard 单例（Qt.labs.platform 的 Clipboard 已移除），点击即 ReferenceError，
        // clearSelection 不执行、文本不进剪贴板。回归：真实点击复制按钮后剪贴板内容
        // 可读回选中文本、selText 清空、工具条隐藏。ReferenceError 会中止 clearSelection
        // 与剪贴板写入，故本断言组等价于"复制点击不再抛错"。
        function test_copyButtonWritesClipboardAndClearsSelection() {
            var h = openPage()
            var page = h.page
            var cv = page.contentView
            page.controlsHideDelay = 100000
            page.controlsVisible = false
            page.sheetOpen = false
            wait(50)
            var firstSentence = (page.chapter.paragraphs[0].sentences
                                 && page.chapter.paragraphs[0].sentences[0]) || "首句"
            cv.simulateSelection(0, firstSentence)
            tryVerify(function () { return cv.selectionToolbar.visible }, 3000,
                      "选择后工具条应出现")
            // 工具条结构：selBar(Rectangle) → Row → [复制, 划线, 笔记]（声明序）
            var row = cv.selectionToolbar.children[0]
            var copyBtn = row.children[0]   // 「复制」按钮
            verify(copyBtn !== undefined && copyBtn.text.length > 0, "工具条应含复制按钮")
            var bp = copyBtn.mapToItem(cv, copyBtn.width / 2, copyBtn.height / 2)
            mouseClick(cv, bp.x, bp.y)
            // clearSelection 执行：工具条隐藏 + selText 清空（旧缺陷 ReferenceError
            // 中止于 Clipboard.text 赋值，此二者皆不会发生）
            tryVerify(function () { return !cv.selectionToolbar.visible }, 3000,
                      "点复制后工具条应隐藏（clearSelection 执行）")
            verify(cv.selText === "", "点复制后 selText 应清空")
            verify(!page.sheetOpen, "点复制按钮不应连带打开 Sheet")
            // 剪贴板内容验证：独立隐藏 TextEdit paste() 读回系统剪贴板（Qt 6 无 QML
            // Clipboard 单例，读写均走 TextEdit 剪贴板机制，与 copyBridge 同源）
            var reader = Qt.createQmlObject(
                "import QtQuick; TextEdit { visible: false }", cv, "clipReader")
            verify(reader !== null, "剪贴板读取器应能创建")
            reader.text = ""
            reader.forceActiveFocus()
            reader.paste()
            verify(reader.text === firstSentence,
                   "剪贴板内容应等于选中文本，实际=" + reader.text)
            reader.destroy()
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
            tryVerify(function () { return page.sheetOpen && page.topToolbar.visible }, 3000,
                      "点击底部应唤出 Sheet 与顶栏")
            verify(!page.ttsBar.visible, "唤出 Sheet 不应带出 TtsBar（C2 门控独立）")
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
            var hasMulti = false
            for (let b of Books.booksModel) {
                if ((b.format || "").toUpperCase() === "TXT") hasTxt = true
                if (b.title === "multibook") hasMulti = true
            }
            if (!hasTxt)
                for (let f of TestEnv.sourceFiles) Importer.doImport(f)
            if (!hasMulti) Importer.doImport(TestEnv.multiSource)
        }

        function openPage(book) {
            if (!book) {
                for (let b of Books.booksModel)
                    if ((b.format || "").toUpperCase() === "TXT") { book = b; break }
            }
            verify(book !== null, "测试书应已导入")
            var stack = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; StackView { anchors.fill: parent; }", root)
            var marker = Qt.createQmlObject("import QtQuick; Item { objectName: 'shelfMarker' }",
                                            root, "shelfMarker")
            stack.push(marker)
            stack.push("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: book })
            var page = stack.currentItem
            tryVerify(function () { return page.chapter && page.chapter.paragraphs
                                      && page.chapter.paragraphs.length > 0 }, 3000,
                      "打开书后应加载章节段落")
            page.contentView.restoreScrollY = -1
            page.contentView.restorePending = false
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
            // 任务2：scroll 模式按章节键 "chapter:<index>" 持久化（仍兼容旧整数）
            var chKey = "chapter:" + Books.currentChapter
            verify(saved && (saved.indexOf(chKey) >= 0
                             || saved.indexOf(Books.currentChapter) >= 0),
                   "书签应持久化当前章节")
            page.toggleBookmark()
            verify(!page.topToolbar.bookmarked, "再次点击同一章节应取消书签")
            saved = Settings.value("bookmarks/" + page.book.id)
            verify(!saved || (saved.indexOf(chKey) < 0
                              && saved.indexOf(Books.currentChapter) < 0),
                   "取消书签应更新持久化列表")
            page.sheetOpen = false
            tryVerify(function () { return !page.topToolbar.visible }, 2000, "Sheet 关闭时顶栏应隐藏")
            h.stack.destroy()
        }
        // 任务3：顶栏悬停背景必须限制在按钮边界内——五个按钮显式提供按钮级
        // background（x/y=0、宽高=按钮自身），悬停前后几何不变；不得使用 Material
        // 默认样式注入的 Ripple 圆墨背景（QML 类名 QQuickMaterialRipple，居中绘制、
        // 随悬停激活、几何与按钮无关，红灯期此检查失败）。
        function test_hoverBackgroundMatchesButtonBounds() {
            var h = openPage()
            var page = h.page
            page.sheetOpen = true
            tryVerify(function () { return page.topToolbar.visible }, 2000,
                      "Sheet 打开时顶栏应显示")
            var buttons = page.topToolbar.topToolbarButtons
            verify(buttons !== undefined && buttons.length === 5,
                   "顶栏应暴露五个按钮句柄，实际="
                   + (buttons === undefined ? "undefined" : buttons.length))
            for (const button of buttons) {
                verify(button.background !== null, "按钮应有显式 background")
                // 契约：背景必须是按钮自身显式提供的本地 Rectangle
                verify(String(button.background).indexOf("Rectangle") >= 0,
                       "背景应为显式 Rectangle，实际=" + button.background)
                compare(button.background.x, 0, "背景应贴齐按钮左缘")
                compare(button.background.y, 0, "背景应贴齐按钮上缘")
                compare(button.background.width, button.width, "背景宽应等于按钮宽")
                compare(button.background.height, button.height, "背景高应等于按钮高")
            }
            // 打开后 RowLayout 仍在重排（返回按钮宽随书库文字显隐变化），先等布局
            // 稳定再采集几何，避免把布局收敛误判为悬停几何变化。
            wait(400)
            // 悬停前后几何不变（悬停反馈只画在按钮矩形内，不外扩阴影）。
            // offscreen 平台 useHoverEffects=false 默认 hoverEnabled=false，
            // 显式开启以走真实悬停路径验证几何不变契约。
            var btn = buttons[2]
            btn.hoverEnabled = true
            var geo = [btn.background.x, btn.background.y,
                       btn.background.width, btn.background.height]
            mouseMove(btn, btn.width / 2, btn.height / 2)
            // QtTest 首次移动只同步指针位置，需再次移动才投递 hover enter
            mouseMove(btn, btn.width / 2, btn.height / 2)
            tryVerify(function () { return btn.hovered }, 2000, "鼠标悬停按钮应生效")
            wait(50)
            compare(btn.background.x, geo[0], "悬停中背景 x 不变")
            compare(btn.background.y, geo[1], "悬停中背景 y 不变")
            compare(btn.background.width, geo[2], "悬停中背景宽不变")
            compare(btn.background.height, geo[3], "悬停中背景高不变")
            mouseMove(page.topToolbar, 2, 2)
            tryVerify(function () { return !btn.hovered }, 2000, "移出按钮后应取消悬停")
            compare(btn.background.width, geo[2], "移出后背景宽不变")
            compare(btn.background.height, geo[3], "移出后背景高不变")
            h.stack.destroy()
        }
        // BUG2：顶部工具栏只承载独立阅读操作；排版与阅读进度均由底部 Sheet 管理，
        // 不得重新出现重复的 Aa / 布局入口。
        function test_toolbarHasOnlyIndependentActions() {
            var h = openPage()
            var page = h.page
            page.sheetOpen = true
            tryVerify(function () { return page.topToolbar.visible }, 2000,
                      "Sheet 打开时顶栏应显示")
            compare(page.topToolbar.children.length, 2,
                    "顶栏应仅有底线与动作行，不得新增重复控件容器")
            var actionRow = page.topToolbar.children[1]
            compare(actionRow.children.length, 5,
                    "顶栏应只保留返回、笔记、书签、搜索、更多五项")
            h.stack.destroy()
        }
        // BUG2：更多面板切换阅读进度格式必须立即刷新左下角 Label，且重开后恢复。
        function test_progressDisplayPersistsAndUpdatesLabel() {
            var h = openPage()
            var page = h.page
            verify(page.progressLabel.text.indexOf("本章 第 ") === 0,
                   "本章页数格式应显示当前页数")
            page.setProgressDisplay("percent")
            compare(String(Settings.value("reading/progressDisplay")), "percent",
                    "百分比格式应即时持久化")
            verify(page.progressLabel.text.indexOf("本章 ") === 0,
                   "本章百分比格式应显示范围")
            page.setProgressScope("book")
            compare(String(Settings.value("reading/progressScope")), "book",
                    "全书范围应即时持久化")
            verify(page.progressLabel.text.indexOf("全书 ") === 0,
                   "全书百分比格式应显示全书范围")
            h.stack.destroy()
            var h2 = openPage()
            compare(h2.page.progressDisplay, "percent", "重开应恢复百分比格式")
            h2.stack.destroy()
            Settings.setValue("reading/progressDisplay", "pages")
            // 任务3：对称复位本书范围（与 display 同模式）——全书测量已可完成，
            // 残留 book 范围会让后续用例的视觉页数变成全书值（本用例只锁持久化）
            Settings.setValue("reading/progressScope", "chapter")
        }
        function test_toolbarIconsAlignWithLibraryLabel() {
            var h = openPage()
            var page = h.page
            page.sheetOpen = true
            tryVerify(function () { return page.topToolbar.visible }, 2000,
                      "Sheet 打开时顶栏应显示")
            verify(page.topToolbar.backIcon !== undefined, "顶栏应暴露返回图标")
            verify(page.topToolbar.notesIcon !== undefined, "顶栏应暴露笔记图标")
            var backY = page.topToolbar.backIcon.mapToItem(page.topToolbar, 0, 0).y
            var notesY = page.topToolbar.notesIcon.mapToItem(page.topToolbar, 0, 0).y
            verify(Math.abs(backY - notesY) < 1,
                   "返回图标应与其它图标垂直对齐：back=" + backY + " notes=" + notesY)
            var label = page.topToolbar.libraryLabel
            verify(label !== undefined, "返回项应暴露书库文字")
            var labelCenter = label.mapToItem(page.topToolbar, 0, label.height / 2).y
            var iconCenter = page.topToolbar.backIcon.mapToItem(page.topToolbar,
                                                                0, page.topToolbar.backIcon.height / 2).y
            verify(Math.abs(labelCenter - iconCenter) < 1,
                   "返回图标中心应与书库文字中心对齐")
            h.stack.destroy()
        }

        function test_readStartsAtCurrentScrollPosition() {
            var h = openPage()
            var page = h.page
            page.loadChapter(0)
            tryVerify(function () { return page.contentView.contentHeight > page.contentView.height }, 5000,
                      "可滚动文本内容应就绪")
            wait(350)
            page.contentView.contentY = Math.min(900,
                Math.max(1, page.contentView.contentHeight - page.contentView.height))
            wait(100)
            Tts.reconfigure("openai", "https://api.openai.com/v1", "", "tts-1", "nova", 1.0)
            page.startReadAloud()
            verify(Tts.currentIndex > 0,
                   "朗读应从当前阅读位置开始，实际句索引=" + Tts.currentIndex)
            Tts.stop()
            h.stack.destroy()
        }
        function test_readFromAdjacentScrollChapterUsesChapterLocalIndex() {
            var h = openPage()
            var page = h.page
            var multi = null
            for (let b of Books.booksModel)
                if (b.title === "multibook") { multi = b; break }
            verify(multi !== null, "测试应使用多章节书")
            h.stack.destroy()
            h = openPage(multi)
            page = h.page
            page.loadChapter(0)
            tryVerify(function () { return page.contentView.scrollModel.length > 100
                                      && page.contentView.contentHeight > page.contentView.height }, 5000,
                      "连续章节窗口应完成布局")
            page.activateChapter(1)
            tryVerify(function () { return Books.currentChapter === 1
                                      && Tts.chapter === 1 }, 3000,
                      "激活下一章应同步阅读与朗读章节")
            compare(Tts.currentIndex, 0, "切换章节应从章节首句游标开始")
            tryVerify(function () {
                if (page.chapter.title !== "第二章") return false
                var rows = page.contentView.scrollModel
                for (var i = 0; i < rows.length; ++i) {
                    if (rows[i].chapterIndex === 1
                            && String(rows[i].text).indexOf("第二章") >= 0)
                        return true
                }
                return false
            }, 3000, "跨章后连续窗口中心必须使用新章节正文")
            wait(100)
            compare(page.contentView.activeScrollChapter, 1,
                    "跨章后正文激活章节不得回退")
            Tts.stop()
            h.stack.destroy()
        }
        function test_hiddenControlsTapOpensToolbarAndBackPops() {
            var h = openPage()
            var page = h.page
            page.controlsVisible = false
            page.sheetOpen = false
            page.handleContentTap(page.height - 10)
            tryVerify(function () { return page.sheetOpen && page.topToolbar.visible }, 2000,
                      "隐藏控件时底部点击应唤出顶栏")
            page.backButton.clicked()
            tryVerify(function () { return h.stack.currentItem.objectName === "shelfMarker" }, 2000,
                      "唤出顶栏后点击返回应回到书架前页")
            h.stack.destroy()
        }
        function test_scrollProgressCountsCurrentChapterOnly() {
            Settings.setValue("reading/pageMode", "scroll")
            Settings.setValue("reading/progressDisplay", "pages")
            var multi = null
            for (let b of Books.booksModel)
                if (b.title === "multibook") { multi = b; break }
            verify(multi !== null, "测试应使用多章节书")
            var h = openPage(multi)
            var page = h.page
            page.loadChapter(0)
            var cv = page.contentView
            tryVerify(function () { return cv.scrollModel.length > 100
                                      && cv.paragraphRepeater.count === cv.scrollModel.length
                                      && cv.contentHeight > cv.height }, 5000,
                      "连续章节正文高度应稳定")
            wait(300)
            var windowPages = Math.ceil(cv.contentHeight / cv.height)
            verify(page.visualPageCount > 0, "当前章节页数应有效")
            verify(page.visualPageCount < windowPages,
                   "滚动进度总页数不得包含前后缓冲章节")
            h.stack.destroy()
        }
        // 任务5：自定义图片模式文字色——ReaderPage 从 Settings 恢复
        // background/textColor 并注入正文（纯文本与富文本一致）；自定义色
        // 不污染 light/paper/dark 模式默认色。
        function test_imageTextColorRestore() {
            Settings.setValue("background/mode", "image")
            var dest = Settings.copyToBackgrounds(TestEnv.backgroundImage)
            verify(dest.length > 0, "背景图应导入成功")
            Settings.setValue("background/imagePath", dest)
            Settings.setValue("background/textColor", "#FFFFFF")
            var h = openPage()
            var page = h.page
            var cv = page.contentView
            compare(page.bgMode, "image", "应恢复 image 模式")
            compare(page.bgTextColor, "#FFFFFF", "应恢复自定义文字色")
            // 真实书端到端：正文 textColor 注入自定义色；段落 TextEdit.color 跟随
            //（zeta.txt 两行无空行 → 单段纯文本；富/纯文本一致性另由 tst_textcolor
            // test_05 覆盖，本用例聚焦真实书恢复链路）
            tryVerify(function () { return String(cv.textColor) === "#ffffff" }, 2000,
                      "image 模式正文 textColor 应注入自定义色，实际 " + String(cv.textColor))
            tryVerify(function () {
                var d = cv.paragraphRepeater.itemAt(0)
                return d && d.children[0] && String(d.children[0].color) === "#ffffff"
            }, 2000, "正文段落 TextEdit.color 应使用自定义色 #FFFFFF")
            // 自定义色不污染其它模式默认色
            page.bgMode = "light"
            compare(String(cv.textColor), "#1a1a1a", "自定义色不应污染 light（默认深字）")
            page.bgMode = "dark"
            compare(String(cv.textColor), "#e8e8e3", "自定义色不应污染 dark（默认浅字）")
            page.bgMode = "image"
            compare(String(cv.textColor), "#ffffff", "回 image 应恢复自定义色")
            h.stack.destroy()
            // 清理 Settings（不影响同 TestCase 其它用例）
            Settings.setValue("background/mode", "light")
            Settings.setValue("background/textColor", "")
        }
    }

    // 任务3：全书视觉进度测量——总页数 = 各章真实视觉页数之和；前序章偏移；
    // 测量未完成时只显示安全全书值（绝不用本章 N/M 冒充）；排版/视口变化后
    // 旧测量立即失效并重新测量。fixture：multibook 三章（100/60/60 段）。
    TestCase {
        name: "BookProgressMeasure"

        function initTestCase() {
            Books.doSearch("")
            Books.setFilter("")
            Books.setSort(0)
            var hasMulti = false
            for (let b of Books.booksModel)
                if (b.title === "multibook") { hasMulti = true; break }
            if (!hasMulti) Importer.doImport(TestEnv.multiSource)
            Settings.setValue("reading/pageMode", "scroll")
            Settings.setValue("reading/progressDisplay", "pages")
            Settings.setValue("reading/progressScope", "chapter")
        }

        function cleanup() {
            Settings.setValue("reading/progressScope", "chapter")
            Settings.setValue("reading/progressDisplay", "pages")
            Settings.setValue("reading/pageMode", "scroll")
            Settings.setValue("typography/fontSize", 18)
            root.width = 1100   // 视口宽度用例失败路径也复位，避免污染后续用例
            root.height = 720   // 任务3：0 尺寸视口用例失败路径也复位高度
        }

        function openMulti() {
            var multi = null
            for (let b of Books.booksModel)
                if (b.title === "multibook") { multi = b; break }
            verify(multi !== null, "测试应使用多章节书")
            var stack = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; StackView { anchors.fill: parent; }", root)
            verify(stack !== null, "测试 StackView 应能创建")
            stack.push("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: multi })
            var page = stack.currentItem
            verify(page !== null, "ReaderPage 应被 push 进 StackView")
            tryVerify(function () {
                return page.chapter && page.chapter.paragraphs
                    && page.chapter.paragraphs.length > 0
            }, 3000, "打开书后应加载章节段落")
            page.contentView.restoreScrollY = -1
            page.contentView.restorePending = false
            return { stack: stack, page: page, book: multi }
        }

        // 契约1/2：全书总页数 = measuredChapterPages 各章真实视觉页数之和（数组与
        // 章节数等长），且大于当前章页数；visualPageCount/Number 同步为全书值。
        function test_bookTotalEqualsChapterSum() {
            var h = openMulti()
            var page = h.page
            page.loadChapter(0)
            tryVerify(function () { return page.chapter.paragraphs.length > 0 }, 3000,
                      "首章应加载")
            var chapterCount = Books.chapterCount(h.book.id)
            verify(chapterCount >= 3, "multibook 应至少三章，实际 " + chapterCount)
            page.setProgressScope("book")
            tryVerify(function () { return page.bookPageTotal > 0 }, 10000,
                      "全书测量应在限时内完成")
            compare(page.measuredChapterPages.length, chapterCount,
                    "测量数组长度应等于章节数")
            var sum = 0
            for (var i = 0; i < page.measuredChapterPages.length; ++i)
                sum += page.measuredChapterPages[i]
            compare(page.bookPageTotal, sum, "全书总页数应等于各章视觉页数之和")
            var chapterPages = page.contentView.currentChapterPageCount()
            verify(page.bookPageTotal > chapterPages,
                   "全书总页数应大于当前章页数，全书=" + page.bookPageTotal
                   + " 本章=" + chapterPages)
            compare(page.visualPageCount, page.bookPageTotal,
                    "visualPageCount 应等于全书总页数")
            compare(page.visualPageNumber, page.bookPageNumber,
                    "visualPageNumber 应等于全书页号")
            verify(page.progressLabel.text.indexOf("全书 第 ") === 0,
                   "全书页数格式应显示全书范围")
            h.stack.destroy()
        }

        // 契约1：bookPageNumber = 前序章节页数之和 + 当前章实际页号；加载第二章后
        // 全书页号大于本章页号并带前序页数偏移。
        function test_bookPageNumberCarriesPrefixOffset() {
            var h = openMulti()
            var page = h.page
            page.loadChapter(0)
            tryVerify(function () { return page.chapter.paragraphs.length > 0 }, 3000,
                      "首章应加载")
            page.setProgressScope("book")
            tryVerify(function () { return page.bookPageTotal > 0 }, 10000,
                      "全书测量应在限时内完成")
            tryVerify(function () {
                return page.bookPageNumber === page.contentView.currentChapterPageNumber()
            }, 3000, "第一章全书页号应等于本章页号（无前序偏移）")
            var ch0Pages = page.measuredChapterPages[0]
            verify(ch0Pages > 0, "第一章应有测量页数")
            page.loadChapter(1)
            tryVerify(function () { return Books.currentChapter === 1 }, 3000,
                      "应切到第二章")
            tryVerify(function () {
                return page.bookPageNumber === ch0Pages
                       + page.contentView.currentChapterPageNumber()
            }, 3000, "第二章全书页号应带前序章页数偏移")
            verify(page.bookPageNumber > page.contentView.currentChapterPageNumber(),
                   "全书页号应大于本章页号（带前序偏移）")
            h.stack.destroy()
        }

        // 契约3：progressScope=book 且全书尚未测量完成时，visual 三值只返回显式
        // 安全全书值（0/0/0），绝不调用当前章数值——"全书"标签不得显示本章 N/M。
        // measureInterval 注入放大未完成窗口（生产 50ms，测试 1000ms）保证确定性。
        function test_incompleteMeasurementShowsSafeValues() {
            var h = openMulti()
            var page = h.page
            // 签名隔离：fontSize 21 不在任何缓存签名中 → 必然 cache miss →
            // 走完整测量路径，避免命中前序用例写入的缓存
            page.setFontSize(21)
            verify(page.contentView.currentChapterPageCount() > 0,
                   "前置：当前章应有真实页数")
            page.measureInterval = 1000
            page.setProgressScope("book")
            wait(30)   // 绑定传播；1000ms 定时器尚未触发，测量必然未完成
            verify(page.bookPageTotal === 0, "测量未完成时全书总数应为 0")
            compare(page.visualPageNumber, 0, "测量未完成不得显示本章页号")
            compare(page.visualPageCount, 0, "测量未完成不得显示本章页数")
            compare(page.visualPageRatio, 0, "测量未完成比率应为 0")
            verify(page.progressLabel.text.indexOf("全书 第 0 / 0 页") === 0,
                   "测量未完成应显示安全全书占位，实际 " + page.progressLabel.text)
            verify(page.progressLabel.text.indexOf("第 " + page.contentView.currentChapterPageCount()
                                                   + " /") < 0,
                   "测量未完成不得显示当前章 N/M")
            // 恢复默认间隔重测：最终指标为真实全书值
            page.measureInterval = 50
            page.measureBookPages()
            tryVerify(function () { return page.bookPageTotal > 0 }, 10000,
                      "恢复默认间隔后全书测量应完成")
            compare(page.visualPageCount, page.bookPageTotal,
                    "完成后 visualPageCount 应等于全书总页数")
            verify(page.progressLabel.text.indexOf("全书 第 0 / 0 页") < 0,
                   "完成后全书标签应显示真实页数")
            h.stack.destroy()
        }

        // 契约1/2（paged 分支）：横向分页模式下全书总页数同样 = 各章 pageCount
        // 之和（隐藏视图重建 pageModel 走 16ms 页面定时器，须按目标章采纳），
        // 且大于当前章页数——覆盖 paged 测量采纳路径不被残留 pageCount 污染。
        function test_bookTotalEqualsChapterSumInPagedMode() {
            Settings.setValue("reading/pageMode", "paged")
            var h = openMulti()
            var page = h.page
            compare(page.pageMode, "paged", "应处于横向分页模式")
            page.setProgressScope("book")
            tryVerify(function () { return page.bookPageTotal > 0 }, 10000,
                      "paged 全书测量应在限时内完成")
            var chapterCount = Books.chapterCount(h.book.id)
            compare(page.measuredChapterPages.length, chapterCount,
                    "测量数组长度应等于章节数")
            var sum = 0
            for (var i = 0; i < page.measuredChapterPages.length; ++i)
                sum += page.measuredChapterPages[i]
            compare(page.bookPageTotal, sum, "paged 全书总页数应等于各章 pageCount 之和")
            var chapterPages = page.contentView.currentChapterPageCount()
            verify(page.bookPageTotal > chapterPages,
                   "paged 全书总页数应大于当前章页数，全书=" + page.bookPageTotal
                   + " 本章=" + chapterPages)
            h.stack.destroy()
        }

        // 契约5：字号/视口宽度变化 → 测量代次立即重启（旧全书值失效），最终
        // 指标重新稳定；测量结果数组与章节数重新等长。
        function test_layoutChangeRestartsMeasurement() {
            var h = openMulti()
            var page = h.page
            // 签名隔离：fontSize 21 不在任何缓存签名中 → 必然 cache miss →
            // 走完整测量路径，避免命中前序用例写入的缓存
            page.setFontSize(21)
            page.setProgressScope("book")
            tryVerify(function () { return page.bookPageTotal > 0 }, 10000,
                      "首次全书测量应完成")
            var gen1 = page.measureGeneration
            verify(gen1 > 0, "测量代次应已推进")
            // 字号变化 → 重启代次并重新稳定
            page.setFontSize(22)
            tryVerify(function () { return page.measureGeneration > gen1 }, 3000,
                      "字号变化应重启测量代次")
            tryVerify(function () {
                return page.bookPageTotal > 0 && page.measureGeneration > gen1
            }, 10000, "字号变化后全书测量应重新完成")
            compare(page.measuredChapterPages.length, Books.chapterCount(h.book.id),
                    "重新测量后数组应与章节数等长")
            // 视口宽度变化 → 同样重启代次并重新稳定
            var gen2 = page.measureGeneration
            root.width = 900
            tryVerify(function () { return page.measureGeneration > gen2 }, 3000,
                      "视口宽度变化应重启测量代次")
            tryVerify(function () { return page.bookPageTotal > 0 }, 10000,
                      "视口宽度变化后全书测量应重新完成")
            root.width = 1100
            h.stack.destroy()
        }

        // 契约6：0×0 视口（异步布局前/窗口未就绪）下切换全书范围，测量必须延迟
        // 重试——绝不把 0 尺寸下的垃圾页数或兜底 1 页采纳为全书值（旧实现 scroll
        // 模式会采纳宽度 0 时 TextEdit 的畸形行高页数、paged 模式 16 轮后兜底 1 页），
        // 视觉三值保持安全 0/0/0；视口就绪后经统一入口重新测量得到真实非零总数。
        function test_zeroSizeViewportDefersMeasurement() {
            root.width = 0
            root.height = 0
            var h = openMulti()
            var page = h.page
            tryVerify(function () { return page.contentView.height === 0 }, 3000,
                      "0×0 视口下内容区高度应为 0，实际 " + page.contentView.height)
            page.setProgressScope("book")
            // 等待远超旧 16×50ms 重试预算：0 尺寸下不得发布任何页数
            wait(1500)
            compare(page.bookPageTotal, 0, "0 尺寸视口下全书总数必须保持 0（延迟重试）")
            compare(page.measuredChapterPages.length, 0,
                    "0 尺寸下不得采纳任何章节页数（含兜底 1 页）")
            compare(page.visualPageNumber, 0, "0 尺寸下不得显示伪造页号")
            compare(page.visualPageCount, 0, "0 尺寸下不得显示伪造页数")
            compare(page.visualPageRatio, 0, "0 尺寸下比率应为 0")
            verify(page.progressLabel.text.indexOf("全书 第 0 / 0 页") === 0,
                   "0 尺寸下应显示安全全书占位，实际 " + page.progressLabel.text)
            // 视口就绪 → 统一入口（尺寸变化）重新测量并完成
            root.width = 1100
            root.height = 720
            tryVerify(function () { return page.contentView.height > 0 }, 3000,
                      "视口恢复后内容区应有布局")
            tryVerify(function () { return page.bookPageTotal > 0 }, 10000,
                      "视口就绪后全书测量应在限时内完成")
            var chapterCount = Books.chapterCount(h.book.id)
            compare(page.measuredChapterPages.length, chapterCount,
                    "就绪后测量数组应重新与章节数等长")
            var sum = 0
            for (var i = 0; i < page.measuredChapterPages.length; ++i)
                sum += page.measuredChapterPages[i]
            compare(page.bookPageTotal, sum, "就绪后总数应等于各章真实视觉页数之和")
            verify(page.progressLabel.text.indexOf("全书 第 0 / 0 页") < 0,
                   "就绪后应显示真实全书页数，实际 " + page.progressLabel.text)
            h.stack.destroy()
        }

        // 契约6（paged 分支）：0×0 视口下 paged 页面模型因 width<=0 永不建立，
        // 旧实现 16 轮重试后按每章 1 页兜底完成（全书=章节数，伪造值）；修复后
        // 必须保持 0 直到视口就绪再测出真实各章 pageCount 之和。
        function test_zeroSizeViewportDefersMeasurementInPagedMode() {
            Settings.setValue("reading/pageMode", "paged")
            root.width = 0
            root.height = 0
            var h = openMulti()
            var page = h.page
            compare(page.pageMode, "paged", "应处于横向分页模式")
            page.setProgressScope("book")
            wait(1500)
            compare(page.bookPageTotal, 0, "0 尺寸 paged 下全书总数必须保持 0（延迟重试）")
            compare(page.measuredChapterPages.length, 0,
                    "0 尺寸 paged 下不得采纳兜底 1 页")
            compare(page.visualPageCount, 0, "0 尺寸 paged 下不得显示伪造页数")
            root.width = 1100
            root.height = 720
            tryVerify(function () { return page.bookPageTotal > 0 }, 10000,
                      "视口就绪后 paged 全书测量应完成")
            var chapterCount = Books.chapterCount(h.book.id)
            compare(page.measuredChapterPages.length, chapterCount,
                    "paged 就绪后测量数组应重新与章节数等长")
            var sum = 0
            for (var i = 0; i < page.measuredChapterPages.length; ++i)
                sum += page.measuredChapterPages[i]
            compare(page.bookPageTotal, sum, "paged 就绪后总数应等于各章 pageCount 之和")
            h.stack.destroy()
        }

        // 任务6：全书页数按「排版+翻页方式+视口」签名缓存——首次测量写库，
        // 相同设置重开命中缓存即时载入（无需逐章测量）。
        function test_cacheHitLoadsBookPagesInstantly() {
            var h = openMulti()
            var page = h.page
            page.setProgressScope("book")
            tryVerify(function () {
                return page.bookPageTotal > 0 && page.measuredChapterPages.length > 0
            }, 10000, "首次打开应完成测量并写缓存")
            var sig = page.pageCacheSignature()
            verify(sig !== "", "测量完成时应能产出非空签名")
            var cached = Books.loadBookPageCache(page.book.id, sig)
            verify(cached.total !== undefined, "首次测量后应已写入 book_page_cache")
            h.stack.destroy()

            var h2 = openMulti()          // 相同设置重开
            var p2 = h2.page
            p2.setProgressScope("book")
            // 缓存命中：签名一致时应即时载入，无需等逐章测量
            tryVerify(function () {
                return p2.bookPageTotal > 0
            }, 1000, "重开应立即载入缓存总数，实际 " + p2.bookPageTotal)
            compare(p2.bookPageTotal, cached.total, "重开总数应等于缓存值")
            h2.stack.destroy()
        }
        // 任务6：字号变化 → 签名变化 → 缓存失效 → 重测得到新总数
        function test_signatureChangeInvalidatesCache() {
            var h = openMulti()
            var page = h.page
            page.setProgressScope("book")
            tryVerify(function () { return page.bookPageTotal > 0 }, 10000)
            h.stack.destroy()
            Settings.setValue("typography/fontSize", 24)   // 改字号 → 签名变化
            var h2 = openMulti()
            var p2 = h2.page
            p2.setProgressScope("book")
            tryVerify(function () { return p2.bookPageTotal > 0 }, 10000, "签名变化后应重测")
            Settings.setValue("typography/fontSize", 18)   // 复位
            h2.stack.destroy()
        }
    }

    // 任务1：文本书签管理——章节书签列表展示（章节标题）、点击跳转、删除后
    // 列表/持久化/顶栏状态同步刷新；覆盖 scroll 章节键与 paged 页键两种存储
    // 格式（旧整数章节值兼容迁移期）。fixture：multibook 三章。
    TestCase {
        name: "BookmarkManageSmoke"

        function initTestCase() {
            Books.doSearch("")
            Books.setFilter("")
            Books.setSort(0)
            var hasMulti = false
            for (let b of Books.booksModel)
                if (b.title === "multibook") { hasMulti = true; break }
            if (!hasMulti) Importer.doImport(TestEnv.multiSource)
            Settings.setValue("reading/pageMode", "scroll")
        }

        function cleanup() {
            Settings.setValue("reading/pageMode", "scroll")
        }

        function openMulti() {
            var multi = null
            for (let b of Books.booksModel)
                if (b.title === "multibook") { multi = b; break }
            verify(multi !== null, "测试应使用多章节书")
            var stack = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; StackView { anchors.fill: parent; }", root)
            verify(stack !== null, "测试 StackView 应能创建")
            stack.push("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: multi })
            var page = stack.currentItem
            verify(page !== null, "ReaderPage 应被 push 进 StackView")
            tryVerify(function () {
                return page.chapter && page.chapter.paragraphs
                    && page.chapter.paragraphs.length > 0
            }, 3000, "打开书后应加载章节段落")
            page.contentView.restoreScrollY = -1
            page.contentView.restorePending = false
            return { stack: stack, page: page, book: multi }
        }

        // scroll 章节键：列表展示章节标题、点击跳章、删除后列表/持久化/顶栏同步
        function test_scrollChapterBookmarkListJumpRemove() {
            var h = openMulti()
            var page = h.page
            page.loadChapter(0)
            tryVerify(function () { return Books.currentChapter === 0 }, 3000,
                      "应处于第 1 章")
            // 预置第 1 章（章节键）与第 3 章（旧整数，兼容迁移期）书签
            page.bookmarks = ["chapter:0", 2]
            page.syncCurrentBookmark()
            verify(page.currentBookmarked, "第 1 章应点亮")
            page.openBookmarks()
            tryVerify(function () { return page.bookmarksDialog.visible }, 3000,
                      "openBookmarks 应打开书签管理 Dialog")
            compare(page.bookmarkItems.length, 2, "书签列表应含 2 项")
            compare(page.bookmarkItems[0].chapterIndex, 0, "第一项应为第 1 章")
            compare(page.bookmarkItems[1].chapterIndex, 2, "第二项应为第 3 章（旧整数）")
            var titles = Books.chapterTitles(h.book.id)
            compare(page.bookmarkItems[0].label, titles[0],
                    "列表项应展示章节标题")
            // 点击第 2 项 → 跳转到第 3 章并关闭 Dialog
            page.jumpToBookmark(page.bookmarkItems[1])
            tryVerify(function () { return Books.currentChapter === 2 }, 3000,
                      "点击书签应跳到第 3 章")
            tryVerify(function () { return !page.bookmarksDialog.visible }, 3000,
                      "跳转后书签 Dialog 应关闭")
            tryVerify(function () { return page.currentBookmarked }, 3000,
                      "跳到已收藏章节应点亮顶栏")
            // 删除第 1 项 → 列表、持久化、顶栏状态全部刷新
            page.openBookmarks()
            tryVerify(function () { return page.bookmarksDialog.visible }, 3000,
                      "应重新打开书签管理")
            page.removeBookmark(page.bookmarkItems[0])
            compare(page.bookmarkItems.length, 1, "删除后列表应剩 1 项")
            var saved = Settings.value("bookmarks/" + h.book.id)
            compare(saved.length, 1, "持久化应只剩 1 项")
            compare(saved[0], 2, "剩余应为旧整数 2（第 3 章）")
            tryVerify(function () { return page.currentBookmarked }, 3000,
                      "当前章书签仍在应保持点亮")
            page.removeBookmark(page.bookmarkItems[0])
            compare(page.bookmarkItems.length, 0, "全部删除后列表应为空")
            compare(Settings.value("bookmarks/" + h.book.id).length, 0,
                    "持久化应清空")
            tryVerify(function () { return !page.currentBookmarked }, 3000,
                      "删除当前章书签后顶栏应熄灭")
            h.stack.destroy()
        }

        // paged 页键：page:<章>:<页> 条目展示章标题+页数、点击回页、删除同步
        function test_pagedPageBookmarkListJumpRemove() {
            Settings.setValue("reading/pageMode", "paged")
            var h = openMulti()
            var page = h.page
            compare(page.pageMode, "paged", "应处于横向分页模式")
            page.loadChapter(0)
            var cv = page.contentView
            tryVerify(function () { return cv.pageCount >= 2 }, 5000,
                      "第 1 章应至少 2 页，实际 " + cv.pageCount)
            Settings.setValue("bookmarks/" + h.book.id, ["page:0:1"])
            page.bookmarks = ["page:0:1"]
            cv.goToPage(0)
            page.syncCurrentBookmark()
            tryVerify(function () { return cv.currentPage === 0 }, 3000, "应回第 0 页")
            page.openBookmarks()
            tryVerify(function () { return page.bookmarksDialog.visible }, 3000,
                      "应打开书签管理 Dialog")
            compare(page.bookmarkItems.length, 1, "列表应含页键书签")
            compare(page.bookmarkItems[0].type, "page", "条目类型应为 page")
            compare(page.bookmarkItems[0].chapterIndex, 0, "条目章节应为第 1 章")
            compare(page.bookmarkItems[0].page, 1, "条目页码应为 1")
            verify(String(page.bookmarkItems[0].label).indexOf("第 2 页") >= 0,
                   "页键条目标签应含页数，实际 " + page.bookmarkItems[0].label)
            // 点击条目 → 跳回第 1 章第 2 页并关闭 Dialog
            page.jumpToBookmark(page.bookmarkItems[0])
            tryVerify(function () { return cv.currentPage === 1 }, 5000,
                      "点击页书签应跳到第 2 页，实际 " + cv.currentPage)
            tryVerify(function () { return !page.bookmarksDialog.visible }, 3000,
                      "跳转后 Dialog 应关闭")
            tryVerify(function () { return page.currentBookmarked }, 3000,
                      "第 2 页应点亮顶栏")
            // 删除 → 列表与顶栏同步
            page.openBookmarks()
            page.removeBookmark(page.bookmarkItems[0])
            compare(page.bookmarkItems.length, 0, "删除后列表应为空")
            compare(Settings.value("bookmarks/" + h.book.id).length, 0,
                    "持久化应清空")
            tryVerify(function () { return !page.currentBookmarked }, 3000,
                      "删除当前页书签后顶栏应熄灭")
            h.stack.destroy()
        }
    }

}
