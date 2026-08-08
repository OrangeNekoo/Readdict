import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Readdict.Backend

// D3：WebDAV 同步设置页。配置（url/user/password/勾选项）落 SettingsStore 的
// webdav 分区（password 明文存本机 settings.json，设计文档已定，永不上传——
// 见 SyncManager.cpp 的 kSyncSections 白名单）；"保存并立即同步"触发 Sync.run。
// 同步日志来自 SyncController.log（SyncManager 逐条操作记录，含时间戳）。
Page {
    id: page
    title: qsTr("WebDAV 同步")
    // U2：导航页标识（Main 底部导航直达同步页；经设置页推入时高亮跟随）
    property string navId: "sync"
    // 测试/外部句柄（QML 冒烟经此驱动配置与自动同步开关，ShelfPage 同模式）
    property alias syncUrlField: urlField
    property alias syncAutoCheck: cbAuto
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 12

        RowLayout {
            Button {
                text: qsTr("返回")
                onClicked: page.StackView.view.pop()
            }
            Label {
                text: qsTr("WebDAV 同步")
                font.bold: true
                font.pixelSize: 18
            }
        }

        RowLayout {
            Label { text: qsTr("服务器地址") }
            TextField {
                id: urlField
                Layout.fillWidth: true
                text: Settings.value("webdav/url").toString()
                placeholderText: "https://dav.example.com/dav/readdict"
            }
        }
        RowLayout {
            Label { text: qsTr("用户名") }
            TextField {
                id: userField
                Layout.fillWidth: true
                text: Settings.value("webdav/user").toString()
            }
        }
        RowLayout {
            Label { text: qsTr("密码") }
            TextField {
                id: passField
                Layout.fillWidth: true
                echoMode: TextInput.Password
                text: Settings.value("webdav/password").toString()
            }
        }
        Label { text: qsTr("同步内容") }
        Column {
            spacing: 4
            CheckBox {
                id: cbSettings
                text: qsTr("设置")
                checked: Settings.value("webdav/syncSettings") === true
            }
            CheckBox {
                id: cbProgress
                text: qsTr("阅读进度")
                checked: Settings.value("webdav/syncProgress") === true
            }
            CheckBox {
                id: cbNotes
                text: qsTr("划线笔记")
                checked: Settings.value("webdav/syncHighlights") === true
            }
            CheckBox {
                id: cbBooks
                text: qsTr("书籍文件")
                checked: Settings.value("webdav/syncBooks") === true
            }
            CheckBox {
                id: cbAuto
                text: qsTr("每 30 分钟自动同步")
                // autoSync 持久化（webdav/autoSync，默认 false）：重启后恢复上次选择，
                // main.cpp 启动时据此调 Sync.setAutoSync
                checked: Settings.value("webdav/autoSync") === true
            }
        }
        RowLayout {
            Button {
                text: qsTr("保存并立即同步")
                onClicked: page.saveAndSync()
            }
            BusyIndicator { running: Sync.running }
            Label {
                id: statusLabel
                text: ""
                color: "#2E7D32"
            }
        }
        Label { text: qsTr("同步日志"); font.bold: true }
        ListView {
            id: logView
            Layout.fillHeight: true
            Layout.fillWidth: true
            clip: true
            model: Sync.log
            delegate: Label {
                text: modelData
                width: ListView.view.width
                wrapMode: Text.Wrap
                font.pixelSize: 12
                // 失败行 = 时间戳后紧跟"失败"的消息（books 信息行可能含书名里的"失败"字）
                color: page.isFailureLine(modelData) ? "#C62828" : Material.secondaryTextColor
            }
            ScrollBar.vertical: ScrollBar {}
        }
    }

    // 日志行是否真实失败：SyncManager::log 格式 "yyyy-MM-dd HH:mm:ss <消息>"，
    // 只认消息起始为"失败"（与 SyncController::doSync 的判定同源）
    function isFailureLine(line) {
        return line.length > 20 && line.substring(20).startsWith("失败")
    }

    // 保存配置并立即同步（SettingsPage.saveTts 同模式：函数可被测试直接调用）
    function saveAndSync() {
        Settings.setValue("webdav/url", urlField.text.trim())
        Settings.setValue("webdav/user", userField.text.trim())
        Settings.setValue("webdav/password", passField.text)
        Settings.setValue("webdav/syncSettings", cbSettings.checked)
        Settings.setValue("webdav/syncProgress", cbProgress.checked)
        Settings.setValue("webdav/syncHighlights", cbNotes.checked)
        Settings.setValue("webdav/syncBooks", cbBooks.checked)
        Settings.setValue("webdav/autoSync", cbAuto.checked)
        Sync.setAutoSync(cbAuto.checked)
        Sync.run(cbSettings.checked, cbProgress.checked, cbNotes.checked, cbBooks.checked)
    }

    // finished 信号到达后刷新状态提示（同步是阻塞的，这里只在结束时执行一次）
    Connections {
        target: Sync
        function onFinished(ok, error) {
            statusLabel.color = ok ? "#2E7D32" : "#C62828"
            statusLabel.text = ok ? qsTr("同步完成") : qsTr("同步失败：") + error
            logView.positionViewAtEnd()
        }
    }
}
