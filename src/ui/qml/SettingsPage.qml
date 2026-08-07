import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window
import Readdict.Backend

Page {
    id: page
    title: qsTr("设置")
    // D3：测试/外部句柄（QML 冒烟经此验证设置页 → 同步页导航）
    property alias syncEntryButton: syncEntryButton
    // D4：设置页 → 阅读统计页导航入口（QML 冒烟同模式驱动）
    property alias statsEntryButton: statsEntryButton
    // D5：背景分区测试句柄（QML 冒烟经此驱动单选/滑条与导入）
    property alias bgLightRadio: bgLightRadio
    property alias bgDarkRadio: bgDarkRadio
    property alias bgPaperRadio: bgPaperRadio
    // B5：彩色墨水屏（eink）单选句柄——五态单选含 eink
    property alias bgEinkRadio: bgEinkRadio
    property alias bgImageRadio: bgImageRadio
    property alias bgBlurSlider: bgBlurSlider
    property alias bgBrightnessSlider: bgBrightnessSlider
    // D6：语言下拉测试句柄（QML 冒烟经此驱动三语切换）
    property alias languageBox: languageBox
    // B2：封面刷新按钮/提示测试句柄（QML 冒烟经此触发 refreshCovers 数据流）
    property alias refreshCoversButton: refreshCoversButton
    property alias refreshCoversHint: refreshCoversHint
    // B4：返回按钮测试句柄（QML 冒烟经此模拟返回书架导航，onClicked 即 goBack）
    property alias backButton: backButton
    // C4：设置页滚动句柄（QML 冒烟经 settingsScroll 断言最小窗口下可滚动到底；
    // settingsLayout 供 SettingsTtsSmoke 访问卡片索引——B5 起布局索引随卡片化变化，
    // C4 起 ColumnLayout 包入 ScrollView，经此句柄访问不受包装层级影响）
    property alias settingsLayout: settingsLayout
    property alias settingsScroll: settingsScroll
    // 当前背景分区状态（onCompleted 从 Settings 恢复；导入后更新）
    property string bgImagePath: ""
    property real bgBlur: 0.0
    property real bgBrightness: 1.0

    // B5：Kindle 风格分组卡片——圆角 + 浅底色，分区标题统一；视觉重组不改任何
    // 测试句柄。卡片内 ColumnLayout（body）首个子项是标题 Label，其后是调用方内容。
    // 注意：ColumnLayout 直接子项索引随卡片化变化（SettingsTtsSmoke 已同步）——
    // children[0]=返回按钮 [1]=外观卡 [2]=语言卡 [3]=朗读(TTS)卡 [4]=阅读背景卡
    // [5]=同步卡 [6]=统计卡 [7]=版本标签；卡内 body.children[0]=标题，其后为分区内容。
    component SectionCard: Rectangle {
        id: card
        required property string title
        default property alias content: body.data
        Layout.fillWidth: true
        // Rectangle 不随子项自动撑高：显式以内容 implicit 尺寸 + 边距 14×2 作为自身
        // implicit 尺寸，否则卡片高度为 0、内部 ColumnLayout 溢出覆盖后续卡片
        implicitWidth: body.implicitWidth + 28
        implicitHeight: body.implicitHeight + 28
        radius: 10
        color: Material.theme === Material.Dark ? "#1E1E1E" : "#F6F5F1"
        border.color: Material.theme === Material.Dark ? "#33FFFFFF" : "#1A000000"
        border.width: 1
        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8
            Label {
                text: card.title
                font.bold: true
                color: Material.theme === Material.Dark ? "#E6E6E6" : "#1A1A1A"
            }
        }
    }

    // C4：整页滚动——最小窗口高度(600)下分组卡片总高可能超高（B5 卡片化后
    // 返回行 + 外观/语言/朗读/背景/同步/统计 6 张卡 + 版本标签），包 ScrollView
    // 使内容可滚动到底（底部同步/统计入口与版本标签小窗可达）。ColumnLayout
    // 不再 anchors.fill：width 绑 availableWidth（视图区宽度，避免横向滚动条），
    // 高度由 ScrollView 按内容 implicit 高度自动追踪 contentHeight（Qt 6.11 实测）。
    // 滚动条样式统一 AsNeeded：内容不超高时不占用空间。
    ScrollView {
        id: settingsScroll
        anchors.fill: parent
        anchors.margins: 24
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        ColumnLayout {
            id: settingsLayout
            width: settingsScroll.availableWidth
            spacing: 12
        // B4：返回书架——顶部返回按钮（SyncPage/StatsPage 同款导航位），
        // onClicked 走 goBack()（抽函数暴露供 QML 冒烟驱动）
        ToolButton {
            id: backButton
            text: "← " + qsTr("返回")
            onClicked: page.goBack()
        }
        // B5：外观分区卡片（深色模式 + B2 封面刷新）
        SectionCard {
            title: qsTr("外观")
            RowLayout {
                Label { text: qsTr("深色模式") }
                ComboBox {
                    id: themeBox
                    model: [qsTr("跟随系统"), qsTr("浅色"), qsTr("深色")]
                    Component.onCompleted: {
                        const mode = Settings.value("theme/mode")
                        currentIndex = mode === "auto" ? 0 : mode === "light" ? 1 : mode === "dark" ? 2 : 0
                    }
                    onActivated: (index) => {
                        const mode = ["auto", "light", "dark"][index]
                        Settings.setValue("theme/mode", mode)
                        // Main.qml 的 stack id 是文件内私有、跨文件不可见；Item.window 也非 QML 属性。
                        // Window.window 附加属性指向 ApplicationWindow 根对象，其 applyTheme 同步 Material.theme 三态
                        Window.window.applyTheme(mode)
                    }
                }
            }
            // B2：存量书籍封面刷新——EPUB/PDF 重提真实封面覆盖早期导入的占位。
            // 同步调用（逐本提取，大书库可能数百 ms～秒级，属一次性维护操作，可接受）。
            // 更新经 Importer.coversRefreshed → Books.booksChanged 使书架封面即时生效。
            RowLayout {
                Button {
                    id: refreshCoversButton
                    text: qsTr("刷新封面")
                    onClicked: {
                        const n = Importer.refreshCovers()
                        refreshCoversHint.text = qsTr("已刷新 %1 本书的封面").arg(n)
                        refreshCoversHintTimer.restart()
                    }
                }
                Label {
                    id: refreshCoversHint
                    text: ""
                    color: Material.secondaryTextColor
                }
            }
            Timer {
                id: refreshCoversHintTimer
                interval: 4000
                onTriggered: refreshCoversHint.text = ""
            }
        }
        // B5：语言分区卡片（D6 语言下拉）
        SectionCard {
            title: qsTr("语言")
            ComboBox {
                id: languageBox
                model: [qsTr("简体中文"), qsTr("繁體中文"), qsTr("English")]
                // D6：启动恢复上次选择；切换即写 settings.json 的 ui/language 并触发
                // Lang.applyLanguage 加载对应 .qm（main.cpp 的 languageChanged →
                // QQmlEngine::retranslate 刷新全部 qsTr 文本，重启后保持）。
                Component.onCompleted: {
                    const code = String(Settings.value("ui/language") || "zh_CN")
                    currentIndex = code === "zh_TW" ? 1 : code === "en" ? 2 : 0
                }
                onActivated: (index) => {
                    const code = ["zh_CN", "zh_TW", "en"][index]
                    Settings.setValue("ui/language", code)
                    Lang.applyLanguage(code)
                }
            }
        }
        // B5：朗读（TTS）分区卡片（C5 配置区）
        SectionCard {
            title: qsTr("朗读（TTS）")
            RowLayout {
                Label { text: qsTr("引擎") }
                ComboBox {
                    id: ttsEngineBox
                    Layout.preferredWidth: 200
                    textRole: "text"
                    model: [
                        { text: qsTr("系统语音"), value: "system" },
                        { text: "OpenAI", value: "openai" }
                    ]
                    Component.onCompleted: {
                        const engine = Settings.value("tts/engine") || "system"
                        for (let i = 0; i < model.length; i++)
                            if (model[i].value === engine) { currentIndex = i; break }
                    }
                }
                Label {
                    text: Tts.engineAvailable ? qsTr("引擎可用") : qsTr("引擎不可用：请检查下方配置")
                    color: Tts.engineAvailable ? "#2E7D32" : "#C62828"
                }
            }
            // OpenAI 引擎参数（引擎为 system 时折叠）
            ColumnLayout {
                visible: ttsEngineBox.currentIndex === 1
                spacing: 8
                RowLayout {
                    Label { text: qsTr("服务地址") }
                    TextField {
                        id: ttsUrlField
                        Layout.fillWidth: true
                        placeholderText: "https://api.openai.com/v1"
                        // 只需 https://xxx 或 …/v1，软件按 speechUrl 语义自动补全 /audio/speech
                        Component.onCompleted: text = Settings.value("tts/url") || ""
                    }
                }
                RowLayout {
                    Label { text: qsTr("API Key") }
                    TextField {
                        id: ttsKeyField
                        Layout.fillWidth: true
                        echoMode: TextInput.Password
                        placeholderText: qsTr("sk-…（仅保存在本机 settings.json）")
                        Component.onCompleted: text = Settings.value("tts/key") || ""
                    }
                }
                RowLayout {
                    Label { text: qsTr("模型") }
                    TextField {
                        id: ttsModelField
                        Layout.fillWidth: true
                        placeholderText: "tts-1"
                        Component.onCompleted: text = Settings.value("tts/model") || "tts-1"
                    }
                }
                RowLayout {
                    Label { text: qsTr("音色") }
                    TextField {
                        id: ttsVoiceField
                        Layout.fillWidth: true
                        placeholderText: "alloy / echo / fable / onyx / nova / shimmer"
                        Component.onCompleted: text = Settings.value("tts/voice") || "alloy"
                    }
                }
                RowLayout {
                    Label { text: qsTr("语速（0.25–4.0）") }
                    TextField {
                        id: ttsSpeedField
                        Layout.preferredWidth: 120
                        validator: DoubleValidator { bottom: 0.25; top: 4.0; decimals: 2 }
                        Component.onCompleted: text = String(Settings.value("tts/rate") || 1.0)
                    }
                }
            }
            // 保存/试音按钮常驻（不在 openai 折叠区内）：切回系统引擎也必须能保存应用
            RowLayout {
                Button {
                    text: qsTr("保存并应用")
                    onClicked: page.saveTts()
                }
                Button {
                    text: qsTr("测试发音")
                    // 试音不改变朗读游标（Tts.testVoice 抑制自动推进）
                    onClicked: Tts.testVoice(qsTr("你好，这是一段测试语音。"))
                }
                Label {
                    id: ttsSavedHint
                    text: ""
                    color: "#2E7D32"
                }
            }
            Timer {
                id: ttsSavedHintClear
                interval: 3000
                onTriggered: ttsSavedHint.text = ""
            }
        }

        // D5：阅读背景——五模式单选（浅/深/米白/彩色墨水屏 eink/自定义图片）持久化
        // background/mode；自定义图片经 FileDialog 选图 → Settings.copyToBackgrounds 复制到
        // AppData/backgrounds/ → background/imagePath + mode=image；
        // 模糊/亮度滑条即改即存 background/blur、background/brightness（阅读页打开时恢复）。
        // B5：新增 eink——浅彩纸色 + 纸纹层 + 墨色文字 + 图片降饱和（见 ReaderBackground/
        // ReaderContent/ReaderPage 三处联动），单选/循环/持久化与既有模式同构。
        SectionCard {
            title: qsTr("阅读背景")
            RowLayout {
                Label { text: qsTr("背景模式") }
                RadioButton {
                    id: bgLightRadio
                    text: qsTr("浅色")
                    ButtonGroup.group: bgGroup
                    onToggled: if (checked) page.setBgMode("light")
                }
                RadioButton {
                    id: bgDarkRadio
                    text: qsTr("深色")
                    ButtonGroup.group: bgGroup
                    onToggled: if (checked) page.setBgMode("dark")
                }
                RadioButton {
                    id: bgPaperRadio
                    text: qsTr("米白")
                    ButtonGroup.group: bgGroup
                    onToggled: if (checked) page.setBgMode("paper")
                }
                RadioButton {
                    id: bgEinkRadio
                    text: qsTr("彩色墨水屏")
                    ButtonGroup.group: bgGroup
                    onToggled: if (checked) page.setBgMode("eink")
                }
                RadioButton {
                    id: bgImageRadio
                    text: qsTr("自定义图片")
                    ButtonGroup.group: bgGroup
                    onToggled: if (checked) page.setBgMode("image")
                }
                ButtonGroup { id: bgGroup }
            }
            // B5：eink 模式说明（选中时显示）
            Label {
                text: qsTr("彩色墨水屏：类纸纹理 + 墨色文字，图片自动降饱和")
                color: Material.secondaryTextColor
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                visible: bgEinkRadio.checked
            }
            RowLayout {
                Label { text: qsTr("背景图片") }
                Button {
                    text: qsTr("选择图片…")
                    onClicked: bgFileDialog.open()
                }
                Label {
                    id: bgImageHint
                    text: page.bgImagePath ? page.bgImagePath : qsTr("未选择")
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                    color: Material.secondaryTextColor
                }
            }
            FileDialog {
                id: bgFileDialog
                title: qsTr("选择背景图片")
                fileMode: FileDialog.OpenFile
                nameFilters: ["图片 (*.png *.jpg *.jpeg *.webp *.bmp *.gif)"]
                onAccepted: page.importBackgroundImage(bgFileDialog.selectedFiles[0])
            }
            RowLayout {
                Label { text: qsTr("模糊度") }
                Slider {
                    id: bgBlurSlider
                    Layout.fillWidth: true
                    from: 0.0
                    to: 1.0
                    stepSize: 0.05
                    // ready 门闩：onCompleted 恢复初值不写盘；此后任意变更即持久化
                    property bool ready: false
                    Component.onCompleted: { value = page.bgBlur; ready = true }
                    onValueChanged: if (ready) page.setBgBlur(value)
                }
                Label {
                    text: bgBlurSlider.value.toFixed(2)
                    Layout.preferredWidth: 40
                    horizontalAlignment: Text.AlignRight
                }
            }
            RowLayout {
                Label { text: qsTr("亮度") }
                Slider {
                    id: bgBrightnessSlider
                    Layout.fillWidth: true
                    from: 0.5
                    to: 1.5
                    stepSize: 0.05
                    property bool ready: false
                    Component.onCompleted: { value = page.bgBrightness; ready = true }
                    onValueChanged: if (ready) page.setBgBrightness(value)
                }
                Label {
                    text: bgBrightnessSlider.value.toFixed(2)
                    Layout.preferredWidth: 40
                    horizontalAlignment: Text.AlignRight
                }
            }
            Label {
                id: bgErrorText
                text: ""
                color: "#C62828"
                visible: false
            }
            Timer {
                id: bgErrorTimer
                interval: 3000
                onTriggered: bgErrorText.visible = false
            }
        }
        // D3：WebDAV 同步入口——同步配置独立成页（SyncPage.qml），此处只放导航按钮
        SectionCard {
            title: qsTr("同步")
            Button {
                id: syncEntryButton
                text: qsTr("WebDAV 同步设置")
                onClicked: page.StackView.view.push("SyncPage.qml")
            }
        }
        // D4：阅读统计入口——统计独立成页（StatsPage.qml），卡片网格展示聚合数据
        SectionCard {
            title: qsTr("统计")
            Button {
                id: statsEntryButton
                text: qsTr("阅读统计")
                onClicked: page.StackView.view.push("StatsPage.qml")
            }
        }

        Label { text: qsTr("版本 0.1.0"); color: Material.secondaryTextColor }
        }
    }
    // B4：返回上一页（书架）。SyncPage/StatsPage 内联 pop()，此处抽函数暴露供
    // QML 冒烟测试驱动（返回按钮 onClicked 即此路径，等价于点击）
    function goBack() {
        page.StackView.view.pop()
    }

    // 保存 TTS 配置：写 settings.json 的 tts/ 分区 → Tts.reconfigure 重建引擎
    function saveTts() {
        const engine = ttsEngineBox.model[ttsEngineBox.currentIndex].value
        const url = ttsUrlField.text.trim()
        const key = ttsKeyField.text
        const model = ttsModelField.text.trim() || "tts-1"
        const voice = ttsVoiceField.text.trim() || "alloy"
        const rate = Math.min(4, Math.max(0.25, parseFloat(ttsSpeedField.text) || 1.0))
        Settings.setValue("tts/engine", engine)
        Settings.setValue("tts/url", url)
        Settings.setValue("tts/key", key)
        Settings.setValue("tts/model", model)
        Settings.setValue("tts/voice", voice)
        Settings.setValue("tts/rate", rate)
        Tts.reconfigure(engine, url, key, model, voice, rate)
        Tts.rate = rate
        ttsSavedHint.text = qsTr("已保存并应用")
        ttsSavedHintClear.restart()
    }

    // ---- D5：阅读背景分区（background/mode、imagePath、blur、brightness）----
    function setBgMode(mode) {
        Settings.setValue("background/mode", mode)
    }
    function setBgBlur(v) {
        Settings.setValue("background/blur", Math.max(0, Math.min(1, v)))
    }
    function setBgBrightness(v) {
        Settings.setValue("background/brightness", Math.max(0.5, Math.min(1.5, v)))
    }
    // 选图导入：复制到 AppData/backgrounds/ 成功后写 imagePath + mode=image，并同步单选/提示。
    // 注：程序化 checked=true 不触发 onToggled（Qt 6.11 实测），mode 必须显式写。
    function importBackgroundImage(url) {
        const dest = Settings.copyToBackgrounds(url)
        if (!dest) {
            bgErrorText.text = qsTr("图片导入失败，请换一张重试")
            bgErrorText.visible = true
            bgErrorTimer.restart()
            return
        }
        page.bgImagePath = dest
        bgImageHint.text = dest
        bgImageRadio.checked = true
        Settings.setValue("background/mode", "image")
        Settings.setValue("background/imagePath", dest)
    }
    // 启动恢复：从 Settings 读 background/ 分区应用到单选/滑条/路径（含钳制）
    function restoreBackground() {
        let mode = Settings.value("background/mode")
        // B5：五态含 eink
        if (mode !== "light" && mode !== "paper" && mode !== "dark" && mode !== "eink" && mode !== "image")
            mode = "light"
        bgLightRadio.checked = true
        if (mode === "dark") bgDarkRadio.checked = true
        else if (mode === "paper") bgPaperRadio.checked = true
        else if (mode === "eink") bgEinkRadio.checked = true
        else if (mode === "image") bgImageRadio.checked = true
        page.bgImagePath = Settings.value("background/imagePath") || ""
        bgImageHint.text = page.bgImagePath || qsTr("未选择")
        const blur = Number(Settings.value("background/blur")) || 0.0
        page.bgBlur = Math.max(0, Math.min(1, blur))
        const bright = Number(Settings.value("background/brightness")) || 1.0
        page.bgBrightness = Math.max(0.5, Math.min(1.5, bright))
    }
    Component.onCompleted: page.restoreBackground()
}
