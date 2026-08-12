import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.UI 1.0

// Kindle 阅读页顶栏（唤出态）：← 书库 | Aa | 布局 | 笔记 | 书签 | 搜索 | ⋮
// 只渲染与上报，页面宿主负责导航、弹层和持久化。
Rectangle {
    id: bar
    height: 40
    color: UITheme.bgPrimary
    opacity: 1

    property bool bookmarked: false
    signal back()
    signal aa()
    signal layout()
    signal notes()
    signal bookmark()
    signal search()
    signal menu()
    property alias backBtn: backBtn
    property alias menuBtn: menuBtn

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: UITheme.divider
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 12
        spacing: 0

        ToolButton {
            id: backBtn
            Layout.fillWidth: true
            contentItem: RowLayout {
                spacing: 4
                Label { text: "←"; color: UITheme.textPrimary }
                Label {
                    text: qsTr("书库")
                    color: UITheme.textPrimary
                    font.pixelSize: UITheme.fsListItem
                }
            }
            onClicked: bar.back()
        }
        ToolButton {
            Layout.fillWidth: true
            contentItem: Text {
                text: "Aa"
                color: UITheme.textPrimary
                font.pixelSize: 15
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            onClicked: bar.aa()
        }
        ToolButton {
            Layout.fillWidth: true
            contentItem: Text {
                text: qsTr("布局")
                color: UITheme.textPrimary
                font.pixelSize: UITheme.fsListItem
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            onClicked: bar.layout()
        }
        ToolButton {
            Layout.fillWidth: true
            contentItem: KdIcons {
                name: "notes"
                size: 20
                color: UITheme.textPrimary
            }
            onClicked: bar.notes()
        }
        ToolButton {
            Layout.fillWidth: true
            contentItem: KdIcons {
                name: bar.bookmarked ? "bookmarkFill" : "bookmark"
                size: 20
                color: UITheme.textPrimary
            }
            onClicked: bar.bookmark()
        }
        ToolButton {
            Layout.fillWidth: true
            contentItem: KdIcons {
                name: "search"
                size: 20
                color: UITheme.textPrimary
            }
            onClicked: bar.search()
        }
        ToolButton {
            id: menuBtn
            Layout.fillWidth: true
            contentItem: Text {
                text: "⋮"
                color: UITheme.textPrimary
                font.pixelSize: 18
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            onClicked: bar.menu()
        }
    }
}
