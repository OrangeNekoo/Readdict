import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.Backend

// 阅读页主组件：背景五态（浅/深/米白/彩色墨水屏 eink/自定义图片）+ 章节渲染 + 底部控制栏 + 目录 Dialog。
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
    // C1：顶栏返回按钮（冒烟测试经此点击验证返回导航链路，同 SettingsPage.backButton 模式）
    property alias backButton: backBtn
    // C1：朗读条（冒烟测试经此断言贴底布局——y=0 即 D7 锚失效回归，见 ttsBar 锚注释）
    property alias ttsBar: ttsBar

    ReaderBackground {
        anchors.fill: parent
        mode: page.bgMode
        imagePath: page.bgImagePath
        blur: page.bgBlur
        brightness: page.bgBrightness
    }

    // B5：Kindle 化顶栏——细条极简（36px）：返回 + 书名 · 章节，去加粗装饰。
    // 颜色随背景模式：dark 深底浅字、eink 纸色底墨字、其余浅底深字。
    Rectangle {
        id: topBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 36
        color: page.bgMode === "dark" ? "#E6121212"
             : (page.bgMode === "eink" ? "#E6F2E8D5" : "#E6FFFFFF")
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
            spacing: 6
            ToolButton {
                id: backBtn
                text: qsTr("返回")
                font.pixelSize: 13
                onClicked: page.StackView.view.pop()
            }
            Label {
                id: topBarTitle
                Layout.fillWidth: true
                // D7：顶栏显示 书名 · 章节——章节标题与书名相同（TXT 单章书首章即书名）
                // 时不再重复拼接
                text: {
                    const t = page.book && page.book.title ? page.book.title : ""
                    const c = page.chapter && page.chapter.title ? page.chapter.title : ""
                    return t + (c && c !== t ? " · " + c : "")
                }
                elide: Text.ElideRight
                font.pixelSize: 13
                color: page.bgMode === "dark" ? "#CCCCCC"
                     : (page.bgMode === "eink" ? "#3A3A3A" : "#555555")
            }
        }
    }

    ReaderContent {
        id: content
        anchors.top: topBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: page.ttsBarVisible ? ttsBar.top : controlsHost.top
        chapter: page.chapter
        typography: page.typography
        // B3：正文前景色随背景模式——dark 传浅色 #E0E0E0；B5：eink 传墨色 #3A3A3A；
        // 其余（light/paper/image）视为浅底用深字 #212121（image 模式内容区域透明露出自定义图片，按浅色处理）
        bgMode: page.bgMode
        textColor: page.bgMode === "dark" ? "#E0E0E0"
                 : (page.bgMode === "eink" ? "#3A3A3A" : "#212121")
        // C7：划线上下文——bookId 供 addHighlight，highlights 供逐句渲染查表
        bookId: (page.book && page.book.id) || -1
        highlights: page.highlights
        // 规格 §7：滚动接近章末 → 自动加载下一章（末章由 autoNextChapter 兜底不换）
        onRequestNextChapter: page.autoNextChapter()
    }

    // C2：朗读条门控——朗读会话激活（Tts.state != 0 播放/暂停）才显示，否则隐藏且正文
    // 占满到底部控制栏（用户反馈 BUG ②：未点朗读却自动出现语速条）。content/hover 区
    // 锚点随本属性切换，保证隐藏时不挤占正文。
    // C3 扩展点：在此之上叠加"点底部唤出 + 5s 自动隐藏"统一显隐——如朗读会话中用户
    // 手动收起，需在本属性处引入手动隐藏覆盖（勿在 TtsBar 上另写 visible 绑定，C3 统一接管）。
    property bool ttsBarVisible: Tts.state !== 0

    // C5：朗读控制条（播放/暂停/停止/跳句/语速/音色），信号接 Tts 单例；
    // 引擎不可用时 TtsBar 内部禁用播放并显示提示。
    // C2：visible 由 page.ttsBarVisible 门控（仅朗读会话激活时显示）。
    TtsBar {
        id: ttsBar
        anchors.left: parent.left
        anchors.right: parent.right
        // C1 修复：D7 把 ReaderControls 包进 controlsHost 后，controls 不再是 ttsBar 的
        // 兄弟项，锚 controls.top 被 QML 丢弃（"Cannot anchor to an item that isn't a
        // parent or sibling"）→ ttsBar 失去纵向定位落到 y=0 压住顶栏（返回不可点）、
        // content.bottom 解析为 0（内容高度 -36 全空白）。改锚兄弟项 controlsHost.top，
        // 几何不变（controlsHost 恒 52px 贴底，可见性动画不影响布局）。
        anchors.bottom: controlsHost.top
        visible: page.ttsBarVisible
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
        // 规格 §7：朗读越过章末 → 自动换下一章并继续朗读（continueReadingFromTts）
        function onChapterCompleted(ch) { page.continueReadingFromTts(ch) }
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

    // D7：底部控制栏自动隐藏——鼠标静置 3s 淡出，移动恢复。
    // C2：朗读条不再常显（默认隐藏，仅朗读会话激活时显示，见 ttsBarVisible 门控），
    // 会话中播放/暂停/停止随时可达。opacity 动画不改变布局（内容区锚点不动，无跳动）。
    property bool controlsVisible: true

    Item {
        id: controlsHost
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 52
        opacity: page.controlsVisible ? 1.0 : 0.0
        visible: page.controlsVisible || opacity > 0.01
        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
        }
        ReaderControls {
            id: controls
            anchors.fill: parent
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
    }

    // D7：静置 3s 淡出控制栏（running 常开——滚轮/键盘翻页不动鼠标也会淡出；
    // 鼠标移动经下方 hover 追踪 restart）
    Timer {
        id: hideControlsTimer
        interval: 3000
        repeat: false
        running: true
        onTriggered: page.controlsVisible = false
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

    // 规格 §7：章末自动续章——ReaderContent 滚动接近底部触发，当前章非末章时换下一章。
    // 与手动换章（控制栏/目录）同走 loadChapter（含 Tts.stop 复位）；末章直接返回，
    // 避免 loadChapter 的钳制把读者从章尾拽回本章开头。
    function autoNextChapter() {
        const titles = Books.chapterTitles(page.book.id)
        if (!titles || Books.currentChapter + 1 >= titles.length) return
        page.loadChapter(Books.currentChapter + 1)
    }

    // 规格 §7：朗读续章——Tts.chapterCompleted（自然读完/下一句越过章末）→ 换下一章
    // 并继续朗读（新章句子已由 loadChapter 喂给 Tts，play() 从首句发声）；
    // 末章朗读结束不再自动（停在末章句尾）。
    function continueReadingFromTts(ch) {
        const titles = Books.chapterTitles(page.book.id)
        if (!titles || ch + 1 >= titles.length) return
        page.loadChapter(ch + 1)   // loadChapter 内部 Tts.stop() 复位游标
        Tts.play()                 // 新章从首句继续朗读
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
        // 五态循环（浅→米白→深→彩色墨水屏 eink→图片）；未选图片时跳过 image，
        // 避免切到"无图可显"的态
        const order = page.bgImagePath ? ["light", "paper", "dark", "eink", "image"]
                                       : ["light", "paper", "dark", "eink"]
        const cur = Math.max(0, order.indexOf(page.bgMode))
        page.bgMode = order[(cur + 1) % order.length]
        Settings.setValue("background/mode", page.bgMode)
    }

    // D5：启动恢复——从 Settings 的 background/ 分区读背景参数（含钳制）。
    // 旧版 reader/background 键的迁移在 SettingsStore 构造函数预置默认分区时完成
    //（QML 加载前），此处只读新键，不再有迁移分支。
    function backgroundFromSettings() {
        const mode = Settings.value("background/mode")
        // B5：五态含 eink
        page.bgMode = (mode === "light" || mode === "paper" || mode === "dark" || mode === "eink" || mode === "image") ? mode : "light"
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

    // D7：hover 追踪（静置计时复位）——只覆盖正文内容区（topBar 下沿 → 朗读条上沿，
    // C2 起与正文同界：朗读条隐藏时扩展到控制栏顶，该区域在隐藏时是正文），
    // 刻意排除顶栏/朗读条/控制栏：全页 NoButton hover MouseArea 会截走按钮的 hover 反馈
    //（Qt 把 hover 路由到最顶层项），限制区域后按钮 hover 高亮保留；鼠标从正文移到
    // 控制栏的过程中最后一次正文 onPositionChanged 已重置计时，按钮悬停 3s 内保持可见。
    // acceptedButtons: Qt.NoButton 不拦截任何点击（正文选择/按钮点击照常透传）。
    MouseArea {
        anchors.top: topBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: page.ttsBarVisible ? ttsBar.top : controlsHost.top
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        onPositionChanged: {
            page.controlsVisible = true
            hideControlsTimer.restart()
        }
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
