import QtQuick
import QtQuick.Controls
import QtTest
import Readdict.Backend

// D6：三语切换冒烟——U5 起语言设置迁入子页（SettingsLanguagePage，KdRadioGrid
// 单选 zh_CN/zh_TW/en）：驱动设置页"语言"行 → 子页 → 选中即持久化 ui/language →
// Lang 加载对应 .qm → 新建页面实例取到新语言文本（子页标题 语言/語言/Language）。
// 注：quicktest 引擎不调用 QQmlEngine::retranslate（生产 main.cpp 里
// languageChanged → retranslate 刷新存量页面），故用"切换后新建实例"断言翻译
// 已生效；存量页面刷新由 tst_language 覆盖的 translator 安装链路保证。
Item {
    id: root
    width: 1100; height: 720
    Component {
        id: langPageComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/SettingsLanguagePage.qml" }
    }
    TestCase {
        name: "LanguageSwitchSmoke"
        function test_switchChain() {
            // 初始 zh_CN（tst_qmlmain 注册 Lang 以 zh_CN 起步；settings 未设置语言）
            var loader = langPageComp.createObject(root)
            var page = loader.item
            verify(page !== null, "SettingsLanguagePage 应能加载")
            compare(page.title, "语言", "初始应为简体中文标题")
            compare(page.languageGrid.currentValue, "zh_CN", "语言单选应恢复为 zh_CN")
            // 切繁体：持久化 + Lang 切换 + 新实例取繁体翻译
            page.languageGrid.selectValue("zh_TW")
            compare(String(Settings.value("ui/language")), "zh_TW", "切换应持久化 ui/language")
            compare(Lang.currentLanguage, "zh_TW", "Lang 应已切换到 zh_TW")
            var tw = langPageComp.createObject(root)
            compare(tw.item.title, "語言", "繁体下新建语言子页标题应为 語言")
            compare(tw.item.languageGrid.currentValue, "zh_TW", "繁体下语言单选应恢复为 zh_TW")
            tw.destroy()
            // 切英文
            page.languageGrid.selectValue("en")
            compare(String(Settings.value("ui/language")), "en")
            compare(Lang.currentLanguage, "en", "Lang 应已切换到 en")
            var en = langPageComp.createObject(root)
            compare(en.item.title, "Language", "英文下新建语言子页标题应为 Language")
            compare(en.item.languageGrid.currentValue, "en", "英文下语言单选应恢复为 en")
            en.destroy()
            // 切回简体（重启保持语义：再次新建页面回到中文）
            page.languageGrid.selectValue("zh_CN")
            compare(String(Settings.value("ui/language")), "zh_CN")
            compare(Lang.currentLanguage, "zh_CN")
            var cn = langPageComp.createObject(root)
            compare(cn.item.title, "语言", "切回简体后新建语言子页标题应为 语言")
            cn.destroy()
            loader.destroy()
        }
        // U5：设置页"语言"行 → push SettingsLanguagePage（导航链路）
        function test_settingsLanguageEntry() {
            var stack = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; StackView { width: 1100; height: 720 }",
                root, "langStack")
            stack.push("qrc:/qt/qml/Readdict/ui/qml/SettingsPage.qml")
            var page = stack.currentItem
            verify(page !== null, "SettingsPage 应能加载")
            verify(page.languageEntryButton !== undefined, "设置页应暴露语言入口行句柄")
            compare(page.settingsLayout.children[1].text, "语言", "语言行主文案")
            page.languageEntryButton.clicked()
            var langPage = stack.currentItem
            verify(langPage !== page, "点击语言行应推入语言子页")
            verify(langPage.languageGrid !== undefined, "语言子页应暴露 languageGrid 句柄")
            // 返回设置页：goBack 路径
            langPage.goBack()
            verify(stack.currentItem === page, "语言子页返回应 pop 回设置页")
            stack.destroy()
        }
    }
}
