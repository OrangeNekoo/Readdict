import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.UI 1.0

// U5：Kindle ○/● 单选网格（分析报告 §4：空心圆○/实心圆● + 文字标签，网格布局）。
// - options: [{text, value}]；currentValue：当前选中值；columns：列数（默认 2）。
// - 选中：空心圆 → 实心圆（边框黑 + 内圆实心）；文本颜色随选中加深。
// - 交互：点击单元格 → selectValue(value) → currentValue + selected(value) 信号。
// - 恢复路径（页面 onCompleted 直接赋 currentValue）不触发 selected，避免回写 Settings。
// 测试/外部句柄：cells（Repeater，cell.modelData.value 可定位）、
// selectValue(v)（与点击同路径，供测试驱动真实选中逻辑）。
Item {
    id: grid

    property var options: []
    property string currentValue: ""
    property int columns: 2
    signal selected(string value)

    property alias cells: cellRepeater

    // 行数 = ceil(n/columns)，行高 44：隐式高度供 ColumnLayout 布局
    implicitHeight: Math.ceil(Math.max(1, options.length) / Math.max(1, columns)) * 44
    implicitWidth: 200

    Grid {
        id: g
        anchors.fill: parent
        columns: grid.columns
        rowSpacing: 4
        columnSpacing: 12

        Repeater {
            id: cellRepeater
            model: grid.options
            delegate: Item {
                id: cell
                required property var modelData
                readonly property bool isSelected: cell.modelData.value === grid.currentValue

                width: (g.width - (grid.columns - 1) * g.columnSpacing) / Math.max(1, grid.columns)
                height: 44

                RowLayout {
                    anchors.fill: parent
                    spacing: 8
                    // ○/● 圆圈：外框 18px（选中深色/未选中浅灰），内圆 10px 实心选中显示
                    Rectangle {
                        width: 18; height: 18; radius: 9
                        border.width: 1.5
                        border.color: cell.isSelected ? UITheme.borderActive : UITheme.borderDefault
                        color: "transparent"
                        Rectangle {
                            anchors.centerIn: parent
                            width: 10; height: 10; radius: 5
                            visible: cell.isSelected
                            color: UITheme.borderActive
                        }
                    }
                    Label {
                        text: cell.modelData.text
                        font.pixelSize: UITheme.fsListItem
                        color: cell.isSelected ? UITheme.textPrimary : UITheme.textSecondary
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: grid.selectValue(cell.modelData.value)
                }
            }
        }
    }

    // 选中：更新 currentValue 并发出 selected（页面据此写 Settings 即时生效）。
    // 与单元格点击同路径（MouseArea.onClicked → selectValue），测试直接调用等价点击。
    function selectValue(v) {
        if (grid.currentValue === v) return
        grid.currentValue = v
        grid.selected(v)
    }
}
