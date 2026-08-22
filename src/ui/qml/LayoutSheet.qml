import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.UI 1.0

// U5：Sheet「布局」标签面板——方向、页边距、行间距改用 Kindle 图标卡，
// 并保留对齐 KdSegmentedSlider。只渲染与上报，设置持久化由 ReaderPage 处理。
// 接口：pageMode/pageWidth/lineHeight/align；信号 setPageMode/setPageWidth/
// setLineHeight/setAlign。测试句柄：modeItems/marginItems/lineItems/alignSlider。
Item {
    id: layoutSheet
    objectName: "layoutSheetPanel"
    // 完整内容高度 = layoutColumn 隐式高度 + 上下 16px 边距。KdBottomSheet 的
    // panelScroller 依此测量 contentHeight 并门控 interactive，保证底部对齐
    // 控件计入内容高度、滚动到底完整可见。
    implicitHeight: layoutColumn.implicitHeight + 32
    property string pageMode: "scroll"
    property string pageWidth: "normal"
    property real lineHeight: 1.6
    property string align: "left"
    signal setPageMode(string mode)
    signal setPageWidth(string width)
    signal setLineHeight(real lineHeight)
    signal setAlign(string align)

    // value 为存储 token/数值，glyph 为 KdIconCard 的示意图形。
    // 任务3：文案与语义对齐——scroll = 竖向连续滚动（单列竖流），paged = 横向分页
    //（页面沿 x 轴排列，左右/上下键整页翻动）。
    property var modeModel: [
        { text: qsTr("竖向连续滚动"), value: "scroll", glyph: "v" },
        { text: qsTr("横向分页"), value: "paged", glyph: "h" }
    ]
    property var marginModel: [
        { text: qsTr("窄"), value: "narrow", glyph: "narrow" },
        { text: qsTr("正常"), value: "normal", glyph: "normal" },
        { text: qsTr("宽"), value: "wide", glyph: "wide" }
    ]
    property var lineModel: [
        { text: qsTr("紧凑"), value: 1.4, glyph: "tight" },
        { text: qsTr("标准"), value: 1.6, glyph: "normal" },
        { text: qsTr("宽松"), value: 2.0, glyph: "loose" }
    ]
    property var alignModel: [
        { label: qsTr("左"), value: "left" },
        { label: qsTr("中"), value: "center" },
        { label: qsTr("右"), value: "right" }
    ]

    property alias modeItems: modeRepeater
    property alias marginItems: marginRepeater
    property alias lineItems: lineRepeater
    property alias alignSlider: alignSlider

    ColumnLayout {
        id: layoutColumn
        // 只锚定上/左/右，不锚底部：列高由内容隐式高度决定，避免与根
        // implicitHeight 形成锚点/隐式高度循环；16px 底边距随隐式高度计入。
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        spacing: 10

        Label {
            text: qsTr("方向")
            font.pixelSize: 13
            color: UITheme.textSecondary
        }
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            Row {
                id: modeRow
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                Repeater {
                    id: modeRepeater
                    model: layoutSheet.modeModel
                    KdIconCard {
                        required property var modelData
                        selected: modelData.value === layoutSheet.pageMode
                        glyph: modelData.glyph
                        onClicked: layoutSheet.setPageMode(modelData.value)
                    }
                }
            }
        }

        Label {
            text: qsTr("页边距")
            font.pixelSize: 13
            color: UITheme.textSecondary
        }
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            Row {
                id: marginRow
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                Repeater {
                    id: marginRepeater
                    model: layoutSheet.marginModel
                    KdIconCard {
                        required property var modelData
                        selected: modelData.value === layoutSheet.pageWidth
                        glyph: modelData.glyph
                        onClicked: layoutSheet.setPageWidth(modelData.value)
                    }
                }
            }
        }

        Label {
            text: qsTr("行间距")
            font.pixelSize: 13
            color: UITheme.textSecondary
        }
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            Row {
                id: lineRow
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                Repeater {
                    id: lineRepeater
                    model: layoutSheet.lineModel
                    KdIconCard {
                        required property var modelData
                        selected: modelData.value === layoutSheet.lineHeight
                        glyph: modelData.glyph
                        onClicked: layoutSheet.setLineHeight(modelData.value)
                    }
                }
            }
        }

        KdSegmentedSlider {
            id: alignSlider
            Layout.fillWidth: true
            segments: layoutSheet.alignModel
            currentValue: layoutSheet.align
            onSelected: (value) => layoutSheet.setAlign(value)
        }
    }
}
