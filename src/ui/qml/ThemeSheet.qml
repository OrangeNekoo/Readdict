import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.Backend
import Readdict.UI 1.0

// U4：Sheet「主题」标签面板（分析报告 §4：2×2 主题预设网格、单选 ○● 勾选标记、
// 选中即应用）。本组件只渲染与上报——读写由 ReaderPage 处理（与 ReaderControls
// 同模式：组件无状态，current 值由宿主注入）。
// 四态数据与 ReaderPage bgMode / Settings background/mode 一致（浅/深/米白/自定义
// 图片——E1 后无 eink）；"保存当前设置"描边按钮在 Sheet 容器底部操作区（§4）。
// L10（P1#10）：主题预设持久化——
//   · 预设网格 = 内置 4 态 + themes/custom 自定义预设（{name, bg, text, fontFamily,
//     fontSize, lineHeight, ...}），保存/管理返回后经 refresh() 重算；
//   · 「保存当前设置」→ 命名输入 Dialog → saveCurrentTheme(name) 追加（同名覆盖）
//     themes/custom 并重算网格；「管理主题」行 push ThemeManagePage.qml；
//   · 选中自定义 → applyCustom(preset) 上报宿主（ReaderPage 写 typography/background
//     键并激活 themes/active）；激活态高亮自定义项，否则高亮匹配 bgMode 的内置项。
// 接口：bgMode（当前背景模式）、bgImagePath（有无自定义图，驱动 image 项提示）、
// fontFamily（存储 token）/typography（fontSize/lineHeight 原始值——保存快照用）；
// 信号 setBackgroundMode(mode)、applyPreset(preset)。
// 测试句柄：themeItems（网格 Repeater）、saveDialog/themeNameField（命名 Dialog）、
// manageRow（管理主题入口）、openSaveDialog()/saveCurrentTheme(name)/refresh()。
Item {
    id: themeSheet

    objectName: "themeSheetPanel"
    property string bgMode: "light"
    property string bgImagePath: ""
    property string fontFamily: ""
    property var typography: ({})
    signal setBackgroundMode(string mode)
    signal applyPreset(var preset)
    signal requestManageThemes()

    property var builtinModel: [
        { text: qsTr("浅色"), value: "light" },
        { text: qsTr("深色"), value: "dark" },
        { text: qsTr("米白"), value: "paper" },
        { text: qsTr("自定义图片"), value: "image" }
    ]
    // L10：自定义预设（themes/custom 数组，元素 {name, bg, text, fontFamily,
    // fontSize, lineHeight}；bg=image 时附 bgImagePath）与当前激活预设名
    //（themes/active——删除当前激活预设时回退内置默认的判定依据）
    property var customThemes: themeSheet.loadCustomThemes()
    property string activeCustom: String(Settings.value("themes/active") || "")
    property var model: themeSheet.buildModel()

    property alias themeItems: themeRepeater
    property alias saveDialog: saveThemeDialog
    property alias themeNameField: nameField
    property alias manageRow: manageEntry

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        // §4：主题预设卡片网格（内置 4 + 自定义；卡片间距 16px，选中描边加深 + ●）。
        // 卡片最小高 44（与 FontSheet 行高一致）：≤5 预设（3 行）在 Sheet 内容区
        // 内完整放下；更多时与 FontSheet 同模式（内容超出，可接受密度）
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
                    readonly property bool isSel: modelData.isCustom
                        ? themeSheet.activeCustom === modelData.value.name
                        : (themeSheet.activeCustom === "" && modelData.value === themeSheet.bgMode)
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 44
                    radius: 6
                    color: "transparent"
                    border.color: isSel ? UITheme.borderActive : UITheme.borderDefault
                    border.width: isSel ? 2 : 1

                    MouseArea {
                        anchors.fill: parent
                        // 内置项 → setBackgroundMode；自定义项 → applyCustom（激活 + 上报）
                        onClicked: {
                            if (modelData.isCustom)
                                themeSheet.applyCustom(modelData.value)
                            else
                                themeSheet.setBackgroundMode(modelData.value)
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 12
                        spacing: 8
                        // 单选指示 ○/●（§4 左上角勾选标记的 ○● 等价形态）
                        Label {
                            text: isSel ? "●" : "○"
                            font.pixelSize: 16
                            color: isSel ? UITheme.textPrimary : UITheme.textSecondary
                        }
                        Label {
                            text: modelData.text
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: 15
                            color: isSel ? UITheme.textPrimary : UITheme.textSecondary
                        }
                        // 无自定义图时 image 项灰色提示（选择入口在设置页选图）
                        Label {
                            visible: !modelData.isCustom && modelData.value === "image"
                                     && themeSheet.bgImagePath.length === 0
                            text: qsTr("未设置")
                            font.pixelSize: 11
                            color: UITheme.textDisabled
                        }
                    }
                }
            }
        }

        // L10：「管理主题」入口——自定义预设列表 + 删除（push ThemeManagePage.qml）。
        // 注：本面板位于 Loader（KdBottomSheet.contentLoader）内，StackView.view 附加
        // 属性在 Loader 内容中不解析（探针实证为 null）——上报宿主（ReaderPage）push。
        Rectangle {
            id: manageEntry
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            radius: 6
            color: manageMouse.containsMouse ? "#0A000000" : "transparent"
            MouseArea {
                id: manageMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: themeSheet.requestManageThemes()
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 12
                spacing: 12
                KdIcons {
                    name: "settings"
                    size: 22
                    color: UITheme.textPrimary
                }
                Label {
                    text: qsTr("管理主题")
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: 15
                    color: UITheme.textPrimary
                }
                Label {
                    text: "›"
                    font.pixelSize: 20
                    color: UITheme.textSecondary
                }
            }
        }
    }

    // L10：保存命名输入 Dialog——「保存当前设置」按钮（KdBottomSheet actionBar）
    // 经 ReaderPage.onSaveThemeRequested → openSaveDialog() 唤起；确定 → saveCurrentTheme
    Dialog {
        id: saveThemeDialog
        title: qsTr("保存当前设置")
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        width: 320
        height: 180
        contentItem: ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10
            Label {
                text: qsTr("预设名称")
                font.pixelSize: 13
                color: UITheme.textSecondary
            }
            TextField {
                id: nameField
                Layout.fillWidth: true
                placeholderText: qsTr("如：夜间护眼")
                selectByMouse: true
            }
        }
        onAccepted: themeSheet.saveCurrentTheme(nameField.text.trim())
    }

    // 读取 themes/custom 数组（容错：缺失/非数组/非法元素过滤）
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

    // 网格模型 = 内置 4 态 + 自定义（自定义项 value 即预设对象，isCustom 标记）
    function buildModel() {
        const m = []
        for (let i = 0; i < themeSheet.builtinModel.length; ++i)
            m.push(themeSheet.builtinModel[i])
        for (let j = 0; j < themeSheet.customThemes.length; ++j) {
            const p = themeSheet.customThemes[j]
            m.push({ text: p.name, value: p, isCustom: true })
        }
        return m
    }

    // 重算：自定义列表 + 激活态 + 网格模型（保存后/管理页返回后调用）
    function refresh() {
        themeSheet.customThemes = themeSheet.loadCustomThemes()
        themeSheet.activeCustom = String(Settings.value("themes/active") || "")
        themeSheet.model = themeSheet.buildModel()
    }

    // 「保存当前设置」入口（KdBottomSheet actionBar → ReaderPage.onSaveThemeRequested）
    function openSaveDialog() {
        nameField.text = ""
        saveThemeDialog.open()
    }

    // 保存当前排版/背景快照为主题预设：追加 themes/custom（同名覆盖，避免激活态
    // 按名查重失效）并重算网格。text 存派生文字色 token（文字色随背景派生，应用
    // 只涉及 typography/background 键，见 ReaderPage.applyThemePreset）。
    function saveCurrentTheme(name) {
        if (!name) return
        const list = themeSheet.loadCustomThemes()
        let idx = -1
        for (let i = 0; i < list.length; ++i) {
            if (list[i].name === name) { idx = i; break }
        }
        const preset = {
            name: name,
            bg: themeSheet.bgMode,
            text: themeSheet.bgMode === "dark" ? "darkTextPrimary" : "lightTextPrimary",
            fontFamily: themeSheet.fontFamily || "思源宋体 VF",
            fontSize: Number(themeSheet.typography.fontSize) || 18,
            lineHeight: Number(themeSheet.typography.lineHeight) || 1.6
        }
        if (themeSheet.bgMode === "image" && themeSheet.bgImagePath)
            preset.bgImagePath = themeSheet.bgImagePath
        if (idx >= 0) list[idx] = preset
        else list.push(preset)
        Settings.setValue("themes/custom", list)
        themeSheet.refresh()
    }

    // 「管理主题」入口上报（Loader 内容中 StackView.view 为 null，push 由
    // ReaderPage 处理——直接栈子项可解析，见 ReaderPage.openThemeManagePage）

    // 选中自定义预设：更新激活态显示并上报宿主应用（写 typography/background 键）
    function applyCustom(p) {
        if (!p || !p.name) return
        themeSheet.activeCustom = p.name
        themeSheet.applyPreset(p)
    }
}
