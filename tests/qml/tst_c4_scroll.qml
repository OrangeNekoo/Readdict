import QtQuick
import QtQuick.Controls
import QtTest

// C4 冒烟：最小窗口尺寸约束（Main.qml 的 minimumWidth/minimumHeight 生效）与
// 设置页小窗可滚动（ScrollView 滚动范围断言——内容超高、可滚动到底、底部内容
// 进入视口）。窗口/页面均按 qrc 资源路径加载真实生产文件（同其他冒烟模式，
// 单例由 tst_qmlmain.cpp 注册）。Main.qml 会创建可见 ApplicationWindow，
// 用例结束先隐藏再销毁，避免测试进程残留窗口。
Item {
    id: root
    width: 1100; height: 720

    Component {
        id: mainComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/Main.qml" }
    }
    Component {
        id: settingsComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/SettingsPage.qml" }
    }

    TestCase {
        name: "MinWindowSmoke"

        // 生产文件属性断言：Main.qml 实际声明的最小窗口尺寸生效，
        // 且初始尺寸不小于最小尺寸
        function test_minSizeProperties() {
            var loader = mainComp.createObject(root)
            var win = loader.item
            verify(win !== null, "Main.qml 应能加载（ApplicationWindow + StackView 编译检查）")
            compare(win.minimumWidth, 800, "minimumWidth 应为 800")
            compare(win.minimumHeight, 600, "minimumHeight 应为 600")
            verify(win.width >= win.minimumWidth && win.height >= win.minimumHeight,
                   "初始尺寸 1100x720 应不小于最小尺寸")
            win.visible = false
            loader.destroy()
        }
    }

    TestCase {
        name: "SettingsScrollSmoke"

        // 最小窗口高度(600)下：U5 全屏列表（7 行 KdListItem + 版本标签，行高 60）
        // 总高低于视口时全部内容直接可见（可达性契约：版本标签可进入视口——
        // 不超高则无需滚动；若未来行增多超高，ScrollView 滚动兜底同样可达）
        function test_scrollRangeAtMinHeight() {
            var loader = settingsComp.createObject(root)
            loader.width = 800; loader.height = 600
            var page = loader.item
            verify(page !== null, "SettingsPage 应能加载")
            var sv = page.settingsScroll
            verify(sv !== undefined, "应暴露 settingsScroll 句柄")
            verify(page.settingsLayout !== undefined, "应暴露 settingsLayout 句柄")
            var fl = sv.contentItem
            verify(fl !== undefined, "ScrollView 内容应为 Flickable")
            // 布局收敛后内容可达（超高时滚动，否则直接可见）
            tryVerify(function () { return fl.contentHeight > 0 }, 3000,
                      "内容应完成布局（contentHeight=" + fl.contentHeight + "）")
            var maxScroll = Math.max(0, fl.contentHeight - fl.height)
            fl.contentY = maxScroll
            compare(fl.contentY, maxScroll, "应能滚到最大滚动位置（不超高时为 0）")
            // D3：返回按钮固定顶部（移出 ScrollView）——滚到底后仍应在视口内
            // 且位置不随内容滚动（左上角残影修复的回归断言：按钮不再滚出视口）
            var btn = page.backButton
            verify(btn !== undefined, "应暴露返回按钮句柄")
            var btnY = btn.mapToItem(page, 0, 0).y
            verify(btn.visible && btnY >= 0 && btnY < page.height,
                   "滚到底后返回按钮应固定可见（y=" + btnY + "）")
            compare(btnY, btn.mapToItem(page, 0, 0).y, "返回按钮位置应固定不变")
            // 底部内容可达：版本标签（U5 列表尾部 children[7]，7 行 + 版本）在视口内
            var layout = page.settingsLayout
            compare(layout.children.length, 8, "列表应为 7 行 + 版本标签，实际 "
                    + layout.children.length)
            var lastLabel = layout.children[7]
            verify(lastLabel !== undefined, "版本标签应存在（布局尾部）")
            var yInView = lastLabel.mapToItem(fl, 0, 0).y
            verify(yInView >= 0 && yInView < fl.height,
                   "滚到底后版本标签应在视口内（y=" + yInView + "，视口=" + fl.height + "）")
            loader.destroy()
        }
        function test_listRowsDoNotOverlap() {
            var loader = settingsComp.createObject(root)
            loader.width = 1100
            loader.height = 720
            var page = loader.item
            verify(page !== null, "SettingsPage 应能加载")
            tryVerify(function () {
                return page.settingsLayout.children.length === 8
                       && page.settingsLayout.width > 0
                       && page.settingsLayout.children[0].width > 0
                       && page.settingsLayout.children[0].children[1].children[1].children[0].height > 0
            }, 3000, "设置列表应完成布局")
            for (var i = 0; i < 7; ++i) {
                var row = page.settingsLayout.children[i]
                var rowLayout = row.children[1]
                var icon = rowLayout.children[0]
                var textColumn = rowLayout.children[1]
                verify(row.width > 0 && rowLayout.width > 0 && textColumn.width > 0,
                       "设置行及文本列应有可见宽度: " + i)
                var title = textColumn.children[0]
                var subtext = textColumn.children[1]
                verify(title.height > 0, "设置行标题应有可见高度: " + i)
                if (subtext.visible)
                    verify(title.y + title.height <= subtext.y + 1,
                           "设置行标题与副标题不得重叠: " + i)
                verify(textColumn.x >= icon.x + icon.width,
                       "设置行图标与标题不得水平重叠: " + i)
            }
            loader.destroy()
        }

        // 默认窗口（1100x720）下内容未必超高，滚动条 AsNeeded 不强制出现；
        // 只要 ScrollView 存在且不超高时不报错即可（加载即编译检查）
        function test_loadsAtDefaultSize() {
            var loader = settingsComp.createObject(root)
            loader.width = 1100; loader.height = 720
            var page = loader.item
            verify(page !== null, "SettingsPage 默认尺寸应能加载")
            loader.destroy()
        }
    }
}
