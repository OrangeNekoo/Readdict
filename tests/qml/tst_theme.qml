import QtQuick
import QtQuick.Controls
import QtTest
import Readdict.Backend
import Readdict.Test 1.0
import Readdict.UI 1.0

// U1：Kindle 设计 Token 基座冒烟——UITheme 单例浅/深两套 Token 值、字体/间距常量、
// 深浅切换（isDark）解析、以及背景/文字色随 Token 的联动（ReaderBackground 底色、
// ReaderContent 默认前景）。值来源 kindel-ui-analysis.md §7（U6 审计一致性）。
// 结构约定（与 tst_main/tst_background 一致）：根为带尺寸的 Item，TestCase 是其子项，
// 组件经 Loader createObject(root) 挂到该 Item 下。
Item {
    id: root
    width: 1100; height: 720

    Component { id: bgComp; Loader { source: "qrc:/qt/qml/Readdict/ui/qml/ReaderBackground.qml" } }
    Component { id: contentComp; Loader { source: "qrc:/qt/qml/Readdict/ui/qml/ReaderContent.qml" } }
    Component { id: mainComp; Loader { source: "qrc:/qt/qml/Readdict/ui/qml/Main.qml" } }

    TestCase {
        id: testCase
        name: "ThemeSmoke"

        // 浅色 Token 值（§7 逐项）——颜色规范化后比较（QML color 类型 lower-case hex）
        function test_01_lightTokens() {
            UITheme.isDark = false
            compare(String(UITheme.bgPrimary), "#f5f5f0", "浅主背景应为暖白 #F5F5F0")
            compare(String(UITheme.bgSecondary), "#edeceb", "设置页背景 #EDECEB")
            compare(String(UITheme.bgSearch), "#e8e8e3", "搜索框背景 #E8E8E3")
            compare(String(UITheme.textPrimary), "#1a1a1a", "主文字近黑 #1A1A1A")
            compare(String(UITheme.textSecondary), "#888888", "辅助文字 #888888")
            compare(String(UITheme.textDisabled), "#bbbbbb", "不可用文字 #BBBBBB")
            compare(String(UITheme.borderDefault), "#cccccc", "默认边框 #CCCCCC")
            compare(String(UITheme.borderActive), "#1a1a1a", "选中边框 #1A1A1A")
            compare(String(UITheme.divider), "#e0e0e0", "分隔线 #E0E0E0")
            compare(String(UITheme.overlay), "#4d000000", "遮罩 rgba(0,0,0,0.3)")
            compare(String(UITheme.shadowBook), "#14000000", "封面投影 rgba(0,0,0,0.08)")
            compare(String(UITheme.bgPaper), "#f5efe0", "米白纸色（paper 模式，沿袭既有值）")
            // 派生 Token 同值
            compare(String(UITheme.lightBgPrimary), "#f5f5f0", "lightBgPrimary 显式值")
        }

        // 深色 Token 值（Kindle 深色系映射）
        function test_02_darkTokens() {
            UITheme.isDark = true
            compare(String(UITheme.bgPrimary), "#1e1e1e", "深主背景 #1E1E1E")
            compare(String(UITheme.bgSecondary), "#262626", "深次级背景 #262626")
            compare(String(UITheme.textPrimary), "#e8e8e3", "深主文字 #E8E8E3")
            compare(String(UITheme.textSecondary), "#9a9a9a", "深辅助文字 #9A9A9A")
            compare(String(UITheme.borderDefault), "#3a3a3a", "深默认边框 #3A3A3A")
            compare(String(UITheme.borderActive), "#e8e8e3", "深选中边框 #E8E8E3")
            compare(String(UITheme.divider), "#333333", "深分隔线 #333333")
            // U1 复审：dark 派生别名（任务映射未给出，Theme.qml 取同族派生值）
            compare(String(UITheme.bgSearch), "#333333", "深搜索框背景（派生 #333333）")
            compare(String(UITheme.bgPaper), "#2a2a26", "深米白纸色（派生 #2A2A26）")
            // 深浅切换后解析别名跟随
            UITheme.isDark = false
            compare(String(UITheme.textPrimary), "#1a1a1a", "切回浅色后 textPrimary 应解析浅值")
        }

        // 字体层级与间距常量（§7 Typography/Spacing）
        function test_03_typographyAndSpacing() {
            compare(UITheme.fsPageTitle, 24, "页面标题 22-24 Bold → 24")
            compare(UITheme.fsSectionTitle, 20, "分区标题 20-22 Bold → 20")
            compare(UITheme.fsTabNav, 17, "标签导航 16-18 → 17")
            compare(UITheme.fsBody, 19, "正文 18-20 → 19")
            compare(UITheme.fsListItem, 15, "列表项 15-16 → 15")
            compare(UITheme.fsCaption, 13, "辅助文字 12-14 → 13")
            compare(UITheme.pageMargin, 22, "页边距 20-24 → 22")
            compare(UITheme.sectionGap, 16, "分区间距 16")
            compare(UITheme.itemGap, 12, "条目间距 12-16 → 12")
            compare(UITheme.lineHeight, 1.7, "阅读行高 1.6-1.8 → 1.7")
        }

        // 背景底色随 Token：ReaderBackground light/dark/paper 三态引用 UITheme 值
        function test_04_backgroundFollowsToken() {
            var loader = bgComp.createObject(root)
            verify(loader.item !== null, "ReaderBackground 应能加载")
            var b = loader.item
            b.width = 200; b.height = 300
            b.mode = "light"
            compare(String(b.children[0].color), "#f5f5f0", "light 底色应随 Token bgPrimary")
            b.mode = "dark"
            compare(String(b.children[0].color), "#1e1e1e", "dark 底色应随 Token darkBgPrimary")
            b.mode = "paper"
            compare(String(b.children[0].color), "#f5efe0", "paper 底色应随 Token bgPaper")
            loader.destroy()
        }

        // 文字色随 Token：ReaderContent 默认前景 = lightTextPrimary；切 dark 文字随
        // ReaderPage 传入 darkTextPrimary（ReaderPage 绑定见 tst_textcolor test_03）
        function test_05_textFollowsToken() {
            var loader = contentComp.createObject(root)
            loader.width = 800; loader.height = 600
            var c = loader.item
            verify(c !== null, "ReaderContent 应能加载")
            compare(String(c.textColor), "#1a1a1a", "默认 textColor 应随 Token lightTextPrimary")
            loader.destroy()
            // UITheme.isDark 为 false 时解析别名与 lightTextPrimary 一致
            UITheme.isDark = false
            compare(String(UITheme.textPrimary), String(UITheme.lightTextPrimary),
                    "浅色下 textPrimary 应等于 lightTextPrimary")
        }

        // U1 复审：Main.qml 顶层绑定 UITheme.isDark: root.effectiveDark——auto 模式下
        // 系统深浅切换（Qt.styleHints.colorScheme 变化）即时同步 Token，而非依赖
        // applyTheme 命令式赋值（命令式在系统切换时不会重跑）。加载真实 Main 组件，
        // 驱动 theme 属性验证 isDark 由 effectiveDark 派生：显式 light/dark 两态 +
        // auto 态应等于系统深色判定。末尾复位 isDark 避免污染后续用例。
        function test_06_mainIsDarkBinding() {
            var loader = mainComp.createObject(root)
            loader.setSource("qrc:/qt/qml/Readdict/ui/qml/Main.qml")
            var win = loader.item
            verify(win !== null, "Main.qml 应能加载（含 UITheme.isDark 绑定）")
            win.theme = "light"
            tryVerify(function () { return UITheme.isDark === false }, 2000,
                      "theme=light 时 isDark 应为 false（绑定驱动）")
            win.theme = "dark"
            tryVerify(function () { return UITheme.isDark === true }, 2000,
                      "theme=dark 时 isDark 应为 true（绑定驱动）")
            // auto：跟随系统 colorScheme（测试环境系统值不可控，断言绑定链已建立——
            // 显式两态证明 isDark 由 effectiveDark 派生而非命令式赋值）
            win.theme = "auto"
            var sysDark = Qt.styleHints.colorScheme === Qt.ColorScheme.Dark
            compare(UITheme.isDark, sysDark, "auto 模式 isDark 应等于系统深色判定")
            loader.destroy()
            UITheme.isDark = false
        }
    }
}
