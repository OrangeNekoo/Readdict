import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Window
import Readdict.Backend

Page {
    id: page
    title: qsTr("设置")
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 24; spacing: 16
        Label { text: qsTr("外观"); font.bold: true }
        RowLayout {
            Label { text: qsTr("深色模式") }
            ComboBox {
                id: themeBox
                model: [qsTr("跟随系统"), qsTr("浅色"), qsTr("深色")]
                Component.onCompleted: {
                    const mode = Settings.value("theme/mode")
                    currentIndex = mode === "auto" ? 0 : mode === "light" ? 1 : mode === "dark" ? 2 : 0
                }
                onActivated: {
                    const mode = ["auto", "light", "dark"][index]
                    Settings.setValue("theme/mode", mode)
                    // Main.qml 的 stack id 是文件内私有、跨文件不可见；Item.window 也非 QML 属性。
                    // Window.window 附加属性指向 ApplicationWindow 根对象，其 applyTheme 同步 Material.theme 三态
                    Window.window.applyTheme(mode)
                }
            }
        }
        Label { text: qsTr("语言"); font.bold: true }
        ComboBox {
            model: [qsTr("简体中文"), qsTr("繁體中文"), qsTr("English")]
            // 语言持久化先落 settings.json 的 ui/language，翻译加载在计划 D 完善
            onActivated: Settings.setValue("ui/language", ["zh_CN", "zh_TW", "en"][index])
        }

        // C5：朗读（TTS）配置——引擎选择 + OpenAI 参数，保存后 Tts.reconfigure 热切换。
        Label { text: qsTr("朗读（TTS）"); font.bold: true }
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
        }

        Label { text: qsTr("版本 0.1.0"); color: Material.secondaryTextColor }
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
    Timer {
        id: ttsSavedHintClear
        interval: 3000
        onTriggered: ttsSavedHint.text = ""
    }
}
