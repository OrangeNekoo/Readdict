import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Readdict.Backend
import Readdict.UI 1.0

// U5：语言设置子页（Kindle 全屏列表化——设置页"语言"行进入）。
// KdRadioGrid 单选 zh_CN/zh_TW/en：选中即写 settings.json 的 ui/language +
// Lang.applyLanguage 加载对应 .qm（main.cpp languageChanged → retranslate 刷新）。
// 返回：固定顶部"← 返回"（B4 模式，onClicked → goBack() → pop）。
// 测试/外部句柄：backButton、goBack()、languageGrid（KdRadioGrid，
// currentValue/selectValue 驱动三语切换，与点击同路径）。
Page {
    id: page
    title: qsTr("语言")
    // U5：子页属于设置导航（保持顶部标签/底部导航"设置"高亮）
    property string navId: "settings"
    property alias backButton: backButton
    property alias languageGrid: langGrid

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        anchors.topMargin: 16
        anchors.bottomMargin: 24
        spacing: 16

        // 固定顶部：返回 + 页面标题（B4 返回导航位，同 SyncPage/StatsPage 模式）
        RowLayout {
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

        // 三语单选：恢复当前语言 → 选中即持久化 + 切换
        KdRadioGrid {
            id: langGrid
            Layout.fillWidth: true
            columns: 3
            options: [
                { text: qsTr("简体中文"), value: "zh_CN" },
                { text: qsTr("繁體中文"), value: "zh_TW" },
                { text: "English", value: "en" }
            ]
            // D6 恢复：启动/进入时按 ui/language 选中（直接赋 currentValue 不触发
            // selected，不会回写 Settings——与背景模式恢复同语义）
            Component.onCompleted: {
                const code = String(Settings.value("ui/language") || "zh_CN")
                langGrid.currentValue = code
            }
            onSelected: (v) => {
                Settings.setValue("ui/language", v)
                Lang.applyLanguage(v)
            }
        }

        Item { Layout.fillHeight: true }
    }

    // B4：返回上一页（设置页）。抽函数暴露供 QML 冒烟测试驱动
    function goBack() {
        page.StackView.view.pop()
    }
}
