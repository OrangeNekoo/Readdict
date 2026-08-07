import QtQuick
import QtQuick.Controls
import QtTest
import Readdict.Backend

// B4 冒烟：设置页返回导航——书架 → push SettingsPage → 点击返回按钮（生产路径
// onClicked → goBack → StackView.pop）→ 断言回到书架。quicktest harness 不推进
// StackView 过渡动画（见 tst_main.qml B10 注释：push/pop 亦然），pop 后栈顶
// currentItem 同步切回书架，但被 pop 项的销毁/出栈依赖退场动画完成——depth 归位
// 用 tryVerify 尽力断言；主断言取 currentItem 恢复（与 tst_statspage/tst_syncpage
// 的栈断言同模式，取舍：depth 不可靠时仅 currentItem + goBack 调用路径成立）。
Item {
    id: root
    width: 1100; height: 720

    TestCase {
        name: "SettingsNavSmoke"
        // 书架 → 设置页 → 返回：全链路（生产 Main.qml 的 StackView initialItem 即 ShelfPage）
        function test_settingsBackToShelf() {
            var stack = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; StackView { anchors.fill: parent; }", root)
            verify(stack !== null, "测试 StackView 应能创建")
            stack.push("qrc:/qt/qml/Readdict/ui/qml/ShelfPage.qml")
            var shelf = stack.currentItem
            verify(shelf !== null, "ShelfPage 应被 push 进 StackView（书架根页）")
            stack.push("qrc:/qt/qml/Readdict/ui/qml/SettingsPage.qml")
            var settingsPage = stack.currentItem
            verify(settingsPage !== null, "SettingsPage 应被 push 进 StackView")
            verify(stack.depth === 2, "栈深度应为 2（书架 + 设置页），实际 " + stack.depth)
            // 生产返回按钮（测试句柄 alias backButton）：点击走 onClicked → goBack() → pop
            verify(settingsPage.backButton !== undefined, "设置页应暴露返回按钮句柄")
            verify(settingsPage.goBack !== undefined, "设置页应暴露 goBack() 供测试")
            settingsPage.backButton.clicked()
            // pop 同步更新 currentItem：栈顶应恢复为书架页（主断言，动画无关）
            verify(stack.currentItem === shelf, "点击返回后应回到书架页")
            // depth 归位依赖退场动画（quicktest 不推进），尽力断言；若失败按上述取舍
            tryVerify(function () { return stack.depth === 1 }, 3000,
                      "返回后栈深度应回到 1（书架），实际 " + stack.depth)
            stack.destroy()
        }
    }
}
