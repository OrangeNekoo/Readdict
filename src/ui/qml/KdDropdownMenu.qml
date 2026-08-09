import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.UI 1.0

// Kindle ⋮ 下拉菜单：遮罩 rgba(0,0,0,0.3) + 实色面板（无圆角/极小圆角），
// 线性图标 + 文字项，divider 元素渲染分割线。锚定右上角（anchorRight=true）。
// 接口：items=[{id,icon,text} | {divider:true}]；open()/close()；信号 itemClicked(id)。
// 测试句柄：overlay / itemRepeater。
Item {
    id: menu
    anchors.fill: parent
    visible: false
    property var items: []
    signal itemClicked(string id)
    property alias overlay: mask
    property alias itemRepeater: rep

    function open() { menu.visible = true }
    function close() { menu.visible = false }

    Rectangle {
        id: mask
        anchors.fill: parent
        color: UITheme.overlay
        MouseArea { anchors.fill: parent; onClicked: menu.close() }
    }
    Rectangle {
        id: panel
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 4
        anchors.rightMargin: 8
        width: Math.max(220, parent.width * 0.45)
        height: col.height + 8
        color: UITheme.bgPrimary
        border.color: UITheme.borderDefault
        border.width: 1
        Item {
            id: col
            anchors.top: parent.top
            anchors.topMargin: 4
            anchors.left: parent.left
            anchors.right: parent.right
            function totalHeight() {
                var total = 0
                for (var i = 0; i < menu.items.length; ++i)
                    total += menu.items[i].divider ? 9 : 48
                return total
            }
            height: totalHeight()
            Repeater {
                id: rep
                model: menu.items
                delegate: Loader {
                    width: col.width
                    y: {
                        var offset = 0
                        for (var i = 0; i < index; ++i)
                            offset += menu.items[i].divider ? 9 : 48
                        return offset
                    }
                    height: modelData.divider ? 9 : 48
                    sourceComponent: modelData.divider ? dividerComp : itemComp
                    required property int index
                    required property var modelData
                }
            }
        }
    }
    Component {
        id: dividerComp
        Rectangle { height: 9; color: "transparent"
            Rectangle { anchors.centerIn: parent; width: parent.width - 16; height: 1; color: UITheme.divider }
        }
    }
    Component {
        id: itemComp
        Rectangle {
            height: 48
            color: ma.containsMouse ? "#0A000000" : "transparent"
            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                onClicked: { menu.close(); menu.itemClicked(modelData.id) }
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12
                KdIcons { name: modelData.icon || "dot"; size: 22; color: UITheme.textPrimary }
                Label {
                    text: modelData.text
                    font.pixelSize: UITheme.fsListItem
                    color: UITheme.textPrimary
                    Layout.fillWidth: true
                }
            }
        }
    }
}
