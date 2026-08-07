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

    // D7：Material 主题主色——浅色 #3D5AFE（靛蓝 A200）；深色模式调暗为靛蓝 600，
    // 在深色背景上降低高饱和主色的刺眼度，同时保证按钮/进度条等主色控件的对比度。
    // accent 同族微调，保证选中态（复选框/滑块/搜索框焦点）与主色协调。
    // effectiveDark 取实际生效的深色：显式 dark，或 auto 且系统为深色
    //（Qt.styleHints.colorScheme 跟随系统实时变化，auto 模式换肤即时生效）。
    property bool effectiveDark: root.theme === "dark"
        || (root.theme === "auto" && Qt.styleHints.colorScheme === Qt.ColorScheme.Dark)
    Material.primary: root.effectiveDark ? "#3949AB" : "#3D5AFE"
    Material.accent: root.effectiveDark ? "#5C6BC0" : "#536DFE"

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
