import QtQuick
import QtQuick.Controls
import QtTest
import Readdict.Backend

// D3 冒烟：SyncPage 可加载（WebDAV 配置 + 日志列表编译检查）；错误配置
// （空 URL/无服务器）下 syncNow 不崩溃、finished(false, error) 到达、
// 日志记录失败行、running 复位。tst_qmlmain 注册的 Sync 指向测试临时目录的
// settings.json（与 Settings 单例同文件），run() 走真实 WebDavClient——
// 空 URL / 未注册协议使 QNetworkReply 立即失败，无网络依赖、确定性快速。
// L8（P1#11）：配置项即改即写（CheckBox/TextField 的 onChanged 直写 Settings），
// syncNow() 只触发同步。
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
            page.syncNow()
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
            verify(syncPage !== null && syncPage.syncNow !== undefined,
                   "栈顶应为 SyncPage（含 syncNow 函数）")
            stack.destroy()
        }

        // 即改即写：url/autoSync 经 onChanged 直接持久化到 settings.json，
        // 未勾选项保持默认；syncNow 用未注册协议 URL 立即失败（不联网）
        function test_savePersistsSettingsAndAutoSync() {
            var loader = syncPageComp.createObject(root)
            var page = loader.item
            verify(page !== null, "SyncPage 应能加载")
            page.syncUrlField.text = "notarealscheme://dav.example.invalid/dav"
            page.syncAutoCheck.checked = true
            page.syncNow()
            compare(String(Settings.value("webdav/url")), "notarealscheme://dav.example.invalid/dav",
                    "服务器地址应持久化")
            compare(Settings.value("webdav/autoSync"), true, "autoSync 勾选应持久化")
            compare(Settings.value("webdav/syncBooks"), false, "未勾选项应保持默认 false")
            verify(!Sync.running, "同步结束后 running 应为 false")
            loader.destroy()
        }
    }

    // 任务 1：小窗口下整页表单必须可滚动——页面级 ScrollView 存在且内容超出视口
    //（真实可滚动范围）；日志区域保留明确可用高度与内部垂直滚动句柄，不被压缩成 0。
    // 布局时序用 tryVerify 轮询，不用固定 sleep。
    TestCase {
        name: "SyncPageScrollSmoke"

        function test_smallWindowFormScrollsAndLogKeepsHeight() {
            var host = Qt.createQmlObject(
                "import QtQuick; Item { width: 480; height: 420 }",
                root, "syncSmallHost")
            var loader = syncPageComp.createObject(host)
            loader.width = host.width
            loader.height = host.height
            var page = loader.item
            verify(page !== null, "SyncPage 应能加载")
            // 页面级滚动容器 + 日志句柄必须存在并完成布局（宽度非零）
            tryVerify(function () {
                return page.syncScroll !== undefined
                       && page.syncScroll.width > 0
                       && page.syncLogView !== undefined
            }, 3000, "SyncPage 应暴露页面级滚动容器与日志句柄")
            // 实际滚动范围：小窗口下整页表单内容高度 > 视口高度
            tryVerify(function () {
                return page.syncScroll.contentHeight > page.syncScroll.height
            }, 3000, "小窗口下表单内容应超出视口，页面滚动范围有效")
            // 日志区域保留明确可用高度（不被压缩到 0）
            verify(page.syncLogView.height > 0,
                   "日志区域应有可用高度，实际 " + page.syncLogView.height)
            // 日志列表保留内部垂直滚动句柄
            verify(page.syncLogView.ScrollBar.vertical !== null,
                   "日志列表应保留内部垂直滚动条")
            // 800x600（验收窗口）下同样无零宽度内容、日志区可用
            host.width = 800
            host.height = 600
            loader.width = 800
            loader.height = 600
            tryVerify(function () {
                return page.syncScroll.width > 0
                       && page.syncForm !== undefined && page.syncForm.width > 0
                       && page.syncLogView.width > 0 && page.syncLogView.height > 0
            }, 3000, "800x600 下内容宽度与日志区高度应非零")
            loader.destroy()
            host.destroy()
        }

        // BUG1：返回按钮固定顶部——header 移出页面滚动容器，滚动后不随表单
        // 滚出视口（同 SettingsPage B4 模式：固定 header + ScrollView 顶部锚接）
        function test_backButtonFixedWhileFormScrolls() {
            var host = Qt.createQmlObject(
                "import QtQuick; Item { width: 480; height: 420 }",
                root, "syncSmallHostFixedHeader")
            var loader = syncPageComp.createObject(host)
            loader.width = host.width
            loader.height = host.height
            var page = loader.item
            verify(page !== null, "SyncPage 应能加载")
            verify(page.backButton !== undefined, "SyncPage 应暴露返回按钮句柄")
            tryVerify(function () {
                return page.syncScroll !== undefined
                       && page.syncScroll.width > 0
                       && page.syncScroll.contentHeight > 0
            }, 3000, "页面滚动容器应完成布局")
            // 返回按钮位于滚动容器上方（固定 header，不参与内容滚动）
            var btnBottom = page.backButton.mapToItem(page, 0, page.backButton.height).y
            var scrollTop = page.syncScroll.mapToItem(page, 0, 0).y
            verify(btnBottom <= scrollTop,
                   "返回按钮应位于滚动容器上方：btnBottom=" + btnBottom
                   + " scrollTop=" + scrollTop)
            // ScrollView 通过 contentItem 的 Flickable 承载滚动位置；使用其真实
            // contentY 驱动滚底，避免把 ScrollView 自身当作 Flickable。
            var scrollFlick = page.syncScroll.contentItem
            verify(scrollFlick !== null, "ScrollView 应暴露内容 Flickable")
            var beforeY = page.backButton.mapToItem(page, 0, 0).y
            scrollFlick.contentY = Math.max(0,
                scrollFlick.contentHeight - scrollFlick.height)
            compare(page.backButton.mapToItem(page, 0, 0).y, beforeY,
                    "滚动后返回按钮位置不应移动")
            var btnY = beforeY
            verify(page.backButton.visible && btnY >= 0
                   && btnY + page.backButton.height <= page.height,
                   "滚动后返回按钮应固定可见（y=" + btnY + "）")
            // 必要滚动条：内容超高 → 垂直滚动条策略允许按需出现（AsNeeded）
            verify(page.syncScroll.ScrollBar.vertical !== null,
                   "页面级垂直滚动条句柄应存在")
            verify(page.syncScroll.ScrollBar.vertical.policy !== ScrollBar.AlwaysOff,
                   "垂直滚动条策略应允许按需出现")
            loader.destroy()
            host.destroy()
        }
    }
}
