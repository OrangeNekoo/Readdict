import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs
import QtQuick.Effects
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
    property alias bgImageRadio: bgImageRadio
    property alias bgBlurSlider: bgBlurSlider
    property alias bgBrightnessSlider: bgBrightnessSlider
    // E2：背景缩略图预览测试句柄（QML 冒烟经此断言可见性/图片就绪/效果参数联动）
    property alias bgThumb: bgThumb
    property alias bgThumbImg: bgThumbImg
    property alias bgThumbFx: bgThumbFx
    // E4：翻页方式单选测试句柄（QML 冒烟经此驱动 reading/pageMode 持久化）
    property alias pageModeScrollRadio: pageModeScrollRadio
    property alias pageModePagedRadio: pageModePagedRadio
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
    // D3 起返回按钮移出 ScrollView 固定顶部，不再占用布局索引：
    // children[0]=外观卡 [1]=语言卡 [2]=朗读(TTS)卡 [3]=阅读背景卡
    // [4]=同步卡 [5]=统计卡 [6]=版本标签；卡内 body.children[0]=标题，其后为分区内容。
    component SectionCard: Rectangle {
        id: card
        required property string title
        default property alias content: body.data
        Layout.fillWidth: true
        // Rectangle 不随子项自动撑高：显式以内容 implicit 尺寸 + 边距 14×2 作为自身
        // implicit 尺寸，否则卡片高度为 0、内部 ColumnLayout 溢出覆盖后续卡片
        implicitWidth: body.implicitWidth + 28
        implicitHeight: body.implicitHeight + 28
        // C5：卡片更扁平（radius 8）+ 浅米白底，接近 Kindle 设置分组卡片
        radius: 8
        color: Material.theme === Material.Dark ? "#1E1E1E" : "#F6F5F1"
        border.color: Material.theme === Material.Dark ? "#33FFFFFF" : "#1A000000"
        border.width: 1
        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8
            // C5：Kindle 风格分组标题——小字（13px）灰色非加粗 + 底部细分隔线。
            // 分隔线经 Label.background 实现（background 是属性对象，不进入 body
            // 的 children 列表）——SettingsTtsSmoke 依赖的卡内索引（body.children
            // [0]=标题 [1]=引擎行…）不变。
            Label {
                text: card.title
                font.pixelSize: 13
                color: Material.secondaryTextColor
                Layout.fillWidth: true
                bottomPadding: 6
                background: Rectangle {
                    color: "transparent"
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: Material.theme === Material.Dark ? "#26FFFFFF" : "#14000000"
                    }
                }
            }
        }
    }

    // D3：返回书架——固定顶部导航（移出 ScrollView）。滚动时返回按钮不再随内容
    // 滚出视口：既消除左上角滚动残影（用户反馈 BUG 3，按钮滚出裁剪边界时残留
    // 渲染层），也与 SyncPage/StatsPage 固定导航位一致；滚动到页面底部仍可随时返回。
    // onClicked 走 goBack()（抽函数暴露供 QML 冒烟驱动）
    ToolButton {
        id: backButton
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: 24
        anchors.topMargin: 24
        text: "← " + qsTr("返回")
        onClicked: page.goBack()
    }
    // C4：整页滚动——最小窗口高度(600)下分组卡片总高可能超高（B5 卡片化后
    // 外观/语言/朗读/背景/同步/统计 6 张卡 + 版本标签），包 ScrollView
    // 使内容可滚动到底（底部同步/统计入口与版本标签小窗可达）。ColumnLayout
    // 不再 anchors.fill：width 绑 availableWidth（视图区宽度，避免横向滚动条），
    // 高度由 ScrollView 按内容 implicit 高度自动追踪 contentHeight（Qt 6.11 实测）。
    // D3：视图区从固定返回按钮下方开始（top 锚 backButton.bottom + 12），
    // 滚动内容与固定导航分离，左上角不再有滚动元素。滚动条样式统一 AsNeeded：
    // 内容不超高时不占用空间。
    ScrollView {
        id: settingsScroll
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.top: backButton.bottom
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        anchors.bottomMargin: 24
        anchors.topMargin: 12
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        ColumnLayout {
            id: settingsLayout
            width: settingsScroll.availableWidth
            spacing: 12
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
            // D4：正文字体选择已移入阅读界面（ReaderControls 字体按钮 + 弹层，4 族全量）。
            // 设置页移除避免双入口——阅读页切换即时生效（setFontFamily 写后重组合
            // typography 属性），设置页旧下拉只能影响下次打开，两者并存会令用户困惑。
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

        // D5：阅读背景——四模式单选（浅/深/米白/自定义图片）持久化
        // background/mode；自定义图片经 FileDialog 选图 → Settings.copyToBackgrounds 复制到
        // AppData/backgrounds/ → background/imagePath + mode=image；
        // 模糊/亮度滑条即改即存 background/blur、background/brightness（阅读页打开时恢复）。
        // E2：选图后卡片内缩略图实时预览模糊/亮度（bgThumb 行，MultiEffect 同阅读页参数）。
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
                    id: bgImageRadio
                    text: qsTr("自定义图片")
                    ButtonGroup.group: bgGroup
                    onToggled: if (checked) page.setBgMode("image")
                }
                ButtonGroup { id: bgGroup }
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
            // E2：缩略图预览——选图后卡片内实时预览模糊/亮度效果，与 ReaderBackground 同
            // MultiEffect 参数（blur 直通、brightness 换算 -1..1）。滑条移动经
            // setBgBlur/setBgBrightness 同步 page.bgBlur/bgBrightness 作绑定源（实时联动）。
            // 未选图整行隐藏；图片加载失败时效果层隐藏露出底色（不显示黑块，同阅读页兜底）。
            Rectangle {
                id: bgThumb
                visible: page.bgImagePath !== ""
                Layout.fillWidth: true
                Layout.preferredHeight: 135
                radius: 6
                color: Material.theme === Material.Dark ? "#262626" : "#EDEBE4"
                clip: true
                Image {
                    id: bgThumbImg
                    anchors.fill: parent
                    // 与 ReaderBackground 同源构造：本地绝对路径补 file://，防御重复前缀
                    source: page.bgImagePath
                            ? (page.bgImagePath.indexOf("file://") === 0
                               ? page.bgImagePath : "file://" + page.bgImagePath)
                            : ""
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                }
                MultiEffect {
                    id: bgThumbFx
                    anchors.fill: parent
                    visible: page.bgImagePath !== "" && bgThumbImg.status === Image.Ready
                    source: bgThumbImg
                    blurEnabled: true
                    blur: page.bgBlur
                    brightness: page.bgBrightness - 1.0   // MultiEffect 亮度范围 -1..1
                }
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
            // E4：翻页方式——竖滚连续（scroll，默认）/ 整页翻动（paged，按视口高度切页）。
            // 持久化 reading/pageMode；ReaderPage 打开时读取。单选互斥同背景模式模式；
            // 冒烟测试句柄 pageModeScrollRadio/pageModePagedRadio（同 bgLightRadio 模式）。
            RowLayout {
                Label { text: qsTr("翻页方式") }
                RadioButton {
                    id: pageModeScrollRadio
                    text: qsTr("连续滚动")
                    ButtonGroup.group: pageModeGroup
                    onToggled: if (checked) Settings.setValue("reading/pageMode", "scroll")
                }
                RadioButton {
                    id: pageModePagedRadio
                    text: qsTr("整页翻动")
                    ButtonGroup.group: pageModeGroup
                    onToggled: if (checked) Settings.setValue("reading/pageMode", "paged")
                }
                ButtonGroup { id: pageModeGroup }
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
        // E2：页面属性作响应层（ReaderPage 同模式）——滑条移动即同步，缩略图 MultiEffect
        // 绑定 page.bgBlur 实时预览；同时持久化 background/blur（含钳制）
        page.bgBlur = Math.max(0, Math.min(1, v))
        Settings.setValue("background/blur", page.bgBlur)
    }
    function setBgBrightness(v) {
        page.bgBrightness = Math.max(0.5, Math.min(1.5, v))
        Settings.setValue("background/brightness", page.bgBrightness)
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
        // E1：四态白名单；旧版 eink（B5 彩色墨水屏）值在此归一为 light（默认回退，
        // 与其余非法值同路径），并回写 settings.json 使存储值同步归一
        if (mode !== "light" && mode !== "paper" && mode !== "dark" && mode !== "image") {
            mode = "light"
            Settings.setValue("background/mode", mode)
        }
        bgLightRadio.checked = true
        if (mode === "dark") bgDarkRadio.checked = true
        else if (mode === "paper") bgPaperRadio.checked = true
        else if (mode === "image") bgImageRadio.checked = true
        page.bgImagePath = Settings.value("background/imagePath") || ""
        bgImageHint.text = page.bgImagePath || qsTr("未选择")
        const blur = Number(Settings.value("background/blur")) || 0.0
        page.bgBlur = Math.max(0, Math.min(1, blur))
        const bright = Number(Settings.value("background/brightness")) || 1.0
        page.bgBrightness = Math.max(0.5, Math.min(1.5, bright))
        // E4：翻页方式——reading/pageMode 白名单归一后选中对应单选
        //（程序化 checked=true 不触发 onToggled，不会回写 Settings，同背景模式恢复）
        pageModeScrollRadio.checked = true
        if (Settings.value("reading/pageMode") === "paged")
            pageModePagedRadio.checked = true
    }
    Component.onCompleted: page.restoreBackground()
}
