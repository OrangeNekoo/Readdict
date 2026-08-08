import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.UI 1.0

// U4：Sheet「布局」标签面板——翻页方向（竖滚 scroll / 横翻 paged，E4 的
// reading/pageMode）+ 页边距（typography/pageWidth 窄/正常/宽）+ 行间距
//（typography/lineHeight 紧凑/标准/宽松）分段选择。
// 只渲染与上报：current 值由宿主注入（page.pageMode / page.typography），
// 变更发信号由宿主写 Settings 并刷新（方向即时生效 pageMode，排版重组合 typography）。
// 接口：pageMode/pageWidth/lineHeight；信号 setPageMode/setPageWidth/setLineHeight。
// 测试句柄：modeItems/marginItems/lineItems（三个 Repeater，供点击驱动）。
// 注：分段行用普通 Repeater 委托（required modelData 模式，同 ThemeSheet/FontSheet），
// 不抽内联组件——组件实例拿不到 Repeater 注入的 modelData 上下文属性（探针实证）。
Item {
    id: layoutSheet

    objectName: "layoutSheetPanel"
    property string pageMode: "scroll"
    property string pageWidth: "normal"
    property real lineHeight: 1.6
    signal setPageMode(string mode)
    signal setPageWidth(string width)
    signal setLineHeight(real lineHeight)

    // 分段数据（text 可翻译，value 为存储 token/数值）
    property var modeModel: [
        { text: qsTr("连续滚动"), value: "scroll" },
        { text: qsTr("整页翻动"), value: "paged" }
    ]
    property var marginModel: [
        { text: qsTr("窄"), value: "narrow" },
        { text: qsTr("正常"), value: "normal" },
        { text: qsTr("宽"), value: "wide" }
    ]
    property var lineModel: [
        { text: qsTr("紧凑"), value: 1.4 },
        { text: qsTr("标准"), value: 1.6 },
        { text: qsTr("宽松"), value: 2.0 }
    ]

    property alias modeItems: modeRepeater
    property alias marginItems: marginRepeater
    property alias lineItems: lineRepeater

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        Label {
            text: qsTr("方向")
            font.pixelSize: 13
            color: UITheme.textSecondary
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                id: modeRepeater
                model: layoutSheet.modeModel
                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: 6
                    color: "transparent"
                    border.color: modelData.value === layoutSheet.pageMode
                                  ? UITheme.borderActive : UITheme.borderDefault
                    border.width: modelData.value === layoutSheet.pageMode ? 2 : 1
                    MouseArea {
                        anchors.fill: parent
                        onClicked: layoutSheet.setPageMode(modelData.value)
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        spacing: 8
                        Label {
                            text: parent.parent.modelData.value === layoutSheet.pageMode ? "●" : "○"
                            font.pixelSize: 13
                            color: parent.parent.modelData.value === layoutSheet.pageMode
                                   ? UITheme.textPrimary : UITheme.textSecondary
                        }
                        Label {
                            text: parent.parent.modelData.text
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: 14
                            color: parent.parent.modelData.value === layoutSheet.pageMode
                                   ? UITheme.textPrimary : UITheme.textSecondary
                        }
                    }
                }
            }
        }

        Label {
            text: qsTr("页边距")
            font.pixelSize: 13
            color: UITheme.textSecondary
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                id: marginRepeater
                model: layoutSheet.marginModel
                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: 6
                    color: "transparent"
                    border.color: modelData.value === layoutSheet.pageWidth
                                  ? UITheme.borderActive : UITheme.borderDefault
                    border.width: modelData.value === layoutSheet.pageWidth ? 2 : 1
                    MouseArea {
                        anchors.fill: parent
                        onClicked: layoutSheet.setPageWidth(modelData.value)
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        spacing: 8
                        Label {
                            text: parent.parent.modelData.value === layoutSheet.pageWidth ? "●" : "○"
                            font.pixelSize: 13
                            color: parent.parent.modelData.value === layoutSheet.pageWidth
                                   ? UITheme.textPrimary : UITheme.textSecondary
                        }
                        Label {
                            text: parent.parent.modelData.text
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: 14
                            color: parent.parent.modelData.value === layoutSheet.pageWidth
                                   ? UITheme.textPrimary : UITheme.textSecondary
                        }
                    }
                }
            }
        }

        Label {
            text: qsTr("行间距")
            font.pixelSize: 13
            color: UITheme.textSecondary
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                id: lineRepeater
                model: layoutSheet.lineModel
                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: 6
                    color: "transparent"
                    border.color: modelData.value === layoutSheet.lineHeight
                                  ? UITheme.borderActive : UITheme.borderDefault
                    border.width: modelData.value === layoutSheet.lineHeight ? 2 : 1
                    MouseArea {
                        anchors.fill: parent
                        onClicked: layoutSheet.setLineHeight(modelData.value)
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        spacing: 8
                        Label {
                            text: parent.parent.modelData.value === layoutSheet.lineHeight ? "●" : "○"
                            font.pixelSize: 13
                            color: parent.parent.modelData.value === layoutSheet.lineHeight
                                   ? UITheme.textPrimary : UITheme.textSecondary
                        }
                        Label {
                            text: parent.parent.modelData.text
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: 14
                            color: parent.parent.modelData.value === layoutSheet.lineHeight
                                   ? UITheme.textPrimary : UITheme.textSecondary
                        }
                    }
                }
            }
        }
    }
}
