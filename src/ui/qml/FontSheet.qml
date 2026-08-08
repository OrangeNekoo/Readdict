import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.UI 1.0

// U4：Sheet「字体」标签面板——4 字体族单选（映射 D4 字体弹层同源数据：
// 思源宋体/黑体 + 已加载的 HW/得意黑）+ 字号分段滑块。
// 数据与 ReaderControls.fontListModel / Books.resolveFontFamily 映射链一致
//（value 为存储 token，text 可翻译；译文不改变 token）。字号分段 [14,16,18,20,22,24]。
// 只渲染与上报：current 值由宿主注入，变更发信号由宿主写 Settings 并刷新排版。
// 接口：fontFamily（存储 token）、fontSize；信号 setFontFamily/setFontSize。
// 测试句柄：fontItems/sizeItems（两个 Repeater，供点击驱动）。
Item {
    id: fontSheet

    objectName: "fontSheetPanel"
    property string fontFamily: ""
    property int fontSize: 18
    signal setFontFamily(string family)
    signal setFontSize(int size)

    property var fontModel: [
        { text: qsTr("思源宋体 VF"), value: "思源宋体 VF" },
        { text: qsTr("思源黑体 VF"), value: "思源黑体 VF" },
        { text: qsTr("思源黑体 HW VF"), value: "SourceHanSansHW-VF" },
        { text: qsTr("得意黑"), value: "得意黑" }
    ]
    property var sizeSegments: [14, 16, 18, 20, 22, 24]

    property alias fontItems: fontRepeater
    property alias sizeItems: sizeRepeater

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        Label {
            text: qsTr("字体")
            font.pixelSize: 13
            color: UITheme.textSecondary
        }
        // 4 字体族单选行（○● + 显示名，选中描边加深）
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                id: fontRepeater
                model: fontSheet.fontModel
                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 6
                    color: "transparent"
                    border.color: modelData.value === fontSheet.fontFamily
                                  ? UITheme.borderActive : UITheme.borderDefault
                    border.width: modelData.value === fontSheet.fontFamily ? 2 : 1
                    MouseArea {
                        anchors.fill: parent
                        onClicked: fontSheet.setFontFamily(modelData.value)
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 12
                        spacing: 8
                        Label {
                            text: modelData.value === fontSheet.fontFamily ? "●" : "○"
                            font.pixelSize: 14
                            color: modelData.value === fontSheet.fontFamily
                                   ? UITheme.textPrimary : UITheme.textSecondary
                        }
                        Label {
                            text: modelData.text
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: 15
                            color: modelData.value === fontSheet.fontFamily
                                   ? UITheme.textPrimary : UITheme.textSecondary
                        }
                    }
                }
            }
        }

        Label {
            text: qsTr("字号")
            font.pixelSize: 13
            color: UITheme.textSecondary
        }
        // 字号分段滑块：A− [14..24] A+，当前值加深描边
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Label {
                text: "A−"
                font.pixelSize: 14
                color: UITheme.textSecondary
            }
            Repeater {
                id: sizeRepeater
                model: fontSheet.sizeSegments
                Rectangle {
                    required property int modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    radius: 6
                    color: "transparent"
                    border.color: modelData === fontSheet.fontSize
                                  ? UITheme.borderActive : UITheme.borderDefault
                    border.width: modelData === fontSheet.fontSize ? 2 : 1
                    MouseArea {
                        anchors.fill: parent
                        onClicked: fontSheet.setFontSize(modelData)
                    }
                    Label {
                        anchors.centerIn: parent
                        text: modelData
                        font.pixelSize: 13
                        color: modelData === fontSheet.fontSize
                               ? UITheme.textPrimary : UITheme.textSecondary
                    }
                }
            }
            Label {
                text: "A+"
                font.pixelSize: 14
                color: UITheme.textSecondary
            }
        }
    }
}
