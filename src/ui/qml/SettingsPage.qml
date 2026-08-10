import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Window
import Readdict.Backend
import Readdict.UI 1.0

// U5：设置页 Kindle 全屏列表化（分析报告 §4/§7：无卡片分组，全屏列表——
// 线性图标 + 文字 + 右箭头 chevron → 进入子页；开关项即时生效）。
// 行结构：深色模式（L10 改三态 radio 即时生效）/ 语言（→ SettingsLanguagePage 子页）/
// 朗读（TTS）（→ SettingsTtsPage 子页）/ 阅读背景（→ SettingsBackgroundPage 子页）/
// 刷新封面（操作行）/ 同步（→ SyncPage）/ 统计（→ StatsPage）/ 版本标签。
// 功能行为不变（设置键/入口与 D3-D6/C5/B2 一致），仅 UI 从 SectionCard 分组
// 迁移到 KdListItem 列表 + StackView push 子页（语言/TTS/背景）。
// 返回按钮保持 B4 固定顶部（移出滚动区，左上角无滚动残影）。
// 测试/外部句柄：syncEntryButton/statsEntryButton/refreshCoversButton/
// refreshCoversHint/themeModeGrid/backButton/settingsLayout/settingsScroll/
// ttsEntryButton/languageEntryButton/backgroundEntryButton、goBack()。
Page {
    id: page
    title: qsTr("设置")
    // U2：导航页标识（Main 据此联动顶部标签/底部导航高亮与沉浸隐藏）
    property string navId: "settings"
    // D3：测试/外部句柄（QML 冒烟经此验证设置页 → 同步页导航）
    property alias syncEntryButton: syncItem
    // D4：设置页 → 阅读统计页导航入口（QML 冒烟同模式驱动）
    property alias statsEntryButton: statsItem
    // B2：封面刷新按钮/提示测试句柄（QML 冒烟经此触发 refreshCovers 数据流）
    property alias refreshCoversButton: refreshItem
    property alias refreshCoversHint: refreshCoversHint
    // L10：深色三态 radio 句柄（冒烟经此驱动 theme/mode auto/light/dark 选择）
    property alias themeModeGrid: themeGrid
    // U5：子页入口句柄（冒烟经此驱动 push 语言/TTS/背景子页）
    property alias languageEntryButton: languageItem
    property alias ttsEntryButton: ttsItem
    property alias backgroundEntryButton: bgItem
    // B4：返回按钮测试句柄（QML 冒烟经此模拟返回书架导航，onClicked 即 goBack）
    property alias backButton: backButton
    // C4：设置页滚动句柄（QML 冒烟经 settingsScroll/settingsLayout 断言内容可达）
    property alias settingsLayout: settingsLayout
    property alias settingsScroll: settingsScroll

    // 固定顶部：返回 + 页面标题（B4 返回导航位；U5 列表页标题 24px Bold）
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

    // 全屏列表（C4：包 ScrollView，最小窗口高度下内容可达；滚动条 AsNeeded）
    ScrollView {
        id: settingsScroll
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.top: header.bottom
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        anchors.bottomMargin: 24
        anchors.topMargin: 12
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        ColumnLayout {
            id: settingsLayout
            // 不绑定 ScrollView.availableWidth：该属性在内容尺寸计算前可能为 0，
            // 会使所有 KdListItem 宽度坍缩并导致图标/文字重叠。使用视口实际宽度
            // 建立单向约束，滚动范围仍由 ColumnLayout 总高度决定。
            width: Math.max(0, settingsScroll.width
                                - settingsScroll.leftPadding - settingsScroll.rightPadding)
            spacing: 0

            // ---- 深色模式：三选一 radio（跟随系统/浅色/深色 → theme/mode）----
            // L10（P1#8）：原二元 KdToggle 改 KdRadioGrid 三态——修复 auto 单向丢失：
            // 三值直写 theme/mode = auto/light/dark，subtext 显示当前值；选择后经
            // Main.applyTheme 同步 Material.theme 三态与 UITheme.isDark（既有机制不变）。
            KdListItem {
                id: themeItem
                Layout.fillWidth: true
                icon: "theme"
                text: qsTr("深色模式")
                subtext: page.themeModeName()
                showChevron: false
                KdRadioGrid {
                    id: themeGrid
                    width: 300
                    height: 44
                    columns: 3
                    options: [
                        { text: qsTr("跟随系统"), value: "auto" },
                        { text: qsTr("浅色"), value: "light" },
                        { text: qsTr("深色"), value: "dark" }
                    ]
                    // 恢复：按 theme/mode 三态选中（直接赋 currentValue 不触发
                    // selected，不会回写 Settings——与语言/背景恢复同语义）
                    Component.onCompleted: {
                        const mode = String(Settings.value("theme/mode") || "auto")
                        themeGrid.currentValue = (mode === "light" || mode === "dark") ? mode : "auto"
                    }
                    onSelected: (v) => {
                        Settings.setValue("theme/mode", v)
                        page.refreshSubtexts()
                        // Main.qml 的 applyTheme 同步 Material.theme 三态与 UITheme.isDark
                        //（Window.window 附加属性指向 ApplicationWindow 根对象；测试宿主
                        // 无窗口时跳过——Loader 直载场景下主题仍写 Settings 持久化）
                        const win = Window.window
                        if (win && win.applyTheme) win.applyTheme(v)
                    }
                }
            }
            // ---- 语言：进入子页（KdRadioGrid 单选 zh_CN/zh_TW/en）----
            KdListItem {
                id: languageItem
                Layout.fillWidth: true
                icon: "globe"
                text: qsTr("语言")
                subtext: page.languageName()
                onClicked: page.StackView.view.push("SettingsLanguagePage.qml")
            }
            // ---- 朗读（TTS）：进入子页（引擎/参数/语速档位/保存试音）----
            KdListItem {
                id: ttsItem
                Layout.fillWidth: true
                icon: "read"
                text: qsTr("朗读（TTS）")
                subtext: page.ttsEngineName()
                onClicked: page.StackView.view.push("SettingsTtsPage.qml")
            }
            // ---- 阅读背景：进入子页（四态单选/图片选择/缩略图/模糊亮度/翻页方式）----
            KdListItem {
                id: bgItem
                Layout.fillWidth: true
                icon: "image"
                text: qsTr("阅读背景")
                subtext: page.bgModeName()
                onClicked: page.StackView.view.push("SettingsBackgroundPage.qml")
            }
            // ---- 刷新封面：操作行（即时执行，提示文案走尾部 Label）----
            // B2：存量书籍封面刷新——EPUB/PDF 重提真实封面覆盖早期导入的占位。
            // 同步调用（逐本提取，大书库可能数百 ms～秒级，属一次性维护操作，可接受）。
            // 更新经 Importer.coversRefreshed → Books.booksChanged 使书架封面即时生效。
            KdListItem {
                id: refreshItem
                Layout.fillWidth: true
                icon: "shelf"
                text: qsTr("刷新封面")
                showChevron: false
                onClicked: page.refreshCovers()
                Label {
                    id: refreshCoversHint
                    text: ""
                    color: UITheme.textSecondary
                    font.pixelSize: UITheme.fsCaption
                    // 尾部槽非布局容器：显式绑定隐式尺寸，文本变化时自撑/收缩
                    width: implicitWidth
                    height: implicitHeight
                }
            }
            Timer {
                id: refreshCoversHintTimer
                interval: 4000
                onTriggered: refreshCoversHint.text = ""
            }
            // ---- 同步：入口保留（KdListItem → push SyncPage，U2 导航可达）----
            KdListItem {
                id: syncItem
                Layout.fillWidth: true
                icon: "sync"
                text: qsTr("同步")
                subtext: qsTr("WebDAV 同步设置")
                onClicked: page.StackView.view.push("SyncPage.qml")
            }
            // ---- 统计：入口保留（KdListItem → push StatsPage）----
            KdListItem {
                id: statsItem
                Layout.fillWidth: true
                icon: "stats"
                text: qsTr("统计")
                subtext: qsTr("阅读统计")
                onClicked: page.StackView.view.push("StatsPage.qml")
            }

            Label {
                text: qsTr("版本 0.1.0")
                color: UITheme.textSecondary
                font.pixelSize: UITheme.fsCaption
                topPadding: 16
                bottomPadding: 8
            }
        }
    }

    // B4：返回上一页（书架）。SyncPage/StatsPage 内联 pop()，此处抽函数暴露供
    // QML 冒烟测试驱动（返回按钮 onClicked 即此路径，等价于点击）
    function goBack() {
        page.StackView.view.pop()
    }

    // B2：刷新封面——同步调用并显示提示（经 Importer.coversRefreshed 联动书架）
    function refreshCovers() {
        const n = Importer.refreshCovers()
        refreshCoversHint.text = qsTr("已刷新 %1 本书的封面").arg(n)
        refreshCoversHintTimer.restart()
    }

    // ---- U5：行副文案（当前值显示；子页返回后经 refreshSubtexts 刷新）----
    function themeModeName() {
        const mode = Settings.value("theme/mode")
        if (mode === "dark") return qsTr("深色")
        if (mode === "light") return qsTr("浅色")
        return qsTr("跟随系统")
    }
    function languageName() {
        const code = String(Settings.value("ui/language") || "zh_CN")
        if (code === "zh_TW") return qsTr("繁體中文")
        if (code === "en") return "English"
        return qsTr("简体中文")
    }
    function ttsEngineName() {
        return Settings.value("tts/engine") === "openai" ? "OpenAI" : qsTr("系统语音")
    }
    function bgModeName() {
        const mode = Settings.value("background/mode")
        if (mode === "dark") return qsTr("深色")
        if (mode === "paper") return qsTr("米白")
        if (mode === "image") return qsTr("自定义图片")
        return qsTr("浅色")
    }
    function refreshSubtexts() {
        themeItem.subtext = page.themeModeName()
        languageItem.subtext = page.languageName()
        ttsItem.subtext = page.ttsEngineName()
        bgItem.subtext = page.bgModeName()
    }
    // 初始 + 从子页返回时刷新副文案（StackView.onActivated；Loader 直载场景不触发，
    // 仅 onCompleted 生效——无栈时 attached 属性静默）
    Component.onCompleted: page.refreshSubtexts()
    StackView.onActivated: page.refreshSubtexts()
}
