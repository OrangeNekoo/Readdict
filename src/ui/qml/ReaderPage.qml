import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.Backend

// 阅读页主组件：背景四态（浅/深/米白/自定义图片）+ 章节渲染 + 底部控制栏 + 目录 Dialog。
// typography 由 Settings 的 typography/ 分区组合（QML 侧组合，避免跨单例依赖），
// 背景由 Settings 的 background/ 分区恢复（mode/imagePath/blur/brightness，onCompleted 读取；
// Settings.value 无变更信号，页面属性作响应层，与 typography 同模式）；
// 章节进度经 Books.currentChapter 持久化到 settings.json 的 progress/<bookId>。
Page {
    id: page
    property var book: ({})
    property var chapter: ({})
    property var typography: ({})
    property string bgMode: "light"          // 与 Settings background/mode 同步
    property string bgImagePath: ""          // background/imagePath（图片背景）
    property real bgBlur: 0.0                // background/blur（0..1）
    property real bgBrightness: 1.0          // background/brightness（0.5..1.5）
    property var tocTitles: []
    // C7：本书全部划线（Highlights.highlightsForBook 结果，供渲染注入与笔记列表）
    property var highlights: []
    // B10：暴露内容视图（滚动恢复冒烟测试经此读写 contentY/contentHeight）
    property alias contentView: content
    // C7：笔记列表 Dialog（冒烟测试经此打开/关闭）
    property alias notesDialog: notesDlg
    // C8：全文搜索结果跳转目标（书架全文搜索 push 时传入；-1 表示正常打开）。
    // 打开后 loadChapter(initialChapter) 并滚动到 initialParagraph，跳过滚动恢复。
    property int initialChapter: -1
    property int initialParagraph: -1
    // C8：书内搜索 Dialog（冒烟测试经此打开/关闭）
    property alias searchDialog: searchDlg

    ReaderBackground {
        anchors.fill: parent
        mode: page.bgMode
        imagePath: page.bgImagePath
        blur: page.bgBlur
        brightness: page.bgBrightness
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
        // C7：划线上下文——bookId 供 addHighlight，highlights 供逐句渲染查表
        bookId: (page.book && page.book.id) || -1
        highlights: page.highlights
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
        onOpenNotes: notesDlg.open()
        onOpenSearch: searchDlg.open()
    }

    // C7：划线增删改（addHighlight/removeHighlight/updateNote）后从 Highlights 重载，
    // 驱动 content.highlights → 逐句重渲染
    Connections {
        target: Highlights
        function onHighlightsChanged(bookId) {
            if (page.book && bookId === page.book.id)
                page.reloadHighlights()
        }
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

    // C7：笔记列表（侧滑面板形态的 Dialog）——列出本书全部划线（章节/文本/笔记），
    // 点击跳转该句；支持编辑笔记与删除划线
    Dialog {
        id: notesDlg
        title: qsTr("笔记") + "（" + page.highlights.length + "）"
        modal: true
        standardButtons: Dialog.Close
        width: 480
        height: 540
        contentItem: ListView {
            id: notesList
            clip: true
            model: page.highlights
            delegate: Rectangle {
                width: ListView.view.width
                height: bodyCol.implicitHeight + 18
                color: index % 2 === 0 ? "#0A000000" : "transparent"
                Column {
                    id: bodyCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Row {
                        spacing: 6
                        Rectangle {
                            width: 10
                            height: 10
                            radius: 5
                            color: modelData.color || "#CCCCCC"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Label {
                            text: modelData.chapter || ""
                            font.pixelSize: 12
                            color: "#888888"
                        }
                    }
                    Label {
                        text: (modelData.text || "").slice(0, 80)
                        elide: Text.ElideRight
                        font.pixelSize: 14
                    }
                    Label {
                        text: modelData.note ? qsTr("笔记：") + modelData.note : qsTr("（无笔记）")
                        font.pixelSize: 12
                        color: modelData.note ? "#555555" : "#AAAAAA"
                        wrapMode: Text.Wrap
                    }
                    Row {
                        spacing: 12
                        Button {
                            text: qsTr("跳转")
                            font.pixelSize: 12
                            onClicked: page.jumpToHighlight(modelData)
                        }
                        Button {
                            text: qsTr("编辑")
                            font.pixelSize: 12
                            onClicked: {
                                editNoteDlg.targetId = modelData.id
                                editNoteArea.text = modelData.note || ""
                                editNoteDlg.open()
                            }
                        }
                        Button {
                            text: qsTr("删除")
                            font.pixelSize: 12
                            onClicked: Highlights.removeHighlight(modelData.id)
                        }
                    }
                }
            }
            ScrollBar.vertical: ScrollBar {}
        }
        onOpened: page.reloadHighlights()
    }

    // C7：编辑笔记 Dialog
    Dialog {
        id: editNoteDlg
        title: qsTr("编辑笔记")
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        width: 380
        height: 250
        property int targetId: -1
        contentItem: ColumnLayout {
            spacing: 12
            Label {
                text: qsTr("修改这条划线的笔记：")
                color: "#555555"
            }
            TextArea {
                id: editNoteArea
                Layout.fillWidth: true
                Layout.preferredHeight: 130
                placeholderText: qsTr("写下你的想法…")
                wrapMode: TextEdit.Wrap
            }
        }
        onAccepted: {
            if (editNoteDlg.targetId > 0)
                Highlights.updateNote(editNoteDlg.targetId, editNoteArea.text)
        }
    }

    // C8：书内搜索 Dialog——输入即查本书全文（Search.searchModel），
    // 结果列表（章节/摘要），点击 loadChapter + 滚动到命中段。
    Dialog {
        id: searchDlg
        title: qsTr("书内搜索")
        modal: true
        standardButtons: Dialog.Close
        width: 480
        height: 520
        property var hits: []
        contentItem: ColumnLayout {
            spacing: 8
            TextField {
                id: searchInput
                Layout.fillWidth: true
                placeholderText: qsTr("输入关键词…")
                // 防抖：输入停止 250ms 后才查 FTS
                onTextChanged: searchDlgDebounce.restart()
            }
            Timer {
                id: searchDlgDebounce
                interval: 250
                repeat: false
                onTriggered: {
                    searchDlg.hits = (page.book && page.book.id)
                        ? Search.searchModel(page.book.id, searchInput.text) : []
                }
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: searchDlg.hits
                delegate: ItemDelegate {
                    width: ListView.view.width
                    onClicked: {
                        page.jumpToSearchHit(modelData)
                        searchDlg.close()
                    }
                    contentItem: Column {
                        spacing: 2
                        Label {
                            text: (modelData.chapterTitle || qsTr("无标题"))
                                  + " · " + qsTr("第%1段").arg((modelData.paragraphIndex ?? 0) + 1)
                            font.pixelSize: 12
                            color: "#888888"
                        }
                        Label {
                            text: modelData.snippet || ""
                            elide: Text.ElideRight
                        }
                    }
                }
                ScrollBar.vertical: ScrollBar {}
            }
        }
        onOpened: {
            searchInput.text = ""
            searchDlg.hits = []
        }
    }

    // C7：跳转——定位到划线所在章并滚动/闪烁该句（120ms 等章节委托就绪）
    Timer {
        id: jumpTimer
        interval: 120
        repeat: false
        onTriggered: {
            content.flashSentence(jumpTimer.targetIndex)
            content.followSentence(jumpTimer.targetIndex)
        }
        property int targetIndex: -1
    }

    // C8：全文搜索跳转——章节切换后等段落委托就绪再滚动到目标段
    Timer {
        id: paraJumpTimer
        interval: 120
        repeat: false
        onTriggered: content.scrollToParagraph(paraJumpTimer.targetIndex)
        property int targetIndex: -1
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
        // C5：换章先停朗读——否则旧章在途 finished 会在 setSentences 复位游标后
        // 触发 next() 把游标推到 1，导致新章从第 2 句开始（首句被跳过）
        Tts.stop()
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
        // 四态循环（浅→米白→深→图片）；未选图片时跳过 image，避免切到"无图可显"的态
        const order = page.bgImagePath ? ["light", "paper", "dark", "image"]
                                       : ["light", "paper", "dark"]
        const cur = Math.max(0, order.indexOf(page.bgMode))
        page.bgMode = order[(cur + 1) % order.length]
        Settings.setValue("background/mode", page.bgMode)
    }

    // D5：启动恢复——从 Settings 的 background/ 分区读四态背景参数（含钳制）。
    // 旧版本写的是 reader/background 键（三态），新键缺失时迁移并持久化，
    // 否则设置页（读 background/mode）与阅读页（读旧键）显示不一致。
    function backgroundFromSettings() {
        let mode = Settings.value("background/mode")
        if (mode !== "light" && mode !== "paper" && mode !== "dark" && mode !== "image") {
            const legacy = Settings.value("reader/background")
            mode = (legacy === "light" || legacy === "paper" || legacy === "dark") ? legacy : "light"
            Settings.setValue("background/mode", mode)
        }
        page.bgMode = mode
        page.bgImagePath = Settings.value("background/imagePath") || ""
        const blur = Number(Settings.value("background/blur")) || 0.0
        page.bgBlur = Math.max(0, Math.min(1, blur))
        const bright = Number(Settings.value("background/brightness")) || 1.0
        page.bgBrightness = Math.max(0.5, Math.min(1.5, bright))
    }

    // B10：滚动偏移持久化（章节 + contentY 原子写入，恢复时先 loadChapter 再设 scrollY）
    function saveScroll() {
        if (!page.book || !page.book.id) return
        // 恢复未应用前 contentY 仍是 0：此刻写入会把已保存位置覆盖为 0
        //（含图章章节的收敛窗口内退出即丢位置），跳过本次保存
        if (content.restorePending) return
        Books.savePosition(page.book.id, Books.currentChapter, content.contentY)
    }

    // C7：从 Highlights 加载本书全部划线（打开阅读页/划线变更/笔记列表打开时调用）
    function reloadHighlights() {
        if (!page.book || !page.book.id) return
        page.highlights = Highlights.highlightsForBook(page.book.id)
    }

    // C8：书内搜索跳转——按索引定位章节（标题可能重复/为空，索引最可靠），
    // loadChapter 后滚动到命中段
    function jumpToSearchHit(hit) {
        if (!hit || hit.chapterIndex === undefined || hit.paragraphIndex === undefined) return
        page.loadChapter(hit.chapterIndex)
        paraJumpTimer.targetIndex = hit.paragraphIndex
        paraJumpTimer.restart()
    }

    // C8：外部（书架全文搜索入口）定位——同一跳转路径，供 initial* 属性复用
    function jumpToChapterParagraph(ci, pi) {
        page.loadChapter(ci)
        paraJumpTimer.targetIndex = pi
        paraJumpTimer.restart()
    }

    // C7：笔记列表跳转——按章节标题定位章索引，loadChapter 后滚动/闪烁目标句
    function jumpToHighlight(hl) {
        if (!hl || hl.sentenceIndex === undefined || hl.sentenceIndex < 0) return
        const titles = Books.chapterTitles(page.book.id)
        const ci = titles.indexOf(hl.chapter)
        if (ci < 0) return
        notesDlg.close()
        page.loadChapter(ci)
        jumpTimer.targetIndex = hl.sentenceIndex
        jumpTimer.restart()
    }

    Component.onCompleted: {
        page.typography = page.typographyFromSettings()
        page.backgroundFromSettings()
        // 恢复：定位到保存的章节（progress/<bookId>），滚动偏移交给 ReaderContent
        // 在内容高度就绪后设置（progress/scroll_<bookId>）。
        // C8：全文搜索跳转打开时（initialChapter/initialParagraph >= 0）改用目标章节，
        // 并跳过滚动恢复（恢复会覆盖跳转位置）；段落滚动由 paraJumpTimer 完成。
        const initChapter = page.initialChapter >= 0
            ? page.initialChapter : Books.lastChapter(page.book.id)
        page.loadChapter(initChapter)
        if (page.initialParagraph >= 0) {
            paraJumpTimer.targetIndex = page.initialParagraph
            paraJumpTimer.restart()
        } else {
            content.restoreScrollY = Books.lastScrollY(page.book.id)
        }
        if (page.book && page.book.id) {
            page.reloadHighlights()   // C7：重新进入阅读页加载本书全部划线
            Books.startTracking(page.book.id)  // 阅读计时开始
        }
    }

    Component.onDestruction: {
        page.saveScroll()          // 离开页面补写滚动位置
        Books.stopTracking()       // 结算阅读秒数
    }
}
