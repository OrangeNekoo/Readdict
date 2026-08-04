import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import Readdict.Backend

ApplicationWindow {
    id: root
    width: 1100; height: 720
    visible: true
    title: qsTr("Readdict")

    // 主题三态：auto 跟随系统、light 浅色、dark 深色；持久化于 Settings 的 theme/mode
    property string theme: "auto"
    function applyTheme(mode) { root.theme = mode }

    Material.theme: root.theme === "dark" ? Material.Dark
                   : root.theme === "light" ? Material.Light
                   : Material.System

    // 启动时从 settings.json 恢复上次主题选择（SettingsStore 默认值即 auto）
    Component.onCompleted: {
        const mode = Settings.value("theme/mode")
        root.theme = (mode === "auto" || mode === "light" || mode === "dark") ? mode : "auto"
    }

    StackView {
        id: stack
        anchors.fill: parent
        initialItem: "ShelfPage.qml"
    }
}
