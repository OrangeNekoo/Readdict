import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.UI 1.0

// U5：Kindle 分段滑块（分析报告 §4：等宽矩形段，已选实心深色/未选浅色轮廓，
// 两端 −/+ 按钮，当前值上方显示）。
// - segments: [{label, value}]；currentValue：当前选中值；selected(value) 信号。
// - 点击段 = 直接选中；−/+ = 前后挪一段（钳在边界）。
// - 段：选中 = 深色实心（浅色主题黑底白字/深色主题浅底深字）；未选 = 边框 + 主文字。
// - 等宽：段宽 = (可用宽 - 两按钮宽 - 间距) / 段数。
// 测试/外部句柄：minusBtn/plusBtn（Button，clicked() 驱动）、
// selectValue(v)（与点击同路径）。
Item {
    id: seg

    property var segments: []
    property var currentValue: ""
    signal selected(var value)

    property alias minusBtn: minusButton
    property alias plusBtn: plusButton

    implicitHeight: 44
    height: 44

    RowLayout {
        anchors.fill: parent
        spacing: 8
        // − 按钮
        Button {
            id: minusButton
            text: "−"
            Layout.preferredWidth: 40
            Layout.fillHeight: true
            font.pixelSize: 18
            // 平面 −/+ 风格：透明背景、零边框，仅文字随主题/禁用态
            background: Rectangle {
                color: "transparent"
                border.width: 0
            }
            contentItem: Text {
                text: minusButton.text
                font.pixelSize: 18
                color: minusButton.enabled ? UITheme.textPrimary : UITheme.textDisabled
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            onClicked: seg.nudge(-1)
        }
        // 等宽段
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4
            Repeater {
                model: seg.segments
                delegate: Item {
                    id: segCell
                    required property var modelData
                    readonly property bool isSelected: segCell.modelData.value === seg.currentValue
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Rectangle {
                        anchors.fill: parent
                        radius: 4
                        color: segCell.isSelected ? UITheme.borderActive : "transparent"
                        border.color: segCell.isSelected ? UITheme.borderActive : UITheme.borderDefault
                        border.width: 1
                    }
                    Label {
                        anchors.centerIn: parent
                        text: segCell.modelData.label
                        font.pixelSize: UITheme.fsCaption
                        color: segCell.isSelected ? UITheme.bgPrimary : UITheme.textPrimary
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: seg.selectValue(segCell.modelData.value)
                    }
                }
            }
        }
        // + 按钮
        Button {
            id: plusButton
            text: "+"
            Layout.preferredWidth: 40
            Layout.fillHeight: true
            font.pixelSize: 18
            background: Rectangle {
                color: "transparent"
                border.width: 0
            }
            contentItem: Text {
                text: plusButton.text
                font.pixelSize: 18
                color: plusButton.enabled ? UITheme.textPrimary : UITheme.textDisabled
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            onClicked: seg.nudge(1)
        }
    }

    // −/+：按当前索引前后挪一段（选中即发 selected；边界处钳住）
    function nudge(delta) {
        const idx = seg.indexFor(seg.currentValue)
        if (idx < 0) return
        const target = Math.max(0, Math.min(seg.segments.length - 1, idx + delta))
        if (target !== idx)
            seg.selectValue(seg.segments[target].value)
    }
    function indexFor(v) {
        for (let i = 0; i < seg.segments.length; ++i)
            if (seg.segments[i].value === v) return i
        return -1
    }
    // 选中：currentValue + selected（页面据此写 Settings/字段）。与点击同路径。
    function selectValue(v) {
        if (seg.currentValue === v) return
        seg.currentValue = v
        seg.selected(v)
    }
}
