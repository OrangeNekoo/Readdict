import QtQuick
import QtQuick.Controls
import QtTest
import Readdict.Backend
import Readdict.UI 1.0

// U5：设置页 Kindle 全屏列表化冒烟——列表项结构（KdListItem 图标/文字/chevron/
// 字号 Token）、深色模式三态 radio 即时生效（L10：写 theme/mode auto/light/dark +
// Main.applyTheme + UITheme Token 跟随 + 启动恢复）、子页 push/返回（语言/TTS/
// 背景/同步/统计入口不丢、背景子页 radio 选择生效）。
// 结构约定（与 tst_main 等一致）：根为带尺寸的 Item，TestCase 是其子项，
// 组件经 createObject(root) 挂到该 Item 下；Main.qml 用例结束先隐藏再销毁。
Item {
    id: root
    width: 1100; height: 720

    Component { id: mainComp; Loader { source: "qrc:/qt/qml/Readdict/ui/qml/Main.qml" } }
    Component { id: settingsComp; Loader { source: "qrc:/qt/qml/Readdict/ui/qml/SettingsPage.qml" } }

    TestCase {
        id: testCase
        name: "SettingsListSmoke"

        // U5 列表结构：7 行 KdListItem（深色模式/语言/TTS/背景/刷新封面/同步/统计）
        // + 版本标签；图标/chevron/字号走 Kindle Token（fsListItem 15px）
        function test_listItemStructure() {
            var loader = settingsComp.createObject(root)
            var page = loader.item
            verify(page !== null, "SettingsPage 应能加载")
            var layout = page.settingsLayout
            compare(layout.children.length, 8, "列表应为 7 行 + 版本标签，实际 "
                    + layout.children.length)
            var rows = [
                { idx: 0, text: "深色模式", icon: "theme", chevron: false },
                { idx: 1, text: "语言", icon: "globe", chevron: true },
                { idx: 2, text: "朗读（TTS）", icon: "read", chevron: true },
                { idx: 3, text: "阅读背景", icon: "image", chevron: true },
                { idx: 4, text: "刷新封面", icon: "shelf", chevron: false },
                { idx: 5, text: "同步", icon: "sync", chevron: true },
                { idx: 6, text: "统计", icon: "stats", chevron: true }
            ]
            for (var i = 0; i < rows.length; ++i) {
                var row = layout.children[rows[i].idx]
                verify(row !== undefined, "行 " + i + " 应存在")
                compare(row.text, rows[i].text, "行 " + i + " 主文案应为 "
                        + rows[i].text + "，实际 " + row.text)
                compare(row.icon, rows[i].icon, "行 " + i + " 图标应为 " + rows[i].icon)
                verify(row.chevronIcon !== undefined, "行 " + i + " 应暴露 chevronIcon")
                compare(row.chevronIcon.visible, rows[i].chevron,
                        "行 " + i + " chevron 可见性（开关/操作行无、子页行有）")
                compare(row.textLabel.font.pixelSize, UITheme.fsListItem,
                        "行 " + i + " 文字字号应为 fsListItem（Kindle §7）")
            }
            // 版本标签收尾（版本号语言无关，避免翻译影响断言）
            verify(layout.children[7].text.indexOf("0.1.0") >= 0, "尾部应为版本标签")
            loader.destroy()
        }

        // L10：深色三态 KdRadioGrid——选择即写 theme/mode(auto/light/dark) +
        // Main.applyTheme → Material/UITheme Token 跟随；subtext 显示当前值；
        // 启动恢复三值
        function test_themeModeRadio() {
            const prevMode = String(Settings.value("theme/mode") || "auto")
            Settings.setValue("theme/mode", "light")
            var loader = mainComp.createObject(root)
            var win = loader.item
            verify(win !== null, "Main.qml 应能加载")
            win.visible = false
            win.navigateTo("settings")
            var sp = win.navStack.currentItem
            verify(sp !== null && sp.navId === "settings", "应进入设置页")
            verify(sp.themeModeGrid !== undefined, "设置页应暴露深色三态 radio 网格")
            compare(sp.themeModeGrid.currentValue, "light", "light 模式应选中浅色")
            compare(sp.settingsLayout.children[0].subtext, "浅色", "subtext 应显示当前值")
            // 选深色 → 写 theme/mode=dark + applyTheme（Token 跟随）
            sp.themeModeGrid.selectValue("dark")
            compare(String(Settings.value("theme/mode")), "dark", "选深色应写 theme/mode=dark")
            compare(win.theme, "dark", "Main.theme 应同步为 dark")
            tryVerify(function () { return UITheme.isDark === true }, 2000,
                      "深色 Token 应即时生效")
            compare(sp.settingsLayout.children[0].subtext, "深色", "subtext 应显示深色")
            // 选浅色
            sp.themeModeGrid.selectValue("light")
            compare(String(Settings.value("theme/mode")), "light", "选浅色应写 theme/mode=light")
            tryVerify(function () { return UITheme.isDark === false }, 2000,
                      "浅色 Token 应即时生效")
            // 选跟随系统 → auto（L10：三态直写，不再单向丢失）
            sp.themeModeGrid.selectValue("auto")
            compare(String(Settings.value("theme/mode")), "auto", "选跟随系统应写 theme/mode=auto")
            compare(win.theme, "auto", "Main.theme 应同步为 auto")
            var sysDark = Qt.styleHints.colorScheme === Qt.ColorScheme.Dark
            tryVerify(function () { return UITheme.isDark === sysDark }, 2000,
                      "auto 模式 Token 应跟随系统实际深浅")
            compare(sp.settingsLayout.children[0].subtext, "跟随系统", "subtext 应显示跟随系统")
            win.visible = false
            loader.destroy()
            // 启动恢复：dark/light/auto 三值 → currentValue 对应选中
            Settings.setValue("theme/mode", "dark")
            var l2 = settingsComp.createObject(root)
            compare(l2.item.themeModeGrid.currentValue, "dark", "theme/mode=dark 应选中深色")
            l2.destroy()
            Settings.setValue("theme/mode", "light")
            var l3 = settingsComp.createObject(root)
            compare(l3.item.themeModeGrid.currentValue, "light", "theme/mode=light 应选中浅色")
            l3.destroy()
            Settings.setValue("theme/mode", "auto")
            var l4 = settingsComp.createObject(root)
            compare(l4.item.themeModeGrid.currentValue, "auto", "theme/mode=auto 应选中跟随系统")
            l4.destroy()
            Settings.setValue("theme/mode", prevMode)
        }

        // 子页导航：六入口句柄不丢；背景子页 push + radio 选择 + 返回；
        // 同步/统计入口（U2 可达）push/返回
        function test_subpageEntries() {
            var stack = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; StackView { width: 1100; height: 720 }",
                root, "u5Stack")
            stack.push("qrc:/qt/qml/Readdict/ui/qml/SettingsPage.qml")
            var page = stack.currentItem
            verify(page !== null, "SettingsPage 应能加载")
            // 功能入口不丢（TTS/背景/同步/统计/刷新封面/语言）
            verify(page.languageEntryButton !== undefined, "语言入口句柄")
            verify(page.ttsEntryButton !== undefined, "TTS 入口句柄")
            verify(page.backgroundEntryButton !== undefined, "背景入口句柄")
            verify(page.refreshCoversButton !== undefined, "刷新封面入口句柄")
            verify(page.syncEntryButton !== undefined, "同步入口句柄")
            verify(page.statsEntryButton !== undefined, "统计入口句柄")
            // 背景子页：push → KdRadioGrid 选择写 Settings → 返回
            page.backgroundEntryButton.clicked()
            var bgPage = stack.currentItem
            verify(bgPage !== page, "点背景行应推入背景子页")
            verify(bgPage.bgGrid !== undefined, "背景子页应暴露四态单选网格")
            bgPage.bgGrid.selectValue("paper")
            compare(String(Settings.value("background/mode")), "paper",
                    "子页选择应写 background/mode")
            bgPage.goBack()
            verify(stack.currentItem === page, "背景子页返回应 pop 回设置页")
            // 同步入口（U2 导航可达）
            page.syncEntryButton.clicked()
            verify(stack.currentItem.navId === "sync", "同步入口应推入 SyncPage")
            stack.pop(null, StackView.Immediate)
            verify(stack.currentItem === page, "同步页返回应回设置页")
            // 统计入口
            page.statsEntryButton.clicked()
            verify(stack.currentItem.navId === "stats", "统计入口应推入 StatsPage")
            stack.pop(null, StackView.Immediate)
            verify(stack.currentItem === page, "统计页返回应回设置页")
            stack.destroy()
            Settings.setValue("background/mode", "light")
        }
    }
}
