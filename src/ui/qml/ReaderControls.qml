import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// 阅读页底部浮动控制栏：章节导航 / 目录 / 字号 / 背景三态 / 对齐 / 页宽。
// 全部以信号上报 ReaderPage 处理（状态读写集中在页面，本组件无状态）。
Rectangle {
    id: controls
    property int fontSize: 18
    property string bgMode: "light"   // 随阅读背景切换前景/底色，保证深色下可读
    signal prevChapter()
    signal nextChapter()
    signal changeFontSize(int size)
    signal toggleBackground()
    signal toggleAlign()
    signal togglePageWidth()
    signal openToc()

    height: 52
    color: controls.bgMode === "dark" ? "#F2121212" : "#F2FFFFFF"
    property color fgColor: controls.bgMode === "dark" ? "#E6E6E6" : "#1A1A1A"

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: controls.bgMode === "dark" ? "#33FFFFFF" : "#1A000000"
    }

    component CtlBtn: ToolButton {
        required property string lbl
        text: lbl
        font.pixelSize: 13
        contentItem: Text {
            text: parent.text
            color: controls.fgColor
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 4
        CtlBtn { lbl: qsTr("上一章"); onClicked: controls.prevChapter() }
        CtlBtn { lbl: qsTr("目录"); onClicked: controls.openToc() }
        Item { Layout.fillWidth: true }
        CtlBtn { lbl: "A−"; onClicked: controls.changeFontSize(controls.fontSize - 1) }
        Label {
            text: controls.fontSize
            color: controls.fgColor
            Layout.preferredWidth: 30
            horizontalAlignment: Text.AlignHCenter
        }
        CtlBtn { lbl: "A+"; onClicked: controls.changeFontSize(controls.fontSize + 1) }
        CtlBtn { lbl: qsTr("背景"); onClicked: controls.toggleBackground() }
        CtlBtn { lbl: qsTr("对齐"); onClicked: controls.toggleAlign() }
        CtlBtn { lbl: qsTr("页宽"); onClicked: controls.togglePageWidth() }
        CtlBtn { lbl: qsTr("下一章"); onClicked: controls.nextChapter() }
    }
}
