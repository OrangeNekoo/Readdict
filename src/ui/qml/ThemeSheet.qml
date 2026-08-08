import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.UI 1.0

// U4：Sheet「主题」标签面板（分析报告 §4：2×2 主题预设网格、单选 ○● 勾选标记、
// 选中即应用）。本组件只渲染与上报——读写由 ReaderPage 处理（与 ReaderControls
// 同模式：组件无状态，current 值由宿主注入）。
// 四态数据与 ReaderPage bgMode / Settings background/mode 一致（浅/深/米白/自定义
// 图片——E1 后无 eink）；"保存当前设置"描边按钮在 Sheet 容器底部操作区（§4），
// 非本面板内容。
// 接口：bgMode（当前背景模式）、bgImagePath（有无自定义图，驱动 image 项提示）；
// 信号 setBackgroundMode(mode)。
// 测试句柄：themeItems（网格 Repeater，供点击驱动）。
Item {
    id: themeSheet

    objectName: "themeSheetPanel"
    property string bgMode: "light"
    property string bgImagePath: ""
    signal setBackgroundMode(string mode)

    property var model: [
        { text: qsTr("浅色"), value: "light" },
        { text: qsTr("深色"), value: "dark" },
        { text: qsTr("米白"), value: "paper" },
        { text: qsTr("自定义图片"), value: "image" }
    ]

    property alias themeItems: themeRepeater

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14

        // §4：2×2 主题预设卡片网格（卡片间距 16px，选中描边加深 + ● 单选标记）
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 2
            rowSpacing: 12
            columnSpacing: 12

            Repeater {
                id: themeRepeater
                model: themeSheet.model
                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 56
                    radius: 6
                    color: "transparent"
                    border.color: modelData.value === themeSheet.bgMode
                                  ? UITheme.borderActive : UITheme.borderDefault
                    border.width: modelData.value === themeSheet.bgMode ? 2 : 1

                    MouseArea {
                        anchors.fill: parent
                        onClicked: themeSheet.setBackgroundMode(modelData.value)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 12
                        spacing: 8
                        // 单选指示 ○/●（§4 左上角勾选标记的 ○● 等价形态）
                        Label {
                            text: modelData.value === themeSheet.bgMode ? "●" : "○"
                            font.pixelSize: 16
                            color: modelData.value === themeSheet.bgMode
                                   ? UITheme.textPrimary : UITheme.textSecondary
                        }
                        Label {
                            text: modelData.text
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: 15
                            color: modelData.value === themeSheet.bgMode
                                   ? UITheme.textPrimary : UITheme.textSecondary
                        }
                        // 无自定义图时 image 项灰色提示（选择入口在设置页选图）
                        Label {
                            visible: modelData.value === "image" && themeSheet.bgImagePath.length === 0
                            text: qsTr("未设置")
                            font.pixelSize: 11
                            color: UITheme.textDisabled
                        }
                    }
                }
            }
        }
    }
}
