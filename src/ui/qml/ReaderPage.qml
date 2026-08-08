import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.Backend
import Readdict.UI 1.0

// 阅读页主组件：背景四态（浅/深/米白/自定义图片）+ 章节渲染 + 底部控制栏 + 目录 Dialog。
// typography 由 Settings 的 typography/ 分区组合（QML 侧组合，避免跨单例依赖），
// 背景由 Settings 的 background/ 分区恢复（mode/imagePath/blur/brightness，onCompleted 读取；
// Settings.value 无变更信号，页面属性作响应层，与 typography 同模式）；
// 章节进度经 Books.currentChapter 持久化到 settings.json 的 progress/<bookId>。
Page {
    id: page
    // U2：沉浸页标识（Main 据此隐藏标签/底部导航；返回后恢复）
    property string navId: "reader"
    // E4：阅读页获得键盘焦点——StackView push 时焦点随 currentItem 交给本页，
    // 页内 focus:true 的 ReaderContent（Flickable）获得 activeFocus 接收方向键；
    // 弹层/Dialog 打开时焦点在弹层内，正文 Keys 不触发（不干扰输入框）。
    focus: true
    property var book: ({})
    property var chapter: ({})
    property var typography: ({})
    property string bgMode: "light"          // 与 Settings background/mode 同步
    property string bgImagePath: ""          // background/imagePath（图片背景）
    property real bgBlur: 0.0                // background/blur（0..1）
    property real bgBrightness: 1.0          // background/brightness（0.5..1.5）
    // E4：翻页方式——"scroll"（竖滚连续，默认）/ "paged"（横翻整页）。
    // 由 Settings 的 reading/pageMode 读取（onCompleted），注入 ReaderContent
    // 驱动方向键分流与页边界吸附；设置页"阅读背景"卡可切换（写 reading/pageMode）。
    property string pageMode: "scroll"
    // L4（P0#5）：解析失败错误占位——loadChapter 返回 {error} 时置本属性，
    // 内容区显示居中错误 Label + 重试按钮；正常加载清空（样式 U 阶段再对齐）
    property string loadError: ""
    property int loadErrorIndex: 0   // 重试目标章索引（失败章，重试重调 loadChapter）
    property var tocTitles: []
    // C7：本书全部划线（Highlights.highlightsForBook 结果，供渲染注入与笔记列表）
    property var highlights: []
    // B10：暴露内容视图（滚动恢复冒烟测试经此读写 contentY/contentHeight）
    property alias contentView: content
    // C7：笔记列表 Dialog（冒烟测试经此打开/关闭）
    property alias notesDialog: notesDlg
    // U4：Kindle 底部 Sheet 工具栏——点屏幕中部/边缘弹出（Kindle 语义：Sheet 本身
    // 含操作，无需 5s 隐藏；Sheet 打开时暂停控制栏计时）；C3 控制栏保留为快捷条
    //（上/下章、A±、朗读），唤出整合见 handleContentTap 注释与 task-U4-report。
    property bool sheetOpen: false
    property string sheetTab: "theme"
    property bool menuOpen: false
    // U4：MoreSheet 开关——自动续章（reading/autoContinue，默认开，门控
    // autoNextChapter）与深色跟随（reading/darkFollow，默认关，effectiveBg 派生
    // 跟随应用主题深浅，覆盖显式背景选择；关闭后还原显式选择——page.bgMode 未被覆盖）
    property bool autoContinue: true
    property bool darkFollow: false
    // U4：当前字族存储 token（FontSheet 高亮/选择；setFontFamily 同步更新，
    // 与 controls.fontFamily 同源——Settings typography/fontFamily）
    property string fontFamily: ""
    // U4：有效背景模式——darkFollow 开时跟随应用主题（UITheme.isDark 实时绑定），
    // 否则显式选择（bgMode）；驱动背景渲染/顶栏/控制栏/朗读条的文字与底色
    property string effectiveBg: page.darkFollow
        ? (UITheme.isDark ? "dark" : "light") : page.bgMode
    // U4：测试句柄（冒烟经此驱动 Sheet 开合/标签/面板与右上角菜单）
    property alias bottomSheet: bottomSheet
    property alias readerMenu: menuOverlay
    property alias menuItems: menuRepeater
    // U4：控制栏自动隐藏计时器（冒烟断言 Sheet 开合对计时的暂停/恢复）
    property alias hideTimer: hideControlsTimer

    // C8：全文搜索结果跳转目标（书架全文搜索 push 时传入；-1 表示正常打开）。
    // 打开后 loadChapter(initialChapter) 并滚动到 initialParagraph，跳过滚动恢复。
    property int initialChapter: -1
    property int initialParagraph: -1
    // C8：书内搜索 Dialog（冒烟测试经此打开/关闭）
    property alias searchDialog: searchDlg
    // U4：目录 Dialog（右上角菜单/MoreSheet 入口冒烟经此断言打开）
    property alias tocDlg: tocDialog
    // C1：顶栏返回按钮（冒烟测试经此点击验证返回导航链路，同 SettingsPage.backButton 模式）
    property alias backButton: backBtn
    // C1：朗读条（冒烟测试经此断言贴底布局——y=0 即 D7 锚失效回归，见 ttsBar 锚注释）
    property alias ttsBar: ttsBar
    // C2：控制栏朗读按钮（冒烟测试经此点击启动朗读会话——TtsBar 门控后的唯一启动入口）
    property alias readAloudButton: controls.readAloudBtn
    // D4：控制栏字体弹层句柄（冒烟经此打开弹层/驱动字体切换）
    property alias fontPopup: controls.fontPopup
    property alias fontList: controls.fontList
    // E3：控制栏本体（冒烟经此按 children 索引点按钮）+ 三个上拉框句柄
    property alias controlsBar: controls
    property alias bgPopup: controls.bgPopup
    property alias bgList: controls.bgList
    property alias alignPopup: controls.alignPopup
    property alias alignList: controls.alignList
    property alias widthPopup: controls.widthPopup
    property alias widthList: controls.widthList

    ReaderBackground {
        anchors.fill: parent
        mode: page.effectiveBg
        imagePath: page.bgImagePath
        blur: page.bgBlur
        brightness: page.bgBrightness
    }

    // B5：Kindle 化顶栏——细条极简（36px）：返回 + 书名 · 章节，去加粗装饰。
    // 颜色随背景模式：dark 深底浅字、其余浅底深字。
    Rectangle {
        id: topBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 36
        color: page.effectiveBg === "dark" ? "#E6121212" : "#E6FFFFFF"
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: page.effectiveBg === "dark" ? "#33FFFFFF" : "#1A000000"
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
                color: page.effectiveBg === "dark" ? "#CCCCCC" : "#555555"
            }
            // U4：右上角菜单入口（§5：点击弹出下拉菜单 + 遮罩）——"⋯" 三点按钮
            ToolButton {
                id: menuBtn
                text: "⋯"
                font.pixelSize: 18
                padding: 4
                onClicked: page.menuOpen = !page.menuOpen
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
        // B3：正文前景色随背景模式——dark 传 Kindle 深色系浅字（darkTextPrimary
        // #E8E8E3）；其余（light/paper/image）视为浅底用暖白系深字（lightTextPrimary
        // #1A1A1A，image 模式内容区域透明露出自定义图片，按浅色处理）。
        // U1：两色均引用 UITheme Token（原 #E0E0E0/#212121）。
        // U4：随 effectiveBg（darkFollow 开时跟随主题深浅）
        textColor: page.effectiveBg === "dark" ? UITheme.darkTextPrimary : UITheme.lightTextPrimary
        // C7：划线上下文——bookId 供 addHighlight，highlights 供逐句渲染查表
        bookId: (page.book && page.book.id) || -1
        highlights: page.highlights
        // L5（P0#6）：当前章 1 起索引随翻章更新（currentChapter 由 loadChapter 写），
        // addHighlight 末参——划线按阅读顺序跨章排序
        chapterIndex: Books.currentChapter + 1
        // E4：翻页方式（方向键分流 + 页边界吸附）
        pageMode: page.pageMode
        // 规格 §7：滚动接近章末 → 自动加载下一章（末章由 autoNextChapter 兜底不换）
        onRequestNextChapter: page.autoNextChapter()
        // E4：方向键 ← 翻上一章（autoPrevChapter：首章兜底不换，同 autoNextChapter 对称；
        // paged 模式 pagePrev 在章首 contentY=0 时发本信号，见 E4 复审）
        onRequestPrevChapter: page.autoPrevChapter()
    }

    // L4（P0#5）：解析失败错误占位——loadError 非空时盖住内容区：居中错误文案
    //（UITheme.danger）+ 重试按钮（重调 loadChapter）。最小实现，样式 U 阶段对齐。
    Item {
        id: loadErrorHost
        anchors.fill: content
        visible: page.loadError.length > 0
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 12
            Label {
                Layout.maximumWidth: loadErrorHost.width - 48
                text: page.loadError
                color: UITheme.danger
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
            Button {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("重试")
                onClicked: page.loadChapter(page.loadErrorIndex)
            }
        }
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
        bgMode: page.effectiveBg
        onPlayClicked: Tts.play()
        onPauseClicked: Tts.pause()
        onStopClicked: Tts.stop()
        onPrevClicked: Tts.previous()
        onNextClicked: Tts.next()
        onRateChanged: (r) => { Tts.rate = r; Settings.setValue("tts/rate", r) }
        // L7（P1#15）：音色键按引擎拆分；TtsBar 音色下拉仅系统引擎有列表（Tts.voices），写 tts/systemVoice
        onVoiceChanged: (v) => { Tts.voice = v; Settings.setValue("tts/systemVoice", v) }
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

    // C3：底部控制栏显隐框架——点击正文底部 1/4 唤出；5s 无操作淡出隐藏
    // （用户反馈 BUG ⑤：D7 的 hover 恢复在隐藏后无法唤出，改点击唤出）。
    // 鼠标移动/轻点只重置 5s 计时（不再唤出），隐藏后计时停止。
    // opacity 动画不改变布局（内容区锚点不动，无跳动）。
    // C2 协同决策：本框架只作用于控制栏；TtsBar 显隐仍由 ttsBarVisible
    // （C2 门控，state!=0 显示）单独决定，唤出不带出、隐藏不影响朗读条
    // （朗读中暂停/停止随时可达）。见 task-C3-report。
    property bool controlsVisible: true
    // C3：无操作自动隐藏延迟（ms）——冒烟测试注入短间隔收敛 5s 语义
    property int controlsHideDelay: 5000
    // C5：阅读进度（0..1，章节粒度）——驱动控制栏底部 Kindle 式进度细条与
    // 百分比；按章节序（currentChapter+1）/总章数，末章封顶 1（与书架进度条
    // 同语义：读完即满）。无书/无章节信息时为 0。
    property real chapterProgress: {
        const id = page.book ? page.book.id : -1
        if (id <= 0) return 0
        // L6（P1#14）：改读 Books.chapterCount 缓存（chapterTitles/loadChapter 已解析本书
        // 时直接命中；绑定随 currentChapter 变更重算，不再每次构造完整标题列表）
        const n = Books.chapterCount(id)
        return n > 0 ? Math.min(1, (Books.currentChapter + 1) / n) : 0
    }

    Item {
        id: controlsHost
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        // C5：46px 与 TtsBar 同高——控制栏更细条（Kindle 底部工具栏为细条），
        // tst_readerpage 的几何断言（正文高 = 总高 - 36 顶栏 - 46 控制栏）同步更新
        height: 46
        opacity: page.controlsVisible ? 1.0 : 0.0
        visible: page.controlsVisible || opacity > 0.01
        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
        }
        ReaderControls {
            id: controls
            anchors.fill: parent
            bgMode: page.effectiveBg
            fontSize: page.typography.fontSize ?? 18
            chapterProgress: page.chapterProgress
            // E3：当前值注入——bgImagePath 驱动上拉框 image 项启用态，
            // align/pageWidth 驱动高亮当前项（Settings 无变更信号，页面属性作响应层）
            bgImagePath: page.bgImagePath
            align: page.typography.align ?? "left"
            pageWidth: page.typography.pageWidth ?? "normal"
            // D4：当前字族（存储 token）——打开弹层时经 onFontMenuOpenChanged 重读刷新
            fontFamily: String(Settings.value("typography/fontFamily") || "思源宋体 VF")
            onPrevChapter: page.loadChapter(Books.currentChapter - 1)
            onNextChapter: page.loadChapter(Books.currentChapter + 1)
            onChangeFontSize: (size) => page.setFontSize(size)
            // E3：上拉框直接选择——不再轮询循环
            onSetBackgroundMode: (m) => page.setBackgroundMode(m)
            onSetAlign: (a) => page.setAlign(a)
            onSetPageWidth: (w) => page.setPageWidth(w)
            onOpenToc: tocDialog.open()
            onOpenNotes: notesDlg.open()
            onOpenSearch: searchDlg.open()
            // C2：朗读入口——无会话/已暂停时启动（播放中忽略，TtsBar 已显示）；
            // Tts.play 对暂停态恢复、对空闲态开播，会话激活后 TtsBar 随门控显示
            onReadAloud: { if (Tts.state !== 1) Tts.play() }
            // D4：字体切换——写 typography/fontFamily 并立即刷新排版（见 setFontFamily）
            onSetFontFamily: (value) => page.setFontFamily(value)
            // D4：弹层开合联动——打开时暂停控制栏 5s 自动隐藏（弹层是独立窗口，
            // 其内点击不会重置页面 hideControlsTimer，不暂停会弹层开着控制栏就淡出）；
            // 关闭且控制栏显示态时恢复计时。同时重读 Settings 刷新弹层高亮
            //（Settings 无变更信号，靠打开时重读保证刚切换过的字体仍高亮正确）。
            onFontMenuOpenChanged: {
                if (controls.fontMenuOpen) {
                    hideControlsTimer.stop()
                    controls.fontFamily = String(Settings.value("typography/fontFamily") || "思源宋体 VF")
                } else if (page.controlsVisible) {
                    hideControlsTimer.restart()
                }
            }
            // E3：上拉框开合联动——任一打开暂停 5s 自动隐藏（同 fontMenuOpen 语义：
            // 弹层是独立窗口，其内点击不重置页面计时器）；全部关闭且控制栏显示态时恢复
            onSheetOpenChanged: {
                if (controls.sheetOpen) {
                    hideControlsTimer.stop()
                } else if (page.controlsVisible) {
                    hideControlsTimer.restart()
                }
            }
        }
    }

    // C3：无操作 5s 自动隐藏控制栏——显示后启动、隐藏后停止（running 不绑定声明式
    // 表达式：restart()/start() 的命令式写入会与绑定纠缠，改由 onControlsVisibleChanged
    // 显式启停，状态单一）。计时重置入口：正文 hover 移动（下方 MouseArea）、
    // 任意轻点（下方 TapHandler）。
    Timer {
        id: hideControlsTimer
        interval: page.controlsHideDelay
        repeat: false
        running: false
        onTriggered: page.controlsVisible = false
    }
    onControlsVisibleChanged: {
        if (page.controlsVisible) hideControlsTimer.start()
        else hideControlsTimer.stop()
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

    // L8（P1#18）：同步成功应用远端划线后重载本书划线——SyncManager 直连
    // readdict_sync 连接写库，Highlights 单例（readdict_highlights 连接）的
    // highlightsChanged 不会触发，经 Sync.dataApplied 信号驱动刷新
    Connections {
        target: Sync
        function onDataApplied() { page.reloadHighlights() }
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
                            color: modelData.color || UITheme.borderDefault
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Label {
                            text: modelData.chapter || ""
                            font.pixelSize: 12
                            color: UITheme.textSecondary
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
                        // U6：正文→textSecondary、占位→textDisabled（原硬编码 #555555/#AAAAAA）
                        color: modelData.note ? UITheme.textSecondary : UITheme.textDisabled
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
                color: UITheme.textSecondary
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
                            color: UITheme.textSecondary
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
            fontFamily: Books.resolveFontFamily(Settings.value("typography/fontFamily") || "思源宋体 VF"),
            fontSize: Settings.value("typography/fontSize") || 18,
            lineHeight: Settings.value("typography/lineHeight") || 1.6,
            align: Settings.value("typography/align") || "left",
            pageWidth: Settings.value("typography/pageWidth") || "normal"
        }
    }

    function loadChapter(i) {
        if (!page.book || !page.book.id) return
        const titles = Books.chapterTitles(page.book.id)
        if (!titles || titles.length === 0) {
            // L4（P0#5）：无章节——探测解析错误（全书解析失败的书 titles 为空，
            // 若不探测则错误占位永无显示机会）；空文档无错误维持旧行为直接返回
            const probe = Books.loadChapter(page.book.id, 0)
            if (probe && probe.error) {
                page.loadError = probe.error
                page.loadErrorIndex = 0
                page.chapter = ({})
            }
            return
        }
        i = Math.max(0, Math.min(i, titles.length - 1))
        // C5：换章先停朗读——否则旧章在途 finished 会在 setSentences 复位游标后
        // 触发 next() 把游标推到 1，导致新章从第 2 句开始（首句被跳过）
        Tts.stop()
        const loaded = Books.loadChapter(page.book.id, i)
        // L4（P0#5）：解析失败上抛 {error} → 置 loadError 显示错误占位（重试经
        // loadErrorIndex 重调本函数）；空文档无错误维持旧行为空 map 渲染
        if (loaded && loaded.error) {
            page.loadError = loaded.error
            page.loadErrorIndex = i
            page.chapter = ({})
            return
        }
        page.loadError = ""
        page.chapter = loaded
        Books.currentChapter = i   // 写时持久化 progress/<bookId>
        // L6（P1#13）：章节加载成功后上报书架进度——reportProgress 取 max 不 regress：
        // 前进刷新 progress 与书架，回翻只刷 last_read_at（不 emit，书架模型不重建）
        Books.reportProgress(page.book.id, i + 1, Books.chapterCount(page.book.id))
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
    // U4：自动续章开关（MoreSheet/reading/autoContinue）——关时滚动触底不换章
    function autoNextChapter() {
        if (!page.autoContinue) return
        const titles = Books.chapterTitles(page.book.id)
        if (!titles || Books.currentChapter + 1 >= titles.length) return
        page.loadChapter(Books.currentChapter + 1)
    }

    // E4 复审：paged 模式 ← 章首回上一章——ReaderContent.pagePrev 在 contentY=0
    // 时请求翻上一章（与 pageNext 章末翻章对称，修复"章首 ← 死键"）；首章直接
    // 返回，避免 loadChapter 的钳制把读者从章首重载回本章开头。
    function autoPrevChapter() {
        const titles = Books.chapterTitles(page.book.id)
        if (!titles || Books.currentChapter - 1 < 0) return
        page.loadChapter(Books.currentChapter - 1)
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

    // D4：正文字体切换——写 typography/fontFamily（存储 token，Books.resolveFontFamily
    // 在 typographyFromSettings 内映射到已安装字族）。Settings 无变更信号，与
    // setFontSize 同模式：写后重组合 typography 属性 → ReaderContent 的
    // font.family 绑定即时重渲染，无需重开阅读页。
    function setFontFamily(family) {
        Settings.setValue("typography/fontFamily", family)
        page.fontFamily = family
        page.typography = page.typographyFromSettings()
    }

    // U4：Sheet 方向选择——写 reading/pageMode 并即时生效（pageMode 注入
    // ReaderContent 驱动方向键分流与页边界吸附；设置页同键，双入口一致）
    function setPageMode(m) {
        if (m !== "scroll" && m !== "paged") return
        Settings.setValue("reading/pageMode", m)
        page.pageMode = m
    }

    // U4：Sheet 行间距选择——写 typography/lineHeight 并重组合排版
    function setLineHeight(lh) {
        lh = Math.max(1.2, Math.min(2.4, Number(lh) || 1.6))
        Settings.setValue("typography/lineHeight", lh)
        page.typography = page.typographyFromSettings()
    }

    // U4：自动续章开关——写 reading/autoContinue（门控 autoNextChapter）
    function setAutoContinue(on) {
        page.autoContinue = !!on
        Settings.setValue("reading/autoContinue", page.autoContinue)
    }

    // U4：深色跟随开关——写 reading/darkFollow（effectiveBg 派生跟随应用主题；
    // 显式背景选择保存在 page.bgMode 不被覆盖，关闭后自动还原）
    function setDarkFollow(on) {
        page.darkFollow = !!on
        Settings.setValue("reading/darkFollow", page.darkFollow)
    }

    // U4：Sheet 底部"保存当前设置"按钮（§4 占位）——保存主题预设功能待 U 审核后
    // 实现；当前为占位：记录操作不改变任何设置
    function onSaveThemeRequested() {
        console.log("U4 占位：保存当前设置为主题预设（功能待 U 审核）")
    }

    // E3：上拉框直接选择——背景四态白名单校验后应用（写 background/mode）；
    // image 无图时防御性拒绝（上拉框已禁用该选项，双保险防手改属性绕过）
    function setBackgroundMode(mode) {
        if (mode !== "light" && mode !== "paper" && mode !== "dark" && mode !== "image") return
        if (mode === "image" && !page.bgImagePath) return
        page.bgMode = mode
        Settings.setValue("background/mode", mode)
    }

    function setAlign(a) {
        if (a !== "left" && a !== "center" && a !== "right") return
        Settings.setValue("typography/align", a)
        page.typography = page.typographyFromSettings()
    }

    function setPageWidth(w) {
        if (w !== "narrow" && w !== "normal" && w !== "wide") return
        Settings.setValue("typography/pageWidth", w)
        page.typography = page.typographyFromSettings()
    }

    // D5：启动恢复——从 Settings 的 background/ 分区读背景参数（含钳制）。
    // 旧版 reader/background 键的迁移在 SettingsStore 构造函数预置默认分区时完成
    //（QML 加载前），此处只读新键，不再有迁移分支。
    function backgroundFromSettings() {
        let mode = Settings.value("background/mode")
        // E1：四态白名单；旧版 eink（B5 彩色墨水屏）值在此归一为 light（默认回退，
        // 与其余非法值同路径），并回写 settings.json 使存储值同步归一
        if (mode !== "light" && mode !== "paper" && mode !== "dark" && mode !== "image") {
            mode = "light"
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

    // C3：hover 追踪（5s 计时复位）——只覆盖正文内容区（topBar 下沿 → 朗读条上沿，
    // C2 起与正文同界：朗读条隐藏时扩展到控制栏顶，该区域在隐藏时是正文），
    // 刻意排除顶栏/朗读条/控制栏：全页 NoButton hover MouseArea 会截走按钮的 hover 反馈
    //（Qt 把 hover 路由到最顶层项），限制区域后按钮 hover 高亮保留（D7b 修复不回归）。
    // 语义变更：移动只重置计时、不再唤出（唤出走点击 TapHandler，隐藏态计时已停，
    // restart 为空操作）；鼠标从正文移到控制栏的过程中最后一次 onPositionChanged
    // 已重置计时，按钮操作在 5s 内保持可见。
    // acceptedButtons: Qt.NoButton 不拦截任何点击（正文选择/按钮点击照常透传）。
    MouseArea {
        anchors.top: topBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: page.ttsBarVisible ? ttsBar.top : controlsHost.top
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        onPositionChanged: {
            // 只在显示态重置（restart 会启动停止态的计时器，隐藏态禁止——见 handleContentTap 注释）
            if (page.controlsVisible)
                hideControlsTimer.restart()
        }
    }

    // C3：点击唤出热区——TapHandler 观察页面内全部轻点（DragThreshold 手势策略：
    // 按下后位移超过阈值即取消，正文拖拽选择/滚动不受影响；观察模式不拦截任何
    // 按钮的 hover 与点击，D7b 区域限定修复不回归。同 PdfReaderPage 双击检测模式）。
    // 语义（U4 整合，决策见 task-U4-report）：
    //   · Sheet 打开时任意轻点关闭（Kindle"点面板外关闭"）；菜单打开时轻点关闭
    //   · 控件隐藏且轻点正文底部 1/4（content.y + 0.75*高至控制栏顶，含隐藏时
    //     控制栏空位带）→ 唤出快捷控制栏（C3 保留为快捷条）
    //   · 其余轻点（屏幕中部/边缘）→ 弹出 KdBottomSheet（Kindle 主操作面）
    // TtsBar 显隐由 C2 门控独立决定，本框架不作用于朗读条。
    // 状态机收敛在 handleContentTap（页面坐标 y）——TapHandler 手势桥接 + 冒烟
    // 注入共用同一入口（quicktest harness 无法可靠合成鼠标事件，见 C7 同款取舍）。
    // 注意：Timer.restart() 对停止态的计时器会重新启动（Qt 语义），隐藏态禁止
    // 调用——否则违反"隐藏后计时停止"；重置只发生在显示态。
    function handleContentTap(y) {
        // E4：点击正文重新聚焦（弹层/控制栏按钮抢焦点后，方向键翻页随点击恢复）
        content.forceActiveFocus()
        if (page.sheetOpen) { page.sheetOpen = false; return }
        if (page.menuOpen) { page.menuOpen = false; return }
        const summonBottom = content.y + content.height * 0.75
        if (!page.controlsVisible && y >= summonBottom) {
            // 隐藏态：底部轻点唤出快捷控制栏（计时经 onControlsVisibleChanged 启动）
            page.controlsVisible = true
        } else {
            // 中部/边缘轻点（含显示态任意轻点）→ 弹 Sheet（onSheetOpenChanged 暂停计时）
            page.sheetOpen = true
        }
    }
    // U4：Sheet 开合联动——打开暂停控制栏 5s 自动隐藏（Sheet 是页面内覆盖层，
    // 其内点击不重置页面计时器）；关闭且控制栏显示态时恢复（同 E3 弹层语义）
    onSheetOpenChanged: {
        if (page.sheetOpen) hideControlsTimer.stop()
        else if (page.controlsVisible) hideControlsTimer.restart()
    }
    TapHandler {
        onTapped: page.handleContentTap(point.position.y)
    }

    // ---- U4：Kindle 底部 Sheet 工具栏（点屏幕中部弹出）----
    // 四个标签面板以 ReaderPage 内联 Component 注入（创建上下文为 ReaderPage，
    // 面板可直接引用 page/Settings；经 KdBottomSheet 的 Loader 按 currentId 切换）。
    // 面板只渲染与上报，业务读写集中在 ReaderPage（与 ReaderControls 同模式）。

    // 右上角下拉菜单数据（§5：KdListItem 风格列表）——功能入口与 MoreSheet 一致
    property var menuModel: [
        { icon: "toc", text: qsTr("目录"), act: "openToc" },
        { icon: "notes", text: qsTr("笔记"), act: "openNotes" },
        { icon: "search", text: qsTr("书内搜索"), act: "openSearch" },
        { icon: "read", text: qsTr("朗读"), act: "readAloud" },
        { icon: "prev", text: qsTr("上一章"), act: "prevChapter" },
        { icon: "next", text: qsTr("下一章"), act: "nextChapter" }
    ]

    // 菜单项分发（关闭菜单后执行对应动作——与 MoreSheet 入口同一组功能）
    function menuAction(act) {
        page.menuOpen = false
        switch (act) {
        case "openToc": tocDialog.open(); break
        case "openNotes": notesDlg.open(); break
        case "openSearch": searchDlg.open(); break
        case "readAloud": if (Tts.state !== 1) Tts.play(); break
        case "prevChapter": page.loadChapter(Books.currentChapter - 1); break
        case "nextChapter": page.loadChapter(Books.currentChapter + 1); break
        }
    }

    // 右上角下拉菜单（§5：右上弹出、60-65% 宽、实色面板 + 全页遮罩，点击遮罩关闭）
    Item {
        id: menuOverlay
        anchors.fill: parent
        visible: page.menuOpen
        // 遮罩（rgba(0,0,0,0.3)，淡入）
        Rectangle {
            anchors.fill: parent
            color: UITheme.overlay
            opacity: page.menuOpen ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: page.menuOpen = false
            }
        }
        // 菜单面板：贴右上角（顶栏下方），实色背景 + 细边框，无圆角（§5 组件样式）
        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 38
            anchors.right: parent.right
            anchors.rightMargin: 8
            width: parent.width * 0.62
            color: UITheme.bgPrimary
            border.color: UITheme.divider
            border.width: 1
            Column {
                width: parent.width
                Repeater {
                    id: menuRepeater
                    model: page.menuModel
                    Rectangle {
                        required property var modelData
                        width: parent.width
                        height: 48
                        color: menuRowMouse.containsMouse ? "#0A000000" : "transparent"
                        MouseArea {
                            id: menuRowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: page.menuAction(modelData.act)
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 14
                            KdIcons {
                                name: modelData.icon
                                size: 22
                                color: UITheme.textPrimary
                            }
                            Label {
                                text: modelData.text
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.pixelSize: 15
                                color: UITheme.textPrimary
                            }
                        }
                    }
                }
            }
        }
    }

    // 主题标签面板：四态背景网格（与 bgMode/Settings background/mode 一致）
    Component {
        id: themePanelComp
        ThemeSheet {
            bgMode: page.bgMode
            bgImagePath: page.bgImagePath
            onSetBackgroundMode: (m) => page.setBackgroundMode(m)
        }
    }
    // 字体标签面板：4 字体族 + 字号分段（current 经 page.fontFamily/typography 注入）
    Component {
        id: fontPanelComp
        FontSheet {
            fontFamily: page.fontFamily
            fontSize: page.typography.fontSize ?? 18
            onSetFontFamily: (v) => page.setFontFamily(v)
            onSetFontSize: (s) => page.setFontSize(s)
        }
    }
    // 布局标签面板：方向/页边距/行间距（current 经 page.pageMode/typography 注入）
    Component {
        id: layoutPanelComp
        LayoutSheet {
            pageMode: page.pageMode
            pageWidth: page.typography.pageWidth ?? "normal"
            lineHeight: page.typography.lineHeight ?? 1.6
            onSetPageMode: (m) => page.setPageMode(m)
            onSetPageWidth: (w) => page.setPageWidth(w)
            onSetLineHeight: (lh) => page.setLineHeight(lh)
        }
    }
    // 更多标签面板：开关 + 功能菜单入口
    Component {
        id: morePanelComp
        MoreSheet {
            autoContinue: page.autoContinue
            darkFollow: page.darkFollow
            onSetAutoContinue: (on) => page.setAutoContinue(on)
            onSetDarkFollow: (on) => page.setDarkFollow(on)
            onRequestToc: tocDialog.open()
            onRequestNotes: notesDlg.open()
            onRequestSearch: searchDlg.open()
            onRequestReadAloud: { if (Tts.state !== 1) Tts.play() }
            onRequestPrevChapter: page.loadChapter(Books.currentChapter - 1)
            onRequestNextChapter: page.loadChapter(Books.currentChapter + 1)
        }
    }

    // Sheet 本体（声明在最后 → 覆盖全页，含顶栏；遮罩/面板按 open 显隐）
    KdBottomSheet {
        id: bottomSheet
        anchors.fill: parent
        open: page.sheetOpen
        tabs: [
            { id: "theme", text: qsTr("主题") },
            { id: "font", text: qsTr("字体") },
            { id: "layout", text: qsTr("布局") },
            { id: "more", text: qsTr("更多") }
        ]
        pages: [
            { id: "theme", source: themePanelComp },
            { id: "font", source: fontPanelComp },
            { id: "layout", source: layoutPanelComp },
            { id: "more", source: morePanelComp }
        ]
        currentId: page.sheetTab
        // §4：底部描边按钮"保存当前设置"——仅主题标签显示（占位：功能待 U 审核）
        actionText: page.sheetTab === "theme" ? qsTr("保存当前设置") : ""
        onTabClicked: (id) => page.sheetTab = id
        onActionClicked: page.onSaveThemeRequested()
        onMaskClicked: page.sheetOpen = false
    }

    Component.onCompleted: {
        hideControlsTimer.start()   // C3：初始可见 → 5s 无操作自动隐藏
        page.typography = page.typographyFromSettings()
        page.backgroundFromSettings()
        // E4：翻页方式——reading/pageMode 白名单归一（非法值回退 scroll）
        const pm = Settings.value("reading/pageMode")
        page.pageMode = (pm === "paged") ? "paged" : "scroll"
        // U4：MoreSheet 开关与当前字族初值（reading/autoContinue 默认开、
        // darkFollow 默认关；fontFamily 供 FontSheet 高亮/选择）
        page.autoContinue = Settings.value("reading/autoContinue") !== false
        page.darkFollow = Settings.value("reading/darkFollow") === true
        page.fontFamily = String(Settings.value("typography/fontFamily") || "思源宋体 VF")
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
            // L5（P0#6）：旧库 chapter_index=0 的划线按章节标题回填 1 起索引（幂等），
            // 随后重载使列表按跨章顺序呈现
            Highlights.backfillChapterIndexes(page.book.id, Books.chapterTitles(page.book.id))
            page.reloadHighlights()   // C7：重新进入阅读页加载本书全部划线
            Books.startTracking(page.book.id)  // 阅读计时开始
        }
        // E4：阅读页获得键盘焦点——Flickable focus:true 需要页内 activeFocus，
        // 打开即聚焦正文（方向键立即可用）；点击正文（handleContentTap）同样
        // 重新聚焦（弹层/按钮抢焦点后点击内容即恢复方向键）。
        content.forceActiveFocus()
    }

    Component.onDestruction: {
        page.saveScroll()          // 离开页面补写滚动位置
        Books.stopTracking()       // 结算阅读秒数
    }
}
