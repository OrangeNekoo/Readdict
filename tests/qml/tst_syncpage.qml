import QtQuick
import QtTest
import Readdict.Backend

// D3 冒烟：SyncPage 可加载（WebDAV 配置 + 日志列表编译检查）；错误配置
// （空 URL/无服务器）下 saveAndSync 不崩溃、finished(false, error) 到达、
// 日志记录失败行、running 复位。tst_qmlmain 注册的 Sync 指向测试临时目录的
// settings.json（与 Settings 单例同文件），run() 走真实 WebDavClient——
// 空 URL / 未注册协议使 QNetworkReply 立即失败，无网络依赖、确定性快速。
Item {
    id: root
    width: 1100; height: 720

    Component {
        id: syncPageComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/SyncPage.qml" }
    }

    TestCase {
        name: "SyncPageSmoke"
        function test_pageLoads() {
            var loader = syncPageComp.createObject(root)
            verify(loader.item !== null, "SyncPage 应能加载（WebDAV 配置表单 + 日志列表编译检查）")
            loader.destroy()
        }

        // 错误配置（空服务器地址）不崩溃：finished(false, error) 必须到达、
        // 日志记录失败行、running 复位为 false
        function test_saveWithoutServerFailsGracefully() {
            Settings.setValue("webdav/url", "")
            var loader = syncPageComp.createObject(root)
            var page = loader.item
            verify(page !== null, "SyncPage 应能加载")
            var got = null
            Sync.finished.connect(function (ok, error) { got = { ok: ok, error: error } })
            page.saveAndSync()
            verify(got !== null, "finished 信号应同步到达（run 是阻塞的）")
            compare(got.ok, false, "空 URL 的同步应判定失败")
            verify((got.error || "").length > 0, "失败应带 error 文本，实际 " + got.error)
            verify(Sync.log.length > 0, "失败应记录到同步日志")
            var hasFail = false
            for (var i = 0; i < Sync.log.length; i++)
                if (Sync.log[i].indexOf("失败") >= 0) { hasFail = true; break }
            verify(hasFail, "日志应含失败行，实际 " + Sync.log.join(" | "))
            compare(Sync.running, false, "同步结束后 running 应为 false")
            loader.destroy()
        }

        // 设置页入口按钮 → StackView push SyncPage：真实导航链（生产路径）
        function test_settingsEntryOpensSyncPage() {
            var stack = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; StackView { anchors.fill: parent; }", root)
            verify(stack !== null, "测试 StackView 应能创建")
            stack.push("qrc:/qt/qml/Readdict/ui/qml/SettingsPage.qml")
            var settingsPage = stack.currentItem
            verify(settingsPage !== null, "SettingsPage 应被 push 进 StackView")
            verify(settingsPage.syncEntryButton !== undefined, "设置页应暴露同步入口按钮")
            settingsPage.syncEntryButton.clicked()
            verify(stack.currentItem !== settingsPage, "点击后应导航离开设置页")
            verify(stack.depth === 2, "栈深度应为 2（设置页 + 同步页），实际 " + stack.depth)
            var syncPage = stack.currentItem
            verify(syncPage !== null && syncPage.saveAndSync !== undefined,
                   "栈顶应为 SyncPage（含 saveAndSync 函数）")
            stack.destroy()
        }

        // 保存应把配置与勾选项持久化到 settings.json（含 autoSync），
        // 并置 Sync 的自动同步开关；未注册协议 URL 立即失败（不联网）
        function test_savePersistsSettingsAndAutoSync() {
            var loader = syncPageComp.createObject(root)
            var page = loader.item
            verify(page !== null, "SyncPage 应能加载")
            page.syncUrlField.text = "notarealscheme://dav.example.invalid/dav"
            page.syncAutoCheck.checked = true
            page.saveAndSync()
            compare(String(Settings.value("webdav/url")), "notarealscheme://dav.example.invalid/dav",
                    "服务器地址应持久化")
            compare(Settings.value("webdav/autoSync"), true, "autoSync 勾选应持久化")
            compare(Settings.value("webdav/syncBooks"), false, "未勾选项应保持默认 false")
            verify(!Sync.running, "同步结束后 running 应为 false")
            loader.destroy()
        }
    }
}
