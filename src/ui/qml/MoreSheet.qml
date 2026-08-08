import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.UI 1.0

// U4：Sheet「更多」标签面板——Toggle 开关项（自动续章 reading/autoContinue、
// 深色跟随 reading/darkFollow）+ 功能菜单项（目录/笔记/书内搜索/朗读/上一章/
// 下一章——现有 ReaderControls 入口迁入 Sheet，功能不丢）。
// 只渲染与上报：开关当前值由宿主注入，变更发信号由宿主写 Settings（自动续章
// 门控 ReaderPage.autoNextChapter，深色跟随门控 effectiveBg 派生）；菜单项发
// 信号由宿主打开对应 Dialog / 换章 / 启动朗读。
// 接口：autoContinue/darkFollow；信号 setAutoContinue/setDarkFollow +
// requestToc/requestNotes/requestSearch/requestReadAloud/requestPrevChapter/
// requestNextChapter。
// 测试句柄：continueToggle/followToggle/menuItems（菜单项 Repeater）。
Item {
    id: moreSheet

    objectName: "moreSheetPanel"
    property bool autoContinue: true
    property bool darkFollow: false
    signal setAutoContinue(bool on)
    signal setDarkFollow(bool on)
    signal requestToc()
    signal requestNotes()
    signal requestSearch()
    signal requestReadAloud()
    signal requestPrevChapter()
    signal requestNextChapter()

    property var menuModel: [
        { icon: "toc", text: qsTr("目录"), sig: "requestToc" },
        { icon: "notes", text: qsTr("笔记"), sig: "requestNotes" },
        { icon: "search", text: qsTr("书内搜索"), sig: "requestSearch" },
        { icon: "read", text: qsTr("朗读"), sig: "requestReadAloud" },
        { icon: "prev", text: qsTr("上一章"), sig: "requestPrevChapter" },
        { icon: "next", text: qsTr("下一章"), sig: "requestNextChapter" }
    ]

    property alias continueToggle: continueToggle
    property alias followToggle: followToggle
    property alias menuItems: menuRepeater

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        // Toggle 开关行（Kindle 开关语义：右侧开关）
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

        // 分隔线
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: UITheme.divider
            Layout.topMargin: 4
            Layout.bottomMargin: 4
        }

        // 功能菜单项（KdListItem 风格：线性图标 + 文字，点击上报）
        Repeater {
            id: menuRepeater
            model: moreSheet.menuModel
            Rectangle {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                radius: 6
                color: menuMouse.containsMouse ? "#0A000000" : "transparent"
                MouseArea {
                    id: menuMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        // 经模型 sig 字段分发到对应信号（信号可作方法调用）
                        moreSheet[modelData.sig]()
                    }
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 12
                    spacing: 12
                    KdIcons {
                        name: modelData.icon
                        size: 22
                        color: UITheme.textPrimary
                    }
                    Label {
                        text: modelData.text
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.pixelSize: 15
                        color: UITheme.textPrimary
                    }
                }
            }
        }
    }
}
