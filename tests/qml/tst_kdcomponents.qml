import QtQuick
import QtTest

// U1 冒烟：三个新导航组件——KdTopSearchBar（搜索胶囊 + ⋮ 按钮 menuClicked）、
// KdDropdownMenu（遮罩 + 右上实色面板：open/close、点击项分发 itemClicked 并
// 自动关闭、点遮罩关闭）、KdBottomTabs（2 等宽文字标签选中加粗 + 3px 下划线
// 跟随、中间悬浮迷你封面随 currentBook 显隐）。
// 结构约定（与 tst_nav/tst_u4 一致）：根为带尺寸 Item，组件经 Loader + qrc
// 资源路径加载（测试进程未链接 Readdict QML 模块，裸类型名不可解析）。
Item {
    id: root
    width: 1100; height: 720

    Component {
        id: barComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/KdTopSearchBar.qml" }
    }
    Component {
        id: menuComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/KdDropdownMenu.qml" }
    }
    Component {
        id: tabsComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/KdBottomTabs.qml" }
    }

    TestCase {
        name: "TopSearchBarSmoke"
        // KdTopSearchBar：text 双向绑定内部输入框、占位透传、⋮ 点击发 menuClicked
        function test_textPlaceholderAndMenuSignal() {
            var loader = barComp.createObject(root)
            loader.width = 400
            var bar = loader.item
            verify(bar !== null, "KdTopSearchBar 应能加载")
            compare(bar.height, 44, "搜索栏应为 44px 高")
            bar.text = "hello"
            compare(bar.field.text, "hello", "text 应绑定内部输入框")
            compare(bar.field.placeholderText, bar.placeholderText, "占位文本应透传")
            var btn = bar.menuButton
            verify(btn !== null && btn.width > 0, "menuButton 句柄应就绪")
            var got = false
            bar.menuClicked.connect(function () { got = true })
            mouseClick(btn, btn.width / 2, btn.height / 2)
            verify(got, "点击 ⋮ 应发 menuClicked")
            loader.destroy()
        }
    }

    TestCase {
        name: "DropdownMenuSmoke"
        // KdDropdownMenu：open/close；items 渲染（含 divider）；点击第一项委托
        // 分发 itemClicked(a) 并自动关闭（委托为 Loader，点击取其 item）
        function test_openCloseAndItemClick() {
            var loader = menuComp.createObject(root)
            loader.width = 400; loader.height = 300
            var menu = loader.item
            verify(menu !== null, "KdDropdownMenu 应能加载")
            verify(!menu.visible, "初始应隐藏")
            menu.items = [
                { id: "a", icon: "dot", text: "A" },
                { divider: true },
                { id: "b", icon: "dot", text: "B" }
            ]
            menu.open()
            verify(menu.visible, "open() 后应可见")
            tryVerify(function () { return menu.itemRepeater.count === 3 }, 3000,
                      "应渲染 3 项（含 divider），实际 " + menu.itemRepeater.count)
            tryVerify(function () {
                var dl = menu.itemRepeater.itemAt(0)
                return dl !== null && dl.item !== null && dl.item.width > 10
            }, 3000, "第一项委托应就绪且完成布局")
            var clicked = ""
            menu.itemClicked.connect(function (id) { clicked = id })
            var first = menu.itemRepeater.itemAt(0).item // Loader → itemComp Rectangle
            var p = first.mapToItem(menu, first.width / 2, first.height / 2)
            mouseClick(menu, p.x, p.y)
            compare(clicked, "a", "点击第一项应发 itemClicked(a)")
            verify(!menu.visible, "点击项后应自动关闭")
            loader.destroy()
        }
        // 点击面板外遮罩 → 关闭（面板锚定右上，左下必在遮罩区）
        function test_maskClickCloses() {
            var loader = menuComp.createObject(root)
            loader.width = 400; loader.height = 300
            var menu = loader.item
            verify(menu !== null, "KdDropdownMenu 应能加载")
            menu.items = [{ id: "a", icon: "dot", text: "A" }]
            menu.open()
            verify(menu.visible)
            mouseClick(menu.overlay, 10, 250)
            verify(!menu.visible, "点击遮罩应关闭菜单")
            loader.destroy()
        }
    }

    TestCase {
        name: "BottomTabsSmoke"
        // 下划线跟随：home 选中时仅主页标签有 3px 下划线且加粗；切 shelf 后迁移
        function test_underlineFollowsSelection() {
            var loader = tabsComp.createObject(root)
            loader.width = 400
            var tabs = loader.item
            verify(tabs !== null, "KdBottomTabs 应能加载")
            compare(tabs.height, 52, "底部标签栏应为 52px 高")
            // 标签 Item 子项为 Label/下划线 Rectangle/MouseArea，按高度 3 + 有 color 找下划线
            function underlineOf(tabLabel) {
                var children = tabLabel.parent.children
                for (var i = 0; i < children.length; ++i) {
                    var ch = children[i]
                    if (ch !== null && ch.height === 3 && "color" in ch) return ch
                }
                return null
            }
            var homeUl = underlineOf(tabs.homeTab)
            var libUl = underlineOf(tabs.libraryTab)
            verify(homeUl !== null && libUl !== null, "下划线矩形应能找到")
            tabs.currentId = "home"
            verify(homeUl.visible && !libUl.visible, "home 选中 → 仅主页标签有下划线")
            verify(tabs.homeTab.font.bold && !tabs.libraryTab.font.bold, "选中标签应加粗")
            tabs.currentId = "shelf"
            compare(tabs.currentId, "shelf")
            verify(!homeUl.visible && libUl.visible, "shelf 选中 → 下划线迁到图书馆标签")
            verify(!tabs.homeTab.font.bold && tabs.libraryTab.font.bold, "加粗应跟随选中")
            // 点击左区（主页标签单元）→ tabClicked(home)
            var got = ""
            tabs.tabClicked.connect(function (id) { got = id })
            var homeCell = tabs.homeTab.parent
            mouseClick(homeCell, 10, homeCell.height / 2)
            compare(got, "home", "点击主页区应发 tabClicked(home)")
            loader.destroy()
        }
        // 迷你封面：currentBook 非 null 显示、null 隐藏
        function test_miniCoverVisibility() {
            var loader = tabsComp.createObject(root)
            loader.width = 400
            var tabs = loader.item
            verify(tabs !== null, "KdBottomTabs 应能加载")
            tabs.currentBook = ({ cover: "", title: "x" })
            verify(tabs.miniCover.visible, "currentBook 存在时迷你封面应可见")
            tabs.currentBook = null
            verify(!tabs.miniCover.visible, "currentBook 为 null 时迷你封面应隐藏")
            loader.destroy()
        }
    }
}
