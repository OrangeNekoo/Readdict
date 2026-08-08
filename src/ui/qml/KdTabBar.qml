import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.UI 1.0

// U2：Kindle 顶部文字标签导航（分析报告 §1：三标签等宽、选中项 3px 下划线 +
// 动画跟动、无背景无圆角；§Typography 标签 16-18px 选中 Bold）。
// 本组件只渲染标签与发 tabClicked 信号，页面切换由 Main.navigateTo 处理；
// 标签数据由 Main 注入（tabs: [{id, text}]），currentId 绑定当前页。
// 测试/外部句柄：underline（下划线矩形）、items（标签 Repeater，供点击驱动）。
Item {
    id: tabBar

    // Kindle 标签栏上下 padding ~12px × 2 + 文字 17px ≈ 44px
    height: 44

    property var tabs: []            // [{id, text}] —— 标签数据（Main 注入）
    property string currentId: ""    // 当前选中标签 id（Main 绑定当前页 navId）
    signal tabClicked(string id)

    property alias underline: underlineRect
    property alias items: tabRepeater

    // 下划线几何：单元宽 = 全宽均分；目标 x = 选中索引 × 单元宽（Behavior 动画跟动）
    property real unitWidth: tabBar.width / Math.max(1, tabs.length)
    property int currentIndex: {
        for (var i = 0; i < tabs.length; ++i)
            if (tabs[i].id === tabBar.currentId) return i
        return -1
    }

    Rectangle {
        id: underlineRect
        // 无匹配选中项（如底部导航直达统计页，顶部两标签都不对应，currentIndex=-1）
        // 时隐藏指示器——避免误导为书库选中；有匹配时 x = 选中索引 × 单元宽
        visible: tabBar.currentIndex >= 0
        x: Math.max(0, tabBar.currentIndex) * tabBar.unitWidth
        width: tabBar.unitWidth
        height: 3
        anchors.bottom: parent.bottom
        color: UITheme.borderActive
        Behavior on x {
            NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Repeater {
            id: tabRepeater
            model: tabBar.tabs
            Item {
                id: tabItem
                required property var modelData
                Layout.fillWidth: true
                Layout.fillHeight: true

                Text {
                    anchors.centerIn: parent
                    text: modelData.text
                    font.pixelSize: UITheme.fsTabNav
                    font.bold: modelData.id === tabBar.currentId
                    color: modelData.id === tabBar.currentId
                           ? UITheme.textPrimary : UITheme.textSecondary
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: tabBar.tabClicked(modelData.id)
                }
            }
        }
    }
}
