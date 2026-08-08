import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import Readdict.Backend
import Readdict.UI 1.0

ApplicationWindow {
    id: root
    width: 1100; height: 720
    // C4：最小窗口尺寸——800 宽保证书架分类侧栏(160) + 封面网格(单元格 184，
    // 至少 1 列) + 工具栏在窗口内可读；600 高保证设置页分组卡片（外观/语言/
    // TTS/背景/同步/统计）顶部内容可见，超高部分由 SettingsPage 的 ScrollView
    // 滚动兜底（最小尺寸取值与各页滚动方案见 .superpowers/sdd/task-C4-report.md）
    minimumWidth: 800
    minimumHeight: 600
    visible: true
    title: qsTr("Readdict")

    // 主题三态：auto 跟随系统、light 浅色、dark 深色；持久化于 Settings 的 theme/mode
    property string theme: "auto"
    // U1：applyTheme 现同步两处——Material.theme 三态（QtQuick.Controls 控件仍由
    // Material 样式渲染，保留）与 UITheme.isDark（Kindle Token 深浅解析）。颜色全部
    // 走 Token，不再覆盖 Material.primary/accent（靛蓝移除，见下方 Material 声明注释）。
    function applyTheme(mode) {
        root.theme = mode
        UITheme.isDark = root.effectiveDark
    }

    Material.theme: root.theme === "dark" ? Material.Dark
                   : root.theme === "light" ? Material.Light
                   : Material.System

    // effectiveDark 取实际生效的深色：显式 dark，或 auto 且系统为深色
    //（Qt.styleHints.colorScheme 跟随系统实时变化，auto 模式换肤即时生效）。
    property bool effectiveDark: root.theme === "dark"
        || (root.theme === "auto" && Qt.styleHints.colorScheme === Qt.ColorScheme.Dark)

    // U1：去 Material 靛蓝（原 #3D5AFE/#536DFE 主色/accent 删除，UI 不再引用
    // Material.primary/accent——BookCard/StatsPage 的 accent 用法已改 Token）。
    // Material 框架仍需保留（QtQuick.Controls 控件样式），但颜色全走 Kindle Token：
    // background/foreground 附加属性让默认控件底色/文字随 UITheme 深浅（暖白近黑
    // ↔ Kindle 深色系），窗口底色由下方 background 显式 Rectangle 兜底。
    Material.background: UITheme.bgPrimary
    Material.foreground: UITheme.textPrimary
    background: Rectangle { anchors.fill: parent; color: UITheme.bgPrimary }

    // 启动时从 settings.json 恢复上次主题选择（SettingsStore 默认值即 auto），
    // 并同步 UITheme 深浅（Settings 无变更信号，applyTheme 路径由设置页调用）
    Component.onCompleted: {
        const mode = Settings.value("theme/mode")
        root.theme = (mode === "auto" || mode === "light" || mode === "dark") ? mode : "auto"
        UITheme.isDark = root.effectiveDark
    }

    StackView {
        id: stack
        anchors.fill: parent
        initialItem: "ShelfPage.qml"
    }
}
