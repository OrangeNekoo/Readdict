import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.Backend

// 阅读页主组件：背景三态 + 章节渲染 + 底部控制栏 + 目录 Dialog。
// typography 由 Settings 的 typography/ 分区组合（QML 侧组合，避免跨单例依赖），
// 章节进度经 Books.currentChapter 持久化到 settings.json 的 progress/<bookId>。
Page {
    id: page
    property var book: ({})
    property var chapter: ({})
    property var typography: ({})
    property string bgMode: "light"
    property var tocTitles: []
    // B10：暴露内容视图（滚动恢复冒烟测试经此读写 contentY/contentHeight）
    property alias contentView: content

    ReaderBackground {
        anchors.fill: parent
        mode: page.bgMode
    }

    // 顶部章节条：返回 + 当前章名
    Rectangle {
        id: topBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 44
        color: page.bgMode === "dark" ? "#E6121212" : "#E6FFFFFF"
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: page.bgMode === "dark" ? "#33FFFFFF" : "#1A000000"
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 12
            spacing: 8
            ToolButton {
                text: qsTr("返回")
                onClicked: page.StackView.view.pop()
            }
            Label {
                id: topBarTitle
                Layout.fillWidth: true
                text: page.chapter.title ?? ""
                elide: Text.ElideRight
                font.bold: true
                color: page.bgMode === "dark" ? "#E6E6E6" : "#1A1A1A"
            }
        }
    }

    ReaderContent {
        id: content
        anchors.top: topBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: ttsBar.top
        chapter: page.chapter
        typography: page.typography
    }

    // C5：朗读控制条（播放/暂停/停止/跳句/语速/音色），信号接 Tts 单例；
    // 引擎不可用时 TtsBar 内部禁用播放并显示提示。
    TtsBar {
        id: ttsBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: controls.top
        bgMode: page.bgMode
        onPlayClicked: Tts.play()
        onPauseClicked: Tts.pause()
        onStopClicked: Tts.stop()
        onPrevClicked: Tts.previous()
        onNextClicked: Tts.next()
        onRateChanged: (r) => { Tts.rate = r; Settings.setValue("tts/rate", r) }
        onVoiceChanged: (v) => { Tts.voice = v; Settings.setValue("tts/voice", v) }
    }

    // C5：Tts 状态/错误同步到 TtsBar（playing 图标切换、错误提示 4 秒后消失）
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

    // B10：滚动位置每 5 秒写一次 settings.json（章节索引 + 章内偏移），
    // 离开页面时 onDestruction 再补写一次，崩溃窗口不超过 5 秒。
    Timer {
        id: scrollSaveTimer
        interval: 5000
        repeat: true
        running: true
        onTriggered: page.saveScroll()
    }

    ReaderControls {
        id: controls
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        bgMode: page.bgMode
        fontSize: page.typography.fontSize ?? 18
        onPrevChapter: page.loadChapter(Books.currentChapter - 1)
        onNextChapter: page.loadChapter(Books.currentChapter + 1)
        onChangeFontSize: (size) => page.setFontSize(size)
        onToggleBackground: page.cycleBackground()
        onToggleAlign: page.cycleAlign()
        onTogglePageWidth: page.cyclePageWidth()
        onOpenToc: tocDialog.open()
    }

    Dialog {
        id: tocDialog
        title: qsTr("目录")
        modal: true
        standardButtons: Dialog.Close
        width: 380
        height: 480
        contentItem: ListView {
            id: tocList
            clip: true
            model: page.tocTitles
            delegate: ItemDelegate {
                width: ListView.view.width
                text: modelData
                highlighted: ListView.isCurrentItem
                onClicked: {
                    page.loadChapter(index)
                    tocDialog.close()
                }
            }
            ScrollBar.vertical: ScrollBar {}
        }
        onOpened: {
            page.tocTitles = Books.chapterTitles(page.book.id)
            tocList.currentIndex = Books.currentChapter
        }
    }

    // 从 Settings 组合排版参数；fontFamily 经 Books.resolveFontFamily 映射到已安装字族
    function typographyFromSettings() {
        return {
            fontFamily: Books.resolveFontFamily(Settings.value("typography/fontFamily") || "思源黑体 VF"),
            fontSize: Settings.value("typography/fontSize") || 18,
            lineHeight: Settings.value("typography/lineHeight") || 1.6,
            align: Settings.value("typography/align") || "left",
            pageWidth: Settings.value("typography/pageWidth") || "normal"
        }
    }

    function loadChapter(i) {
        if (!page.book || !page.book.id) return
        const titles = Books.chapterTitles(page.book.id)
        if (!titles || titles.length === 0) return
        i = Math.max(0, Math.min(i, titles.length - 1))
        page.chapter = Books.loadChapter(page.book.id, i)
        Books.currentChapter = i   // 写时持久化 progress/<bookId>
        // C5：拍平本段全部段落句子喂给 Tts（顺序与 ReaderContent 的 sentenceStarts 一致），
        // 换章复位游标 → 高亮回到首句；Tts.currentIndex 驱动逐句高亮与滚动跟随。
        const all = []
        for (const p of (page.chapter.paragraphs ?? []))
            for (const s of (p.sentences ?? [])) all.push(s)
        Tts.setSentences(all)
        Tts.setChapter(i)
    }

    function setFontSize(size) {
        size = Math.max(12, Math.min(32, size))
        Settings.setValue("typography/fontSize", size)
        page.typography = page.typographyFromSettings()
    }

    function cycleAlign() {
        const order = ["left", "center", "right"]
        const cur = Math.max(0, order.indexOf(page.typography.align ?? "left"))
        Settings.setValue("typography/align", order[(cur + 1) % order.length])
        page.typography = page.typographyFromSettings()
    }

    function cyclePageWidth() {
        const order = ["narrow", "normal", "wide"]
        const cur = Math.max(0, order.indexOf(page.typography.pageWidth ?? "normal"))
        Settings.setValue("typography/pageWidth", order[(cur + 1) % order.length])
        page.typography = page.typographyFromSettings()
    }

    function cycleBackground() {
        const order = ["light", "paper", "dark"]
        const cur = Math.max(0, order.indexOf(page.bgMode))
        page.bgMode = order[(cur + 1) % order.length]
        Settings.setValue("reader/background", page.bgMode)
    }

    // B10：滚动偏移持久化（章节 + contentY 原子写入，恢复时先 loadChapter 再设 scrollY）
    function saveScroll() {
        if (!page.book || !page.book.id) return
        // 恢复未应用前 contentY 仍是 0：此刻写入会把已保存位置覆盖为 0
        //（含图章章节的收敛窗口内退出即丢位置），跳过本次保存
        if (content.restorePending) return
        Books.savePosition(page.book.id, Books.currentChapter, content.contentY)
    }

    Component.onCompleted: {
        page.typography = page.typographyFromSettings()
        const bg = Settings.value("reader/background")
        page.bgMode = (bg === "light" || bg === "paper" || bg === "dark") ? bg : "light"
        // 恢复：定位到保存的章节（progress/<bookId>），滚动偏移交给 ReaderContent
        // 在内容高度就绪后设置（progress/scroll_<bookId>）
        page.loadChapter(Books.lastChapter(page.book.id))
        content.restoreScrollY = Books.lastScrollY(page.book.id)
        if (page.book && page.book.id)
            Books.startTracking(page.book.id)  // 阅读计时开始
    }

    Component.onDestruction: {
        page.saveScroll()          // 离开页面补写滚动位置
        Books.stopTracking()       // 结算阅读秒数
    }
}
