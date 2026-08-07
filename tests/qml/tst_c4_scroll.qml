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

        // 最小窗口高度(600)下：设置页内容超高（B5 分组卡片化后 6 张卡 + 返回行
        // 总高超过视口）→ ScrollView 可滚动到底，底部版本标签进入视口
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
            // 布局收敛后内容应超高（视口高 = 600 - 边距 24*2）
            tryVerify(function () {
                return fl.contentHeight > fl.height + 50
            }, 3000, "最小窗口高度下设置页内容应超高可滚动（contentHeight="
                     + fl.contentHeight + "，视口=" + fl.height + "）")
            // 滚动到底：contentY 可达最大滚动位置
            fl.contentY = fl.contentHeight - fl.height
            compare(fl.contentY, fl.contentHeight - fl.height, "应能滚到内容底部")
            // 底部内容可达：版本标签（布局尾部 children[7]）滚到底后应进入视口
            var layout = page.settingsLayout
            var lastLabel = layout.children[7]
            verify(lastLabel !== undefined, "版本标签应存在（布局尾部）")
            var yInView = lastLabel.mapToItem(fl, 0, 0).y
            verify(yInView >= 0 && yInView < fl.height,
                   "滚到底后版本标签应在视口内（y=" + yInView + "，视口=" + fl.height + "）")
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
