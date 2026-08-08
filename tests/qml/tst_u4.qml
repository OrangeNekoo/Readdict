import QtQuick
import QtQuick.Controls
import QtTest
import Readdict.Backend
import Readdict.Test 1.0
import Readdict.UI 1.0

// U4 冒烟：Kindle 底部 Sheet 工具栏 + 线性图标集。
// 1. IconSmoke：KdIcons 线性描边图标（15 个图标名可加载绘制，24px 默认尺寸）；
// 2. BottomSheetSmoke：KdBottomSheet 容器——弹出/收回动画（y 平移 + 遮罩淡入）、
//    四标签切换（KdTabBar 下划线跟动 + 内容 Loader 按 currentId 切换）、底部描边
//    操作按钮、点击遮罩关闭；
// 3. ReaderSheetSmoke：ReaderPage 集成——点屏幕中部弹 Sheet（Kindle 语义整合 C3
//    唤出：底部 1/4 仍唤出快捷控制栏）、四标签真实点击、各面板选项生效（绑定现有
//    Settings 键：background/mode、typography/fontFamily/fontSize/pageWidth/
//    lineHeight、reading/pageMode/autoContinue/darkFollow）、自动续章开关门控
//    autoNextChapter、深色跟随派生 effectiveBg、右上角下拉菜单（目录/笔记/搜索/
//    朗读/上/下章入口可达）。
// 结构约定（与 tst_readerpage/tst_nav 一致）：根为带尺寸的 Item，ReaderPage 经
// StackView push（生产路径）；手势注入经 page.handleContentTap(y)（TapHandler
// 桥接共用同一状态机——quicktest harness 无法可靠合成鼠标事件，见 C3 报告）；
// 面板内选项用 QtTest mouseClick 真实点击（面板是可见窗口内组件）。
Item {
    id: root
    width: 1100; height: 720

    Component {
        id: sheetComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/KdBottomSheet.qml" }
    }
    Component {
        id: iconComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/KdIcons.qml" }
    }
    // BottomSheetSmoke 用的两个测试面板组件（声明式 Component，供 pages 注入）
    Component {
        id: panelA
        Rectangle { objectName: "panelA" }
    }
    Component {
        id: panelB
        Rectangle { objectName: "panelB" }
    }

    TestCase {
        name: "IconSmoke"
        // KdIcons：15 个线性描边图标名全部可加载绘制（Canvas 渲染），默认 24px
        function test_allIconNamesRender() {
            var names = ["shelf", "stats", "sync", "settings", "toc", "theme",
                         "font", "layout", "more", "back", "search", "prev",
                         "next", "read", "notes"]
            for (var i = 0; i < names.length; ++i) {
                var loader = iconComp.createObject(root)
                var icon = loader.item
                verify(icon !== null, "KdIcons 应能加载")
                icon.name = names[i]
                icon.color = "#1A1A1A"
                compare(icon.width, 24, names[i] + " 图标默认 24px")
                compare(icon.height, 24, names[i] + " 图标默认 24px")
                verify(icon.children.length >= 1, names[i] + " 应有 Canvas 渲染子项")
                // 指定尺寸覆盖（28px 上限场景）
                icon.size = 28
                compare(icon.width, 28, names[i] + " size 覆盖应生效")
                loader.destroy()
            }
        }
    }

    TestCase {
        name: "BottomSheetSmoke"
        // KdBottomSheet 容器：弹出动画（body.y 滑到目标位 + 遮罩淡入）、标签切换
        //（KdTabBar 点击发 tabClicked）、内容 Loader 按 currentId 切换、底部操作
        // 按钮（actionText 显示/点击发 actionClicked）、点击遮罩发 maskClicked、
        // 收回动画（body.y 回屏外）。
        function test_slideOpenTabsActionMask() {
            var loader = sheetComp.createObject(root)
            loader.width = 400; loader.height = 600
            var sheet = loader.item
            verify(sheet !== null, "KdBottomSheet 应能加载")
            sheet.tabs = [{ id: "a", text: "A" }, { id: "b", text: "B" }]
            sheet.pages = [{ id: "a", source: panelA }, { id: "b", source: panelB }]
            sheet.currentId = "a"
            tryVerify(function () { return sheet.contentLoader.item !== null }, 3000,
                      "内容 Loader 应加载当前标签面板")
            compare(sheet.contentLoader.item.objectName, "panelA", "currentId=a 显示面板 A")
            compare(sheet.tabBar.items.count, 2, "应有 2 个标签")

            // 关闭态：面板在屏外、遮罩透明且禁用
            tryVerify(function () { return Math.abs(sheet.body.y - loader.height) < 2 }, 3000,
                      "关闭时面板应位于屏外，实际 y=" + sheet.body.y)
            compare(Math.round(sheet.mask.opacity), 0, "关闭时遮罩应透明")

            // 打开：面板滑出到目标位 + 遮罩淡入
            sheet.open = true
            tryVerify(function () {
                return Math.abs(sheet.body.y - (loader.height - sheet.body.height)) < 2
            }, 3000, "打开时面板应滑出到目标位，实际 y=" + sheet.body.y)
            tryVerify(function () { return Math.abs(sheet.mask.opacity - 1) < 0.05 }, 3000,
                      "打开时遮罩应淡入")

            // 标签真实点击 → tabClicked（KdTabBar → sheet 接线）
            var gotTab = ""
            sheet.tabClicked.connect(function (id) { gotTab = id })
            tryVerify(function () {
                var it = sheet.tabBar.items.itemAt(1)
                return it !== null && it.width > 50
            }, 2000, "标签委托应就绪")
            mouseClick(sheet.tabBar.items.itemAt(1),
                       sheet.tabBar.items.itemAt(1).width / 2,
                       sheet.tabBar.items.itemAt(1).height / 2)
            compare(gotTab, "b", "点击第二个标签应发 tabClicked(b)")
            // currentId 驱动内容切换
            sheet.currentId = "b"
            tryVerify(function () { return sheet.contentLoader.item.objectName === "panelB" }, 3000,
                      "currentId=b 显示面板 B")

            // 底部操作按钮：actionText 非空 → 显示，点击发 actionClicked
            compare(sheet.actionBar.height, 0, "无 actionText 时操作区高度为 0")
            sheet.actionText = "保存"
            tryVerify(function () { return sheet.actionBar.height > 0 }, 3000,
                      "设置 actionText 后操作区应显示")
            var gotAction = false
            sheet.actionClicked.connect(function () { gotAction = true })
            var btn = sheet.actionBar.children[0]
            verify(btn !== undefined && btn !== null, "操作区应有按钮")
            btn.clicked()
            verify(gotAction, "点击操作按钮应发 actionClicked")

            // 点击遮罩（面板外区域）→ maskClicked
            var gotMask = false
            sheet.maskClicked.connect(function () { gotMask = true })
            mouseClick(sheet.mask, 10, 10)
            verify(gotMask, "点击面板外遮罩应发 maskClicked")

            // 收回：面板滑回屏外
            sheet.open = false
            tryVerify(function () { return Math.abs(sheet.body.y - loader.height) < 2 }, 3000,
                      "关闭时面板应收回到屏外，实际 y=" + sheet.body.y)
            loader.destroy()
        }
    }

    TestCase {
        name: "ReaderSheetSmoke"

        function initTestCase() {
            // 复位搜索/筛选/排序：全量套件中其他用例可能残留过滤状态（tst_u3 分类
            // 筛选等），导致 Books.booksModel 不完整——findBook 会误判书不存在
            //（本文件在套件末尾执行，残留累积最多）
            Books.doSearch("")
            Books.setFilter("")
            Books.setSort(0)
            if (Books.booksModel.length === 0)
                for (let f of TestEnv.sourceFiles) Importer.doImport(f)
            // 多章节书（自动续章门控 + 上/下章入口用例）
            if (!findBook("TXT", "multibook"))
                Importer.doImport(TestEnv.multiSource)
        }
        function findBook(fmt, titlePart) {
            for (let b of Books.booksModel)
                if ((b.format || "").toUpperCase() === fmt
                        && (!titlePart || (b.title || "").indexOf(titlePart) >= 0))
                    return b
            return null
        }
        function openPage(book) {
            // 无参调用回退到任意 TXT（基础页用例）；需要特定书的用例显式传书
            //（findBook 失败即 verify 失败，防止静默误测错误章节行为）
            var b = book ? book : findBook("TXT", null)
            verify(b !== null, "测试书应已就绪（initTestCase 应已导入）")
            var stack = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; StackView { anchors.fill: parent; }", root)
            verify(stack !== null, "测试 StackView 应能创建")
            stack.push("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: b })
            var page = stack.currentItem
            verify(page !== null, "ReaderPage 应被 push 进 StackView")
            tryVerify(function () {
                return page.chapter && page.chapter.paragraphs
                    && page.chapter.paragraphs.length > 0
            }, 3000, "打开书后应加载章节段落")
            return { stack: stack, page: page }
        }
        // Switch 状态感知点击：与目标状态不一致才点击（避免重复点击来回切换）
        function clickSwitchIfNeeded(sw, wantOn) {
            if (sw.checked === wantOn) return
            mouseClick(sw, sw.width / 2, sw.height / 2)
        }

        // 点屏幕中部 → Sheet 弹出（动画到位 + 遮罩）；再次轻点 → 关闭（点面板外语义）；
        // Sheet 打开暂停控制栏 5s 计时（hideTimer.running 断言），关闭且显示态恢复
        //（短延迟收敛 5s 语义 → 自动隐藏）。
        function test_middleTapOpensSheetAndReTapCloses() {
            var h = openPage()
            var page = h.page
            // 鼠标锚到顶栏按钮（正文 hover 区之外）：正文 hover 区对鼠标活动的计时
            // 重置是 C3 正常语义，残留鼠标位置会以短延迟触发隐藏，干扰计时状态断言
            mouseMove(page.backButton, 5, 5)
            page.controlsHideDelay = 300
            page.sheetOpen = false
            verify(!page.sheetOpen, "初始 Sheet 应关闭")
            page.handleContentTap(200)   // 屏幕中部轻点
            tryVerify(function () { return page.sheetOpen }, 3000, "点屏幕中部应弹出 Sheet")
            var sheet = page.bottomSheet
            tryVerify(function () {
                return Math.abs(sheet.body.y - (page.height - sheet.body.height)) < 2
            }, 3000, "面板应滑出到目标位，实际 y=" + sheet.body.y)
            tryVerify(function () { return Math.abs(sheet.mask.opacity - 1) < 0.05 }, 3000,
                      "遮罩应淡入")
            // Sheet 打开 → 控制栏计时暂停（running 状态精确断言）
            tryVerify(function () { return !page.hideTimer.running }, 3000,
                      "Sheet 打开应暂停控制栏自动隐藏计时")
            // 再点中部 → 关闭（点面板外语义）
            page.handleContentTap(200)
            tryVerify(function () { return !page.sheetOpen }, 3000, "再次轻点应关闭 Sheet")
            tryVerify(function () { return Math.abs(sheet.body.y - page.height) < 2 }, 3000,
                      "面板应收回到屏外，实际 y=" + sheet.body.y)
            // 关闭且控制栏显示 → 计时恢复 → 短延迟后自动隐藏
            tryVerify(function () { return page.hideTimer.running }, 3000,
                      "Sheet 关闭应恢复控制栏计时")
            tryVerify(function () { return !page.controlsVisible }, 3000,
                      "计时恢复后控制栏应自动隐藏")
            // 底部 1/4 轻点仍唤出快捷控制栏（C3 语义保留，与 Sheet 并存）
            page.handleContentTap(600)
            tryVerify(function () { return page.controlsVisible }, 3000,
                      "底部 1/4 轻点应唤出快捷控制栏")
            verify(!page.sheetOpen, "唤出控制栏不应带出 Sheet")
            h.stack.destroy()
        }

        // 四标签真实点击切换（KdTabBar → sheet → page 链路）+ 主题面板四态单选生效
        function test_tabSwitchAndThemePanel() {
            var h = openPage()
            var page = h.page
            page.controlsHideDelay = 100000
            page.handleContentTap(200)
            tryVerify(function () { return page.sheetOpen }, 3000, "点中部应弹出 Sheet")
            var bar = page.bottomSheet.tabBar
            tryVerify(function () { return bar.items.count === 4 }, 3000, "Sheet 应有 4 个标签")

            // 点"字体"标签（index 1）
            tryVerify(function () {
                var it = bar.items.itemAt(1)
                return it !== null && it.width > 50
            }, 2000, "字体标签应就绪")
            mouseClick(bar.items.itemAt(1), bar.items.itemAt(1).width / 2, 10)
            tryVerify(function () { return page.sheetTab === "font" }, 3000,
                      "点击标签应切换 sheetTab")
            tryVerify(function () {
                return page.bottomSheet.contentLoader.item.objectName === "fontSheetPanel"
            }, 3000, "内容应切到字体面板")
            // 点"布局"（index 2）
            mouseClick(bar.items.itemAt(2), bar.items.itemAt(2).width / 2, 10)
            tryVerify(function () {
                return page.bottomSheet.contentLoader.item.objectName === "layoutSheetPanel"
            }, 3000, "内容应切到布局面板")
            // 点"更多"（index 3）
            mouseClick(bar.items.itemAt(3), bar.items.itemAt(3).width / 2, 10)
            tryVerify(function () {
                return page.bottomSheet.contentLoader.item.objectName === "moreSheetPanel"
            }, 3000, "内容应切到更多面板")
            // 回"主题"（index 0）
            mouseClick(bar.items.itemAt(0), bar.items.itemAt(0).width / 2, 10)
            tryVerify(function () {
                return page.bottomSheet.contentLoader.item.objectName === "themeSheetPanel"
            }, 3000, "内容应切回主题面板")

            // 主题面板：四态单选真实点击 → 写 background/mode 并同步 page.bgMode
            var panel = page.bottomSheet.contentLoader.item
            tryVerify(function () { return panel.themeItems.itemAt(1) !== null }, 2000,
                      "深色卡片应就绪")
            mouseClick(panel.themeItems.itemAt(1), 20, 20)
            tryVerify(function () {
                return String(Settings.value("background/mode")) === "dark"
                    && page.bgMode === "dark"
            }, 3000, "选深色应写 background/mode=dark 并同步 bgMode")
            mouseClick(panel.themeItems.itemAt(2), 20, 20)
            tryVerify(function () {
                return String(Settings.value("background/mode")) === "paper"
                    && page.bgMode === "paper"
            }, 3000, "选米白应写 background/mode=paper")
            // 还原浅色
            mouseClick(panel.themeItems.itemAt(0), 20, 20)
            tryVerify(function () {
                return String(Settings.value("background/mode")) === "light"
                    && page.bgMode === "light"
            }, 3000, "还原浅色")
            h.stack.destroy()
        }

        // 字体面板：4 字体族单选 + 字号分段生效（typography/fontFamily、fontSize）
        function test_fontPanelApplies() {
            var h = openPage()
            var page = h.page
            page.controlsHideDelay = 100000
            page.sheetTab = "font"
            page.handleContentTap(200)
            tryVerify(function () { return page.sheetOpen }, 3000, "Sheet 应弹出")
            var panel = page.bottomSheet.contentLoader.item
            tryVerify(function () { return panel.objectName === "fontSheetPanel" }, 3000,
                      "内容应为字体面板")
            // 选"思源黑体 HW VF"（index 2）
            tryVerify(function () { return panel.fontItems.itemAt(2) !== null }, 2000,
                      "HW 字体行应就绪")
            mouseClick(panel.fontItems.itemAt(2), 20, 15)
            tryVerify(function () {
                return String(Settings.value("typography/fontFamily")) === "SourceHanSansHW-VF"
                    && page.fontFamily === "SourceHanSansHW-VF"
            }, 3000, "选 HW 字体应写 typography/fontFamily 并同步 page.fontFamily")
            // 字号 20（index 3）
            tryVerify(function () { return panel.sizeItems.itemAt(3) !== null }, 2000,
                      "字号分段应就绪")
            mouseClick(panel.sizeItems.itemAt(3), 15, 15)
            tryVerify(function () {
                return Number(Settings.value("typography/fontSize")) === 20
                    && page.typography.fontSize === 20
            }, 3000, "选字号 20 应写 typography/fontSize 并刷新排版")
            // 还原默认（思源宋体 VF / 18）
            mouseClick(panel.fontItems.itemAt(0), 20, 15)
            mouseClick(panel.sizeItems.itemAt(2), 15, 15)
            tryVerify(function () {
                return String(Settings.value("typography/fontFamily")) === "思源宋体 VF"
                    && Number(Settings.value("typography/fontSize")) === 18
            }, 3000, "应还原默认字体与字号")
            h.stack.destroy()
        }

        // 布局面板：方向（reading/pageMode）+ 页边距（pageWidth）+ 行间距（lineHeight）
        function test_layoutPanelApplies() {
            var h = openPage()
            var page = h.page
            page.controlsHideDelay = 100000
            page.sheetTab = "layout"
            page.handleContentTap(200)
            tryVerify(function () { return page.sheetOpen }, 3000, "Sheet 应弹出")
            var panel = page.bottomSheet.contentLoader.item
            tryVerify(function () { return panel.objectName === "layoutSheetPanel" }, 3000,
                      "内容应为布局面板")
            // 方向：整页翻动（index 1）
            tryVerify(function () { return panel.modeItems.itemAt(1) !== null }, 2000,
                      "方向分段应就绪")
            mouseClick(panel.modeItems.itemAt(1), 15, 15)
            tryVerify(function () {
                return String(Settings.value("reading/pageMode")) === "paged"
                    && page.pageMode === "paged"
            }, 3000, "选整页翻动应写 reading/pageMode=paged 并即时生效")
            // 页边距：宽（index 2）
            mouseClick(panel.marginItems.itemAt(2), 15, 15)
            tryVerify(function () {
                return String(Settings.value("typography/pageWidth")) === "wide"
                    && page.typography.pageWidth === "wide"
            }, 3000, "选页边距宽应写 typography/pageWidth")
            // 行间距：标准（index 1）
            mouseClick(panel.lineItems.itemAt(1), 15, 15)
            tryVerify(function () {
                return Number(Settings.value("typography/lineHeight")) === 1.6
                    && Number(page.typography.lineHeight) === 1.6
            }, 3000, "选标准行距应写 typography/lineHeight")
            // 还原
            mouseClick(panel.modeItems.itemAt(0), 15, 15)
            mouseClick(panel.marginItems.itemAt(1), 15, 15)
            tryVerify(function () {
                return String(Settings.value("reading/pageMode")) === "scroll"
                    && String(Settings.value("typography/pageWidth")) === "normal"
            }, 3000, "应还原方向与页边距")
            h.stack.destroy()
        }

        // 更多面板：自动续章开关门控 autoNextChapter + 深色跟随派生 effectiveBg
        function test_morePanelToggles() {
            var h = openPage(findBook("TXT", "multibook"))
            var page = h.page
            page.controlsHideDelay = 100000
            page.loadChapter(0)
            wait(100)
            page.sheetTab = "more"
            page.handleContentTap(200)
            tryVerify(function () { return page.sheetOpen }, 3000, "Sheet 应弹出")
            var panel = page.bottomSheet.contentLoader.item
            tryVerify(function () { return panel.objectName === "moreSheetPanel" }, 3000,
                      "内容应为更多面板")
            // 自动续章默认开
            verify(page.autoContinue, "自动续章默认应开启")
            // 关闭开关（真实点击；状态感知：当前开 → 点一次关闭）
            clickSwitchIfNeeded(panel.continueToggle, false)
            tryVerify(function () {
                return !page.autoContinue && Settings.value("reading/autoContinue") === false
            }, 3000, "关闭开关应写 reading/autoContinue=false 并同步 page.autoContinue")
            // 门控生效：autoNextChapter 不再换章
            var ch = Books.currentChapter
            page.autoNextChapter()
            wait(150)
            compare(Books.currentChapter, ch, "关闭自动续章后 autoNextChapter 不应换章")
            // 再开启 → 换章生效
            clickSwitchIfNeeded(panel.continueToggle, true)
            tryVerify(function () { return page.autoContinue }, 3000, "再点开关应恢复开启")
            page.autoNextChapter()
            tryVerify(function () { return Books.currentChapter === ch + 1 }, 3000,
                      "开启后 autoNextChapter 应换下一章")

            // 深色跟随默认关：有效背景 = 显式选择
            verify(!page.darkFollow, "深色跟随默认应关闭")
            compare(page.effectiveBg, page.bgMode, "关闭时有效背景 = 显式选择")
            // 开启 → effectiveBg 跟随 UITheme.isDark（写入单例属性模拟主题深浅切换）
            clickSwitchIfNeeded(panel.followToggle, true)
            tryVerify(function () { return page.darkFollow }, 3000, "开启深色跟随")
            UITheme.isDark = true
            tryVerify(function () { return page.effectiveBg === "dark" }, 3000,
                      "主题深色时有效背景应为 dark")
            UITheme.isDark = false
            tryVerify(function () { return page.effectiveBg !== "dark" }, 3000,
                      "主题浅色时有效背景不应为 dark")
            // 还原（开关关 + isDark 复位，避免污染后续用例）
            clickSwitchIfNeeded(panel.followToggle, false)
            tryVerify(function () { return !page.darkFollow }, 3000, "关闭深色跟随")
            UITheme.isDark = false
            compare(page.effectiveBg, page.bgMode, "关闭后有效背景还原为显式选择")
            // 还原自动续章为开启（后续用例依赖默认行为）
            clickSwitchIfNeeded(panel.continueToggle, true)
            tryVerify(function () { return page.autoContinue }, 3000, "还原自动续章开启")
            h.stack.destroy()
        }

        // 右上角下拉菜单：遮罩开合 + 功能入口可达（目录/笔记/书内搜索/朗读/上/下章）
        function test_topRightMenuEntries() {
            var h = openPage(findBook("TXT", "multibook"))
            var page = h.page
            page.controlsHideDelay = 100000
            page.loadChapter(0)
            wait(100)
            // 菜单打开（遮罩 + 面板显示）
            page.menuOpen = true
            tryVerify(function () { return page.readerMenu.visible }, 3000, "菜单应显示")
            tryVerify(function () { return page.menuItems.itemAt(0) !== null }, 2000,
                      "菜单项应就绪")
            // 笔记入口（Modal Dialog 开合后再点菜单项的路径：Dialog.close 后需等退出
            // 动画完全结束（visible=false），否则模态遮罩残留吞掉下一次点击——无头
            // 环境动画推进慢，用 tryVerify(!visible) 自适等待）
            mouseClick(page.menuItems.itemAt(1), 200, 20)
            tryVerify(function () { return !page.menuOpen }, 3000, "点击菜单项应关闭菜单")
            tryVerify(function () { return page.notesDialog.visible }, 3000, "笔记 Dialog 应打开")
            page.notesDialog.close()
            tryVerify(function () { return !page.notesDialog.visible }, 3000,
                      "笔记 Dialog 应完全关闭")
            // 书内搜索入口
            page.menuOpen = true
            mouseClick(page.menuItems.itemAt(2), 200, 20)
            tryVerify(function () { return page.searchDialog.visible }, 3000, "搜索 Dialog 应打开")
            page.searchDialog.close()
            tryVerify(function () { return !page.searchDialog.visible }, 3000,
                      "搜索 Dialog 应完全关闭")
            // 目录入口
            page.menuOpen = true
            mouseClick(page.menuItems.itemAt(0), 200, 20)
            tryVerify(function () { return page.tocDlg.visible }, 3000, "目录 Dialog 应打开")
            page.tocDlg.close()
            tryVerify(function () { return !page.tocDlg.visible }, 3000,
                      "目录 Dialog 应完全关闭")
            // 朗读入口：无会话时点击启动（TtsBar 门控后唯一启动语义同控制栏朗读按钮）
            Tts.reconfigure("openai", "https://api.openai.com/v1", "", "tts-1", "nova", 1.0)
            Tts.setSentences(["测试朗读句子。"])
            page.menuOpen = true
            mouseClick(page.menuItems.itemAt(3), 20, 20)
            tryVerify(function () { return Tts.state === 1 }, 3000, "菜单朗读应启动会话")
            Tts.stop()
            // 上一章：首章钳制（chapter 0 → 0）
            page.menuOpen = true
            mouseClick(page.menuItems.itemAt(4), 20, 20)
            tryVerify(function () { return !page.menuOpen }, 3000, "菜单应关闭")
            compare(Books.currentChapter, 0, "首章上一章应钳制在 0")
            // 下一章：0 → 1
            page.menuOpen = true
            mouseClick(page.menuItems.itemAt(5), 200, 20)
            tryVerify(function () { return Books.currentChapter === 1 }, 3000,
                      "下一章应换到第 2 章")
            // 遮罩关闭：菜单打开后点击面板外区域（顶栏左侧 y=10）→ 关闭
            page.menuOpen = true
            tryVerify(function () { return page.readerMenu.visible }, 3000, "菜单应再次打开")
            mouseClick(page.readerMenu, 30, 10)
            tryVerify(function () { return !page.menuOpen }, 3000, "点击遮罩应关闭菜单")
            h.stack.destroy()
        }
    }
}
