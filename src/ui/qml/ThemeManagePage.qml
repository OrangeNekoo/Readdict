import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.Backend
import Readdict.UI 1.0

// L10（P1#10）：管理主题页——自定义预设列表（themes/custom）+ 删除按钮。
// 经 ThemeSheet「管理主题」行 push 到宿主 StackView（阅读页之上）；navId=reader
// 保持沉浸（顶部标签/底部导航不浮现，同阅读页）。删除当前激活预设（themes/active
// 同名）时回退内置默认（typography 默认 + background/mode=light 并清空激活态）；
// 删除非激活预设仅移除。返回后 ReaderPage.onActivated 重读 Settings 刷新响应层
// 与主题面板网格（删除项不再残留）。
// 返回：固定顶部"← 返回"（B4 模式）。
// 测试/外部句柄：backButton、goBack()、themeList（ListView）、deletePreset(name)。
Page {
    id: page
    title: qsTr("管理主题")
    // L10：阅读页之上保持沉浸（同 ReaderPage navId，两套导航不浮现）
    property string navId: "reader"
    property alias backButton: backButton
    property alias themeList: themeList
    // 自定义预设列表（themes/custom；删除后实时刷新）
    property var customThemes: page.loadCustomThemes()

    // 固定顶部：返回 + 页面标题（B4 返回导航位，同 SettingsBackgroundPage 模式）
    RowLayout {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        anchors.topMargin: 16
        ToolButton {
            id: backButton
            text: "← " + qsTr("返回")
            onClicked: page.goBack()
        }
        Label {
            text: page.title
            font.pixelSize: UITheme.fsPageTitle
            font.bold: true
            color: UITheme.textPrimary
            Layout.leftMargin: 8
        }
    }

    ListView {
        id: themeList
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        anchors.topMargin: 12
        anchors.bottomMargin: 24
        clip: true
        model: page.customThemes
        spacing: 8
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: Rectangle {
            required property var modelData
            width: themeList.width
            height: 52
            radius: 6
            color: "transparent"
            border.color: UITheme.borderDefault
            border.width: 1
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 8
                spacing: 8
                // ○ 圆点标记（与预设网格单选一致；点击名称应用——见 nameMouse）
                Rectangle {
                    width: 18; height: 18; radius: 9
                    border.width: 1.5
                    border.color: modelData.name === String(Settings.value("themes/active") || "")
                                  ? UITheme.borderActive : UITheme.borderDefault
                    color: "transparent"
                    Rectangle {
                        anchors.centerIn: parent
                        width: 10; height: 10; radius: 5
                        visible: modelData.name === String(Settings.value("themes/active") || "")
                        color: UITheme.borderActive
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 2
                    Label {
                        text: modelData.name
                        font.pixelSize: UITheme.fsListItem
                        color: UITheme.textPrimary
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        verticalAlignment: Text.AlignVCenter
                    }
                    Label {
                        text: page.presetSummary(modelData)
                        font.pixelSize: UITheme.fsCaption
                        color: UITheme.textSecondary
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        verticalAlignment: Text.AlignVCenter
                    }
                }
                Button {
                    text: qsTr("删除")
                    font.pixelSize: 13
                    onClicked: page.deletePreset(modelData.name)
                }
            }
        }
    }

    // 空态提示：无自定义预设时居中显示
    Label {
        anchors.centerIn: parent
        text: qsTr("暂无自定义主题")
        font.pixelSize: UITheme.fsListItem
        color: UITheme.textSecondary
        visible: page.customThemes.length === 0
    }

    // 读取 themes/custom（容错同 ThemeSheet.loadCustomThemes）
    function loadCustomThemes() {
        const v = Settings.value("themes/custom")
        if (!v || !Array.isArray(v)) return []
        const out = []
        for (let i = 0; i < v.length; ++i) {
            const p = v[i]
            if (p && typeof p === "object" && p.name) out.push(p)
        }
        return out
    }

    // 行副文案：背景模式名 + 字号（如「米白 · 22px」）
    function presetSummary(p) {
        const bgName = p.bg === "dark" ? qsTr("深色")
                       : p.bg === "paper" ? qsTr("米白")
                       : p.bg === "image" ? qsTr("自定义图片") : qsTr("浅色")
        return bgName + " · " + (Number(p.fontSize) || 18) + "px"
    }

    // 删除预设：移除后写回 themes/custom；删除当前激活预设（themes/active 同名）
    // 时回退内置默认（清激活态 + typography/background 默认键）
    function deletePreset(name) {
        const list = page.loadCustomThemes().filter(function (p) { return p.name !== name })
        Settings.setValue("themes/custom", list)
        if (String(Settings.value("themes/active") || "") === name) {
            Settings.setValue("themes/active", "")
            Settings.setValue("typography/fontFamily", "思源宋体 VF")
            Settings.setValue("typography/fontSize", 18)
            Settings.setValue("typography/lineHeight", 1.6)
            Settings.setValue("background/mode", "light")
        }
        page.customThemes = list
    }

    // B4：返回上一页（阅读页）。抽函数暴露供 QML 冒烟测试驱动
    function goBack() {
        page.StackView.view.pop()
    }
}
