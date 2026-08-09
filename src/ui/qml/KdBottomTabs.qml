import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.UI 1.0

// Kindle 底部导航：2 等宽文字标签（选中加粗 + 3px 下划线）+ 中间悬浮迷你封面
//（当前阅读书，上凸越过分隔线；null 时隐藏占位保持等宽）。
// 接口：currentId；currentBook（var，含 cover/title）；信号 tabClicked(id)/coverClicked()。
// 测试句柄：homeTab/libraryTab/miniCover。
Rectangle {
    id: tabs
    height: 52
    color: UITheme.bgPrimary
    property string currentId: "home"
    property var currentBook: null
    signal tabClicked(string id)
    signal coverClicked()
    property alias homeTab: homeTab
    property alias libraryTab: libraryTab
    property alias miniCover: miniCover

    Rectangle { // 顶部分隔线
        anchors.top: parent.top
        width: parent.width
        height: 2
        color: UITheme.textPrimary
    }
    RowLayout {
        anchors.fill: parent
        spacing: 0
        Item { Layout.fillWidth: true; Layout.fillHeight: true
            Label {
                id: homeTab
                anchors.centerIn: parent
                text: qsTr("主页")
                font.pixelSize: UITheme.fsTabNav
                font.bold: tabs.currentId === "home"
                color: tabs.currentId === "home" ? UITheme.textPrimary : UITheme.textSecondary
            }
            Rectangle { // 下划线
                anchors.top: homeTab.bottom
                anchors.topMargin: 2
                anchors.horizontalCenter: homeTab.horizontalCenter
                width: homeTab.width
                height: 3
                color: UITheme.borderActive
                visible: tabs.currentId === "home"
            }
            MouseArea { anchors.fill: parent; onClicked: tabs.tabClicked("home") }
        }
        Item { // 中间悬浮封面占位
            Layout.preferredWidth: 56
            Layout.fillHeight: true
            Image {
                id: miniCover
                width: 40; height: 54
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                visible: tabs.currentBook !== null
                source: tabs.currentBook ? tabs.currentBook.cover : ""
                fillMode: Image.PreserveAspectCrop
                // U1 修正：Image 无 border 属性（报错致组件加载失败）；描边改由
                // 下方轻投影 Rectangle 承载（borderDefault 1px + shadowBook 外描边）
                layer.enabled: true
            }
            Rectangle { // 描边 + 轻投影
                anchors.fill: miniCover
                anchors.margins: -1
                visible: miniCover.visible
                color: "transparent"
                border.color: UITheme.borderDefault
                border.width: 1
                z: -1
            }
            Rectangle { // 轻投影外晕
                anchors.fill: miniCover
                anchors.margins: -2
                visible: miniCover.visible
                color: "transparent"
                border.color: UITheme.shadowBook
                border.width: 2
                z: -2
            }
            MouseArea {
                anchors.fill: parent
                enabled: tabs.currentBook !== null
                onClicked: tabs.coverClicked()
            }
        }
        Item { Layout.fillWidth: true; Layout.fillHeight: true
            Label {
                id: libraryTab
                anchors.centerIn: parent
                text: qsTr("图书馆")
                font.pixelSize: UITheme.fsTabNav
                font.bold: tabs.currentId === "shelf"
                color: tabs.currentId === "shelf" ? UITheme.textPrimary : UITheme.textSecondary
            }
            Rectangle {
                anchors.top: libraryTab.bottom
                anchors.topMargin: 2
                anchors.horizontalCenter: libraryTab.horizontalCenter
                width: libraryTab.width
                height: 3
                color: UITheme.borderActive
                visible: tabs.currentId === "shelf"
            }
            MouseArea { anchors.fill: parent; onClicked: tabs.tabClicked("shelf") }
        }
    }
}
