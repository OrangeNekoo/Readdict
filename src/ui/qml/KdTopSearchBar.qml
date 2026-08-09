import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.UI 1.0

// Kindle 顶部全宽搜索栏：全圆角浅灰底 + 放大镜 + 占位；右侧 ⋮ 按钮。
// 接口：text（双向）、placeholderText；信号 menuClicked。
// 测试句柄：field / menuButton。
Rectangle {
    id: bar
    height: 44
    color: "transparent"
    property alias text: field.text
    property string placeholderText: qsTr("搜索 Readdict")
    signal menuClicked()
    property alias field: field
    property alias menuButton: menuBtn

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 10
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            radius: 18
            color: UITheme.bgSearch
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 6
                KdIcons { name: "search"; size: 18; color: UITheme.textSecondary }
                TextField {
                    id: field
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    placeholderText: bar.placeholderText
                    background: Rectangle { color: "transparent" }
                    color: UITheme.textPrimary
                    font.pixelSize: UITheme.fsListItem
                }
            }
        }
        ToolButton {
            id: menuBtn
            text: "⋮"
            font.pixelSize: 18
            // U1 修正：contentItem.color 非有效属性（Material 下报错致组件加载失败）；
            // 按仓库既有惯例用 contentItem 赋值
            contentItem: Text {
                text: parent.text
                color: UITheme.textPrimary
                font.pixelSize: 18
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            onClicked: bar.menuClicked()
        }
    }
}
