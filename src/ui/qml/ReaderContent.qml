import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.Backend
import Readdict.UI 1.0

// 章节内容渲染：Flickable + Column + Repeater。
// chapter:   {title, paragraphs:[{text, html, level, imagePath, sentences}]}（Books.loadChapter 返回）
// typography:{fontFamily, fontSize, lineHeight, align, pageWidth}
// 图片段落（imagePath 非空）用 Image 渲染，其余段落用 Text(RichText) 渲染；
// 标题级别由 html 内的 <h1..h6> 体现（Qt RichText 自带标题字号）。
//
// C5 逐句高亮：段落按 sentenceStarts（每段起始句子全局索引，QML 侧由 paragraph.sentences
// 长度累加）判断 Tts.currentIndex 是否落在本段；纯文本段把每句包成独立 <span>（拼接后
// 与原文逐字符一致，保持自然换行），当前句包黄色高亮 span；含 <b>/<i>/<hN>/<img> 的
// 富文本段整体包高亮 span（无法安全定位句边界时退化为段级高亮）。
// D2：朗读游标黄底（含富文本段整段黄标）仅朗读会话激活（flick.ttsActive，state!=0）
// 时显示——Tts.currentIndex 初始为 0（setSentences 复位）且 state=0，未朗读不黄标首句；
// 划线句底色保留（用户主动操作），仅"当前句"指示（黄底/下划线叠加）受朗读状态门控。
// C7 划线渲染：ReaderPage 从 Highlights.highlightsForBook 加载本书全部划线，经 highlights
// 属性注入；rebuildHighlightMap 以 "章节标题|句子全局索引" 为键建 map（与 addHighlight
// 时记录的 chapterTitle + sentenceIndex 一致），逐句渲染时命中即包划线色 span；
// C7b 查重键唯一性由 Books 保证：空/重复章节标题（FB2 无 <title>、TXT 重复 h2）经
// BookManager::uniqueChapterTitles 兜底为 "第N章"，落库标题与查表标题同源，跨章不碰撞；
// 划线句同时是朗读当前句 → 划线色为底 + 下划线叠加（两类信息都可见）。
// 富文本段无法逐句定位：段内任一划线句 → 整段背景（近似，取段内首个划线色）。
// C7 选择交互：句子 Text selectByMouse，松开选择后弹工具条（复制/划线/笔记）；
// 划线→色板（黄/绿/粉）→ Highlights.addHighlight；笔记→Dialog 填 note → updateNote。
// 滚动跟随：Tts.sentenceChanged → 定位所在段落委托的 y → contentY 平滑滚动。
Flickable {
    id: flick
    property var chapter: ({})
    // BUG3：连续滚动章节窗口。ReaderPage 只传当前章及相邻章，正文段落模型带
    // 稳定章节/段落元数据；paged 分支仍使用 chapter/pageModel 原接口。
    property var scrollChapters: []
    property var scrollModel: []
    property var scrollRows: []
    property int scrollWindowStart: 0
    property int scrollFocusChapter: -1
    property int scrollFocusParagraph: -1
    property var pendingScrollTarget: null
    property var pendingWindowAnchor: null
    // 任务1：运行窗口锚点事务的恢复重试计数（防模型切片/未布局时无限自旋；
    // captureWindowAnchor 重置，windowAnchorTimer 达上限后放弃并保持当前 contentY）
    property int windowAnchorRetries: 0
    // 任务1：锚点恢复写 contentY 的瞬间标志——该写入是重建过渡态（视口回到捕获
    // 位置），不得按视口中线激活换章（否则 → 键等显式换章会被反向拉回旧章）。
    property bool windowAnchorRestoring: false
    // 任务1：捕获时的视口位置与内容高度——事务在途且用户主动滚动（内容高度稳定、
    // contentY 已移动）时重捕获锚点，避免延迟重建用过期锚点把视口拽回旧位置。
    property double windowAnchorY: -1
    property double windowAnchorContentHeight: -1
    // 任务1：ttsForChapter 的 setSentences 游标复位区间标记（ReaderPage 设置）——
    // setSentences 同步发出 sentenceChanged(0)，那是换章副作用而非朗读推进；该
    // 复位发生在 onChapterChanged（下一帧）之前，pendingWindowAnchor 尚未捕获，
    // 只能由本标记在复位区间内拦截 followSentence（否则 300ms 动画把 contentY
    // 拽回 0 并覆盖运行窗口锚点恢复——跨章跳回首屏的另一来源）。
    property bool suppressTtsFollow: false
    property int activeScrollChapter: -1
    property int scrollWindowLimit: 180
    signal requestChapterActivation(int index)
    function captureWindowAnchor() {
        if (flick.pageMode !== "scroll" || flick.scrollModel.length === 0) return
        // 运行窗口锚点：模型重建前捕获当前视口顶部段落 {chapterIndex, paragraphIndex, offsetY}，
        // 重建布局完成后由 windowAnchorTimer 恢复同一段落及相对偏移（契约1）。
        // 重建在途时旧委托已换出且未布局（y=0），scrollAnchor 可能读到空/错误段落——
        // 已有待恢复锚点（本次事务首次捕获有效）时不得用无效结果覆盖它。
        var captured = flick.scrollAnchor()
        if (!captured && flick.pendingWindowAnchor) return
        flick.pendingWindowAnchor = captured
        flick.windowAnchorRetries = 0
        flick.windowAnchorY = flick.contentY
        flick.windowAnchorContentHeight = flick.contentHeight
        windowAnchorTimer.restart()
    }
    // 任务1：显式跳转（目录/搜索/笔记/菜单换章）放弃运行锚点事务——跳转有明确
    // 目标位置（paraJumpTimer/followSentence），续章式锚点恢复不应与之竞争。
    function cancelWindowAnchor() {
        flick.pendingWindowAnchor = null
        flick.windowAnchorRetries = 0
        windowAnchorTimer.stop()
    }
    function rebuildScrollModel() {
        if (flick.pageMode === "paged") return
        var rows = []
        var chapters = flick.scrollChapters || []
        if (chapters.length === 0 && flick.chapter && flick.chapter.paragraphs) {
            chapters = [{ index: flick.activeScrollChapter >= 0 ? flick.activeScrollChapter
                        : Math.max(0, flick.chapterIndex - 1), chapter: flick.chapter }]
        }
        for (var c = 0; c < chapters.length; ++c) {
            var entry = chapters[c] || {}
            var source = entry.chapter || {}
            var paras = source.paragraphs || []
            for (var p = 0; p < paras.length; ++p) {
                var raw = paras[p] || {}
                var row = Object.assign({}, raw)
                row.chapterIndex = Number(entry.index)
                row.chapterTitle = String(entry.title || source.title || "")
                row.paragraphIndex = p
                rows.push(row)
            }
        }
        flick.scrollRows = rows
        // 任务1（契约4）：窗口切片优先保留运行锚点段落——锚点行在窗口内时以它为
        // 焦点（保证切片不把它切掉），找不到才按活动章节焦点计算。
        var focus = -1
        var anchor = flick.pendingWindowAnchor
        if (anchor && anchor.chapterIndex !== undefined) {
            for (var a = 0; a < rows.length; ++a) {
                if (rows[a].chapterIndex === Number(anchor.chapterIndex)
                        && rows[a].paragraphIndex === Number(anchor.paragraphIndex)) {
                    focus = a
                    break
                }
            }
        }
        if (focus < 0) {
            var desiredChapter = flick.scrollFocusChapter >= 0
                ? flick.scrollFocusChapter : flick.activeScrollChapter
            for (var n = 0; n < rows.length; ++n) {
                if (rows[n].chapterIndex === desiredChapter
                        && (flick.scrollFocusParagraph < 0
                            || rows[n].paragraphIndex === flick.scrollFocusParagraph)) {
                    focus = n
                    break
                }
            }
        }
        if (focus < 0) focus = 0
        var maxStart = Math.max(0, rows.length - flick.scrollWindowLimit)
        flick.scrollWindowStart = Math.max(0, Math.min(focus - Math.floor(flick.scrollWindowLimit / 3), maxStart))
        flick.scrollModel = rows.slice(flick.scrollWindowStart,
                                       flick.scrollWindowStart + flick.scrollWindowLimit)
        flick.computeSentenceStarts()
    }
    function showScrollChapter(index) {
        // 任务1（契约2）：运行窗口锚点事务由 captureWindowAnchor/windowAnchorTimer
        // 统一处理，这里不再无条件清除 pendingWindowAnchor/windowAnchorTimer——
        // 清除会让跨章换窗后的锚点恢复丢失，重建期间 contentY 被钳回 0（跳回首屏）。
        // restoreAnchor/restoreScrollY 属初次打开/显式跳转路径，由 ReaderPage 各
        // 跳转入口自行清除；此处保留 restoreAnchor=null 兜底（无副作用，见契约3）。
        flick.restoreAnchor = null
        flick.activeScrollChapter = Number(index)
        flick.scrollFocusChapter = flick.activeScrollChapter
        flick.scrollFocusParagraph = -1
        flick.rebuildScrollModel()
    }
    function scrollAnchor() {
        if (flick.pageMode === "paged" || flick.scrollModel.length === 0) return null
        var top = flick.contentY + 2
        for (var i = 0; i < (flick.paragraphRepeater.count || 0); ++i) {
            var it = flick.paragraphRepeater.itemAt(i)
            if (it && it.y + it.height >= top)
                return { chapterIndex: it.paraData.chapterIndex,
                         paragraphIndex: it.paraData.paragraphIndex,
                         offsetY: flick.contentY - it.y }
        }
        return null
    }
    function readingPositionAtViewportCenter() {
        if (flick.pageMode === "paged") {
            var page = flick.currentPage
            var rows = flick.pageModel[page] ? flick.pageModel[page].paragraphs : []
            var first = rows.length > 0 ? Number(rows[0]) : -1
            return { chapterIndex: Math.max(0, Number(flick.chapterIndex) - 1),
                     sentenceIndex: first >= 0 && flick.sentenceStarts.length > first
                         ? Number(flick.sentenceStarts[first]) : 0 }
        }
        var mid = flick.contentY + flick.height / 2
        for (var i = 0; i < rep.count; ++i) {
            var item = rep.itemAt(i)
            if (item && item.y <= mid && item.y + item.height >= mid)
                return { chapterIndex: Number(item.chapterIndex),
                         sentenceIndex: Number(item.sentenceStart) || 0 }
        }
        return { chapterIndex: Number(flick.activeScrollChapter), sentenceIndex: 0 }
    }
    function sentenceIndexAtViewportCenter() {
        return flick.readingPositionAtViewportCenter().sentenceIndex
    }
    function restoreScrollAnchor(anchor) {
        if (!anchor || anchor.chapterIndex === undefined) return
        flick.restoreAnchor = anchor
        flick.restorePending = true
        flick.scheduleRestore()
    }
    property var restoreAnchor: null
    function itemForChapterParagraph(chapter, paragraph) {
        for (var i = 0; i < rep.count; ++i) {
            var item = rep.itemAt(i)
            if (item && item.chapterIndex === chapter && item.paragraphIndex === paragraph)
                return item
        }
        return null
    }
    function focusScrollParagraph(chapter, paragraph) {
        flick.scrollFocusChapter = chapter
        flick.scrollFocusParagraph = paragraph
        flick.rebuildScrollModel()
        flick.pendingScrollTarget = { chapter: chapter, paragraph: paragraph }
        scrollTargetTimer.restart()
    }
    onScrollChaptersChanged: {
        // 任务1（契约2）：scrollChapters 变化走同一运行锚点事务——先捕获当前
        // 视口锚点再重建模型，恢复由 windowAnchorTimer 统一完成；不得先清空
        // 运行锚点（旧实现清空后重建期间 contentY 钳回 0，视口被拉回首屏）。
        // 章节变化（loadChapter/activateChapter）已在本 handler 之前的
        // onChapterChanged 中捕获过同一视口锚点——重建在途时旧委托未布局，
        // 二次捕获可能读到空/错误段落，已有待恢复锚点时不再重复捕获。
        if (!flick.pendingWindowAnchor) flick.captureWindowAnchor()
        flick.rebuildScrollModel()
    }
    property var typography: ({})
    // B3：正文前景色——浅色/米白背景默认深字；深色背景由 ReaderPage 按 bgMode 传浅色。
    // TextEdit.color 作为 QTextDocument 默认前景色，h1-h6 等无显式色的富文本继承。
    // U1：默认取 Kindle 暖白系主文字 Token（lightTextPrimary #1A1A1A）；ReaderPage
    // 总是显式传入 bgMode 对应色（dark → darkTextPrimary），本默认仅独立使用兜底。
    property color textColor: UITheme.lightTextPrimary
    // E4：翻页方式——"scroll"（竖滚连续，默认）/ "paged"（严格横向分页）。
    // paged 使用已挂载 TextEdit 的实际行边界建立页面映射；正文只保留一份连续列，
    // 裁剪视口以映射中的纵向偏移显示当前页，contentX 只承担横向页序与动画职责。
    property string pageMode: "scroll"
    // 每项 { top, bottom, paragraphs }：top/bottom 是共享正文列的真实视觉行边界，
    // paragraphs 为本页相交段落的全局索引。pageCount 为其长度。
    property var pageModel: []
    property int pageCount: 0
    // 任务3 审查修复：逻辑当前页（动画目标即逻辑页）。pagePrev/pageNext 按它
    // 而非 Math.round(contentX/页宽) 计算——动画中途 contentX 处于页间中间值，
    // 四舍五入会把快速反向输入误判到错误页/提前触发换章。goToPage 写入目标页；
    // 无动画运行时的 contentX 变化（拖拽/滚轮/程序化设置）按吸附页同步。
    property int currentPage: 0
    // E4：键盘翻页——上一章请求（scroll 模式 ←，ReaderPage 接 loadChapter(current-1)；
    // loadChapter 内部钳制到 [0, len-1]，边界不越；paged 首页 ← 同样走此信号换章）
    signal requestPrevChapter()
    // 任务2：真实点击桥接——单击正文宿主（本 Flickable 表面）上报视口坐标 x/y
    //（TapHandler 挂在正文宿主而非 ReaderPage 层：旧实现挂在 Page 末尾，被正文
    // Flickable 的按压 grab 吞掉，生产点击永远到不了 handleContentTap 状态机）。
    // DragThreshold 手势策略：位移超阈值即取消（正文拖动/文本选择不受影响，
    // Flickable 拖动照常），观察模式不抢 grab（Sheet 遮罩/顶栏/TtsBar/按钮点击
    // 照常，本桥接只覆盖正文区）。ReaderPage 接 onContentTapped → handleContentTap；
    // 任务3：x 供 paged 模式左右半屏点击翻页（scroll 模式忽略 x）。
    signal contentTapped(real x, real y)
    // B10：滚动位置恢复——ReaderPage 打开时赋保存的 scrollY（>=0），内容高度就绪后应用；
    // 默认 -1 表示"本次打开无需恢复"，避免内容高度变化时反复设置。
    // 应用时机：内容高度**收敛**（200ms 无变化）后——含图片段章节的首趟高度在图片
    // 异步加载完成前就绪，若首趟高度变化即应用会把保存位置钳制偏低；高度每次变化
    // 都重置收敛计时，图片全部加载完、高度稳定后再一次性应用。
    property double restoreScrollY: -1
    property bool restorePending: false
    property bool restoreApplied: false
    // 恢复实际应用的滚动值（applyRestore 写入的 contentY）：恢复窗口内自动续章不触发，
    // 用户随后主动滚动（差值 >1px）即解除恢复态（见 onContentYChanged）
    property double restoreAppliedY: -1
    // ---- 规格 §7：章末自动续章 ----
    // 滚动距底部 autoNextThreshold 内（且用户已实际滚动、非恢复/TTS 跟随）触发
    // requestNextChapter，由 ReaderPage 接住 loadChapter(next)。
    signal requestNextChapter()
    property int autoNextThreshold: 200
    property bool nextChapterRequested: false
    // TTS 朗读会话活动（state != 0，含暂停）：活动期间滚动位置由 followSentence 驱动
    //（非用户意图）；且暂停会话若被滚动换章打断，loadChapter 的 Tts.stop() 会丢弃暂停
    // 进度且不续读——自动续章改走 ReaderPage 的 Tts.chapterCompleted 路径，活动中停用
    property bool ttsActive: false
    // C5：每段起始句子全局索引（sentenceStarts[i] = 前 i 段句子总数），与
    property var sentenceStarts: []
    property int totalSentences: 0
    // scroll 模式保留窗口内段落，但 TTS 游标始终是当前章节内索引；每章
    // 的 sentenceStart 从 0 重新计数，避免前后章节的句数污染当前章节。
    function computeSentenceStarts() {
        var starts = []
        var totals = ({})
        var rows = flick.pageMode === "paged" ? (flick.chapter.paragraphs || []) : flick.scrollModel
        for (var i = 0; i < rows.length; ++i) {
            var row = rows[i] || {}
            var chapter = flick.pageMode === "paged" ? flick.chapterIndex
                : Number(row.chapterIndex ?? flick.activeScrollChapter)
            var key = String(chapter)
            var start = Number(totals[key] || 0)
            starts.push(start)
            totals[key] = start + (row.sentences || []).length
        }
        flick.sentenceStarts = starts
        var activeKey = String(flick.pageMode === "paged" ? flick.chapterIndex
            : flick.activeScrollChapter)
        flick.totalSentences = Number(totals[activeKey] || 0)
    }
    property color highlightColor: "#FFD54F"   // 当前句高亮底色（黄，TTS 朗读游标）
    property alias paragraphRepeater: rep
    // 任务3：paged 页面 Repeater 与横向翻页动画句柄（冒烟测试经此断言页模型同步
    // 与动画互斥——pageAnimX 启动前 followAnim 已停，两动画驱动同一 contentX 方向）
    property alias pageRepeater: pageRep
    property alias pageAnimationX: pageAnimX
    contentWidth: flick.pageMode === "paged" ? Math.max(flick.width, flick.pageCount * flick.width) : flick.width
    // E4 复审：动画句柄（冒烟测试经此断言互斥——pageAnim 启动前 followAnim 已停，
    property alias selectionToolbar: selBar
    property alias colorToolbar: colorBar
    property alias noteDialog: noteDlg
    property alias noteTextArea: noteArea
    // 两动画驱动同一 contentY，并发会让目标互相覆盖）
    property alias pageAnimation: pageAnim
    property alias followAnimation: followAnim
    function laidOutContentHeight() {
        var bottom = 0
        for (var i = 0; i < rep.count; ++i) {
            var item = rep.itemAt(i)
            if (item && item.height > 0) bottom = Math.max(bottom, item.y + item.height)
        }
        return bottom
    }
    contentHeight: flick.pageMode === "paged" ? flick.height : Math.max(0, col.implicitHeight)
    flickableDirection: flick.pageMode === "paged" ? 1 : 0
    function currentChapterBounds() {
        if (flick.pageMode === "paged")
            return { top: 0, bottom: flick.contentHeight }
        var chapter = flick.activeScrollChapter >= 0 ? flick.activeScrollChapter
                                                     : Math.max(0, flick.chapterIndex - 1)
        var top = -1
        var bottom = -1
        for (var i = 0; i < rep.count; ++i) {
            var item = rep.itemAt(i)
            if (!item || Number(item.chapterIndex) !== chapter) continue
            if (top < 0) top = item.y
            bottom = Math.max(bottom, item.y + item.height)
        }
        if (top < 0 || bottom <= top) return { top: 0, bottom: flick.laidOutContentHeight() }
        return { top: top, bottom: bottom }
    }
    function currentChapterPageCount() {
        if (flick.pageMode === "paged") return Math.max(1, flick.pageCount)
        var bounds = flick.currentChapterBounds()
        return Math.max(1, Math.ceil((bounds.bottom - bounds.top) / Math.max(1, flick.height)))
    }
    function currentChapterPageNumber() {
        if (flick.pageMode === "paged") return Math.max(1, flick.currentPage + 1)
        var bounds = flick.currentChapterBounds()
        var y = Math.max(bounds.top, Math.min(flick.contentY, Math.max(bounds.top, bounds.bottom - flick.height)))
        return Math.max(1, Math.min(flick.currentChapterPageCount(),
                                     Math.floor((y - bounds.top) / Math.max(1, flick.height)) + 1))
    }
    function currentChapterProgressRatio() {
        if (flick.pageMode === "paged")
            return flick.pageCount > 0 ? (flick.currentPage + 1) / flick.pageCount : 0
        var bounds = flick.currentChapterBounds()
        var span = Math.max(1, bounds.bottom - bounds.top - flick.height)
        return Math.max(0, Math.min(1, (flick.contentY - bounds.top) / span))
    }
    focus: true
    function dispatchKeyEvent(event) {
        if (flick.handleKey(event.key, event.modifiers, event.isAutoRepeat))
            event.accepted = true
    }
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: (event) => flick.dispatchKeyEvent(event)
    property alias prevPageHint: prevEdgeHint
    property alias nextPageHint: nextEdgeHint
    // ---- C7：划线/笔记 ----
    property int bookId: -1                      // 当前书 id（addHighlight 参数）
    property var highlights: []                   // Highlights.highlightsForBook 结果（ReaderPage 注入）
    property var highlightMap: ({})               // "chapter|sentenceIndex" → 划线 map，O(1) 渲染查表
    property int flashIndex: -1                   // 笔记跳转目标句（临时下划线提示，1.6s 后复位）
    // L5（P0#6）：当前章 1 起索引（ReaderPage 按 Books.currentChapter+1 注入），
    // addHighlight 末参，供笔记按阅读顺序跨章排序
    property int chapterIndex: 0
    // 划线预设色（黄/绿/粉）与默认色（笔记入口无划线时使用）
    property var markerColors: [
        { name: qsTr("黄"), color: "#FFEB3B" },
        { name: qsTr("绿"), color: "#A5D6A7" },
        { name: qsTr("粉"), color: "#F8BBD0" }
    ]
    property string defaultMarkerColor: "#FFEB3B"
    // 当前选择（句全局索引 + 文本 + 所在段），供工具条动作使用
    property int selSentenceIndex: -1
    property string selText: ""
    property int selParaIndex: -1
    // 工具条在**视口**内的目标位置（selBar 是 contentItem 子项，坐标为内容坐标；
    // 通过 x/y 绑定叠加 contentX/contentY 实现视口固定——滚动后工具条仍可见，见 C7 复审）
    property real selBarVpX: 0
    property real selBarVpY: 0
    onChapterChanged: {
        flick.stopPageAnimations()
        if (flick.pageMode === "scroll") {
            // 任务1（契约2）：章节属性变化同样进入运行锚点事务——宿主随后更新
            // scrollChapters 并触发 onScrollChaptersChanged（同事务，捕获同一视口
            // 锚点）；这里重建前先捕获，避免重建后旧视口信息丢失。
            flick.captureWindowAnchor()
            // 宿主随后更新 scrollChapters；不要在此处写入该输入属性，
            // 否则会切断 ReaderPage 的绑定并丢失前后章节窗口。
            flick.activeScrollChapter = Math.max(0, flick.chapterIndex - 1)
            flick.scrollFocusChapter = flick.activeScrollChapter
            flick.scrollFocusParagraph = -1
            flick.restorePending = false
            flick.restoreApplied = false
            flick.restoreAppliedY = -1
            flick.nextChapterRequested = false
            flick.rebuildScrollModel()
        } else {
            flick.contentY = 0
            flick.contentX = 0
            flick.currentPage = 0
            restoreTimer.stop()
            flick.restorePending = false
            flick.restoreApplied = false
            flick.restoreAppliedY = -1
            flick.nextChapterRequested = false
            flick.computeSentenceStarts()
            flick.schedulePageMeasure()
        }
        flick.flashIndex = -1
        flick.hideSelectionToolbar()
    }
    onContentHeightChanged: flick.scheduleRestore()
    // 任务2：点击桥接宿主（见 contentTapped 注释）——与 PdfReaderPage 双击检测
    // 同模式：TapHandler 直接挂 Flickable，DragThreshold 下轻点触发、拖动让给
    // Flickable；point.position 为视口坐标（handler 非视觉项，不随内容滚动）。
    // 任务2复审：根级 TapHandler 覆盖全视口（含选择工具条/色板）。若轻点命中
    // 可见工具条仍发 contentTapped，ReaderPage 会连带开/关 Sheet——按钮点击
    // 不应受阅读页 Sheet 状态机影响。发送前做视口命中过滤：命中 selBar/colorBar
    // 矩形内不上报（工具条自身按钮行为完全不受影响），屏蔽不依赖 Flickable
    // 按压 grab 的隐式仲裁（不同 Qt 版本/输入设备下该仲裁可能变化）。
    TapHandler {
        id: contentTapHandler
        // paged 模式仍需接收边缘点击；Page 负责把上下热区与左右边缘分流。
        enabled: true
        acceptedButtons: Qt.LeftButton
        gesturePolicy: TapHandler.DragThreshold
        function toolbarHitTest(vx, vy) {
            if (selBar.visible) {
                var sl = selBar.mapToItem(flick, 0, 0)
                if (vx >= sl.x && vx <= sl.x + selBar.width && vy >= sl.y && vy <= sl.y + selBar.height) return true
            }
            if (colorBar.visible) {
                var cl = colorBar.mapToItem(flick, 0, 0)
                if (vx >= cl.x && vx <= cl.x + colorBar.width && vy >= cl.y && vy <= cl.y + colorBar.height) return true
            }
            return false
        }
        onTapped: {
            // Flickable 滚到第 N 页后，handler 坐标属于 contentItem；转换为视口坐标，
            // 否则第二页左缘会被错误解释为右缘。
            var viewport = flick.mapFromItem(flick.contentItem, point.position.x, point.position.y)
            if (!contentTapHandler.toolbarHitTest(viewport.x, viewport.y))
                flick.contentTapped(viewport.x, viewport.y)
        }
    }


    onRestoreScrollYChanged: {
        if (flick.restoreScrollY >= 0) {
            flick.restorePending = true
            flick.restoreApplied = false
            flick.scheduleRestore()
        }
    }
    // 已挂载 TextEdit 的布局会在事件循环中完成；统一合并章节、字体、尺寸、模式变化，
    // 再读取实际行边界，避免以字符数或估算高度分页。
    onPageModeChanged: {
        flick.contentX = 0
        flick.contentY = 0
        flick.currentPage = 0
        // 任务2：进入 paged 模式箭头即可见并启动闲置计时（契约2）；离开 paged
        // 立即隐藏并停表（scroll 模式无边缘翻页提示）。
        if (flick.pageMode === "paged") flick.showEdgeHints()
        else {
            flick.edgeHintsVisible = false
            edgeHintHideTimer.stop()
        }
        flick.schedulePageMeasure()
    }
    onTypographyChanged: flick.schedulePageMeasure()
    onWidthChanged: flick.schedulePageMeasure()
    onHeightChanged: flick.schedulePageMeasure()
    // 任务3：paged 横向滚动收敛吸附——contentX 变化（拖拽/滚轮/程序化设置）后
    // 200ms 无变化即 snapToPage 补齐页边界；键盘翻页动画（pageAnimX）目标本就
    // 在页边界，吸附为幂等 no-op。ttsActive/恢复窗口内跳过（同 scroll 纵吸附门控）。
    onContentXChanged: {
        if (flick.pageMode === "paged" && !flick.ttsActive && !flick.restorePending)
            snapTimer.restart()
        // 任务3 审查修复：无动画运行（拖拽/滚轮/程序化设置/钳制）时按吸附页同步
        // 逻辑当前页；pageAnimX 运行期间 contentX 是页间中间值，逻辑页由动画目标
        //（goToPage 已写 currentPage）决定，中间值不参与计算。
        if (flick.pageMode === "paged" && !flick.pageAnimationX.running) {
            var w = flick.pageWidth()
            flick.currentPage = Math.max(0,
                Math.min(Math.round(flick.contentX / w), flick.pageCount - 1))
        }
    }

    // ---- 严格横向分页模型 ----
    // 只根据已渲染 TextEdit 的 QTextDocument 行布局分页；不使用文本长度、字体或行高
    // 估算。页面从第一条未容纳的完整视觉行开始，故每页单调、非空，长段落自然拆页。
    Timer {
        id: pageMeasureTimer
        interval: 16
        repeat: false
        onTriggered: flick.rebuildPageModel()
    }

    function schedulePageMeasure() {
        flick.stopPageAnimations()
        if (flick.pageMode !== "paged") return
        pageMeasureTimer.restart()
    }

    function rebuildPageModel() {
        var logicalPage = flick.currentPage
        flick.stopPageAnimations()
        var paras = flick.chapter.paragraphs ?? []
        if (flick.pageMode !== "paged" || paras.length === 0 || flick.width <= 0 || flick.height <= 0) {
            flick.pageModel = []
            flick.pageCount = 0
            flick.currentPage = 0
            return
        }
        var visualLines = []
        for (var i = 0; i < rep.count; ++i) {
            var para = rep.itemAt(i)
            if (!para) continue
            if (para.pureImage) {
                if (para.height > 0)
                    visualLines.push({ top: para.y, bottom: para.y + para.height, paragraph: i })
                continue
            }
            var textItem = para.textItem
            var breaks = ReaderText.lineBreaks(textItem)
            for (var j = 0; j < breaks.length; ++j) {
                var line = breaks[j]
                if (line.bottom > line.top)
                    visualLines.push({ top: para.y + textItem.y + line.top,
                                       bottom: para.y + textItem.y + line.bottom,
                                       paragraph: i })
            }
        }
        if (visualLines.length === 0) {
            pageMeasureTimer.restart()
            return
        }
        var pages = []
        var first = 0
        while (first < visualLines.length) {
            var pageTop = visualLines[first].top
            var last = first
            var paragraphs = []
            while (last < visualLines.length) {
                var candidate = visualLines[last]
                if (last > first && candidate.bottom - pageTop > flick.height + 0.01) break
                if (paragraphs.indexOf(candidate.paragraph) < 0) paragraphs.push(candidate.paragraph)
                ++last
            }
            pages.push({ top: pageTop, bottom: visualLines[last - 1].bottom,
                         paragraphs: paragraphs })
            first = last
        }
        flick.pageModel = pages
        flick.pageCount = pages.length
        flick.currentPage = Math.max(0, Math.min(logicalPage, pages.length - 1))
        flick.contentY = 0
        flick.contentX = flick.currentPage * flick.pageWidth()
    }

    // 页宽 = 视口宽（paged 页沿 x 轴每页占满一屏）
    function pageWidth() {
        return Math.max(1, flick.width)
    }

    // 段落全局索引 → 首个相交页号（-1 = 未找到）。长段落可跨页，朗读/搜索定位到
    // 它的首个完整视觉行所在页。
    function pageForParagraph(pi) {
        for (var p = 0; p < flick.pageCount; p++)
            if ((flick.pageModel[p].paragraphs ?? []).indexOf(pi) >= 0) return p
        return -1
    }

    // 正文只实例化一次，两个模式均从主 Repeater 返回同一个段落 Item。
    function paragraphItemAt(pi) {
        return pi < 0 ? null : rep.itemAt(pi)
    }

    // 定位到指定页（钳制到 [0, pageCount-1]，页边界 = 页号×页宽，动画驱动 contentX）
    // 审查修复：currentPage 即逻辑当前页（动画目标）；目标与当前位置一致但仍有
    // 在途动画（如快速反向输入取消上一动画）时必须先停掉，否则旧动画把 contentX
    // 写回旧目标。
    function goToPage(p) {
        if (flick.pageCount <= 0) return
        p = Math.max(0, Math.min(p, flick.pageCount - 1))
        flick.currentPage = p
        var target = p * flick.pageWidth()
        if (Math.abs(target - flick.contentX) < 1 && !flick.pageAnimationX.running) return
        flick.stopPageAnimations()   // 互斥：两动画驱动同一 contentX 方向，启动前停掉对方
        if (Math.abs(target - flick.contentX) < 1) return
        pageAnimX.to = target
        pageAnimX.start()
    }

    function stopPageAnimations() {
        // stop() 会同步触发 onStopped；清除自然到达标志后再停，
        // 中断的动画绝不能被当作抵达章末。
        flick.checkNextOnStop = false
        if (followAnim) followAnim.stop()
        if (pageAnim) pageAnim.stop()
        if (pageAnimX) pageAnimX.stop()
    }

    // 规格 §7：章末自动续章——距底部 autoNextThreshold 内（且用户已实际滚动，contentY>0）
    // 触发 requestNextChapter。恢复窗口内不触发（恢复把用户拽到保存位置，非主动滚动）；
    // TTS 会话活动（播放/暂停）与动画滚动（搜索跳转/朗读跟随）中同样不触发——
    // 朗读续章走 chapterCompleted 路径，暂停会话不应被滚动换章打断丢弃。
    // 任务3：paged 横向滚动收敛吸附计时器（拖拽/滚轮经 onContentXChanged 重启）；
    // snapToPage 内部有 ttsActive/恢复窗口门控，键盘翻页动画（pageAnimX）目标本就
    // 在页边界，吸附为幂等 no-op。
    Timer {
        id: snapTimer
        interval: 200
        repeat: false
        onTriggered: flick.snapToPage()
    }
    onContentYChanged: {
        if (flick.restoreApplied && flick.restoreAppliedY >= 0
                && Math.abs(flick.contentY - flick.restoreAppliedY) > 1)
            flick.restoreApplied = false
        // 任务1：事务在途且用户主动滚动（内容高度稳定未塌缩、contentY 已移动）时
        // 重捕获锚点——offscreen/慢帧下模型重建可能延迟到用户滚动之后，过期锚点
        // 会把视口拽回旧位置；重建塌缩与恢复写入（windowAnchorRestoring）不重捕获，
        // 恢复写入本身已按捕获位置钳位。重捕获后继续走激活/自动续章检查。
        if (!flick.windowAnchorRestoring && flick.pendingWindowAnchor
                && flick.windowAnchorContentHeight > 0
                && flick.contentHeight >= flick.windowAnchorContentHeight - 0.5
                && Math.abs(flick.contentY - flick.windowAnchorY) > 1) {
            flick.captureWindowAnchor()
        }
        flick.checkChapterActivation()
        flick.checkAutoNext()
    }

    function checkAutoNext() {
        if (flick.pageMode === "paged") return
        if (flick.nextChapterRequested || flick.checkNextOnStop || flick.restorePending
                || flick.restoreApplied || flick.ttsActive || followAnim.running || pageAnim.running
                || flick.contentHeight <= 0 || flick.height <= 0)
            return
        if (flick.contentY <= 0 || flick.contentY < flick.contentHeight - flick.height - 1) return
        for (var i = 0; i < flick.scrollModel.length; ++i)
            if (flick.scrollModel[i].chapterIndex > flick.activeScrollChapter) return
        flick.nextChapterRequested = true
        flick.requestNextChapter()
    }

    function checkChapterActivation() {
        if (flick.pageMode === "paged" || flick.scrollModel.length === 0) return
        // 任务1：仅两类重建过渡态不得按视口中线激活——(a) 锚点恢复写入 contentY
        // 的瞬间（windowAnchorRestoring，恢复的是捕获位置，非用户滚动）；
        // (b) 重建塌缩期间（内容高度低于捕获时，contentY 被钳回 0）。其余时刻
        //（用户滚动到真实位置，即使事务在途）正常激活，保证跨章连续语义。
        if (flick.windowAnchorRestoring) return
        if (flick.pendingWindowAnchor && flick.windowAnchorContentHeight > 0
                && flick.contentHeight < flick.windowAnchorContentHeight - 0.5) return
        var mid = flick.contentY + flick.height / 2
        for (var i = 0; i < rep.count; ++i) {
            var it = rep.itemAt(i)
            if (it && it.y <= mid && it.y + it.height >= mid) {
                var ci = it.chapterIndex
                if (ci >= 0 && ci !== flick.activeScrollChapter) {
                    flick.activeScrollChapter = ci
                    flick.requestChapterActivation(ci)
                }
                return
            }
        }
    }

    onHighlightsChanged: flick.rebuildHighlightMap()

    Timer {
        id: restoreTimer
        interval: 200
        repeat: false
        onTriggered: flick.applyRestore()
    }
    Timer {
        id: scrollTargetTimer
        interval: 16
        repeat: false
        onTriggered: {
            var target = flick.pendingScrollTarget
            if (!target) return
            var item = flick.itemForChapterParagraph(target.chapter, target.paragraph)
            if (!item) {
                scrollTargetTimer.restart()
                return
            }
            flick.pendingScrollTarget = null
            var maxY = Math.max(0, flick.contentHeight - flick.height)
            followAnim.stop()
            followAnim.to = Math.max(0, Math.min(item.y - flick.height / 3, maxY))
            followAnim.start()
            flick.scheduleRestore()
        }
    }
    Timer {
        id: windowAnchorTimer
        // 任务1：模型重建在下一帧（polish）才落地，0ms 自旋会在旧委托上恢复导致
        // 随后重建再钳回 0；改 16ms 并等委托数与模型同步后才按新布局恢复，超限放弃。
        interval: 16
        repeat: false
        onTriggered: {
            var anchor = flick.pendingWindowAnchor
            if (!anchor) return
            var item = flick.itemForChapterParagraph(Number(anchor.chapterIndex),
                                                      Number(anchor.paragraphIndex))
            // 委托未随模型同步（重建在途/锚点段落被窗口切片）→ 有限重试；
            // 只做钳制，不写入 0，也不无限自旋。
            if (!item || flick.paragraphRepeater.count !== flick.scrollModel.length) {
                if (flick.windowAnchorRetries++ < 60) {
                    windowAnchorTimer.restart()
                    return
                }
                flick.pendingWindowAnchor = null
                flick.windowAnchorY = -1
                flick.windowAnchorContentHeight = -1
                return
            }
            flick.windowAnchorRestoring = true
            flick.contentY = Math.max(0, Math.min(item.y + Number(anchor.offsetY || 0),
                Math.max(0, flick.contentHeight - flick.height)))
            flick.windowAnchorRestoring = false
            // 任务1：恢复写入完成即清空事务状态——该 contentY 变化触发的章节激活
            // 在 windowAnchorRestoring 期间已被门控（不把显式换章反向拉回旧章）。
            flick.pendingWindowAnchor = null
            flick.windowAnchorY = -1
            flick.windowAnchorContentHeight = -1
        }
    }

    function paragraphForIndex(index) {
        var chapter = flick.ttsActive ? Number(Tts.chapter)
            : (flick.pageMode === "paged"
                ? Math.max(0, Number(flick.chapterIndex) - 1)
                : (flick.activeScrollChapter >= 0 ? flick.activeScrollChapter
                    : Math.max(0, Number(flick.chapterIndex) - 1)))
        var n = flick.sentenceStarts.length
        for (var i = 0; i < n; ++i) {
            var item = flick.paragraphRepeater.itemAt(i)
            if (!item || (flick.pageMode === "scroll" && Number(item.chapterIndex) !== chapter)) continue
            var start = Number(flick.sentenceStarts[i] || 0)
            var end = start + Number(item.sentenceCount || 0)
            if (index >= start && index < end) return i
        }
        return -1
    }

    function scheduleRestore() {
        if (!flick.restorePending || flick.restoreApplied || flick.contentHeight <= 0) return
        restoreTimer.restart()
    }
    function applyRestore() {
        if (!flick.restorePending || flick.restoreApplied || flick.contentHeight <= 0) return
        if (flick.pageMode === "paged") {
            flick.restorePending = false
            return
        }
        if (flick.restoreAnchor) {
            var anchor = flick.restoreAnchor
            var candidate = flick.itemForChapterParagraph(Number(anchor.chapterIndex),
                                                           Number(anchor.paragraphIndex))
            if (!candidate) {
                flick.focusScrollParagraph(Number(anchor.chapterIndex), Number(anchor.paragraphIndex))
                restoreTimer.restart()
                return
            }
            flick.restoreAppliedY = Math.max(0, Math.min(candidate.y + Number(anchor.offsetY || 0),
                Math.max(0, flick.contentHeight - flick.height)))
            flick.restoreAnchor = null
        }
        if (flick.restoreAppliedY < 0) {
            var savedY = Number(flick.restoreScrollY)
            flick.restoreAppliedY = savedY >= 0
                ? Math.max(0, Math.min(savedY, Math.max(0, flick.contentHeight - flick.height))) : 0
        }
        flick.restoreApplied = true
        flick.restorePending = false
        flick.contentY = flick.restoreAppliedY
    }

    // C8：全文搜索跳转——定位到指定段落。scroll：滚动到视口上 1/3 处（同
    // followSentence）；paged：直接翻到该段所在页（页内位置固定为整页，无页内偏移）。
    function scrollToParagraph(pi) {
        if (flick.restorePending) return
        if (flick.pageMode === "paged") {
            var pg = flick.pageForParagraph(pi)
            if (pg >= 0) flick.goToPage(pg)
            return
        }
        if (flick.contentHeight <= 0) return
        var chapter = flick.activeScrollChapter >= 0 ? flick.activeScrollChapter
                                                      : Math.max(0, flick.chapterIndex - 1)
        var item = flick.itemForChapterParagraph(chapter, pi)
        if (!item) {
            flick.focusScrollParagraph(chapter, pi)
            return
        }
        var targetY = item.y - flick.height / 3
        var maxY = Math.max(0, flick.contentHeight - flick.height)
        followAnim.stop()
        followAnim.to = Math.max(0, Math.min(targetY, maxY))
        followAnim.start()
    }

    // 滚动跟随：当前句所在段落定位到视口上 1/3 处（平滑动画）；paged 模式
    // 翻到该段所在页（pageAnimX 横向，页内整页呈现无需再定位）。
    function followSentence(index) {
        if (flick.restorePending) return
        var pi = flick.paragraphForIndex(index)
        if (pi < 0) return
        if (flick.pageMode === "paged") {
            var pg = flick.pageForParagraph(pi)
            if (pg >= 0) flick.goToPage(pg)
            return
        }
        if (flick.contentHeight <= 0) return
        var item = rep.itemAt(pi)
        if (!item) return
        var targetY = item.y - flick.height / 3
        var maxY = Math.max(0, flick.contentHeight - flick.height)
        followAnim.stop()
        followAnim.to = Math.max(0, Math.min(targetY, maxY))
        followAnim.start()
    }

    // ---- E4：方向键翻页 + 横向翻页模式 ----
    // 统一按键入口（Keys.onPressed 与冒烟测试共用；测试经 handleKey 注入，
    // 避免 quicktest harness 合成键盘事件不可靠——同 C7 选择注入取舍）。
    // 修饰键不拦截（Ctrl/Cmd/Shift 组合留给系统与文本选择）；弹层/Dialog
    // 打开时焦点在弹层内，本组件 Keys 不触发（不干扰输入框）。
    // scroll 模式：↑↓/PageUp/PageDown 滚动一视口页，←/→ 翻章；
    // paged 模式：四向 + PageUp/PageDown 均按视口高度整页翻动（←/→ 翻页而非翻章）。
    // isAutoRepeat（键盘按住自动重复 30-60Hz）：scroll 翻章与 paged 翻章
    // 动作忽略重复事件（连按一次只翻一章/翻一页，不因按住连翻多章）；
    // scroll 翻页/paged 翻页是内容位移动作，重复无害（同拖拽滚动语义）。
    function handleKey(key, modifiers, isAutoRepeat) {
        if (modifiers !== Qt.NoModifier) return false
        if (flick.pageMode === "paged") {
            switch (key) {
            case Qt.Key_Up: case Qt.Key_PageUp: case Qt.Key_Left:
            case Qt.Key_W: case Qt.Key_A:
                flick.pagePrev(isAutoRepeat); return true
            case Qt.Key_Down: case Qt.Key_PageDown: case Qt.Key_Right:
            case Qt.Key_S: case Qt.Key_D:
                flick.pageNext(isAutoRepeat); return true
            }
            return false
        }
        switch (key) {
        case Qt.Key_Up: case Qt.Key_PageUp: case Qt.Key_W:
            flick.scrollPage(-1, isAutoRepeat); return true
        case Qt.Key_Down: case Qt.Key_PageDown: case Qt.Key_S:
            flick.scrollPage(1, isAutoRepeat); return true
        case Qt.Key_Left: case Qt.Key_A:
            if (!isAutoRepeat) flick.requestPrevChapter(); return true
        case Qt.Key_Right: case Qt.Key_D:
            if (!isAutoRepeat) flick.requestNextChapter(); return true
        }
        return false
    }

    // scroll 模式：滚动一视口页（± 视口高度，钳制到 [0, maxY]）。
    function scrollPage(dir, isAutoRepeat) {
        if (flick.contentHeight <= 0 || flick.height <= 0) return
        var maxY = Math.max(0, flick.contentHeight - flick.height)
        var target = Math.max(0, Math.min(flick.contentY + dir * flick.height, maxY))
        if (Math.abs(target - flick.contentY) < 1) {
            if (dir > 0 && !isAutoRepeat) flick.requestNextChapter()
            return
        }
        followAnim.stop()
        pageAnim.stop()
        flick.checkNextOnStop = true
        pageAnim.to = target
        pageAnim.start()
    }

    // paged 模式：上一页——按页宽横向整页回退（contentX 页边界 = 页号×页宽）。
    // 首页（contentX=0，目标==当前）时翻页语义变为翻上一章（requestPrevChapter →
    // ReaderPage.autoPrevChapter 兜底首章不换），与 pageNext 章末翻章对称；
    // 短章（一页放得下）同样触发。
    function pagePrev(isAutoRepeat) {
        if (flick.pageCount <= 0 || flick.width <= 0) return
        // 审查修复：按逻辑当前页（动画目标）而非动画中间值 Math.round(contentX/页宽)
        // 计算——快速反向输入时中间值会把 ← 误判为首页提前翻上一章
        if (flick.currentPage <= 0) {
            if (!isAutoRepeat) flick.requestPrevChapter()
            return
        }
        flick.goToPage(flick.currentPage - 1)
    }

    // paged 模式：下一页——按页宽横向整页前进；已到末页（目标 == 当前）时翻页
    // 语义变为翻章（requestNextChapter → ReaderPage.autoNextChapter 兜底末章不换），
    // 与"翻过章末进入下一章"的真实书籍语义一致；短章（一页放得下）同样触发。
    function pageNext(isAutoRepeat) {
        if (flick.pageCount <= 0 || flick.width <= 0) return
        // 审查修复：同 pagePrev——按逻辑当前页计算，动画中间值不得提前换章/丢页
        if (flick.currentPage >= flick.pageCount - 1) {
            if (!isAutoRepeat) flick.requestNextChapter()
            return
        }
        flick.goToPage(flick.currentPage + 1)
    }

    // paged 模式：拖拽/滚轮滚动收敛后吸附到最近页边界（页宽粒度，contentX）。
    // 键盘翻页走 pagePrev/pageNext 已按边界定位，无需吸附；TTS 跟随/恢复窗口内
    // 跳过（ttsActive 门控）。触发源：onMovementEnded（拖拽/惯性）与
    // onContentXChanged → snapTimer（滚轮/程序化设置，200ms 收敛）。
    function snapToPage() {
        if (flick.pageMode !== "paged") return
        if (flick.restorePending || flick.restoreApplied || flick.ttsActive) return
        if (flick.pageCount <= 0 || flick.width <= 0) return
        var w = flick.pageWidth()
        var maxX = Math.max(0, (flick.pageCount - 1) * w)
        var nearest = Math.max(0, Math.min(Math.round(flick.contentX / w) * w, maxX))
        // 末页可能被拖到非页边界：maxX 更近时以其为吸附目标（其余页面 maxX 远在
        // 视口外，行为不变）——与 scroll 纵吸附的 U6 末页停靠位同语义。
        if (Math.abs(maxX - flick.contentX) < Math.abs(nearest - flick.contentX))
            nearest = maxX
        if (Math.abs(nearest - flick.contentX) < 1) return
        flick.goToPage(Math.round(nearest / w))
    }
    onMovementEnded: if (flick.pageMode === "paged") flick.snapToPage()

    // ---- C7：划线查表 ----
    // 从划线列表重建 "chapter|sentenceIndex" → 划线 map（供渲染与查重用）
    function rebuildMapFrom(list) {
        var m = {}
        var rows = list ?? []
        for (var i = 0; i < rows.length; i++) {
            var h = rows[i]
            if (!h || h.sentenceIndex === undefined || h.sentenceIndex < 0) continue
            var key = (h.chapter || "") + "|" + h.sentenceIndex
            m[key] = h
        }
        flick.highlightMap = m
    }
    function rebuildHighlightMap() {
        flick.rebuildMapFrom(flick.highlights ?? [])
    }

    // C7：划线增删改后自刷新查表（ReaderPage 另经 highlights 属性注入并维护笔记列表——
    // 两者幂等；本组件自持保证脱离 ReaderPage 使用时查重/渲染一致，且不动 highlights
    // 属性，避免切断 ReaderPage 的绑定）
    Connections {
        target: Highlights
        function onHighlightsChanged(bookId) {
            if (flick.bookId > 0 && bookId === flick.bookId)
                flick.rebuildMapFrom(Highlights.highlightsForBook(flick.bookId))
        }
    }

    // 笔记列表跳转：目标句下划线提示 1.6s（滚动由 ReaderPage 调 followSentence 完成）
    function flashSentence(index) {
        flick.flashIndex = index
        flashTimer.restart()
    }
    Timer {
        id: flashTimer
        interval: 1600
        repeat: false
        onTriggered: flick.flashIndex = -1
    }

    // ---- C7：选择工具条 ----
    // 真实选择路径（TextEdit.onSelectedTextChanged）与测试注入路径共用。
    // 定位：先映射到视口坐标（flick）做可见区钳制（flick.height 为可见高度），
    // 再换算回内容坐标（selBar 是 Flickable 声明子项 → 挂在 contentItem，坐标为内容坐标，
    // 与文本一起滚动，滚动后仍在选中句附近且不超出视口）
    function showSelectionToolbar(txt, globalIdx, text) {
        if (globalIdx < 0 || !text) return
        flick.selText = text
        flick.selSentenceIndex = globalIdx
        flick.selParaIndex = flick.paragraphForIndex(globalIdx)
        if (flick.selParaIndex < 0) return
        var pos = Math.max(0, txt.selectionStart)
        var rect = txt.positionToRectangle(pos)
        // 映射到视口坐标（flick）并钳制在可见区（flick.height 为可见高度）；
        // selBar 的 x/y 绑定叠回 content 偏移 → 视口固定，滚动不丢
        var vp = txt.mapToItem(flick, rect.x, rect.y)
        flick.selBarVpX = Math.max(0, Math.min(vp.x, flick.width - selBar.width))
        // C7b：优先放选中内容上方；上方空间不足（选中句贴近视口顶，钳到 0
        // 会覆盖所选文字）→ 翻到选中内容下方（以选中**末端**为基准，多行
        // 选择时仍完整让出）
        var aboveY = vp.y - selBar.height - 6
        if (aboveY >= 0) {
            flick.selBarVpY = Math.min(aboveY, flick.height - selBar.height)
        } else {
            var endPos = Math.max(0, txt.selectionEnd > txt.selectionStart
                                     ? txt.selectionEnd - 1 : txt.selectionStart)
            var endRect = txt.positionToRectangle(endPos)
            var endVp = txt.mapToItem(flick, endRect.x, endRect.y)
            flick.selBarVpY = Math.min(endVp.y + endRect.height + 6,
                                       flick.height - selBar.height)
        }
        selBar.visible = true
        colorBar.visible = false
    }

    function hideSelectionToolbar() {
        selBar.visible = false
        colorBar.visible = false
        flick.selText = ""
        flick.selSentenceIndex = -1
        flick.selParaIndex = -1
    }

    function clearSelection() {
        var it = flick.paragraphItemAt(flick.selParaIndex)
        if (it && it.children[0] && it.children[0].deselect)
            it.children[0].deselect()
        flick.hideSelectionToolbar()
    }

    // 划线色板显隐：位置由 x/y 绑定跟随工具条（同一视口固定帧，滚动时同步）
    function toggleColorBar() {
        if (colorBar.visible)
            colorBar.visible = false
        else
            colorBar.visible = true
    }

    // 划线：命中已划线句 → 复用其行 id 更新颜色（不产生重复行）；
    // 否则以 (bookId, chapterTitle, sentenceIndex, text, color) 落库。
    // Highlights.highlightsChanged → ReaderPage.reloadHighlights → 本组件 highlights
    // 更新 → rebuildHighlightMap → 逐句重渲染（绑定依赖 flick.highlightMap）
    function doAddHighlight(color) {
        if (flick.bookId <= 0 || flick.selSentenceIndex < 0 || !flick.selText) return
        var key = (flick.chapter.title || "") + "|" + flick.selSentenceIndex
        var mk = flick.highlightMap[key]
        if (mk && mk.id > 0)
            Highlights.updateColor(mk.id, color)
        else
            Highlights.addHighlight(flick.bookId, flick.chapter.title,
                                    flick.selSentenceIndex, flick.selText, color, "",
                                    flick.chapterIndex)
        flick.clearSelection()
    }

    // 笔记：已有划线 → 直接编辑其 note；无划线 → 先以默认色建划线再填 note
    function openNoteDialog() {
        if (flick.bookId <= 0 || flick.selSentenceIndex < 0 || !flick.selText) return
        var key = (flick.chapter.title || "") + "|" + flick.selSentenceIndex
        var mk = flick.highlightMap[key]
        noteArea.text = mk ? (mk.note || "") : ""
        // C7b：无原有划线时自动创建默认色划线（供 note 附着）；记录 autoCreated，
        // 取消时回滚删除，避免残留默认色划线
        noteDlg.autoCreated = !mk
        noteDlg.targetId = mk ? mk.id : Highlights.addHighlight(flick.bookId, flick.chapter.title,
                                                                flick.selSentenceIndex, flick.selText,
                                                                flick.defaultMarkerColor, "",
                                                                flick.chapterIndex)
        noteDlg.open()
    }

    // 测试注入路径：模拟"选择了全局句 globalIdx 的 text"，走真实定位逻辑
    function simulateSelection(globalIdx, text) {
        var pi = flick.paragraphForIndex(globalIdx)
        if (pi < 0) return
        var it = flick.paragraphItemAt(pi)
        if (!it) return
        flick.showSelectionToolbar(it.children[0], globalIdx, text)
    }

    // C5：朗读游标/换章（setSentences 复位游标 0）驱动高亮与滚动；
    // 规格 §7：TTS 播放中滚动位置由 followSentence 驱动（非用户意图），自动续章
    // 走 ReaderPage 的 chapterCompleted 路径，此处仅跟踪 playing 状态供 checkAutoNext 判定。
    Connections {
        target: Tts
        // 任务1：每次换章加载 ttsForChapter 都会调 Tts.setSentences → 同步发出
        // sentenceChanged(0)。那是游标复位副作用，不是朗读推进；若在此启动
        // followSentence 的 300ms 动画，会把 contentY 拽回 0（跨章跳回首屏的
        // 另一来源），并覆盖运行窗口锚点的恢复。注意 setSentences 在换章的同
        // 一个同步调用栈内发出信号——onChapterChanged 要下一帧才触发、运行锚点
        // 尚未捕获，仅凭 pendingWindowAnchor 无法拦截；必须由 ReaderPage 在
        // ttsForChapter 内用 suppressTtsFollow 标记复位区间。朗读会话真实推进
        //（sentenceChanged 于复位区间外发出）与显式游标移动（TtsBar 跳句/播放
        // 起始）仍照常跟随；运行锚点事务在途（pendingWindowAnchor 非空）时
        // 同样跳过跟随，保证恢复写入不被动画覆盖。
        function onSentenceChanged(index) {
            if (flick.suppressTtsFollow) return
            if (!flick.pendingWindowAnchor) flick.followSentence(index)
        }
        function onStateChanged(state) { flick.ttsActive = state !== 0 }
    }

    // TTS 跟随与搜索跳转独占纵向滚动；翻页动画启动前会显式停止它。
    NumberAnimation {
        id: followAnim
        target: flick
        property: "contentY"
        duration: 300
        easing.type: Easing.OutCubic
    }


    // E4：按键翻页/横翻吸附专用动画（与 followAnim 分离：TTS 跟随/搜索跳转走
    // followAnim，不受翻页动画 onStopped 检查干扰）。
    property bool checkNextOnStop: false
    NumberAnimation {
        id: pageAnim
        target: flick
        property: "contentY"
        duration: 300
        easing.type: Easing.OutCubic
        onStopped: {
            if (!flick.checkNextOnStop) return
            flick.checkNextOnStop = false
            if (flick.pageMode === "scroll") {
                flick.checkChapterActivation()
                flick.checkAutoNext()
            }
        }
    }
    // 任务3：paged 横向翻页/TTS 跟随/搜索跳转共用动画（驱动 contentX）。
    // 与 followAnim（contentY）互斥：goToPage 启动前显式停 followAnim/pageAnim，
    // 避免两个动画同向驱动互相覆盖。
    NumberAnimation {
        id: pageAnimX
        target: flick
        property: "contentX"
        duration: 300
        easing.type: Easing.OutCubic
    }

    // ---- 任务3：段落渲染共享组件 ----
    // scroll 主 Repeater（rep）与 paged 页内 Repeater（pageComp → pageParaRep）
    // 共用同一 paraComp，保证两模式 text/html/image 渲染语义完全一致；同一段落
    // 只会挂在一个 Repeater 上（另一侧 model 置空），无双重渲染。
    // paraData/globalIndex 按上下文判别：scroll 的 modelData 是段落对象（index 为
    // 全局段落号）；paged 页内 Repeater 的 modelData 是段落全局索引数字。两者统一
    // 收敛到 paraData（段落对象）/ globalIndex（全局段落号）两个属性上。
    Component {
        id: paraComp
        Item {
            id: para
            property var paraData: (modelData !== null && typeof modelData === "object")
                ? modelData : ((flick.chapter.paragraphs ?? [])[modelData] ?? {})
            // 复审修复：scroll 模式下段落为 null（解析器异常数据）时 modelData 为
            // null，旧逻辑落入 (modelData ?? 0) 把 null 段落映射为全局索引 0——
            // 其 sentenceStart 错取第 0 段起始、句/划线索引错位。null/undefined
            // 统一按 Repeater 自身 index 处理（scroll 模式 Repeater index = 段落
            // 全局索引）；paged 模式 modelData 恒为数字（段落全局索引，index 是
            // 页内位置），object 恒为 scroll 段落对象 → 均不受影响。
            property int globalIndex: {
                var md = modelData
                if (md === null || md === undefined) return index
                if (typeof md === "object") return index
                return md
            }
            readonly property int chapterIndex: Number(para.paraData.chapterIndex ?? flick.chapterIndex)
            readonly property string chapterTitle: String(para.paraData.chapterTitle ?? flick.chapter.title ?? "")
            readonly property int paragraphIndex: Number(para.paraData.paragraphIndex ?? para.globalIndex)
            width: para.parent ? para.parent.width : 0
            // 纯图片段（html 去掉 img 标签后无其他内容）走 Image 分支等比缩放；
            // 混合段（如 "文本 <img> 文本"，EpubParser 对段内行内图同时填 html 与 imagePath）
            // 走 Text(RichText)——html 内 img src 为本地绝对路径，Qt 富文本可直接渲染。
            readonly property bool pureImage: !!para.paraData.imagePath
                && (para.paraData.html ?? "").replace(/<img[^>]*>/gi, "").trim().length === 0
            // 解析器输出的行内图 src 为无 scheme 的本地绝对路径；QQuickText 会按文档 URL
            // （qrc 模块地址）解析导致加载失败，统一补 file:// 前缀（已有 scheme 的保持原样）
            readonly property string mixedHtml: para.pureImage ? "" : (para.paraData.html ?? "")
                .replace(/src="([^"]*)"/g, function (m, p) {
                    return /^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(p) ? m : 'src="file://' + p + '"'
                })
            // C5 逐句高亮：本段句子与全局起始索引
            readonly property var sentences: para.paraData.sentences ?? []
            readonly property int sentenceStart: (flick.sentenceStarts.length > para.globalIndex)
                ? flick.sentenceStarts[para.globalIndex] : 0
            readonly property int sentenceCount: para.sentences.length
            readonly property int hlInPara: Tts.currentIndex - para.sentenceStart
            readonly property bool inHighlightRange: para.hlInPara >= 0
                && para.hlInPara < para.sentenceCount
            implicitHeight: para.pureImage ? imgPara.height : txt.implicitHeight
            // C7：段落用只读 TextEdit 渲染（富文本渲染与 Text 一致）。
            // 注意：Qt 6.7 起 Text 移除了 selectByMouse/selectedText/selectionStart/
            // positionToRectangle 等选择 API（deprecated 后删除），TextEdit 才是
            // 支持鼠标选择的富文本项——readOnly + selectByMouse 即"可选中不可编辑"。
            TextEdit {
                id: txt
                visible: !para.pureImage
                width: parent.width
                textFormat: TextEdit.RichText
                text: para.buildText()
                // B3：默认前景色随 flick.textColor（富文本 h1-h6 等无显式色的文本继承）
                color: flick.textColor
                // C5：Kindle 默认衬线感——未指定字体时回退思源宋体（衬线），
                // 与 SettingsStore 的 typography/fontFamily 新默认一致
                font.family: flick.typography.fontFamily ?? "思源宋体 VF"
                font.pixelSize: flick.typography.fontSize ?? 18
                horizontalAlignment: flick.typography.align === "center" ? Text.AlignHCenter
                                    : (flick.typography.align === "right" ? Text.AlignRight : Text.AlignLeft)
                wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                readOnly: true
                selectByMouse: true
                cursorVisible: false
                activeFocusOnPress: false
                // C7：行距经 ReaderText 助手施加到富文本文档（TextEdit 无 lineHeight 属性；
                // 文本/字号/行距变化时重施加，与 Text.lineHeight 语义一致）
                readonly property real lineSpacing: flick.typography.lineHeight ?? 1.6
                // 重入守卫：mergeBlockFormat 会触发文档 contentsChanged → textChanged
                // 再次进入本函数（无守卫会递归直至栈溢出）；首次应用后格式相同不再变化
                property bool applyingSpacing: false
                function applyLineSpacing() {
                    if (txt.applyingSpacing) return
                    txt.applyingSpacing = true
                    ReaderText.applyLineSpacing(txt, txt.lineSpacing)
                    txt.applyingSpacing = false
                }
                Component.onCompleted: txt.applyLineSpacing()
                onTextChanged: txt.applyLineSpacing()
                onFontChanged: txt.applyLineSpacing()
                onLineSpacingChanged: txt.applyLineSpacing()
                // C7：松开鼠标 selectedText 非空 → 弹工具条
                onSelectedTextChanged: {
                    if (txt.selectedText.length > 0)
                        para.handleSelection()
                    else
                        flick.hideSelectionToolbar()
                }
            }
            // 分页测量使用同一份正文委托的实际 TextEdit。
            property alias textItem: txt
            Image {
                id: imgPara
                visible: para.pureImage
                width: parent.width
                // 按源图宽高比换算高度（implicit 尺寸即源尺寸）
                height: imgPara.implicitWidth > 0 ? parent.width * imgPara.implicitHeight / imgPara.implicitWidth : 0
                fillMode: Image.PreserveAspectFit
                source: para.paraData.imagePath ? "file://" + para.paraData.imagePath : ""
            }

            // 段内是否含真实行内标记（b/i/em/strong/hN/img/br——解析器实际输出集）：
            // 纯文本段才做逐句 span；含标记段走富文本整段高亮，避免静默丢格式
            function hasMarkup(html) {
                return /<(b|i|em|strong|h[1-6]|img|br)\b/i.test(html)
            }
            function escapeHtml(s) {
                return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
            }

            // C7：全局句索引 → 划线 map 命中（无划线返回 null）
            function markerFor(k) {
                var g = para.sentenceStart + k
                return flick.highlightMap[(flick.chapter.title || "") + "|" + g] || null
            }
            // C7：富文本段取段内首个划线色（整段背景近似）
            function paraMarkerColor() {
                for (var m = 0; m < para.sentenceCount; m++) {
                    var mk = para.markerFor(m)
                    if (mk && mk.color) return mk.color
                }
                return ""
            }
            // C7：单句 span——划线色优先（朗读游标叠加时划线色为底 + 下划线），
            // 未划线且是朗读当前句 → TTS 黄底；跳转提示额外下划线。
            // B3 复审：高亮底恒为浅色板（TTS 黄/划线黄绿粉），追加显式深色前景
            // color:#212121——否则 dark 模式文档默认前景 #E0E0E0 浅字浅底，
            // 对比度仅约 1.1-1.6:1；深字不随背景模式变化（浅底场景下与默认
            // 深字一致，无视觉回归）。
            function sentenceSpan(k, s) {
                var mk = para.markerFor(k)
                // D2：朗读游标（黄底 / 划线句的下划线叠加）仅朗读会话激活时生效——
                // Tts.currentIndex 在 setSentences 时复位为 0 且 state=0，若不门控，
                // 未朗读也会把首段首句误标为"当前句"；划线句底色不受影响（划线是
                // 用户主动操作保留，见 C7），仅不再叠加"朗读游标"下划线
                var isCur = para.inHighlightRange && k === para.hlInPara && flick.ttsActive
                var isFlash = (para.sentenceStart + k) === flick.flashIndex
                var styles = []
                if (mk && mk.color) {
                    styles.push("background-color:" + mk.color)
                    styles.push("color:#212121")
                    if (isCur) styles.push("text-decoration:underline")
                } else if (isCur) {
                    styles.push("background-color:" + flick.highlightColor)
                    styles.push("color:#212121")
                }
                if (isFlash && styles.indexOf("text-decoration:underline") < 0)
                    styles.push("text-decoration:underline")
                if (styles.length === 0) return s
                return "<span style='" + styles.join(";") + "'>" + s + "</span>"
            }

            // 显示用富文本：纯文本段每句独立 span（划线色 / 当前句高亮）；富文本段整段高亮
            function buildText() {
                if (para.pureImage) return ""
                var htmlSrc = para.mixedHtml
                var plain = htmlSrc.length === 0 || !para.hasMarkup(htmlSrc)
                if (plain) {
                    var parts = []
                    for (var k = 0; k < para.sentenceCount; k++) {
                        var s = para.escapeHtml(para.sentences[k])
                        parts.push(para.sentenceSpan(k, s))
                    }
                    if (parts.length > 0) return parts.join("")
                    // 无句子（如解析器未分句）→ 回退原文（纯文本按字面转义）
                    return para.escapeHtml(para.paraData.text ?? "")
                }
                // 富文本段：无法逐句定位 → 段内任一划线句整段背景（近似，取首个划线色）；
                // 与朗读整段高亮叠加时以划线色为底（取舍：富文本段不做逐句，见 C7 报告）。
                // 注意：外层必须用 <div>（块级）而非 <span>——Qt 富文本会丢弃包裹块级
                // 元素的 span 背景（C5 富文本段高亮因此从未实际渲染，C7 顺带修复）。
                // B3 复审：高亮底恒为浅色板，追加 color:#212121 避免 dark 模式浅字浅底
                //（div 上的默认前景色，段内显式色 span 仍优先覆盖，同 C7 划线色保留）。
                var mc = para.paraMarkerColor()
                if (mc.length > 0)
                    return "<div style='background-color:" + mc + ";color:#212121'>" + htmlSrc + "</div>"
                // D2：富文本段整段黄标同样仅朗读会话激活（未朗读 currentIndex=0
                // 不误标首段；划线色 div 分支在上方已优先返回，不受影响）
                if (para.inHighlightRange && flick.ttsActive && htmlSrc.length > 0)
                    return "<div style='background-color:" + flick.highlightColor + ";color:#212121'>" + htmlSrc + "</div>"
                return htmlSrc
            }

            // C7：选择起点（Text.selectionStart，文档字符流坐标）→ 段内句子序号。
            // 纯文本段文档流 = 各句拼接（span 标记不占字符），逐句长度累加定位
            function sentenceIndexAt(docPos) {
                var acc = 0
                for (var k = 0; k < para.sentenceCount; k++) {
                    acc += para.sentences[k].length
                    if (docPos < acc) return k
                }
                return para.sentenceCount - 1 // 段尾选择（含全选）钳制到末句
            }
            function handleSelection() {
                if (txt.selectedText.length > 0)
                    flick.showSelectionToolbar(txt, para.sentenceStart + para.sentenceIndexAt(txt.selectionStart),
                                               txt.selectedText)
                else
                    flick.hideSelectionToolbar()
            }
        }
    }

    // ---- paged 页面占位 Repeater ----
    // 正文不在页委托中复制；pageRepeater 仅保留公开句柄并反映 pageModel 数量。
    Component {
        id: pageComp
        Item {
            width: flick.width
            height: flick.height
        }
    }

    // C5：正文列 Kindle 化——页宽系数外再设**档位相关**上限：宽窗口下正文列不再无限
    // 拉宽，保持"书本栏"比例（Kindle 桌面版同样固定阅读列宽，居中于窗口）。
    // 档位上限随页宽档递增（narrow 520 / normal 700 / wide 880），宽窗下三档仍保持
    // 可区分（页宽切换在任意窗宽都生效；窄窗由系数主导，上限只约束宽窗）。
    // 任务3：scroll 模式唯一渲染路径；paged 时 model 置空（页面走 pageRow，
    // C5：正文列 Kindle 化——同一份委托同时服务 scroll 与 paged；paged 仅移动该列的
    // 横向锚点和实际页顶，不复制正文，也不提供任何页内滚动路径。
    Column {
        id: col
        visible: true
        x: flick.pageMode === "paged"
            ? flick.contentX + (flick.width - col.width) / 2
            : (flick.width - col.width) / 2
        y: flick.pageMode === "paged" && flick.pageModel.length > 0
            ? -Number(flick.pageModel[flick.currentPage].top || 0) : 0
        width: Math.min(flick.width * flick.pageWidthFactor(), Math.max(1, flick.width - 48), flick.pageWidthCap())
        spacing: 8
        Repeater {
            id: rep
            model: flick.pageMode === "paged" ? (flick.chapter.paragraphs ?? []) : flick.scrollModel
            delegate: paraComp
        }
    }
    // ---- 任务3：paged 横向页序列（页面沿 x 轴排列，每页占满一屏宽）----
    Row {
        id: pageRow
        visible: flick.pageMode === "paged"
        x: 0
        y: 0
        width: flick.pageCount * flick.width
        height: flick.height
        Repeater {
            id: pageRep
            model: flick.pageModel
            delegate: pageComp
        }
    }

    // ---- BUG4：paged 左右边缘翻页提示 ----
    // 半透明圆角箭头条，垂直居中贴左右边缘；纯视觉（不挂 MouseArea/TapHandler，
    // 不拦截点击——边缘点击仍由根级 contentTapHandler 上报 ReaderPage 翻页）。
    // 视口固定：x 叠加 contentX（同 selBar 模式；paged 下 contentY 恒 0）；
    // z 低于选择工具条（selBar/colorBar z:10）。仅 paged 模式显示；Sheet/菜单
    // 打开时被全页遮罩盖住，无需额外显隐联动。
    // 任务2（契约2）：闲置隐藏状态机——进入 paged 模式（onPageModeChanged）即显示
    // 并启动 edgeHintHideTimer；到期后两箭头隐藏；鼠标在视口左右约 15% 热区移动时
    // 重新显示并重启计时（悬停由 ReaderPage 的 C3 NoButton MouseArea 上报——Qt 把
    // hover 路由给最顶层项，正文内 HoverHandler 收不到，见 ReaderPage C3 注释）；
    // 鼠标停留不移动时 Timer 仍可到期隐藏。测试注入短 edgeHintHideDelay 验证显隐。
    property int edgeHintHideDelay: 3000
    property bool edgeHintsVisible: false
    function showEdgeHints() {
        if (flick.pageMode !== "paged") return
        flick.edgeHintsVisible = true
        edgeHintHideTimer.restart()
    }
    // 任务2：视口悬停上报（ReaderPage C3 MouseArea 每次位置变化调用）——命中
    // 左右约 15% 热区即重新显示并重启计时；中部移动不干预（Timer 照常到期隐藏）。
    function notifyEdgeHintHover(vx) {
        if (flick.pageMode !== "paged") return
        if (vx <= flick.width * 0.15 || vx >= flick.width * 0.85)
            flick.showEdgeHints()
    }
    Timer {
        id: edgeHintHideTimer
        interval: flick.edgeHintHideDelay
        repeat: false
        onTriggered: flick.edgeHintsVisible = false
    }
    Rectangle {
        id: prevEdgeHint
        visible: flick.pageMode === "paged" && flick.edgeHintsVisible
        x: flick.contentX + 10
        y: flick.contentY + flick.height / 2 - prevEdgeHint.height / 2
        width: 36
        height: 52
        radius: 8
        color: "#2E000000"
        z: 5
        Text {
            anchors.centerIn: parent
            text: "‹"
            color: "white"
            font.pixelSize: 26
        }
    }
    Rectangle {
        id: nextEdgeHint
        visible: flick.pageMode === "paged" && flick.edgeHintsVisible
        x: flick.contentX + flick.width - nextEdgeHint.width - 10
        y: flick.contentY + flick.height / 2 - nextEdgeHint.height / 2
        width: 36
        height: 52
        radius: 8
        color: "#2E000000"
        z: 5
        Text {
            anchors.centerIn: parent
            text: "›"
            color: "white"
            font.pixelSize: 26
        }
    }

    // ---- C7：选择工具条（复制/划线/笔记），位于选中句上方 ----
    // 复制经隐藏 TextEdit 的 copy() 走系统剪贴板——Qt 6 已无 QML Clipboard 单例
    //（Qt.labs.platform 的 Clipboard 类型在 Qt 6 移除、Qt.clipboardText 亦移除），
    // TextEdit.copy() 内部经 QGuiApplication::clipboard() 写入，是标准可用路径，
    // 无额外依赖。text → selectAll → copy 顺序不可调换（改 text 会重置选区）。
    TextEdit {
        id: copyBridge
        visible: false
        function copyText(s) {
            copyBridge.text = s
            copyBridge.selectAll()
            copyBridge.copy()
        }
    }
    Rectangle {
        id: selBar
        visible: false
        // 视口固定：内容坐标 = 视口目标 + 滚动偏移（contentX 恒为 0，公式保留一般性）
        x: flick.contentX + flick.selBarVpX
        y: flick.contentY + flick.selBarVpY
        width: 166   // 3 按钮 × 52 + 间距（Rectangle 不随子项自动撑宽）
        height: 34
        radius: 6
        color: "#EE303030"
        z: 10
        Row {
            anchors.fill: parent
            spacing: 2
            component SelBtn: Button {
                required property string lbl
                text: lbl
                font.pixelSize: 12
                implicitWidth: 52
                implicitHeight: 28
                contentItem: Text {
                    text: parent.text
                    color: "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: parent.down ? "#55FFFFFF" : "transparent"
                    radius: 4
                }
            }
            SelBtn {
                lbl: qsTr("复制")
                onClicked: {
                    if (flick.selText.length > 0)
                        copyBridge.copyText(flick.selText)
                    flick.clearSelection()
                }
            }
            SelBtn {
                lbl: qsTr("划线")
                onClicked: flick.toggleColorBar()
            }
            SelBtn {
                lbl: qsTr("笔记")
                onClicked: flick.openNoteDialog()
            }
        }
    }

    // ---- C7：划线色板（黄/绿/粉），位于工具条下方 ----
    Rectangle {
        id: colorBar
        visible: false
        // 跟随工具条（工具条视口固定 → 色板同样视口固定）；C7b：底部空间不足
        // （工具条贴近视口底，硬钳到视口底会与工具条重叠）→ 翻到工具条上方
        x: Math.max(0, Math.min(selBar.x, flick.width - colorBar.width))
        y: (selBar.y + selBar.height + 4 + colorBar.height <= flick.contentY + flick.height)
               ? selBar.y + selBar.height + 4
               : Math.max(flick.contentY, selBar.y - colorBar.height - 4)
        width: 92    // 3 色块 × 20 + 间距 + 内边距
        height: 32
        radius: 6
        color: "#EE303030"
        z: 10
        Row {
            anchors.centerIn: parent
            spacing: 8
            Repeater {
                model: flick.markerColors
                delegate: Rectangle {
                    width: 20
                    height: 20
                    radius: 10
                    color: modelData.color
                    border.color: "#99FFFFFF"
                    MouseArea {
                        anchors.fill: parent
                        onClicked: flick.doAddHighlight(modelData.color)
                    }
                }
            }
        }
    }

    // ---- C7：笔记 Dialog（划线后填 note / 直接加 note）----
    Dialog {
        id: noteDlg
        title: qsTr("笔记")
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        width: 380
        height: 250
        property int targetId: -1
        // C7b：目标划线是否为本次自动创建（无原有划线时）——取消需回滚删除
        property bool autoCreated: false
        contentItem: ColumnLayout {
            spacing: 12
            Label {
                text: qsTr("为这条划线添加笔记：")
                // U6：辅助文字改 Token（原硬编码 #555555——深色对话框下近不可读）
                color: UITheme.textSecondary
            }
            TextArea {
                id: noteArea
                Layout.fillWidth: true
                Layout.preferredHeight: 130
                placeholderText: qsTr("写下你的想法…")
                wrapMode: TextEdit.Wrap
            }
        }
        onAccepted: {
            if (noteDlg.targetId > 0)
                Highlights.updateNote(noteDlg.targetId, noteArea.text)
            flick.clearSelection()
        }
        onRejected: {
            // 取消：仅本次自动创建的划线需要回滚（原有划线保留不动）
            if (noteDlg.autoCreated && noteDlg.targetId > 0)
                Highlights.removeHighlight(noteDlg.targetId)
            flick.clearSelection()
        }
    }

    function pageWidthFactor() {
        return {narrow: 0.55, normal: 0.7, wide: 0.85}[flick.typography.pageWidth ?? "normal"]
    }
    // C5：页宽档位对应的列宽上限（px）——宽窗下保持档位差异（见 col.width 注释）
    function pageWidthCap() {
        return {narrow: 520, normal: 700, wide: 880}[flick.typography.pageWidth ?? "normal"]
    }
}
