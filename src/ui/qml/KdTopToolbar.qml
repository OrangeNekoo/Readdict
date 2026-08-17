import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.UI 1.0

// Kindle 阅读页顶栏（唤出态）：← 书库 | 笔记 | 书签 | 搜索 | ⋮。
// 主题、字体、布局和进度格式只由底部 Sheet 承担，避免重复入口。
Rectangle {
    id: bar
    height: 40
    color: UITheme.bgPrimary
    opacity: 1

    property bool bookmarked: false
    signal back()
    signal notes()
    signal bookmark()
    signal search()
    signal menu()
    property alias backBtn: backBtn
    property alias menuBtn: menuBtn
    property alias libraryLabel: libraryLabel
    property alias backIcon: backIcon
    property alias notesIcon: notesIcon
    property alias bookmarkIcon: bookmarkIcon
    property alias searchIcon: searchIcon
    property alias menuText: menuText
    property alias bookmarkName: bookmarkIcon.name
    // 任务3：五个 ToolButton 的可观察句柄（悬停背景边界冒烟测试经此断言
    // background 几何等于按钮自身；无此句柄外部只能依赖 children 下标）。
    property list<Item> topToolbarButtons: [backBtn, notesBtn, bookmarkBtn, searchBtn, menuBtn]

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
            Layout.minimumWidth: 44
            Layout.fillWidth: true
            // 任务3：按钮级本地背景——Material 默认 ToolButton 背景是样式注入的
            // Ripple 圆墨（居中/随悬停激活，绘制范围不受按钮边界约束）；此处
            // 显式提供 Rectangle，anchors.fill 严格等于按钮，悬停高亮只画在按钮
            // 矩形内（复用 UITheme.bgSecondary 悬停 token，同 ReaderShell 菜单行）。
            background: Rectangle {
                anchors.fill: parent
                radius: 0
                color: parent.hovered ? UITheme.bgSecondary : "transparent"
            }
            contentItem: Item {
                implicitWidth: backRow.implicitWidth
                implicitHeight: 20
                Row {
                    id: backRow
                    anchors.centerIn: parent
                    spacing: 4
                    KdIcons {
                        id: backIcon
                        name: "back"
                        size: 20
                        color: UITheme.textPrimary
                    }
                    Label {
                        id: libraryLabel
                        height: backIcon.height
                        text: qsTr("书库")
                        color: UITheme.textPrimary
                        font.pixelSize: UITheme.fsListItem
                        visible: backBtn.width >= 96
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
            onClicked: bar.back()
        }
        ToolButton {
            id: notesBtn
            Layout.fillWidth: true
            Layout.minimumWidth: 44
            background: Rectangle {
                anchors.fill: parent
                radius: 0
                color: parent.hovered ? UITheme.bgSecondary : "transparent"
            }
            contentItem: Item {
                implicitWidth: 20
                implicitHeight: 20
                KdIcons {
                    id: notesIcon
                    anchors.centerIn: parent
                    name: "notes"
                    size: 20
                    color: UITheme.textPrimary
                }
            }
            onClicked: bar.notes()
        }
        ToolButton {
            id: bookmarkBtn
            Layout.fillWidth: true
            background: Rectangle {
                anchors.fill: parent
                radius: 0
                color: parent.hovered ? UITheme.bgSecondary : "transparent"
            }
            contentItem: Item {
                property string name: bookmarkIcon.name
                implicitWidth: 20
                implicitHeight: 20
                KdIcons {
                    id: bookmarkIcon
                    anchors.centerIn: parent
                    name: bar.bookmarked ? "bookmarkFill" : "bookmark"
                    size: 20
                    color: UITheme.textPrimary
                }
            }
            onClicked: bar.bookmark()
        }
        ToolButton {
            id: searchBtn
            Layout.fillWidth: true
            Layout.minimumWidth: 44
            background: Rectangle {
                anchors.fill: parent
                radius: 0
                color: parent.hovered ? UITheme.bgSecondary : "transparent"
            }
            contentItem: Item {
                implicitWidth: 20
                implicitHeight: 20
                KdIcons {
                    id: searchIcon
                    anchors.centerIn: parent
                    name: "search"
                    size: 20
                    color: UITheme.textPrimary
                }
            }
            onClicked: bar.search()
        }
        ToolButton {
            id: menuBtn
            Layout.minimumWidth: 44
            Layout.fillWidth: true
            background: Rectangle {
                anchors.fill: parent
                radius: 0
                color: parent.hovered ? UITheme.bgSecondary : "transparent"
            }
            contentItem: Item {
                implicitWidth: 20
                implicitHeight: 20
                Text {
                    id: menuText
                    anchors.centerIn: parent
                    text: "⋮"
                    color: UITheme.textPrimary
                    font.pixelSize: 18
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
            onClicked: bar.menu()
        }
    }
}
