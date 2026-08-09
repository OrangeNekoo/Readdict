import QtQuick
import Readdict.UI 1.0

// Kindle 布局图标卡：72x52 圆角描边卡片，内部用横线或竖线示意布局。
// 选中态只改变边框 Token；点击由宿主处理，组件不持有设置状态。
Rectangle {
    id: card

    width: 72
    height: 52
    radius: 8
    color: "transparent"
    border.color: card.selected ? UITheme.borderActive : UITheme.borderDefault
    border.width: card.selected ? 2.5 : 1

    property bool selected: false
    property int lines: 4
    property bool dense: false
    property string glyph: "h" // h 横线；v 竖线；narrow/normal/wide 宽度；tight/loose 间距
    property alias lineItems: lineRepeater
    signal clicked()

    MouseArea {
        anchors.fill: parent
        onClicked: card.clicked()
    }

    // 横线示意：页边距和行间距卡片通过 glyph 控制线宽/线距。
    Column {
        id: horizontalLines
        visible: !card.dense && card.glyph !== "v"
        anchors.centerIn: parent
        spacing: card.glyph === "loose" ? 6 : card.glyph === "tight" ? 2 : 4

        Repeater {
            id: lineRepeater
            model: card.lines
            Rectangle {
                width: card.glyph === "narrow" ? 34
                       : card.glyph === "wide" ? 52 : 44
                height: 2
                radius: 1
                color: UITheme.textPrimary
            }
        }
    }

    // 竖线示意：连续滚动/竖排 glyph，dense 也可供调用方显式启用。
    Row {
        id: verticalLines
        visible: card.dense || card.glyph === "v"
        anchors.centerIn: parent
        spacing: card.dense ? 2 : 4

        Repeater {
            model: card.lines
            Rectangle {
                width: 2
                height: 30
                radius: 1
                color: UITheme.textPrimary
            }
        }
    }
}
