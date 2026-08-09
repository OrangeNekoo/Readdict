import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.UI 1.0

// U5：Sheet「更多」标签面板——只保留自动续章、深色跟随开关与阅读进度行。
// 阅读进度行通过 requestToc 通知宿主打开目录；其它功能入口统一位于顶栏 ⋮ 菜单。
// 接口：autoContinue/darkFollow；信号 setAutoContinue/setDarkFollow/requestToc。
// 测试句柄：continueToggle/followToggle/progressRow。
Item {
    id: moreSheet

    objectName: "moreSheetPanel"
    property bool autoContinue: true
    property bool darkFollow: false
    signal setAutoContinue(bool on)
    signal setDarkFollow(bool on)
    signal requestToc()

    property alias continueToggle: continueToggle
    property alias followToggle: followToggle
    property alias progressRow: progressRow

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        // Toggle 开关行（Kindle 开关语义：右侧开关）。
        RowLayout {
            Layout.fillWidth: true
            Label {
                text: qsTr("自动续章")
                Layout.fillWidth: true
                font.pixelSize: 15
                color: UITheme.textPrimary
            }
            Switch {
                id: continueToggle
                checked: moreSheet.autoContinue
                onToggled: moreSheet.setAutoContinue(checked)
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Label {
                text: qsTr("深色跟随")
                Layout.fillWidth: true
                font.pixelSize: 15
                color: UITheme.textPrimary
            }
            Switch {
                id: followToggle
                checked: moreSheet.darkFollow
                onToggled: moreSheet.setDarkFollow(checked)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: UITheme.divider
            Layout.topMargin: 4
            Layout.bottomMargin: 4
        }

        // 阅读进度行：点击后仍走目录入口，显示当前阅读位置。
        Item {
            id: progressRow
            Layout.fillWidth: true
            Layout.preferredHeight: 42
            RowLayout {
                anchors.fill: parent
                spacing: 10
                Label {
                    text: qsTr("阅读进度")
                    font.pixelSize: 15
                    color: UITheme.textPrimary
                }
                Item { Layout.fillWidth: true }
                Label {
                    text: qsTr("书中位置")
                    font.pixelSize: UITheme.fsCaption
                    color: UITheme.textSecondary
                }
                Label {
                    text: "›"
                    font.pixelSize: 20
                    color: UITheme.textSecondary
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: moreSheet.requestToc()
            }
        }
    }
}
