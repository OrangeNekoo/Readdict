import QtQuick
import QtQuick.Controls
import QtTest
import Readdict.Backend

// D6：三语切换冒烟——驱动设置页语言下拉：持久化 ui/language → Lang 加载对应
// .qm → 新建页面实例取到新语言文本（设置页标题 设置/設定/Settings）。
// 注：quicktest 引擎不调用 QQmlEngine::retranslate（生产 main.cpp 里
// languageChanged → retranslate 刷新存量页面），故用"切换后新建实例"断言翻译
// 已生效；存量页面刷新由 tst_language 覆盖的 translator 安装链路保证。
Item {
    id: root
    width: 1100; height: 720
    Component {
        id: settingsComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/SettingsPage.qml" }
    }
    TestCase {
        name: "LanguageSwitchSmoke"
        function test_switchChain() {
            // 初始 zh_CN（tst_qmlmain 注册 Lang 以 zh_CN 起步；settings 未设置语言）
            var loader = settingsComp.createObject(root)
            var page = loader.item
            verify(page !== null, "SettingsPage 应能加载")
            compare(page.title, "设置", "初始应为简体中文标题")
            compare(page.languageBox.currentIndex, 0, "语言下拉应恢复为 zh_CN")
            // 切繁体：持久化 + Lang 切换 + 新实例取繁体翻译
            page.languageBox.activated(1)
            compare(String(Settings.value("ui/language")), "zh_TW", "切换应持久化 ui/language")
            compare(Lang.currentLanguage, "zh_TW", "Lang 应已切换到 zh_TW")
            var tw = settingsComp.createObject(root)
            compare(tw.item.title, "設定", "繁体下新建设置页标题应为 設定")
            compare(tw.item.languageBox.currentIndex, 1, "繁体下语言下拉应恢复为 zh_TW")
            tw.destroy()
            // 切英文
            page.languageBox.activated(2)
            compare(String(Settings.value("ui/language")), "en")
            compare(Lang.currentLanguage, "en", "Lang 应已切换到 en")
            var en = settingsComp.createObject(root)
            compare(en.item.title, "Settings", "英文下新建设置页标题应为 Settings")
            compare(en.item.languageBox.currentIndex, 2, "英文下语言下拉应恢复为 en")
            en.destroy()
            // 切回简体（重启保持语义：再次新建页面回到中文）
            page.languageBox.activated(0)
            compare(String(Settings.value("ui/language")), "zh_CN")
            compare(Lang.currentLanguage, "zh_CN")
            var cn = settingsComp.createObject(root)
            compare(cn.item.title, "设置", "切回简体后新建设置页标题应为 设置")
            cn.destroy()
            loader.destroy()
        }
    }
}
