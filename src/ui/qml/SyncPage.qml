import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.Backend
import Readdict.UI 1.0

// D3：WebDAV 同步设置页。配置（url/user/password/勾选项）落 SettingsStore 的
// webdav 分区（password 明文存本机 settings.json，设计文档已定，永不上传——
// 见 SyncManager.cpp 的 kSyncSections 白名单）。L8（P1#11）：所有配置项即改即写
// （与设置页即时生效语义一致），「立即同步」按钮只触发 Sync.run。
// 同步日志来自 SyncController.log（SyncManager 逐条操作记录，含时间戳）。
//
// BUG1：返回按钮固定顶部（B4 模式，同 SettingsPage/SettingsTtsPage/
// SettingsBackgroundPage）——header 移出页面级 ScrollView，滚动后仍固定可见，
// 不再随表单滚出视口（左上角无滚动残影）；ScrollView top 锚接 header.bottom。
// 整页表单放入页面级 ScrollView——小窗口下全部配置项可滚动可达；日志区保留
// 明确高度与内部垂直滚动（不做页面级滚动条的替身）。宽度基于实际 viewport 与
// padding 单向计算（不绑 availableWidth：内容尺寸计算前可能为 0，会使行内
// 控件宽度坍缩，同 SettingsPage 裁定）。
Page {
    id: page
    title: qsTr("WebDAV 同步")
    // B4/BUG1：返回上一页——只 pop 当前层（绝不经 Main.goBack 弹回主页；
    // 无 StackView 上下文如测试直载时安全空操作）
    function goBack() {
        const stack = page.StackView.view
        if (stack && stack.depth > 1) stack.pop()
    }
    // U2：导航页标识（Main 底部导航直达同步页；经设置页推入时高亮跟随）
    property string navId: "sync"
    // 测试/外部句柄（QML 冒烟经此驱动配置与自动同步开关，ShelfPage 同模式）
    property alias syncUrlField: urlField
    property alias syncAutoCheck: cbAuto
    // 页面级滚动容器与日志列表句柄（滚动/宽度冒烟断言用）
    property alias syncScroll: syncScroll
    property alias syncForm: syncForm
    property alias syncLogView: logView
    // BUG1：返回按钮句柄（固定 header，滚到底仍可见——tst_syncpage 断言）
    property alias backButton: backButton

    // 固定顶部：返回 + 页面标题（B4 返回导航位，同 SettingsPage/TTS/背景子页模式）
    RowLayout {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        anchors.topMargin: 16
        ToolButton {
            id: backButton
            text: "← " + qsTr("返回")
            onClicked: page.goBack()
        }
        Label {
            text: page.title
            font.pixelSize: UITheme.fsPageTitle
            font.bold: true
            color: UITheme.textPrimary
            Layout.leftMargin: 8
        }
    }

    // BUG1：页面级滚动容器（header 不在其中——固定 header 不参与内容滚动；
    // clip 显式声明，滚动内容不渗出视口边缘，左上角无灰色残留）
    ScrollView {
        id: syncScroll
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.top: header.bottom
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        anchors.bottomMargin: 24
        anchors.topMargin: 12
        clip: true
        // 配置 ScrollView 已创建的附加滚动条实例，避免替换实例后 Material
        // 样式角落在滚动时残留为灰色方块。
        ScrollBar.vertical.policy: ScrollBar.AsNeeded
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ColumnLayout {
            id: syncForm
            // availableWidth 已扣除垂直滚动条和 padding，避免滚动条出现时内容
            // 比视口多出一列而触发水平滚动。
            width: Math.max(0, syncScroll.availableWidth)
            spacing: 12

            RowLayout {
                Label { text: qsTr("服务器地址") }
                TextField {
                    id: urlField
                    Layout.fillWidth: true
                    text: Settings.value("webdav/url").toString()
                    placeholderText: "https://dav.example.com/dav/readdict"
                    // L8（P1#11）：即改即写——按钮不再承担保存职责
                    onTextChanged: Settings.setValue("webdav/url", text.trim())
                }
            }
            RowLayout {
                Label { text: qsTr("用户名") }
                TextField {
                    id: userField
                    Layout.fillWidth: true
                    text: Settings.value("webdav/user").toString()
                    onTextChanged: Settings.setValue("webdav/user", text.trim())
                }
            }
            RowLayout {
                Label { text: qsTr("密码") }
                TextField {
                    id: passField
                    Layout.fillWidth: true
                    echoMode: TextInput.Password
                    text: Settings.value("webdav/password").toString()
                    onTextChanged: Settings.setValue("webdav/password", text)
                }
            }
            Label { text: qsTr("同步内容") }
            Column {
                spacing: 4
                CheckBox {
                    id: cbSettings
                    text: qsTr("设置")
                    checked: Settings.value("webdav/syncSettings") === true
                    // L8（P1#11）：勾选即写
                    onCheckedChanged: Settings.setValue("webdav/syncSettings", checked)
                }
                CheckBox {
                    id: cbProgress
                    text: qsTr("阅读进度")
                    checked: Settings.value("webdav/syncProgress") === true
                    onCheckedChanged: Settings.setValue("webdav/syncProgress", checked)
                }
                CheckBox {
                    id: cbNotes
                    text: qsTr("划线笔记")
                    checked: Settings.value("webdav/syncHighlights") === true
                    onCheckedChanged: Settings.setValue("webdav/syncHighlights", checked)
                }
                CheckBox {
                    id: cbBooks
                    text: qsTr("书籍文件")
                    checked: Settings.value("webdav/syncBooks") === true
                    onCheckedChanged: Settings.setValue("webdav/syncBooks", checked)
                }
                CheckBox {
                    id: cbAuto
                    text: qsTr("每 30 分钟自动同步")
                    // autoSync 持久化（webdav/autoSync，默认 false）：重启后恢复上次选择，
                    // main.cpp 启动时据此调 Sync.setAutoSync。L8：勾选即写并即时启停定时器
                    checked: Settings.value("webdav/autoSync") === true
                    onCheckedChanged: {
                        Settings.setValue("webdav/autoSync", checked)
                        Sync.setAutoSync(checked)
                    }
                }
            }
            RowLayout {
                Button {
                    // L8（P1#11）：配置已即改即写，按钮只触发同步
                    text: qsTr("立即同步")
                    onClicked: page.syncNow()
                }
                BusyIndicator { running: Sync.running }
                Label {
                    id: statusLabel
                    text: ""
                    color: UITheme.success
                }
            }
            Label { text: qsTr("同步日志"); font.bold: true }
            ListView {
                id: logView
                Layout.fillWidth: true
                // 日志区保留明确高度（小窗口下不被视口压缩成 0），
                // 页面级滚动负责表单整体，日志内部仍独立滚动
                Layout.preferredHeight: 180
                clip: true
                model: Sync.log
                delegate: Label {
                    text: modelData
                    width: ListView.view.width
                    wrapMode: Text.Wrap
                    font.pixelSize: 12
                    // 失败行 = 时间戳后紧跟"失败"/"注册失败"的消息（与 SyncManager::fail
                    // 的两类消息前缀同源；books 信息行可能含书名里的"失败"字）
                    color: page.isFailureLine(modelData) ? UITheme.danger : UITheme.textSecondary
                }
                ScrollBar.vertical: ScrollBar {}
            }
        }
    }

    // 日志行是否真实失败：SyncManager::log 格式 "yyyy-MM-dd HH:mm:ss <消息>"，
    // 只认消息起始为"失败"/"注册失败"（失败消息全集见 SyncManager::fail；
    // 仅展示着色用——成败判定在 SyncController 经结构化 Result，不在此）
    function isFailureLine(line) {
        if (line.length <= 20) return false
        const msg = line.substring(20)
        return msg.startsWith("失败") || msg.startsWith("注册失败")
    }

    // L8（P1#11）：立即同步——配置项已即改即写，此处只按当前勾选触发 Sync.run
    // （函数可被测试直接调用）
    function syncNow() {
        Sync.run(cbSettings.checked, cbProgress.checked, cbNotes.checked, cbBooks.checked)
    }

    // finished 信号到达后刷新状态提示（同步是阻塞的，这里只在结束时执行一次）
    Connections {
        target: Sync
        function onFinished(ok, error) {
            statusLabel.color = ok ? UITheme.success : UITheme.danger
            statusLabel.text = ok ? qsTr("同步完成") : qsTr("同步失败：") + error
            logView.positionViewAtEnd()
        }
    }
}
