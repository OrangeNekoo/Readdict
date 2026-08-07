import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// 阅读页底部浮动控制栏：章节导航 / 目录 / 字号 / 背景五态（含 eink）/ 对齐 / 页宽。
// B5：Kindle 式图标工具栏——unicode 符号 + 短文字（非 emoji），悬停 ToolTip 显全名。
// 全部以信号上报 ReaderPage 处理（状态读写集中在页面，本组件无状态）。
// 注意：按钮 children 顺序不可变（ControlsSmoke 依赖 children[3]=A−、children[5]=A+），
// 新按钮只追加行尾（C7 笔记 / C8 搜索 即行尾追加，B5 未动）。
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
    signal openNotes()
    // C8：书内搜索（ReaderPage 打开 Dialog → Search.searchModel(bookId) → 跳转）
    signal openSearch()

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

    // B5：iconChar 图标字符 + lbl 短文字；tip 为 ToolTip 全名（不参与布局，
    // ToolTip 是附加属性内部对象，不影响 RowLayout children 索引）。
    component CtlBtn: ToolButton {
        required property string lbl
        property string iconChar: ""
        property string tip: ""
        text: iconChar.length > 0 ? iconChar + " " + lbl : lbl
        font.pixelSize: 12
        padding: 4
        ToolTip.visible: hovered && tip.length > 0
        ToolTip.text: tip
        ToolTip.delay: 600
        contentItem: Text {
            text: parent.text
            color: controls.fgColor
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 2
        CtlBtn { iconChar: "⇤"; lbl: qsTr("上章"); tip: qsTr("上一章"); onClicked: controls.prevChapter() }
        CtlBtn { iconChar: "☰"; lbl: qsTr("目录"); tip: qsTr("目录"); onClicked: controls.openToc() }
        Item { Layout.fillWidth: true }
        CtlBtn { lbl: "A−"; tip: qsTr("减小字号"); onClicked: controls.changeFontSize(controls.fontSize - 1) }
        Label {
            text: controls.fontSize
            color: controls.fgColor
            Layout.preferredWidth: 26
            horizontalAlignment: Text.AlignHCenter
        }
        CtlBtn { lbl: "A+"; tip: qsTr("增大字号"); onClicked: controls.changeFontSize(controls.fontSize + 1) }
        CtlBtn { iconChar: "◐"; lbl: qsTr("背景"); tip: qsTr("切换阅读背景"); onClicked: controls.toggleBackground() }
        CtlBtn { iconChar: "☷"; lbl: qsTr("对齐"); tip: qsTr("切换对齐方式"); onClicked: controls.toggleAlign() }
        CtlBtn { iconChar: "↔"; lbl: qsTr("页宽"); tip: qsTr("切换页宽"); onClicked: controls.togglePageWidth() }
        CtlBtn { iconChar: "⇥"; lbl: qsTr("下章"); tip: qsTr("下一章"); onClicked: controls.nextChapter() }
        // C7：笔记列表（追加在行尾，保持既有按钮的 children 索引不变——ControlsSmoke 依赖）
        CtlBtn { iconChar: "≣"; lbl: qsTr("笔记"); tip: qsTr("笔记列表"); onClicked: controls.openNotes() }
        // C8：书内搜索（同样追加行尾，不动既有索引）
        CtlBtn { iconChar: "⌕"; lbl: qsTr("搜索"); tip: qsTr("书内搜索"); onClicked: controls.openSearch() }
    }
}
