import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.Backend
import Readdict.UI 1.0

// 朗读控制条：播放/暂停/停止/上一句/下一句 + 语速滑块 + 音色下拉 + 状态提示。
// 无内部状态：信号上报 ReaderPage 处理（play/pause/stop/prev/next/rate/voice），
// playing/errorText 由 ReaderPage 从 Tts 单例同步；引擎可用性直接读 Tts。
// C2：visible 由宿主（ReaderPage.ttsBarVisible）门控——默认隐藏，仅朗读会话激活时
// 显示；本组件不自行管理可见性。
// C3 决策：阅读控件唤出/自动隐藏框架只作用于底部控制栏（ReaderPage.controlsVisible），
// 朗读条显隐仍仅由 state 门控单独决定——朗读中唤出不带出、控制栏隐藏不影响
// 朗读条（暂停/停止随时可达）。宿主侧实现，本组件不参与。
Rectangle {
    id: bar
    property bool playing: false
    property string errorText: ""
    property string bgMode: "light"   // 随阅读背景切换前景/底色，保证深色下可读
    signal playClicked(); signal pauseClicked(); signal stopClicked()
    signal prevClicked(); signal nextClicked()
    signal rateChanged(double rate); signal voiceChanged(string voice)

    height: 46
    color: bar.bgMode === "dark" ? "#F2121212" : "#F2FFFFFF"
    property color fgColor: bar.bgMode === "dark" ? "#E6E6E6" : "#1A1A1A"

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: bar.bgMode === "dark" ? "#33FFFFFF" : "#1A000000"
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 4

        component BarBtn: ToolButton {
            required property string lbl
            text: lbl
            font.pixelSize: 14
            contentItem: Text {
                text: parent.text
                color: parent.enabled ? bar.fgColor : UITheme.textDisabled
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        BarBtn { lbl: "⏮"; onClicked: bar.prevClicked() }
        BarBtn {
            lbl: bar.playing ? "⏸" : "▶"
            // 引擎不可用（system 无语音 / openai 未配置 key）→ 禁用播放按钮
            enabled: Tts.engineAvailable
            onClicked: bar.playing ? bar.pauseClicked() : bar.playClicked()
        }
        BarBtn { lbl: "⏹"; onClicked: bar.stopClicked() }
        BarBtn { lbl: "⏭"; onClicked: bar.nextClicked() }

        Slider {
            id: rateSlider
            Layout.preferredWidth: 140
            Layout.fillWidth: true
            from: 0.25; to: 4.0   // L7（P1#9）：与 TtsController/设置页语速范围统一
            value: Tts.rate
            stepSize: 0.25   // 与 from 0.25 对齐的整网格（0.1 网格在 0.25 起点下触不到 4.0）
            onMoved: bar.rateChanged(value)
        }
        Label {
            text: qsTr("语速 %1×").arg(rateSlider.value.toFixed(2))   // 0.25 网格需两位小数
            color: bar.fgColor
            Layout.preferredWidth: 80
            horizontalAlignment: Text.AlignLeft
        }
        ComboBox {
            id: voiceBox
            model: Tts.voices
            enabled: Tts.voices.length > 0
            Layout.preferredWidth: 150
            Layout.maximumWidth: 170
            onActivated: (index) => bar.voiceChanged(model[index])
            // 重配置后 voices 刷新：同步选中当前音色（找不到则停在首项）
            function syncFromTts() {
                var i = voiceBox.model.indexOf(Tts.voice)
                voiceBox.currentIndex = i >= 0 ? i : 0
            }
            Component.onCompleted: syncFromTts()
            Connections {
                target: Tts
                function onVoicesChanged() { voiceBox.syncFromTts() }
            }
        }
        // 状态提示：引擎不可用提示 / 最近一次朗读错误
        Label {
            id: statusLabel
            text: Tts.engineAvailable
                  ? (bar.errorText.length > 0 ? bar.errorText : "")
                  : qsTr("TTS 引擎不可用，请到设置配置")
            color: bar.errorText.length > 0 ? UITheme.danger : UITheme.textSecondary
            elide: Text.ElideRight
            Layout.preferredWidth: 150
            Layout.maximumWidth: 190
            visible: text.length > 0
        }
    }
}
