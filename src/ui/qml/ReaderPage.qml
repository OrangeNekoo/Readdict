import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
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
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: (event) => {
        if (page.sheetOpen || page.menuOpen) return
        if (content.handleKey(event.key, event.modifiers, event.isAutoRepeat))
            event.accepted = true
    }
    property var book: ({})
    property var chapter: ({})
    // scroll 模式相邻章节原始数据（最多当前章前后各一章）；正文委托窗口在
    // ReaderContent 内按视口裁剪，因此不会全书常驻。
    property var scrollChapters: []
    property var typography: ({})
    property string bgMode: "light"          // 与 Settings background/mode 同步
    property string bgImagePath: ""          // background/imagePath（图片背景）
    property real bgBlur: 0.0                // background/blur（0..1）
    property real bgBrightness: 1.0          // background/brightness（0.5..1.5）
    // 任务5：自定义图片模式字体颜色（background/textColor 恢复值，白名单校验后的
    // 规范串；非法/缺失为 ""）。仅 effectiveBg==="image" 时注入正文，其它模式沿用
    // 各自默认文字色（不被自定义色污染）。
    property string bgTextColor: ""
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
    // U4：当前书签章节列表（Settings bookmarks/<bookId>），只保存章节索引。
    property var bookmarks: []
    property bool currentBookmarked: false
    // B10：暴露内容视图（滚动恢复冒烟测试经此读写 contentY/contentHeight）
    property alias contentView: content
    // C7：笔记列表 Dialog（冒烟测试经此打开/关闭）
    property alias notesDialog: notesDlg
    // 任务3：共享壳层——顶栏/菜单/TtsBar/底部 Sheet 与显隐状态全部由 ReaderShell
    // 持有，本页只保留文本正文特有的内容与交互策略层（热区/分页点击，见
    // handleContentTap）。公开 alias 保持既有测试/调用者接口不变，读写透传壳层。
    property alias readerShell: readerShell
    property alias topToolbar: readerShell.topToolbar
    // backButton/menuButton 为壳层顶栏（KdTopToolbar）内部按钮：alias 目标链不能
    // 穿越另一 alias（topToolbar），经 onCompleted 运行时赋值（测试只读句柄）。
    property var backButton: null
    property var menuButton: null
    property alias infoDialog: infoDialog
    property alias progressLabel: progressLabel
    // U4：Kindle 底部 Sheet 工具栏（统一由 ReaderShell 提供；默认主题标签在
    // onCompleted 注入）。
    property alias sheetOpen: readerShell.sheetOpen
    property alias sheetTab: readerShell.sheetTab
    property alias menuOpen: readerShell.menuOpen
    // U4：MoreSheet 开关——自动续章（reading/autoContinue，默认开，门控
    // autoNextChapter）与深色跟随（reading/darkFollow，默认关，effectiveBg 派生
    // 跟随应用主题深浅，覆盖显式背景选择；关闭后还原显式选择——page.bgMode 未被覆盖）
    property bool autoContinue: true
    property bool darkFollow: false
    // 左下角阅读进度：格式（页数/百分比）与范围（本章/全书）独立。
    property string progressDisplay: "pages"
    property string progressScope: "chapter"
    property real visualPageRatio: page.progressScope === "book"
        ? (page.bookPageTotal > 0 ? page.bookPageNumber / page.bookPageTotal : 0)
        : (content.pageMode === "paged"
            ? (content.pageCount > 0 ? (content.currentPage + 1) / content.pageCount : 0)
            : content.currentChapterProgressRatio())
    property int visualPageNumber: page.progressScope === "book"
        ? (page.bookPageTotal > 0 ? page.bookPageNumber : 0)
        : content.currentChapterPageNumber()
    property int visualPageCount: page.progressScope === "book"
        ? (page.bookPageTotal > 0 ? page.bookPageTotal : 0)
        : content.currentChapterPageCount()
    property string progressText: {
        const scope = page.progressScope === "book" ? qsTr("全书") : qsTr("本章")
        if (page.progressDisplay === "percent")
            return scope + " " + Math.round(page.visualPageRatio * 100) + "%"
        return scope + " " + qsTr("第 %1 / %2 页").arg(page.visualPageNumber)
                                           .arg(page.visualPageCount)
    }
    property int bookPageNumber: 0
    property int bookPageTotal: 0
    property var measuredChapterPages: []
    property int measureChapterIndex: 0
    property int measurePageSum: 0
    property var measureChapter: ({})
    property var measureView: null
    // 任务3：测量代次/目标章节状态——measureGeneration 每轮自增并随 Timer 校验，
    // 旧代次回调直接丢弃；measureTarget 记录本次目标章节对象，页数只在目标章节
    // 实际布局完成、对应模型稳定后采纳（契约2/4），杜绝采纳前一章异步残留。
    property int measureGeneration: 0
    property int measureTimerGeneration: -1
    property int measureRetries: 0
    property real measureLastHeight: -1
    property var measureTarget: null
    // 任务3：测量轮询间隔注入点（测试放大"测量未完成"窗口；生产 50ms）
    property int measureInterval: 50
    function updateBookPageNumber() {
        if (page.progressScope !== "book" || page.bookPageTotal <= 0) return
        let prefix = 0
        const ch = Math.max(0, Number(Books.currentChapter))
        for (let i = 0; i < ch && i < page.measuredChapterPages.length; ++i)
            prefix += Number(page.measuredChapterPages[i] || 0)
        page.bookPageNumber = prefix + content.currentChapterPageNumber()
    }

    Connections {
        target: content
        function onContentYChanged() { page.updateBookPageNumber() }
        function onCurrentPageChanged() { page.updateBookPageNumber() }
        function onPageCountChanged() { page.updateBookPageNumber() }
        // 任务3（契约1）：换章后即使 contentY/currentPage 未变（如两章都停在
        // 页首），全书页号也必须按新章前序偏移重算
        function onChapterChanged() { page.updateBookPageNumber() }
        // 任务3（契约5）：内容视口尺寸变化后旧全书测量立即失效并重新测量
        function onWidthChanged() { if (page.progressScope === "book") page.measureBookPages() }
        function onHeightChanged() { if (page.progressScope === "book") page.measureBookPages() }
    }
    // 任务3（契约5）：排版/阅读模式变化后重新测量。测量过程只写隐藏测量视图的
    // typography/pageMode（子对象属性），不会回触发本处理器（无环）。
    onTypographyChanged: { if (page.progressScope === "book") page.measureBookPages() }
    onPageModeChanged: { if (page.progressScope === "book") page.measureBookPages() }

    Timer {
        id: measureTimer
        interval: page.measureInterval
        repeat: false
        onTriggered: {
            // 契约4：旧代次 Timer 触发必须丢弃
            if (page.measureTimerGeneration !== page.measureGeneration) return
            page.measureBookStep()
        }
    }

    Component {
        id: measureContentComp
        ReaderContent {
            visible: false
            opacity: 0
            // 任务3：content 为本组件 id（词法解析）。旧实现写 page.content——
            // id 非父对象属性，测量视图恒为 0×0，正文永不布局、测量永不完成。
            width: content.width
            height: content.height
            textColor: page.effectiveBg === "dark" ? UITheme.darkTextPrimary : UITheme.lightTextPrimary
            typography: page.typography
            pageMode: page.pageMode
        }
    }
    function measureBookPages() {
        if (!page.book || !page.book.id) return
        if (!page.measureView) page.measureView = measureContentComp.createObject(page)
        page.measureGeneration += 1
        page.measureChapterIndex = 0
        page.measurePageSum = 0
        page.measuredChapterPages = []
        page.measureRetries = 0
        page.measureLastHeight = -1
        page.measureTarget = null
        // 契约3：旧全书值立即失效（未完成时 visual 只返回安全全书值）
        page.bookPageNumber = 0
        page.bookPageTotal = 0
        page.measureBookStep()
    }

    function scheduleMeasureStep() {
        page.measureTimerGeneration = page.measureGeneration
        measureTimer.restart()
    }

    function measureBookStep() {
        if (!page.measureView || !page.book || !page.book.id) return
        const count = Books.chapterCount(page.book.id)
        if (page.measureChapterIndex >= count) {
            page.bookPageTotal = page.measurePageSum
            page.updateBookPageNumber()
            return
        }
        // 契约4：无布局/尺寸为零等经重试预算兜底——按 1 页继续完成，不死循环
        if (page.measureRetries >= 16) {
            page.measuredChapterPages.push(1)
            page.measurePageSum += 1
            page.measureChapterIndex += 1
            page.measureRetries = 0
            page.measureLastHeight = -1
            page.measureTarget = null
            page.scheduleMeasureStep()
            return
        }
        const view = page.measureView
        const target = page.measureChapterIndex
        if (!page.measureTarget) {
            // 契约2：每章开始测量先清空隐藏视图旧 pageModel/pageCount，记录本次
            // 目标章节；失败/空章按 1 页继续
            view.pageModel = []
            view.pageCount = 0
            view.contentX = 0
            view.contentY = 0
            const loaded = Books.loadChapter(page.book.id, target)
            if (!loaded || loaded.error) {
                page.measuredChapterPages.push(1)
                page.measurePageSum += 1
                page.measureChapterIndex += 1
                page.measureRetries = 0
                page.scheduleMeasureStep()
                return
            }
            page.measureTarget = loaded
            page.measureChapter = loaded
            view.pageMode = page.pageMode
            view.typography = page.typography
            view.scrollChapters = [{ index: target,
                                     title: loaded.title || "", chapter: loaded }]
            view.activeScrollChapter = target
            view.scrollFocusChapter = target
            view.chapter = loaded
            page.measureRetries = 0
            page.measureLastHeight = -1
            page.scheduleMeasureStep()
            return
        }
        // 契约2：只在目标章节实际布局完成、对应模型稳定后采纳页数。
        // 目标章节判定用模型内容而非对象身份：scroll 行自带 chapterIndex（全部
        // 等于目标章）；paged 的 pageCount/pageModel 已在同一同步块内清空后才赋
        // 新章，故 pageCount>0 必为清空后重建的目标章结果（Timer 不会插入同步
        // 块），前一章异步残留不可能被采纳。
        let value = -1
        if (page.pageMode === "paged") {
            if (view.pageCount > 0 && view.pageModel.length === view.pageCount)
                value = view.pageCount
        } else {
            const rows = view.scrollModel || []
            let rowsOk = rows.length > 0
            for (let i = 0; rowsOk && i < rows.length; ++i)
                if (Number(rows[i].chapterIndex) !== target) rowsOk = false
            if (rowsOk && view.paragraphRepeater.count === rows.length
                    && view.contentHeight > 0)
                value = view.currentChapterPageCount()
        }
        if (value <= 0 || value !== page.measureLastHeight) {
            if (value > 0) page.measureLastHeight = value
            page.measureRetries += 1
            page.scheduleMeasureStep()
            return
        }
        page.measuredChapterPages.push(Math.max(1, value))
        page.measurePageSum += value
        page.measureChapterIndex += 1
        page.measureRetries = 0
        page.measureLastHeight = -1
        page.measureTarget = null
        page.scheduleMeasureStep()
    }
    // U4：当前字族存储 token（FontSheet 高亮/选择）。
    property string fontFamily: ""
    // U4：有效背景模式——darkFollow 开时跟随应用主题（UITheme.isDark 实时绑定），
    // 否则显式选择（bgMode）。
    property string effectiveBg: page.darkFollow
        ? (UITheme.isDark ? "dark" : "light") : page.bgMode
    // U4：测试句柄（冒烟经此驱动 Sheet 开合/标签/面板与右上角菜单）——目标为
    // 壳层子对象；menuRepeater 在壳层菜单内层（menuOverlay→menuPanel→menuColumn），
    // 非壳层直属 id，经 onCompleted 运行时解析赋值（alias 目标链不可编译期解析）。
    property alias bottomSheet: readerShell.bottomSheet
    // readerMenu/menuItems/hideTimer 是壳层内部子对象（menuOverlay/menuRepeater/
    // hideControlsTimer 为壳层组件作用域私有 id，外部组件不可引用——QML id 隐私），
    // 由下方 menuOverlayCompat/hideTimerCompat 桥接：菜单遮罩只镜像壳层显隐状态
    //（无任何输入处理，不拦截点击；真实遮罩/菜单项仍在壳层单一实例内），hideTimer
    // 按壳层状态机不变量派生 running（running ⟺ controlsVisible && !sheetOpen，
    // 与壳层 onControlsVisibleChanged/onSheetOpenChanged 驱动的计时状态一致）。
    // 菜单模型由壳层按适配器 capability 与标签构造（结构 read/toc/prev/next/
    // divider/info 与旧 page.menuModel 一致，另带 enabled/disabledReason 字段）。
    property alias menuModel: readerShell.menuModel
    property alias readerMenu: menuOverlayCompat
    property alias menuItems: menuRepeaterCompat
    property alias hideTimer: hideTimerCompat

    // C8：全文搜索结果跳转目标（书架全文搜索 push 时传入；-1 表示正常打开）。
    property int initialChapter: -1
    property int initialParagraph: -1
    property alias searchDialog: searchDlg
    property alias tocDlg: tocDialog
    property alias ttsBar: readerShell.ttsBar

    ReaderBackground {
        anchors.fill: parent
        mode: page.effectiveBg
        imagePath: page.bgImagePath
        blur: page.bgBlur
        brightness: page.bgBrightness
    }

    ReaderContent {
        id: content
        // 锚定壳层（兄弟节点 id）并以边距让出顶栏/TtsBar——alias 引用的项不能作
        // 锚目标（QML 只允许父/兄弟 id），改经 shell 几何数值派生，语义同旧实现：
        // Sheet 打开时正文下移 40px 顶栏；TtsBar 显示时正文上收 46px。
        anchors.top: readerShell.top
        anchors.topMargin: page.sheetOpen ? readerShell.topToolbar.height : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: readerShell.bottom
        anchors.bottomMargin: page.ttsBarVisible ? readerShell.ttsBar.height : 0
        chapter: page.chapter
        scrollChapters: page.scrollChapters
        typography: page.typography
        // 任务5：正文前景色——dark → Kindle 深色系浅字；image → 自定义字体颜色
        //（background/textColor 存储值，白名单校验后存于 page.bgTextColor，缺失/
        // 非法为 "" 走浅色默认）；light/paper/eink 等 → 浅底深字。自定义色只在
        // image 模式生效，不污染其它模式默认色。ReaderContent 的 TextEdit.color
        // 作富文本文档默认前景，纯文本与富文本（无显式色 span）一致继承。
        textColor: page.effectiveBg === "dark" ? UITheme.darkTextPrimary
                 : (page.effectiveBg === "image" && page.bgTextColor
                    ? page.bgTextColor : UITheme.lightTextPrimary)
        bookId: (page.book && page.book.id) || -1
        highlights: page.highlights
        chapterIndex: Books.currentChapter + 1
        pageMode: page.pageMode
        onRequestNextChapter: page.autoNextChapter()
        onRequestPrevChapter: page.autoPrevChapter()
        onRequestChapterActivation: (index) => page.activateChapter(index)
        // 任务2：正文宿主真实点击桥接——TapHandler 在 ReaderContent 内（见
        // ReaderContent.contentTapped 注释），视口坐标 y 换算回页面坐标后进
        // handleContentTap 状态机（隐藏态 content.y=0，换算为恒等；Sheet 打开
        // 时 content 下移 topToolbar 高，仍需换算）。content 为本组件 id（词法
        // 解析），不可写 page.content（id 非父对象属性）。
        // 任务3：x 视口坐标直传（content.x 恒 0），paged 模式左右半屏点击翻页。
        onContentTapped: (x, y) => page.handleContentTap(content.y + y, x)
    }
    Label {
        id: progressLabel
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.bottom: readerShell.bottom
        anchors.bottomMargin: (page.ttsBarVisible ? readerShell.ttsBar.height : 0) + 12
        visible: !page.sheetOpen && page.loadError.length === 0
        z: 10
        text: page.progressText
        font.pixelSize: UITheme.fsCaption
        color: page.effectiveBg === "dark" ? UITheme.darkTextSecondary : UITheme.textSecondary
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
    // 占满到底部。任务3：TtsBar 本体与 Tts 状态连接已迁入 ReaderShell（唯一实例），
    // 本属性透传壳层门控供 content/progressLabel 锚点使用。
    property alias ttsBarVisible: readerShell.ttsBarVisible

    // 兼容旧版阅读页显隐状态接口（任务3：状态机已迁入 ReaderShell，读写透传）。
    property alias controlsVisible: readerShell.controlsVisible
    property alias controlsHideDelay: readerShell.controlsHideDelay
    property real chapterProgress: {
        const id = page.book ? page.book.id : -1
        if (id <= 0) return 0
        const n = Books.chapterCount(id)
        return n > 0 ? Math.min(1, (Books.currentChapter + 1) / n) : 0
    }

    // C5：朗读越过章末 → 自动换下一章并继续朗读（continueReadingFromTts）；
    // TtsBar 的 playing/错误同步由 ReaderShell 的 Connections 承担（不重复）。
    Connections {
        target: Tts
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

    Connections {
        target: Books
        function onCurrentChapterChanged() { page.syncCurrentBookmark() }
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
                    // 任务1：目录跳转是显式导航——先准备（放弃运行锚点事务并标记
                    // 接下来的章节重建不捕获旧视口锚点/不按中线激活旧章），再
                    // loadChapter，随后定位到目标章首段（旧实现经 showScrollChapter→
                    // scheduleRestore 落回保存位置/0，窗口重建期又会被钳回 0——
                    // 改为显式定位）。
                    content.prepareExplicitNavigation()
                    page.loadChapter(index)
                    content.focusScrollParagraph(Number(index), 0)
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

    Dialog {
        id: infoDialog
        title: qsTr("图书信息")
        modal: true
        standardButtons: Dialog.Ok
        width: 380
        contentItem: Label {
            // 任务4：作者/出版社等空字段隐藏对应行（不显示空占位）；进度恒显示
            text: {
                let lines = []
                if (page.book && page.book.title)
                    lines.push(qsTr("书名：%1").arg(page.book.title))
                if (page.book && page.book.author)
                    lines.push(qsTr("作者：%1").arg(page.book.author))
                if (page.book && page.book.publisher)
                    lines.push(qsTr("出版社：%1").arg(page.book.publisher))
                if (page.book && page.book.format)
                    lines.push(qsTr("格式：%1").arg(page.book.format))
                lines.push(qsTr("进度：%1%").arg(Math.round((page.book && page.book.progress ? page.book.progress : 0) * 100)))
                return lines.join("\n")
            }
            wrapMode: Text.Wrap
            color: UITheme.textPrimary
        }
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

    function syncCurrentBookmark() {
        const ch = Number(Books.currentChapter)
        page.currentBookmarked = page.bookmarks.indexOf(ch) >= 0
    }

    function toggleBookmark() {
        if (!page.book || !page.book.id) return
        const ch = Number(Books.currentChapter)
        var list = Array.isArray(page.bookmarks) ? page.bookmarks.slice() : []
        const i = list.indexOf(ch)
        if (i >= 0) list.splice(i, 1)
        else list.push(ch)
        page.bookmarks = list
        Settings.setValue("bookmarks/" + page.book.id, list)
        page.syncCurrentBookmark()
    }
    function ttsForChapter(loaded, index, stopCurrent) {
        if (stopCurrent) Tts.stop()
        const all = []
        try {
            for (const p of (loaded.paragraphs ?? []))
                for (const s of ((p ?? {}).sentences ?? [])) all.push(s)
        } catch (err) {
            page.loadError = qsTr("章节数据异常，部分内容无法朗读")
            page.loadErrorIndex = index
        }
        // 任务1：setSentences 同步发出 sentenceChanged(0)（游标复位副作用，
        // 非朗读推进）——在复位区间内标记 suppressTtsFollow，ReaderContent 的
        // onSentenceChanged 据此跳过 followSentence，避免 300ms 跟随动画把
        // contentY 拽回 0 并覆盖运行窗口锚点恢复（跨章跳回首屏/身份回退）。
        content.suppressTtsFollow = true
        Tts.setSentences(all)
        content.suppressTtsFollow = false
        Tts.setChapter(index)
    }

    // 连续滚动只驻留当前章节和相邻章节的原始数据；ReaderContent 再把它裁成
    // 视口前后有限的完整段落委托，避免全书段落进入 QML 委托。
    function makeScrollChapters(center) {
        const titles = Books.chapterTitles(page.book.id) || []
        const first = Math.max(0, center - 1)
        const last = Math.min(titles.length - 1, center + 1)
        const result = []
        for (let index = first; index <= last; ++index) {
            const isCurrent = index === center && page.chapter && page.chapter.paragraphs
                && Number(Books.currentChapter) === index
            const loaded = isCurrent ? page.chapter : Books.loadChapter(page.book.id, index)
            if (!loaded || loaded.error) continue
            result.push({ index: index, title: loaded.title || titles[index] || "", chapter: loaded })
        }
        return result
    }

    function loadChapter(i) {
        if (!page.book || !page.book.id) return
        const titles = Books.chapterTitles(page.book.id)
        if (!titles || titles.length === 0) {
            const probe = Books.loadChapter(page.book.id, 0)
            if (probe && probe.error) {
                page.loadError = probe.error
                page.loadErrorIndex = 0
                page.chapter = ({})
            }
            return
        }
        i = Math.max(0, Math.min(i, titles.length - 1))
        const loaded = Books.loadChapter(page.book.id, i)
        if (loaded && loaded.error) {
            page.loadError = loaded.error
            page.loadErrorIndex = i
            page.chapter = ({})
            return
        }
        page.loadError = ""
        Books.currentChapter = i
        page.chapter = loaded
        page.ttsForChapter(loaded, i, true)
        page.syncCurrentBookmark()
        if (page.pageMode === "scroll") {
            page.scrollChapters = page.makeScrollChapters(i)
            content.showScrollChapter(i)
        }
        content.forceActiveFocus()
    }
    // ReaderContent 中线激活的章节同步更新页面章节身份与连续窗口。
    function activateChapter(i) {
        if (!page.book || !page.book.id || i === Books.currentChapter) return
        const titles = Books.chapterTitles(page.book.id) || []
        if (i < 0 || i >= titles.length) return
        const loaded = Books.loadChapter(page.book.id, i)
        if (!loaded || loaded.error) return
        Books.currentChapter = i
        page.chapter = loaded
        Books.reportProgress(page.book.id, i + 1, Books.chapterCount(page.book.id))
        page.ttsForChapter(loaded, i, true)
        page.syncCurrentBookmark()
        page.scrollChapters = page.makeScrollChapters(i)
    }

    // 规格 §7：滚动路径的连续窗口已在 ReaderContent 内扩展；这条仅是 paged
    // 末页翻章与无法继续扩展时的兜底。
    function autoNextChapter() {
        if (!page.autoContinue) return
        const titles = Books.chapterTitles(page.book.id)
        if (!titles || Books.currentChapter + 1 >= titles.length) return
        page.loadChapter(Books.currentChapter + 1)
    }

    function autoPrevChapter() {
        const titles = Books.chapterTitles(page.book.id)
        if (!titles || Books.currentChapter - 1 < 0) return
        page.loadChapter(Books.currentChapter - 1)
    }

    function continueReadingFromTts(ch) {
        const titles = Books.chapterTitles(page.book.id)
        if (!titles || ch + 1 >= titles.length) return
        page.loadChapter(ch + 1)
        Tts.play()
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

    function setProgressDisplay(display) {
        page.progressDisplay = display === "percent" ? "percent" : "pages"
        Settings.setValue("reading/progressDisplay", page.progressDisplay)
    }
    function setProgressScope(scope) {
        page.progressScope = scope === "book" ? "book" : "chapter"
        Settings.setValue("reading/progressScope", page.progressScope)
        if (page.progressScope === "book") page.measureBookPages()
    }
    // U4/L10：Sheet 底部"保存当前设置"按钮 → 主题面板命名输入 Dialog
    //（保存当前排版/背景快照为主题预设，追加 themes/custom，见 ThemeSheet）
    function onSaveThemeRequested() {
        const panel = bottomSheet.contentLoader.item
        if (panel && panel.openSaveDialog) panel.openSaveDialog()
    }

    // L10（P1#10）：应用自定义预设——写 typography/* 与 background/* 键并刷新
    // 响应层（Settings 无变更信号，页面属性作响应层）。text 为派生文字色 token，
    // 应用不写（文字色随背景模式派生，B3 语义）；image 预设无图防御性拒绝。
    function applyThemePreset(p) {
        if (!p || typeof p !== "object" || !p.name) return
        Settings.setValue("typography/fontFamily", p.fontFamily || "思源宋体 VF")
        Settings.setValue("typography/fontSize", Number(p.fontSize) || 18)
        Settings.setValue("typography/lineHeight", Number(p.lineHeight) || 1.6)
        const bg = (p.bg === "dark" || p.bg === "paper" || p.bg === "image") ? p.bg : "light"
        if (bg === "image") {
            if (!p.bgImagePath) return   // 无图不可应用 image 预设（同 setBackgroundMode 门控）
            Settings.setValue("background/imagePath", p.bgImagePath)
            page.bgImagePath = p.bgImagePath
        }
        Settings.setValue("background/mode", bg)
        Settings.setValue("themes/active", p.name)
        page.bgMode = bg
        // L10 复审：同步存储 token——FontSheet 高亮与下次「保存当前设置」快照取
        // 预设字体（镜像 setFontFamily 模式；否则 page.fontFamily 残留旧值漂移）
        page.fontFamily = String(p.fontFamily || "思源宋体 VF")
        page.typography = page.typographyFromSettings()
    }

    // L10：「管理主题」入口——push ThemeManagePage.qml（主题面板位于 Loader 内
    // StackView.view 不解析，经 requestManageThemes 上报到本页再 push——本页是
    // 主栈直接子项，附加属性可解析）
    function openThemeManagePage() {
        const sv = page.StackView.view
        if (sv) sv.push("ThemeManagePage.qml")
    }

    // E3：上拉框直接选择——背景四态白名单校验后应用（写 background/mode）；
    // image 无图时防御性拒绝（上拉框已禁用该选项，双保险防手改属性绕过）。
    // L10 复审：内置背景选择清除自定义预设激活态（themes/active）——否则网格
    // 高亮/管理页 ○● 失真，且删除该预设会误触发回退内置默认。先写 active 再切
    // bgMode，保证面板 onBgModeChanged 刷新读到已清除值；显式 panel.refresh()
    // 覆盖同 bg 再选（bgMode 不变不触发 onChanged）的路径。
    function setBackgroundMode(mode) {
        if (mode !== "light" && mode !== "paper" && mode !== "dark" && mode !== "image") return
        if (mode === "image" && !page.bgImagePath) return
        Settings.setValue("themes/active", "")
        page.bgMode = mode
        Settings.setValue("background/mode", mode)
        const panel = bottomSheet.contentLoader.item
        if (panel && panel.refresh) panel.refresh()
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
        const rawMode = Settings.value("background/mode")
        const mode = BackgroundNorm.norm(rawMode)
        if (mode !== rawMode) Settings.setValue("background/mode", mode)
        page.bgMode = mode
        page.bgImagePath = Settings.value("background/imagePath") || ""
        const blur = Number(Settings.value("background/blur")) || 0.0
        page.bgBlur = Math.max(0, Math.min(1, blur))
        const bright = Number(Settings.value("background/brightness")) || 1.0
        page.bgBrightness = Math.max(0.5, Math.min(1.5, bright))
        const tc = Settings.value("background/textColor")
        page.bgTextColor = UITheme.isSafeImageTextColor(tc) ? UITheme.imageTextColorValue(tc) : ""
    }

    function saveScroll() {
        if (!page.book || !page.book.id || content.restorePending) return
        const candidate = content.scrollAnchor()
        // 章节刚切换、但旧窗口的委托尚未换出时，candidate 仍指向上一章。
        // 此时把它持久化会覆盖 Books.currentChapter，重开必然回退；只接受与
        // 当前激活章节一致的完整锚点。其余过渡态保留章节并清掉陈旧锚点。
        const anchor = candidate
            && Number(candidate.chapterIndex) === Books.currentChapter
            && Number(candidate.chapterIndex) === content.activeScrollChapter
            ? candidate : null
        const chapter = anchor ? anchor.chapterIndex : Books.currentChapter
        const offset = anchor ? Math.max(0, Number(anchor.offsetY) || 0) : 0
        Books.savePosition(page.book.id, chapter, offset)
        if (anchor) Settings.setValue("progress/anchor_" + page.book.id, anchor)
        else Settings.removeValue("progress/anchor_" + page.book.id)
    }

    // C7：从 Highlights 加载本书全部划线（打开阅读页/划线变更/笔记列表打开时调用）
    function reloadHighlights() {
        if (!page.book || !page.book.id) return
        page.highlights = Highlights.highlightsForBook(page.book.id)
    }

    // C8：全文搜索跳转——定位到指定段落。scroll：prepareExplicitNavigation 放弃
    // 运行锚点事务并锁定目标章，focusScrollParagraph 滚到视口上 1/3 处；paged：
    // 无运行窗口锚点竞争，沿用 paraJumpTimer 翻页定位（页内整页呈现无需偏移）。
    function jumpToSearchHit(hit) {
        if (!hit || hit.chapterIndex === undefined || hit.paragraphIndex === undefined) return
        content.restoreScrollY = -1
        content.restoreAnchor = null
        content.restorePending = false
        if (page.pageMode === "paged") {
            page.loadChapter(hit.chapterIndex)
            paraJumpTimer.targetIndex = hit.paragraphIndex
            paraJumpTimer.restart()
            return
        }
        content.prepareExplicitNavigation()
        page.loadChapter(hit.chapterIndex)
        content.focusScrollParagraph(hit.chapterIndex, hit.paragraphIndex)
    }

    // C8：外部（书架全文搜索入口）定位——同一跳转路径，供 initial* 属性复用。
    function jumpToChapterParagraph(ci, pi) {
        content.restoreScrollY = -1
        content.restoreAnchor = null
        content.restorePending = false
        if (page.pageMode === "paged") {
            page.loadChapter(ci)
            paraJumpTimer.targetIndex = pi
            paraJumpTimer.restart()
            return
        }
        content.prepareExplicitNavigation()
        page.loadChapter(ci)
        content.focusScrollParagraph(ci, pi)
    }

    // C7：笔记列表跳转——以高亮保存的 1 起 chapterIndex 为目标章（转 0 起），旧
    // 数据无有效 chapterIndex 时回退标题查找；scroll：prepareExplicitNavigation +
    // focusScrollSentence 锁定目标章/目标段（句索引 → 段索引）后闪烁目标句；
    // paged：无运行窗口锚点竞争，沿用原跳转定时器路径（重建后翻页定位）。
    function jumpToHighlight(hl) {
        if (!hl || hl.sentenceIndex === undefined || hl.sentenceIndex < 0) return
        const titles = Books.chapterTitles(page.book.id)
        let ci = -1
        // 任务1 复核：1 起 chapterIndex 须为 [1, titles.length] 内的整数才采用
        //（转 0 起目标章）；旧数据/越界/非整数等无效值时回退到高亮章节标题
        // 查找，而不是静默返回。
        const rawIndex = Number(hl.chapterIndex)
        if (Number.isInteger(rawIndex) && rawIndex > 0 && rawIndex <= titles.length)
            ci = rawIndex - 1
        else if (hl.chapter !== undefined)
            ci = titles.indexOf(hl.chapter)
        if (ci < 0 || ci >= titles.length) return
        notesDlg.close()
        if (page.pageMode === "paged") {
            page.loadChapter(ci)
            jumpTimer.targetIndex = hl.sentenceIndex
            jumpTimer.restart()
            return
        }
        content.prepareExplicitNavigation()
        page.loadChapter(ci)
        content.focusScrollSentence(ci, hl.sentenceIndex)
        content.flashSentence(hl.sentenceIndex)
    }

    // C3：hover 追踪（5s 计时复位）——只覆盖正文内容区（topBar 下沿 → 朗读条上沿，
    // C2 起与正文同界：朗读条隐藏时扩展到控制栏顶，该区域在隐藏时是正文），
    // 刻意排除顶栏/朗读条/控制栏：全页 NoButton hover MouseArea 会截走按钮的 hover 反馈
    //（Qt 把 hover 路由到最顶层项），限制区域后按钮 hover 高亮保留（D7b 修复不回归）。
    // 语义变更：移动只重置计时、不再唤出（唤出走点击 TapHandler，隐藏态计时已停，
    // restart 为空操作）；鼠标从正文移到控制栏的过程中最后一次 onPositionChanged
    // 已重置计时，按钮操作在 5s 内保持可见。
    // acceptedButtons: Qt.NoButton 不拦截任何点击（正文选择/按钮点击照常透传）。
    // 任务2：同因"hover 路由到最顶层项"，正文内 HoverHandler 收不到悬停——本处把
    // 每次位置变化转发给 content.notifyEdgeHintHover（paged 左右约 15% 热区判定在
    // ReaderContent 内），驱动边缘翻页提示重新显示/重启闲置计时（契约2）。
    // C3：点击状态机（U4 整合，决策见 task-U4-report）——任务3 起关闭路径统一
    // 走壳层 handleTap（菜单打开 → 关菜单与 Sheet；Sheet 打开 → 关闭）；隐藏态
    // 的唤出/翻页属文本正文特有策略（壳层注释明确 paged 边缘翻页与正文热区不迁入
    // 壳层），保留在本页策略层：paged 模式点击即翻页——右半屏下一页、左半屏上一页
    //（首末页边界换章由 pageNext/pagePrev → autoNext/autoPrevChapter 处理）；x 缺省
    //（旧直调路径）保持唤出语义不翻页。scroll 模式只在上/下 20% 热区唤出，中部
    // 轻点无动作（BUG4）。x 为视口坐标、y 为页面坐标（content.y 换算见 onContentTapped）。
    // 注意：Timer.restart() 对停止态的计时器会重新启动（Qt 语义），隐藏态禁止
    // 调用——否则违反"隐藏后计时停止"；重置只发生在显示态。
    function handleContentTap(y, x) {
        content.forceActiveFocus()
        if (page.menuOpen || page.sheetOpen) {
            readerShell.handleTap(y, x)   // 统一关闭语义（壳层状态机）
            return
        }
        if (page.pageMode === "paged" && x !== undefined && x >= 0) {
            const hotTop = content.y + content.height * 0.2
            const hotBottom = content.y + content.height * 0.8
            if (y <= hotTop || y >= hotBottom) {
                // 唤出：sheetOpen=true 由壳层 onSheetOpenChanged 自动停计时器
                page.controlsVisible = true
                page.sheetOpen = true
                return
            }
            const edge = Math.max(72, content.width * 0.15)
            if (x <= edge) content.pagePrev(false)
            else if (x >= content.width - edge) content.pageNext(false)
            return
        }
        const hotTop = content.y + content.height * 0.2
        const hotBottom = content.y + content.height * 0.8
        if (y <= hotTop || y >= hotBottom) {
            // 唤出：sheetOpen=true 由壳层 onSheetOpenChanged 自动停计时器
            page.controlsVisible = true
            page.sheetOpen = true
        }
    }

    // ---- U4：Kindle 底部 Sheet 工具栏（点屏幕中部弹出）----
    // 四个标签面板以 ReaderPage 内联 Component 注入（创建上下文为 ReaderPage，
    // 面板可直接引用 page/Settings；经壳层 KdBottomSheet 的 Loader 按 currentId
    // 切换）。面板只渲染与上报，业务读写集中在 ReaderPage。

    function startReadAloud() {
        if (Tts.state === 2) { Tts.play(); return }
        if (Tts.state === 1) return
        const position = content.readingPositionAtViewportCenter()
        if (position.chapterIndex !== Books.currentChapter) {
            const loaded = Books.loadChapter(page.book.id, position.chapterIndex)
            if (loaded && !loaded.error) page.ttsForChapter(loaded, position.chapterIndex, false)
        }
        Tts.setCurrentIndex(position.sentenceIndex)
        Tts.play()
    }

    // 兼容旧菜单入口：统一经壳层 triggerMenuAction（适配器分发，capability 门控）。
    function menuAction(act) {
        readerShell.triggerMenuAction(act)
    }

    // 主题标签面板：四态背景网格 + L10 自定义预设（与 bgMode/Settings background/mode、
    // typography/fontFamily、fontSize/lineHeight 一致；保存快照/应用经宿主处理）
    Component {
        id: themePanelComp
        ThemeSheet {
            bgMode: page.bgMode
            bgImagePath: page.bgImagePath
            fontFamily: page.fontFamily
            typography: page.typography
            onSetBackgroundMode: (m) => page.setBackgroundMode(m)
            onApplyPreset: (p) => page.applyThemePreset(p)
            onRequestManageThemes: page.openThemeManagePage()
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
    // 布局标签面板：方向/页边距/行间距/对齐（current 经 page.pageMode/typography 注入）
    Component {
        id: layoutPanelComp
        LayoutSheet {
            pageMode: page.pageMode
            pageWidth: page.typography.pageWidth ?? "normal"
            lineHeight: page.typography.lineHeight ?? 1.6
            align: page.typography.align ?? "left"
            onSetPageMode: (m) => page.setPageMode(m)
            onSetPageWidth: (w) => page.setPageWidth(w)
            onSetLineHeight: (lh) => page.setLineHeight(lh)
            onSetAlign: (a) => page.setAlign(a)
        }
    }
    Component {
        id: morePanelComp
        MoreSheet {
            autoContinue: page.autoContinue
            darkFollow: page.darkFollow
            progressDisplay: page.progressDisplay
            progressScope: page.progressScope
            progressPreview: page.progressText
            onSetAutoContinue: (on) => page.setAutoContinue(on)
            onSetDarkFollow: (on) => page.setDarkFollow(on)
            onSetProgressDisplay: (display) => page.setProgressDisplay(display)
            onSetProgressScope: (scope) => page.setProgressScope(scope)
        }
    }

    // 任务3：菜单遮罩测试桥——镜像壳层 menuOverlay 的显隐/淡出状态（visible/
    // opacity），但不渲染遮罩、不挂任何输入处理（不拦截点击；真实遮罩与菜单项
    // 由壳层单一实例提供）。menuRepeaterCompat 仅作模型就绪探针（空 Item 委托，
    // 不可见），供既有冒烟测试的 itemAt(0) 句柄保持可用。
    Item {
        id: menuOverlayCompat
        anchors.fill: parent
        visible: page.menuOpen || opacity > 0.01
        opacity: page.menuOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Repeater {
            id: menuRepeaterCompat
            model: page.menuModel
            delegate: Item {}
        }
    }
    // 任务3：自动隐藏计时器测试桥——壳层 hideControlsTimer 是组件私有 id，这里按
    // 壳层状态机不变量派生 running（壳层计时器 running ⟺ controlsVisible && !sheetOpen，
    // 见 ReaderShell onControlsVisibleChanged/onSheetOpenChanged；创建瞬间的初始值
    // 不触发变更处理器，但任何既有冒烟断言都发生在状态变更之后）。
    QtObject {
        id: hideTimerCompat
        property bool running: page.controlsVisible && !page.sheetOpen
    }

    // 任务3：文本阅读适配器——实现统一适配器契约（ReaderShell 只读此对象），把
    // 壳层菜单/顶栏动作映射回本页既有函数与 Dialog（章节导航/目录/搜索/笔记/
    // 书签/朗读）。canGoPrevious/canGoNext 随当前章节实时派生，壳层菜单按
    // capability 禁用边界项（首章上一章/末章下一章不触发，同旧 loadChapter 钳制）；
    // 上/下一项标签取"上一章/下一章"（PDF 适配器取"上一页/下一页"，壳层不硬编码）。
    QtObject {
        id: textReaderAdapter
        property string progressText: page.progressText
        property bool canGoPrevious: Number(Books.currentChapter) > 0
        property bool canGoNext: page.book && page.book.id
            ? Books.currentChapter + 1 < Books.chapterCount(page.book.id) : false
        property bool canReadAloud: true
        property string readAloudUnavailableReason: ""
        property bool supportsContents: true
        property bool supportsSearch: true
        property bool supportsNotes: true
        property bool supportsBookmarks: true
        property string previousLabel: qsTr("上一章")
        property string nextLabel: qsTr("下一章")
        function previous() {
            // 任务1：显式翻章——先准备（放弃运行锚点事务并标记章节重建不捕获
            // 旧视口锚点），再 loadChapter 并定位到目标章首段；仅取消锚点会让
            // 视口停在旧偏移（重建钳制后位置随机）；旧实现的 scheduleRestore
            // 会把 contentY 落回保存位置/0，同样不正确。
            content.prepareExplicitNavigation()
            page.loadChapter(Books.currentChapter - 1)
            content.focusScrollParagraph(Number(Books.currentChapter), 0)
        }
        function next() {
            content.prepareExplicitNavigation()
            page.loadChapter(Books.currentChapter + 1)
            content.focusScrollParagraph(Number(Books.currentChapter), 0)
        }
        function startReadAloud() { page.startReadAloud() }
        function stopReadAloud() { Tts.stop() }
        function openContents() { tocDialog.open() }
        function openSearch() { searchDlg.open() }
        function openNotes() { notesDlg.open() }
        function toggleBookmark() { page.toggleBookmark() }
        function openInfo() { infoDialog.open() }
    }

    // 任务3：共享交互壳层（唯一顶栏/菜单/TtsBar/底部 Sheet/点击显隐状态机/焦点
    // 恢复）——本页注入正文宿主、适配器、面板组件与背景/书签绑定。声明在最后
    // 覆盖全页（同旧 bottomSheet 语义）；ReaderContent 的点击信号经
    // onContentTapped → handleContentTap 统一走壳层状态机（关闭路径）与本页
    // 文本点击策略（热区唤出/paged 翻页）。
    ReaderShell {
        id: readerShell
        anchors.fill: parent
        reader: textReaderAdapter
        contentItem: content
        bookmarked: page.currentBookmarked
        ttsBgMode: page.effectiveBg
        // 返回导航（原 ReaderPage 顶栏 onBack 语义：先关菜单再出栈）
        onBackRequested: {
            page.menuOpen = false
            const win = Window.window
            if (win && win.goBack) win.goBack()
            else {
                const sv = page.StackView.view
                if (sv) sv.pop()
            }
        }
        // hover 区把边缘热区提示转发给正文（paged 左右约 15% 热区显隐，任务2 契约；
        // 壳层自身只负责计时重置与 edgeHover 上报）
        onEdgeHover: (x) => {
            if (content.pageMode === "paged") content.notifyEdgeHintHover(x)
        }
        // §4：底部描边按钮"保存当前设置"——仅主题标签显示（onActionClicked →
        // onSaveThemeRequested → 主题面板命名输入 Dialog；面板槽保留在本页）
        bottomSheet.actionText: page.sheetTab === "theme" ? qsTr("保存当前设置") : ""
        bottomSheet.onActionClicked: page.onSaveThemeRequested()
    }

    Component.onCompleted: {
        // 任务3：注入壳层运行期依赖——sheetTabs/sheetPages 引用本页内联 Component
        //（创建上下文为 ReaderPage，面板可直接访问 page/Settings），须在全部子对象
        // 完成后赋值；默认 Sheet 标签为"主题"（旧 page.sheetTab 默认值）；menuItems
        // 为壳层菜单内层 Repeater（alias 目标链不可编译期解析，运行时赋值）。
        readerShell.sheetTabs = [
            { id: "theme", text: qsTr("主题") },
            { id: "font", text: qsTr("字体") },
            { id: "layout", text: qsTr("布局") },
            { id: "more", text: qsTr("更多") }
        ]
        readerShell.sheetPages = [
            { id: "theme", source: themePanelComp },
            { id: "font", source: fontPanelComp },
            { id: "layout", source: layoutPanelComp },
            { id: "more", source: morePanelComp }
        ]
        readerShell.sheetTab = "theme"
        page.backButton = readerShell.topToolbar.backBtn
        page.menuButton = readerShell.topToolbar.menuBtn
        page.typography = page.typographyFromSettings()
        page.backgroundFromSettings()
        const pm = Settings.value("reading/pageMode")
        page.pageMode = (pm === "paged") ? "paged" : "scroll"
        page.darkFollow = Settings.value("reading/darkFollow") === true
        page.autoContinue = Settings.value("reading/autoContinue") !== false
        const pd = Settings.value("reading/progressDisplay")
        page.progressDisplay = pd === "percent" ? "percent" : "pages"
        const ps = Settings.value("reading/progressScope")
        page.progressScope = ps === "book" ? "book" : "chapter"
        page.fontFamily = String(Settings.value("typography/fontFamily") || "思源宋体 VF")
        const savedBookmarks = Settings.value("bookmarks/" + (page.book ? page.book.id : ""))
        page.bookmarks = Array.isArray(savedBookmarks) ? savedBookmarks.slice() : []
        page.syncCurrentBookmark()
        const initChapter = page.initialChapter >= 0
            ? page.initialChapter : Books.lastChapter(page.book.id)
        page.loadChapter(initChapter)
        if (page.progressScope === "book") page.measureBookPages()
        if (page.initialParagraph >= 0) {
            paraJumpTimer.targetIndex = page.initialParagraph
            paraJumpTimer.restart()
        } else {
            const anchor = Settings.value("progress/anchor_" + page.book.id)
            if (anchor && anchor.chapterIndex !== undefined)
                content.restoreScrollAnchor(anchor)
            else
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

    // L10（P1#10）：从管理主题页返回（pop 回阅读页）时重读 Settings——删除当前
    // 激活预设已回退内置默认（typography/background 键），刷新响应层使排版/背景
    // 即时生效，并让主题面板重算预设网格（删除项不再残留）。初推入时亦触发，
    // 重读同值无副作用。
    StackView.onActivated: {
        page.typography = page.typographyFromSettings()
        // L10 复审：删除回退同样重读存储 token（页面属性作响应层，镜像 onCompleted）
        page.fontFamily = String(Settings.value("typography/fontFamily") || "思源宋体 VF")
        page.backgroundFromSettings()
        // 任务2：StackView 激活（首次 push 与从管理主题页等 pop 返回）后确保正文
        // 持有 activeFocus——方向键经生产 Keys.onPressed → handleKey 立即可用
        //（onCompleted 的 forceActiveFocus 只在首次创建时执行，返回路径需在此补）
        content.forceActiveFocus()
        const panel = bottomSheet.contentLoader.item
        if (panel && panel.refresh) panel.refresh()
    }

    Component.onDestruction: {
        page.saveScroll()          // 离开页面补写滚动位置
        Books.stopTracking()       // 结算阅读秒数
    }
}
