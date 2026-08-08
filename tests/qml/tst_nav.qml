import QtQuick
import QtQuick.Controls
import QtTest
import Readdict.Backend
import Readdict.Test 1.0

// U2 冒烟：Kindle 导航体系——KdTabBar 标签切换下划线跟动（3px、选中 Bold）、
// KdBottomNav 4 项底部导航（56px、点击发 itemClicked、选中态跟随）、Main.qml 集成：
// 顶部标签/底部导航与 StackView 联动（切换导航 → 显示对应页、高亮跟随下划线平移）、
// 阅读页（ReaderPage）push 时导航隐藏（沉浸）/返回后恢复。
// 结构约定（与 tst_c4_scroll 一致）：Main.qml 会创建可见 ApplicationWindow，
// 用例结束先隐藏再销毁，避免测试进程残留窗口。
Item {
    id: root
    width: 1100; height: 720

    Component {
        id: tabComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/KdTabBar.qml" }
    }
    Component {
        id: navComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/KdBottomNav.qml" }
    }
    Component {
        id: mainComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/Main.qml" }
    }

    TestCase {
        name: "TabBarSmoke"
        // KdTabBar：文字标签、3px 下划线、选中切换下划线 x 平移跟动、点击发 tabClicked
        function test_underlineFollowsSelection() {
            var loader = tabComp.createObject(root)
            loader.width = 400
            var bar = loader.item
            verify(bar !== null, "KdTabBar 应能加载")
            bar.tabs = [{ id: "a", text: "A" }, { id: "b", text: "B" }]
            compare(bar.items.count, 2, "应有 2 个标签")
            compare(bar.underline.height, 3, "下划线应为 3px")
            bar.currentId = "a"
            compare(Math.round(bar.underline.x), 0, "选中第一项下划线应在最左")
            // 切到第二项：下划线 x 平移跟动到 200（400/2 单元宽）
            bar.currentId = "b"
            tryVerify(function () { return Math.round(bar.underline.x) === 200 }, 3000,
                      "下划线应平移到第二项（x=200），实际 " + bar.underline.x)
            // 切回第一项：跟动回 0
            bar.currentId = "a"
            tryVerify(function () { return Math.round(bar.underline.x) === 0 }, 3000,
                      "下划线应跟动回第一项（x=0），实际 " + bar.underline.x)
            // 点击标签 → tabClicked(id)（委托结构：children[0]=Text [1]=MouseArea；
            // MouseArea.clicked 带 mouse 参数不可直接信号调用，用 QtTest mouseClick）
            var got = ""
            bar.tabClicked.connect(function (id) { got = id })
            tryVerify(function () {
                var it = bar.items.itemAt(1)
                return it !== null && it.width > 50
            }, 2000, "标签委托应就绪且完成布局")
            var tabItem = bar.items.itemAt(1)
            mouseClick(tabItem, tabItem.width / 2, tabItem.height / 2)
            compare(got, "b", "点击第二个标签应发 tabClicked(b)")
            loader.destroy()
        }
    }

    TestCase {
        name: "BottomNavSmoke"
        // KdBottomNav：4 项、56px 高、点击发 itemClicked、选中态加深跟随 currentId
        function test_itemsAndClick() {
            var loader = navComp.createObject(root)
            loader.width = 400
            var nav = loader.item
            verify(nav !== null, "KdBottomNav 应能加载")
            compare(nav.height, 56, "底部导航应为 56px 高")
            nav.items = [
                { id: "shelf", icon: "⌂", text: "书库" },
                { id: "stats", icon: "▤", text: "统计" },
                { id: "sync", icon: "⇄", text: "同步" },
                { id: "settings", icon: "⚙", text: "设置" }
            ]
            compare(nav.itemRepeater.count, 4, "底部导航应为 4 项")
            // 点击第 3 项 → itemClicked(sync)
            var got = ""
            nav.itemClicked.connect(function (id) { got = id })
            tryVerify(function () {
                var it = nav.itemRepeater.itemAt(2)
                return it !== null && it.width > 50
            }, 2000, "条目委托应就绪且完成布局")
            var item3 = nav.itemRepeater.itemAt(2)
            mouseClick(item3, item3.width / 2, item3.height / 2)
            compare(got, "sync", "点击第 3 项应发 itemClicked(sync)")
            // 选中态跟随 currentId（委托内 selected 属性）
            nav.currentId = "stats"
            tryVerify(function () {
                var item = nav.itemRepeater.itemAt(1)
                return item !== null && item.selected === true
            }, 2000, "currentId=stats 时第 2 项应选中")
            nav.currentId = "settings"
            tryVerify(function () {
                var item = nav.itemRepeater.itemAt(3)
                return item !== null && item.selected === true
            }, 2000, "currentId=settings 时第 4 项应选中")
            loader.destroy()
        }
    }

    TestCase {
        name: "MainNavSmoke"
        // Main.qml 集成：初始书库页 + 导航可见；导航切换显示对应页且高亮/下划线跟随；
        // 阅读页 push 时导航隐藏（沉浸）、返回后恢复。
        function test_navSwitchAndReaderHide() {
            var loader = mainComp.createObject(root)
            var win = loader.item
            verify(win !== null, "Main.qml 应能加载（含 KdTabBar/KdBottomNav 编译检查）")
            tryVerify(function () { return win.navStack.currentItem !== null }, 3000,
                      "初始页应加载")
            compare(win.navStack.currentItem.navId, "shelf", "初始应显示书库页")
            compare(win.currentNavId, "shelf", "当前导航 id 应为 shelf")
            verify(win.navVisible, "书库页应显示导航")
            verify(win.tabBar.visible && win.bottomNav.visible, "标签与底部导航应可见")
            compare(win.tabBar.items.count, 2, "顶部应有 2 个标签（书库/设置）")
            compare(win.bottomNav.itemRepeater.count, 4, "底部应有 4 项导航")

            // 底部导航直达统计页：显示对应页 + 高亮跟随
            win.navigateTo("stats")
            tryVerify(function () { return win.navStack.currentItem.navId === "stats" }, 3000,
                      "导航应切到统计页")
            compare(win.currentNavId, "stats", "当前导航 id 应为 stats")
            compare(win.bottomNav.currentId, "stats", "底部导航高亮应跟随")

            // 顶部标签点击（信号调用——点击→tabClicked 的发射路径已由 TabBarSmoke
            // 用真实鼠标事件锁定；此处锁定 Main 的 onTabClicked → navigateTo 接线）
            win.tabBar.tabClicked("settings")
            tryVerify(function () { return win.navStack.currentItem.navId === "settings" }, 3000,
                      "顶部标签应切到设置页")
            compare(win.currentNavId, "settings", "当前导航 id 应为 settings")
            compare(win.tabBar.currentId, "settings", "顶部标签高亮应跟随")
            tryVerify(function () {
                return Math.round(win.tabBar.underline.x) === Math.round(win.tabBar.width / 2)
            }, 3000, "下划线应平移到设置标签下（x=半宽）")

            // 底部导航点击（信号调用——点击→itemClicked 发射路径已由 BottomNavSmoke
            // 用真实鼠标事件锁定；此处锁定 Main 的 onItemClicked → navigateTo 接线）
            win.bottomNav.itemClicked("shelf")
            tryVerify(function () { return win.navStack.currentItem.navId === "shelf" }, 3000,
                      "底部导航应切回书库页")
            compare(win.currentNavId, "shelf")

            // 阅读页 push → 导航隐藏（沉浸），正文占满（标签栏高度归零）；返回后恢复
            var book = null
            for (let b of Books.booksModel)
                if ((b.format || "").toUpperCase() === "TXT") { book = b; break }
            if (!book) {
                Importer.doImport(TestEnv.sourceFiles[0])
                tryVerify(function () {
                    for (let b of Books.booksModel)
                        if ((b.format || "").toUpperCase() === "TXT") { book = b; return true }
                    return false
                }, 3000, "应导入 TXT 书")
            }
            win.navStack.push("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: book })
            tryVerify(function () { return win.navStack.currentItem.navId === "reader" }, 3000,
                      "ReaderPage 应被 push 进导航栈")
            compare(win.navVisible, false, "阅读页应隐藏导航（沉浸）")
            verify(!win.tabBar.visible && !win.bottomNav.visible, "标签与底部导航应隐藏")
            compare(win.tabBar.height, 0, "标签栏高度应归零（正文占满窗口）")
            compare(win.bottomNav.height, 0, "底部导航高度应归零")

            // 返回（pop）→ 导航恢复
            win.navStack.pop()
            tryVerify(function () { return win.navStack.currentItem.navId === "shelf" }, 3000,
                      "返回后应回到书库页")
            compare(win.navVisible, true, "返回后导航应恢复")
            verify(win.tabBar.visible && win.bottomNav.visible, "返回后标签与底部导航应可见")
            verify(win.tabBar.height > 0 && win.bottomNav.height > 0, "返回后导航高度应恢复")

            win.visible = false
            loader.destroy()
        }
    }
}
