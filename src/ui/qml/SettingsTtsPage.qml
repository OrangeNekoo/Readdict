import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Readdict.Backend
import Readdict.UI 1.0

// U5：朗读（TTS）设置子页（Kindle 全屏列表化——设置页"朗读（TTS）"行进入）。
// 功能与 C5 原设置页 TTS 配置区一致：引擎选择（system/openai）、OpenAI 参数
// （服务地址/key/模型/音色/语速）、保存并应用 + 测试发音。
// U5 新增：语速 KdSegmentedSlider 快速档位（0.5/1.0/1.5/2.0/3.0），与精确输入
// TextField 双向同步（段选择写字段；字段值命中档位时高亮对应段）。
// L7（P1#15）：音色键按引擎拆分——系统引擎新增音色列表写 tts/systemVoice，
// OpenAI 音色文本写 tts/openaiVoice（旧 tts/voice 只由启动迁移读取，不再写）。
// 返回：固定顶部"← 返回"（B4 模式）。测试/外部句柄：backButton、goBack()、
// ttsEngineBox/ttsUrlField/ttsKeyField/ttsModelField/ttsVoiceField/ttsSpeedField、
// ttsSystemVoiceBox、rateSlider（KdSegmentedSlider）、saveTts()、ttsSavedHint。
Page {
    id: page
    title: qsTr("朗读（TTS）")
    property string navId: "settings"
    property alias backButton: backButton
    property alias ttsEngineBox: ttsEngineBox
    property alias ttsUrlField: ttsUrlField
    property alias ttsKeyField: ttsKeyField
    property alias ttsModelField: ttsModelField
    property alias ttsVoiceField: ttsVoiceField
    property alias ttsSystemVoiceBox: ttsSystemVoiceBox
    property alias ttsSpeedField: ttsSpeedField
    property alias rateSlider: rateSlider
    property alias ttsSavedHint: ttsSavedHint

    // 固定顶部：返回 + 页面标题（B4 返回导航位，同 SyncPage/StatsPage 模式）
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

    ScrollView {
        id: ttsScroll
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
            width: Math.max(0, ttsScroll.width
                                - ttsScroll.leftPadding - ttsScroll.rightPadding)
            spacing: 14
            // ScrollView.availableWidth 在内容计算初期可能为 0，使用视口宽度
            // 建立单向尺寸约束，保证 TextField/Slider 行可见且可滚动。

            RowLayout {
                Layout.fillWidth: true
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
                    color: Tts.engineAvailable ? UITheme.success : UITheme.danger
                }
            }
            // L7（P1#15）：系统引擎音色列表（Tts.voices 转发宿主系统语音），写 tts/systemVoice
            RowLayout {
                Layout.fillWidth: true
                visible: ttsEngineBox.currentIndex === 0
                Label { text: qsTr("音色") }
                ComboBox {
                    id: ttsSystemVoiceBox
                    Layout.preferredWidth: 260
                    model: Tts.voices
                    enabled: Tts.voices.length > 0
                    Component.onCompleted: syncVoice()
                    // 恢复持久化音色：列表变更（引擎热切换）后同样同步，找不到则停首项
                    function syncVoice() {
                        const saved = Settings.value("tts/systemVoice") || ""
                        const i = model.indexOf(saved)
                        currentIndex = i >= 0 ? i : 0
                    }
                    Connections {
                        target: Tts
                        function onVoicesChanged() { ttsSystemVoiceBox.syncVoice() }
                    }
                }
            }
            // OpenAI 引擎参数（引擎为 system 时折叠）
            ColumnLayout {
                Layout.fillWidth: true
                visible: ttsEngineBox.currentIndex === 1
                spacing: 10
                RowLayout {
                    Layout.fillWidth: true
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
                    Layout.fillWidth: true
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
                    Layout.fillWidth: true
                    Label { text: qsTr("模型") }
                    TextField {
                        id: ttsModelField
                        Layout.fillWidth: true
                        placeholderText: "tts-1"
                        Component.onCompleted: text = Settings.value("tts/model") || "tts-1"
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: qsTr("音色") }
                    TextField {
                        id: ttsVoiceField
                        Layout.fillWidth: true
                        placeholderText: "alloy / echo / fable / onyx / nova / shimmer"
                        Component.onCompleted: text = Settings.value("tts/openaiVoice") || "alloy"
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: qsTr("语速（0.25–4.0）") }
                    TextField {
                        id: ttsSpeedField
                        Layout.preferredWidth: 120
                        validator: DoubleValidator { bottom: 0.25; top: 4.0; decimals: 2 }
                        Component.onCompleted: text = String(Settings.value("tts/rate") || 1.0)
                        // 字段值命中快速档位 → 高亮对应段（直接赋 currentValue 不触发
                        // selected，无回写循环；未命中档位清高亮）
                        onTextChanged: {
                            const v = parseFloat(ttsSpeedField.text)
                            if (!isNaN(v) && rateSlider.indexFor(v) >= 0)
                                rateSlider.currentValue = v
                            else
                                rateSlider.currentValue = ""
                        }
                    }
                }
                // U5：Kindle 分段滑块快速档位（选中 → 写字段 → 保存走字段值）
                KdSegmentedSlider {
                    id: rateSlider
                    Layout.fillWidth: true
                    segments: [
                        { label: "0.5", value: 0.5 },
                        { label: "1.0", value: 1.0 },
                        { label: "1.5", value: 1.5 },
                        { label: "2.0", value: 2.0 },
                        { label: "3.0", value: 3.0 }
                    ]
                    Component.onCompleted: {
                        const v = Number(Settings.value("tts/rate")) || 1.0
                        rateSlider.currentValue = rateSlider.indexFor(v) >= 0 ? v : ""
                    }
                    onSelected: (v) => { ttsSpeedField.text = String(v) }
                }
            }
            // 保存/试音按钮常驻（不在 openai 折叠区内）：切回系统引擎也必须能保存应用
            RowLayout {
                Layout.fillWidth: true
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
                    color: UITheme.success
                }
            }
            Timer {
                id: ttsSavedHintClear
                interval: 3000
                onTriggered: ttsSavedHint.text = ""
            }
            Item { Layout.fillHeight: true }
        }
    }

    // B4：返回上一页（设置页）。抽函数暴露供 QML 冒烟测试驱动
    function goBack() {
        page.StackView.view.pop()
    }

    // 保存 TTS 配置：写 settings.json 的 tts/ 分区 → Tts.reconfigure 重建引擎。
    // L7（P1#15）：音色按引擎拆键——system 写 tts/systemVoice（音色列表当前项），
    // openai 写 tts/openaiVoice（音色文本）；不再写旧 tts/voice 单键。
    function saveTts() {
        const engine = ttsEngineBox.model[ttsEngineBox.currentIndex].value
        const url = ttsUrlField.text.trim()
        const key = ttsKeyField.text
        const model = ttsModelField.text.trim() || "tts-1"
        const voice = engine === "system"
            ? (ttsSystemVoiceBox.currentText || String(Settings.value("tts/systemVoice") || ""))
            : (ttsVoiceField.text.trim() || "alloy")
        const rate = Math.min(4, Math.max(0.25, parseFloat(ttsSpeedField.text) || 1.0))
        Settings.setValue("tts/engine", engine)
        Settings.setValue("tts/url", url)
        Settings.setValue("tts/key", key)
        Settings.setValue("tts/model", model)
        if (engine === "system") {
            if (voice) Settings.setValue("tts/systemVoice", voice)   // 宿主无语音时列表空，保留旧值
        } else {
            Settings.setValue("tts/openaiVoice", voice)
        }
        Settings.setValue("tts/rate", rate)
        Tts.reconfigure(engine, url, key, model, voice, rate)
        Tts.rate = rate
        if (voice) Tts.voice = voice
        ttsSavedHint.text = qsTr("已保存并应用")
        ttsSavedHintClear.restart()
    }
}
