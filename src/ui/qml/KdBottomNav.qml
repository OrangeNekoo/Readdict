import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.UI 1.0

// U2：Kindle 底部线性图标导航（分析报告 §1/§2：4 图标等宽、56px 高、
// 图标 24-28px 描边 + 12px 文字、选中态加深、无背景无圆角）。
// U4：图标由占位字符换为 KdIcons 线性描边图标（接口不变：icon 为图标名——
// shelf/stats/sync/settings，见 KdIcons.qml）。
// 本组件只渲染与发 itemClicked 信号，页面切换由 Main.navigateTo 处理；
// 条目数据由 Main 注入（items: [{id, icon, text}]），currentId 绑定当前页。
// 测试/外部句柄：itemRepeater（条目 Repeater，供点击驱动）。
Item {
    id: bottomNav

    // Kindle 底部导航栏高度 ~56px（§1）
    height: 56

    property var items: []           // [{id, icon, text}] —— 条目数据（Main 注入）
    property string currentId: ""    // 当前选中条目 id（Main 绑定当前页 navId）
    signal itemClicked(string id)

    property alias itemRepeater: navRepeater

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Repeater {
            id: navRepeater
            model: bottomNav.items
            Item {
                id: navItem
                required property var modelData
                Layout.fillWidth: true
                Layout.fillHeight: true
                property bool selected: modelData.id === bottomNav.currentId

                Column {
                    anchors.centerIn: parent
                    spacing: 2
                    // 线性描边图标（KdIcons，选中加深为 textPrimary）
                    KdIcons {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: modelData.icon || ""
                        size: 24
                        color: navItem.selected
                               ? UITheme.textPrimary : UITheme.textSecondary
                    }
                    // 12px 说明文字（§1 底部导航文字层级）
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.text
                        font.pixelSize: 12
                        font.bold: navItem.selected
                        color: navItem.selected
                               ? UITheme.textPrimary : UITheme.textSecondary
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: bottomNav.itemClicked(modelData.id)
                }
            }
        }
    }
}
