import QtQuick
import QtQuick.Controls
import QtTest
import Readdict.Backend
import Readdict.Test 1.0

// U2 冒烟：Kindle 导航体系——底部主页/图书馆文字标签、悬浮最近阅读封面与 Main.qml
// 集成。结构约定（与其它 QML 冒烟一致）：Main.qml 创建可见 ApplicationWindow，
// 用例结束先隐藏再销毁，避免测试进程残留窗口。
Item {
    id: root
    width: 1100; height: 720

    Component {
        id: tabComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/KdTabBar.qml" }
    }
    Component {
        id: bottomTabsComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/KdBottomTabs.qml" }
    }
    Component {
        id: mainComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/Main.qml" }
    }

    TestCase {
        name: "TabBarSmoke"
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
            bar.currentId = "b"
            tryVerify(function () { return Math.round(bar.underline.x) === 200 }, 3000,
                      "下划线应平移到第二项（x=200），实际 " + bar.underline.x)
            bar.currentId = "a"
            tryVerify(function () { return Math.round(bar.underline.x) === 0 }, 3000,
                      "下划线应跟动回第一项（x=0），实际 " + bar.underline.x)
            loader.destroy()
        }
    }

    TestCase {
        name: "BottomTabsSmoke"
        function test_currentIdAndTabClicks() {
            var loader = bottomTabsComp.createObject(root)
            loader.width = 400
            var tabs = loader.item
            verify(tabs !== null, "KdBottomTabs 应能加载")
            compare(tabs.height, 52, "底部标签栏应为 52px 高")
            compare(tabs.currentId, "home", "默认选中主页")
            tabs.currentId = "shelf"
            compare(tabs.currentId, "shelf", "currentId 应支持图书馆")
            var clicked = ""
            tabs.tabClicked.connect(function (id) { clicked = id })
            mouseClick(tabs.homeTab, tabs.homeTab.width / 2, tabs.homeTab.height / 2)
            compare(clicked, "home", "点击主页标签应发出 tabClicked(home)")
            mouseClick(tabs.libraryTab, tabs.libraryTab.width / 2, tabs.libraryTab.height / 2)
            compare(clicked, "shelf", "点击图书馆标签应发出 tabClicked(shelf)")
            loader.destroy()
        }
    }

    TestCase {
        name: "MainNavSmoke"
        // U6：搜索/筛选残留复位（同 tst_readerpage/tst_shelf 约定）——tst_main
        // FulltextSmoke 的顶部搜索残留会让 booksModel 为空，找不到非 PDF 测试书，
        // 兜底导入又撞上已存在的同名书库文件（全量套件失败源）。
        function initTestCase() {
            Books.doSearch("")
            Books.setFilter("")
            Books.setSort(0)
        }
        function test_navSwitchReaderResume() {
            var loader = mainComp.createObject(root)
            var win = loader.item
            verify(win !== null, "Main.qml 应能加载（含顶部搜索栏/底部标签）")
            tryVerify(function () { return win.navStack.currentItem !== null }, 3000,
                      "初始页应加载")
            compare(win.navStack.currentItem.navId, "home", "初始应显示主页")
            compare(win.currentNavId, "home", "当前导航 id 应为 home")
            verify(win.navVisible, "主页应显示导航")
            verify(win.tabBar.visible && win.bottomNav.visible, "底部标签与悬浮封面应可见")
            compare(win.tabBar.currentId, "home", "主页应高亮")

            mouseClick(win.tabBar.libraryTab, win.tabBar.libraryTab.width / 2,
                       win.tabBar.libraryTab.height / 2)
            tryVerify(function () { return win.navStack.currentItem.navId === "shelf" }, 3000,
                      "点击图书馆应切到书库页")
            compare(win.currentNavId, "shelf")
            compare(win.tabBar.currentId, "shelf")

            mouseClick(win.tabBar.homeTab, win.tabBar.homeTab.width / 2,
                       win.tabBar.homeTab.height / 2)
            tryVerify(function () { return win.navStack.currentItem.navId === "home" }, 3000,
                      "点击主页应回到主页")
            compare(win.navStack.depth, 1, "主页与书库切换不应累积栈页")

            var book = null
            for (let b of Books.booksModel) {
                const fmt = (b.format || "").toUpperCase()
                if (fmt !== "PDF" && String(b.cover || "").length > 0) {
                    book = b
                    break
                }
            }
            if (!book) {
                Importer.doImport(TestEnv.sourceFiles[0])
                tryVerify(function () {
                    for (let b of Books.booksModel) {
                        const fmt = (b.format || "").toUpperCase()
                        if (fmt !== "PDF" && String(b.cover || "").length > 0) {
                            book = b
                            return true
                        }
                    }
                    return false
                }, 3000, "应导入带封面的非 PDF 测试书")
            }
            verify(book !== null, "应存在确定的非 PDF 测试书")
            Books.reportProgress(book.id, 1, 1)
            tryVerify(function () { return win.currentReading !== null }, 3000,
                      "最近阅读书籍应驱动悬浮封面")
            verify(win.bottomNav.miniCover.visible, "最近阅读封面应可见")
            verify(String(win.bottomNav.miniCover.source).indexOf("file:") === 0,
                   "绝对封面路径应转换为 file URL，实际 " + win.bottomNav.miniCover.source)
            var homePage = win.navStack.currentItem
            tryVerify(function () { return homePage.recentBooksModel.length > 0 }, 3000,
                      "阅读活动后主页最近阅读模型应刷新")
            homePage.refreshData()
            verify(homePage.recentBooksModel.length > 0, "refreshData 应重算最近阅读模型")
            mouseClick(win.bottomNav.miniCover, win.bottomNav.miniCover.width / 2,
                       win.bottomNav.miniCover.height / 2)
            tryVerify(function () { return win.navStack.currentItem.navId === "reader" }, 3000,
                      "点击悬浮封面应恢复最近阅读")
            compare(win.navVisible, false, "阅读页应隐藏导航")
            win.navStack.pop()
            tryVerify(function () { return win.navStack.currentItem.navId === "home" }, 3000,
                      "返回后应回到主页")
            verify(win.navVisible, "返回后导航应恢复")

            win.visible = false
            loader.destroy()
        }

        function test_auxiliaryRoutesReturnToOrigin() {
            var loader = mainComp.createObject(root)
            var win = loader.item
            verify(win !== null, "Main.qml 应能加载")
            tryVerify(function () { return win.navStack.currentItem && win.navStack.currentItem.navId === "home" }, 3000)

            win.onShelfMenu("stats")
            tryVerify(function () { return win.navStack.currentItem && win.navStack.currentItem.navId === "stats" }, 3000,
                      "统计菜单应进入统计页")
            verify(win.navStack.currentItem.goBack !== undefined, "统计页应提供统一返回入口")
            win.goBack()
            tryVerify(function () { return win.navStack.currentItem && win.navStack.currentItem.navId === "home" }, 3000,
                      "统计页返回应回到主页")
            compare(win.navStack.depth, 1, "辅助页返回后不应残留栈项")

            win.onShelfMenu("settings")
            tryVerify(function () { return win.navStack.currentItem && win.navStack.currentItem.navId === "settings" }, 3000)
            win.goBack()
            tryVerify(function () { return win.navStack.currentItem && win.navStack.currentItem.navId === "home" }, 3000,
                      "设置页返回应回到主页")

            win.visible = false
            loader.destroy()
        }
        function test_auxiliaryFromShelfHidesMainNavigation() {
            var loader = mainComp.createObject(root)
            var win = loader.item
            verify(win !== null, "Main.qml 应能加载")
            win.navigateTo("shelf")
            tryVerify(function () { return win.navStack.currentItem && win.navStack.currentItem.navId === "shelf" }, 3000)
            win.onShelfMenu("settings")
            tryVerify(function () { return win.navStack.currentItem && win.navStack.currentItem.navId === "settings" }, 3000,
                      "图书馆菜单应进入设置页")
            compare(win.tabBar.visible, false, "辅助页不应显示主导航")
            compare(win.topSearchBar.visible, false, "辅助页不应显示主搜索栏")
            win.goBack()
            tryVerify(function () { return win.navStack.currentItem && win.navStack.currentItem.navId === "shelf" }, 3000,
                      "设置页返回应回到图书馆")
            verify(win.tabBar.visible, "返回图书馆后应恢复主导航")
            win.visible = false
            loader.destroy()
        }
    }

    TestCase {
        name: "SettingsSubpageNavSmoke"
        // BUG2：设置子页逐层 push、返回只 pop 当前层——从设置页进入语言/TTS/
        // 背景/同步/统计后返回必须回到设置页（不得经 Main.goBack 直接弹回主页）
        function test_settingsSubpagesReturnToSettings() {
            var loader = mainComp.createObject(root)
            var win = loader.item
            verify(win !== null, "Main.qml 应能加载")
            tryVerify(function () {
                return win.navStack.currentItem && win.navStack.currentItem.navId === "home"
            }, 3000, "初始应为主页")
            win.onShelfMenu("settings")
            tryVerify(function () {
                return win.navStack.currentItem && win.navStack.currentItem.navId === "settings"
            }, 3000, "书架菜单应进入设置页")
            var settingsPage = win.navStack.currentItem
            var subs = [
                { handle: "languageEntryButton", backHandle: "backButton" },
                { handle: "ttsEntryButton", backHandle: "backButton" },
                { handle: "backgroundEntryButton", backHandle: "backButton" },
                { handle: "syncEntryButton", backHandle: "backButton" },
                { handle: "statsEntryButton", backHandle: "" }
            ]
            for (let sub of subs) {
                let entry = settingsPage[sub.handle]
                verify(entry !== undefined, sub.handle + " 入口句柄应保留")
                entry.clicked()
                tryVerify(function () {
                    return win.navStack.currentItem !== settingsPage
                }, 3000, sub.handle + " 应推入子页")
                var subPage = win.navStack.currentItem
                if (sub.backHandle) {
                    verify(subPage[sub.backHandle] !== undefined,
                           sub.handle + " 子页应暴露返回按钮句柄")
                    subPage[sub.backHandle].clicked()
                } else {
                    verify(subPage.goBack !== undefined, "统计页应暴露 goBack()")
                    subPage.goBack()
                }
                tryVerify(function () {
                    return win.navStack.currentItem === settingsPage
                }, 3000, sub.handle + " 返回应回到设置页（而非主页）")
            }
            // 唯一合法的回主页路径：设置页自身返回
            win.goBack()
            tryVerify(function () {
                return win.navStack.currentItem && win.navStack.currentItem.navId === "home"
            }, 3000, "设置页返回应回到主页")
            win.visible = false
            loader.destroy()
        }
    }
}
