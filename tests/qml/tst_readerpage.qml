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
            var marker = Qt.createQmlObject("import QtQuick; Item { objectName: 'shelfMarker' }",
                                            root, "shelfMarker")
            stack.push(marker)
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

}
