import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Window
import Readdict.Backend

Page {
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
        Label { text: qsTr("版本 0.1.0"); color: Material.secondaryTextColor }
    }
}
