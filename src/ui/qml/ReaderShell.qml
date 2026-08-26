import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.Backend
import Readdict.UI 1.0

// 统一阅读交互壳层（任务2）：为未来文本/PDF 适配器提供格式无关的交互框架——
// 顶栏、右上角菜单遮罩、TtsBar、受控 Sheet 状态、自动隐藏计时与焦点/StackView
// 激活恢复钩子。不拥有主题/字体/正文渲染/PDF 缩放/进度写入/关闭安全（那些留在
// 各自阅读页或适配器）。
//
// 适配器契约（property var reader）：
//   progressText, canGoPrevious, canGoNext,
//   canReadAloud, readAloudUnavailableReason,
//   supportsContents, supportsSearch, supportsNotes, supportsBookmarks,
//   previousLabel, nextLabel,
//   previous(), next(), startReadAloud(), stopReadAloud(),
//   openContents(), openSearch(), openNotes(), toggleBookmark(),
//   openBookmarks()（可选；书签管理 Dialog 由适配器侧提供，业务数据不进壳层）
// 上/下一项标签一律取自 previousLabel/nextLabel，绝不硬编码"上一章/下一章"。
// 朗读禁用项（canReadAloud=false）必须 disabled、携带 readAloudUnavailableReason，
// 且 triggerMenuAction("read") 不调用 startReadAloud、不启动 TTS、不显示 TtsBar。
Item {
    id: shell

    property var reader: null
    // 注入方提供的正文宿主（保持 activeFocus 的焦点目标）；Shell 不拥有正文。
    property var contentItem: null
    property bool bookmarked: false
    // 测试可见句柄。
    property alias topToolbar: topToolbar
    property alias ttsBar: ttsBar
    property alias bottomSheet: bottomSheet
    // TtsBar 前景/底色（随阅读背景切换，由注入方提供；浅色默认）。
    property string ttsBgMode: "light"
    // 底部 Sheet 面板由适配器注入（主题/字体/布局等格式专属内容不迁入壳层）。
    property var sheetTabs: []
    property var sheetPages: []
    property string sheetTab: ""

    // ---- 受控 sheet / 菜单状态 ----
    property bool sheetOpen: false
    property bool menuOpen: false
    property bool controlsVisible: true
    property int controlsHideDelay: 5000

    // 自动隐藏计时器（只控制 Sheet/顶栏；TtsBar 显隐由 state 独立门控）。
    // 语义同 ReaderPage：显示态（controlsVisible && !sheetOpen）期间计时，超时
    // 回退隐藏态；hover/点击重置；Sheet 打开时停止。
    Timer {
        id: hideControlsTimer
        interval: shell.controlsHideDelay
        repeat: false
        running: false
        onTriggered: {
            if (shell.sheetOpen) return
            shell.controlsVisible = false
            shell.sheetOpen = false
        }
    }
    onControlsVisibleChanged: {
        if (shell.controlsVisible && !shell.sheetOpen) hideControlsTimer.start()
        else if (!shell.controlsVisible) hideControlsTimer.stop()
    }
    onSheetOpenChanged: {
        if (shell.sheetOpen) hideControlsTimer.stop()
        else if (shell.controlsVisible) hideControlsTimer.restart()
    }

    // ---- 菜单模型（由适配器 capability 与标签构造；绑定驱动实时刷新）----
    property bool readEnabled: shell.reader ? !!shell.reader.canReadAloud : false
    property string readUnavailableReason: shell.reader
        ? (shell.reader.readAloudUnavailableReason || "") : ""
    property bool prevEnabled: shell.reader ? !!shell.reader.canGoPrevious : false
    property bool nextEnabled: shell.reader ? !!shell.reader.canGoNext : false
    property bool tocEnabled: shell.reader ? !!shell.reader.supportsContents : false
    property bool searchEnabled: shell.reader ? !!shell.reader.supportsSearch : false
    property bool notesEnabled: shell.reader ? !!shell.reader.supportsNotes : false
    property bool bookmarkEnabled: shell.reader ? !!shell.reader.supportsBookmarks : false
    property string prevLabel: shell.reader
        ? (shell.reader.previousLabel || qsTr("上一项")) : qsTr("上一项")
    property string nextLabel: shell.reader
        ? (shell.reader.nextLabel || qsTr("下一项")) : qsTr("下一项")

    property var menuModel: [
        { id: "read", icon: "read", text: qsTr("朗读"), act: "read",
          enabled: shell.readEnabled, disabledReason: shell.readUnavailableReason },
        { id: "toc", icon: "toc", text: qsTr("目录"), act: "toc",
          enabled: shell.tocEnabled },
        { id: "bookmarks", icon: "bookmark", text: qsTr("书签"), act: "bookmarks",
          enabled: shell.bookmarkEnabled },
        { id: "prev", icon: "prev", text: shell.prevLabel, act: "prev",
          enabled: shell.prevEnabled },
        { id: "next", icon: "next", text: shell.nextLabel, act: "next",
          enabled: shell.nextEnabled },
        { divider: true },
        { id: "info", icon: "info", text: qsTr("图书信息"), act: "info", enabled: true }
    ]

    function openMenu() {
        shell.sheetOpen = true
        shell.menuOpen = true
        hideControlsTimer.stop()
    }
    function menuItem(id) {
        for (const m of shell.menuModel)
            if (m.id === id) return m
        return null
    }
    function triggerMenuAction(id) {
        shell.menuOpen = false
        if (!shell.reader) return
        switch (id) {
        case "read":
            // 朗读禁用项不调用适配器、不启动 TTS（TtsBar 由 Tts.state 门控不显示）。
            if (shell.readEnabled && shell.reader.startReadAloud)
                shell.reader.startReadAloud()
            break
        case "toc":
            if (shell.tocEnabled && shell.reader.openContents) shell.reader.openContents()
            break
        case "prev":
            if (shell.prevEnabled && shell.reader.previous) shell.reader.previous()
            break
        case "next":
            if (shell.nextEnabled && shell.reader.next) shell.reader.next()
            break
        case "bookmarks":
            // 统一书签管理入口；openBookmarks 为适配器可选成员（旧假适配器缺失
            // 时不调用、不崩溃）
            if (shell.bookmarkEnabled && shell.reader.openBookmarks)
                shell.reader.openBookmarks()
            break
        case "info":
            if (shell.reader.openInfo) shell.reader.openInfo()
            break
        }
    }

    signal backRequested()
    signal contentTapped(real x, real y)
    signal edgeHover(real x)

    // ---- 顶栏 ----
    KdTopToolbar {
        id: topToolbar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        visible: shell.sheetOpen
        z: 20
        bookmarked: shell.bookmarked
        onBack: shell.backRequested()
        onNotes: { if (shell.notesEnabled && shell.reader && shell.reader.openNotes) shell.reader.openNotes() }
        onBookmark: { if (shell.bookmarkEnabled && shell.reader && shell.reader.toggleBookmark) shell.reader.toggleBookmark() }
        onSearch: { if (shell.searchEnabled && shell.reader && shell.reader.openSearch) shell.reader.openSearch() }
        onMenu: shell.openMenu()
    }

    // 中央 hover：重置自动隐藏计时并转发给适配器驱动边缘热区（NoButton 不拦截点击）。
    MouseArea {
        anchors.top: shell.sheetOpen ? topToolbar.bottom : parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: shell.ttsBarVisible ? ttsBar.top : parent.bottom
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        onPositionChanged: {
            if (shell.controlsVisible) hideControlsTimer.restart()
            shell.edgeHover(mouseX)
        }
    }

    // 统一点击状态机（正文宿主桥接到本函数：y 页面坐标、x 视口坐标，可缺省）。
    // 语义对齐 ReaderPage（scroll 模式）：菜单打开 → 关闭菜单与 sheet；
    // sheet 打开 → 关闭；隐藏态 → 唤出（controlsVisible=true）。paged 边缘翻页
    // 属正文侧逻辑（ReaderContent），不迁入壳层。
    function handleTap(y, x) {
        if (shell.contentItem) shell.contentItem.forceActiveFocus()
        if (shell.menuOpen) { shell.menuOpen = false; shell.sheetOpen = false; return }
        if (shell.sheetOpen) { shell.sheetOpen = false; return }
        shell.controlsVisible = true
        shell.sheetOpen = true
        hideControlsTimer.stop()
    }

    // ---- TtsBar：仅 Tts.state != 0 显示；按钮只调用现有 Tts 方法 ----
    property bool ttsBarVisible: Tts.state !== 0
    TtsBar {
        id: ttsBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: shell.ttsBarVisible
        bgMode: shell.ttsBgMode
        onPlayClicked: Tts.play()
        onPauseClicked: Tts.pause()
        onStopClicked: Tts.stop()
        onPrevClicked: Tts.previous()
        onNextClicked: Tts.next()
        onRateChanged: (r) => { Tts.rate = r; Settings.setValue("tts/rate", r) }
        onVoiceChanged: (v) => { Tts.voice = v; Settings.setValue("tts/systemVoice", v) }
    }
    Timer {
        id: ttsErrorTimer
        interval: 4000
        onTriggered: ttsBar.errorText = ""
    }
    Connections {
        target: Tts
        function onStateChanged(state) { ttsBar.playing = state === 1 }
        function onErrorOccurred(msg) { ttsBar.errorText = msg; ttsErrorTimer.restart() }
    }

    // ---- 底部 Sheet（面板由适配器注入；Shell 只持有受控开合状态）----
    KdBottomSheet {
        id: bottomSheet
        anchors.fill: parent
        open: shell.sheetOpen
        tabs: shell.sheetTabs
        pages: shell.sheetPages
        currentId: shell.sheetTab
        onTabClicked: (id) => shell.sheetTab = id
        onMaskClicked: shell.sheetOpen = false
    }

    // ---- 菜单遮罩 ----
    Item {
        id: menuOverlay
        z: 30
        anchors.fill: parent
        visible: shell.menuOpen || opacity > 0.01
        opacity: shell.menuOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Rectangle {
            anchors.fill: parent
            color: UITheme.overlay
            MouseArea {
                anchors.fill: parent
                enabled: shell.menuOpen
                onClicked: shell.menuOpen = false
            }
        }
        Rectangle {
            id: menuPanel
            anchors.top: parent.top
            anchors.topMargin: 38
            anchors.right: parent.right
            anchors.rightMargin: 8
            width: parent.width * 0.62
            height: menuColumn.implicitHeight
            color: UITheme.bgPrimary
            border.color: UITheme.divider
            border.width: 1
            Column {
                id: menuColumn
                width: parent.width
                Repeater {
                    id: menuRepeater
                    model: shell.menuModel
                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width
                        height: modelData.divider ? 1 : 48
                        color: modelData.divider ? UITheme.divider
                                                 : (modelData.enabled && menuRowMouse.containsMouse
                                                    ? UITheme.bgSecondary : UITheme.bgPrimary)
                        MouseArea {
                            id: menuRowMouse
                            anchors.fill: parent
                            enabled: !modelData.divider && modelData.enabled !== false
                            hoverEnabled: !modelData.divider && modelData.enabled !== false
                            onClicked: shell.triggerMenuAction(modelData.act)
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 14
                            visible: !modelData.divider
                            KdIcons {
                                name: modelData.icon || "dot"
                                size: 22
                                color: modelData.enabled !== false ? UITheme.textPrimary : UITheme.textDisabled
                            }
                            Label {
                                text: modelData.text || ""
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.pixelSize: 15
                                color: modelData.enabled !== false ? UITheme.textPrimary : UITheme.textDisabled
                            }
                            // 朗读禁用原因提示
                            Label {
                                visible: modelData.id === "read" && !modelData.enabled
                                         && modelData.disabledReason
                                text: modelData.disabledReason || ""
                                color: UITheme.textSecondary
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                Layout.preferredWidth: 120
                            }
                        }
                    }
                }
            }
        }
    }

    // 焦点/StackView 激活恢复钩子：注入正文宿主后，本页成为 currentItem 时把
    // activeFocus 交还正文；仅在激活事件触发，不连续抢占（弹层/输入框打开时
    // 不会被本钩子抢焦点）。
    focus: true
    Component.onCompleted: shell.restoreContentFocus()
    // 注入方在创建后才赋值 contentItem——赋值即恢复焦点（延迟焦点路径）。
    onContentItemChanged: shell.restoreContentFocus()
    StackView.onActivated: shell.restoreContentFocus()
    function restoreContentFocus() {
        if (shell.contentItem && !shell.menuOpen && !shell.sheetOpen)
            shell.contentItem.forceActiveFocus()
    }
}
