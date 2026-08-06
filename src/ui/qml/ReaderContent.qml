import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.Backend

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
    property var typography: ({})
    // B10：滚动位置恢复——ReaderPage 打开时赋保存的 scrollY（>=0），内容高度就绪后应用；
    // 默认 -1 表示"本次打开无需恢复"，避免内容高度变化时反复设置。
    // 应用时机：内容高度**收敛**（200ms 无变化）后——含图片段章节的首趟高度在图片
    // 异步加载完成前就绪，若首趟高度变化即应用会把保存位置钳制偏低；高度每次变化
    // 都重置收敛计时，图片全部加载完、高度稳定后再一次性应用。
    property double restoreScrollY: -1
    property bool restorePending: false
    property bool restoreApplied: false
    // C5：每段起始句子全局索引（sentenceStarts[i] = 前 i 段句子总数），与
    // ReaderPage 拍平喂给 Tts.setSentences 的顺序一致；totalSentences 供测试断言。
    property var sentenceStarts: []
    property int totalSentences: 0
    property color highlightColor: "#FFD54F"   // 当前句高亮底色（黄，TTS 朗读游标）
    property alias paragraphRepeater: rep
    // ---- C7：划线/笔记 ----
    property int bookId: -1                      // 当前书 id（addHighlight 参数）
    property var highlights: []                   // Highlights.highlightsForBook 结果（ReaderPage 注入）
    property var highlightMap: ({})               // "chapter|sentenceIndex" → 划线 map，O(1) 渲染查表
    property int flashIndex: -1                   // 笔记跳转目标句（临时下划线提示，1.6s 后复位）
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
    // 测试/外部可访问的 UI 句柄
    property alias selectionToolbar: selBar
    property alias colorToolbar: colorBar
    property alias noteDialog: noteDlg
    property alias noteTextArea: noteArea
    clip: true
    contentWidth: width
    contentHeight: col.implicitHeight

    // 翻章回到顶部：不继承上一章的滚动偏移（否则新章内容矮时被 Flickable 钳制到中间）；
    // 同时取消未应用的恢复——restoreScrollY 属于打开时的章节，收敛窗口内翻章时若继续
    // 等待会把新章节拽到旧偏移，必须作废（重开恢复不受影响：ReaderPage.onCompleted 在
    // loadChapter 之后才赋 restoreScrollY，届时本 handler 已把 pending 清空）
    onChapterChanged: {
        flick.contentY = 0
        restoreTimer.stop()
        flick.restorePending = false
        flick.restoreApplied = false
        flick.computeSentenceStarts()
        // C7：章节变了，旧选择/跳转提示作废
        flick.flashIndex = -1
        flick.hideSelectionToolbar()
    }

    onRestoreScrollYChanged: {
        if (flick.restoreScrollY >= 0) {
            flick.restorePending = true
            flick.restoreApplied = false
            flick.scheduleRestore()
        }
    }
    onContentHeightChanged: flick.scheduleRestore()

    onHighlightsChanged: flick.rebuildHighlightMap()

    Timer {
        id: restoreTimer
        interval: 200
        repeat: false
        onTriggered: flick.applyRestore()
    }

    // C7：跳转提示 1.6s 后复位
    Timer {
        id: flashTimer
        interval: 1600
        repeat: false
        onTriggered: flick.flashIndex = -1
    }

    function scheduleRestore() {
        if (!flick.restorePending || flick.restoreApplied || flick.contentHeight <= 0) return
        restoreTimer.restart() // 高度仍在变化 → 推迟应用，直到收敛
    }

    function applyRestore() {
        if (!flick.restorePending || flick.restoreApplied || flick.contentHeight <= 0) return
        flick.restoreApplied = true
        flick.restorePending = false
        // 章节高度可能因排版参数/图片加载变化，钳制到实际最大滚动值
        flick.contentY = Math.min(flick.restoreScrollY, Math.max(0, flick.contentHeight - flick.height))
    }

    // C5：由段落 sentences 长度累加出每段起始句子索引（与 ReaderPage 拍平顺序一致）
    function computeSentenceStarts() {
        var starts = []
        var acc = 0
        var paras = flick.chapter.paragraphs ?? []
        for (var i = 0; i < paras.length; i++) {
            starts.push(acc)
            acc += (paras[i].sentences ?? []).length
        }
        flick.sentenceStarts = starts
        flick.totalSentences = acc
    }

    // 全局句子索引 → 段落序号（-1 = 无匹配，如章末 atEnd 游标）
    function paragraphForIndex(index) {
        var n = flick.sentenceStarts.length
        for (var i = 0; i < n; i++) {
            var end = (i + 1 < n) ? flick.sentenceStarts[i + 1] : flick.totalSentences
            if (index >= flick.sentenceStarts[i] && index < end) return i
        }
        return -1
    }

    // C8：全文搜索跳转——滚动到指定段落（定位到视口上 1/3 处，同 followSentence）。
    // 段落后于句子粒度，经 rep.itemAt 直接取段落 y，不依赖句子映射。
    function scrollToParagraph(pi) {
        if (flick.restorePending || flick.contentHeight <= 0) return
        var item = rep.itemAt(pi)
        if (!item) return
        var targetY = item.y - flick.height / 3
        var maxY = Math.max(0, flick.contentHeight - flick.height)
        followAnim.stop()
        followAnim.to = Math.max(0, Math.min(targetY, maxY))
        followAnim.start()
    }

    // 滚动跟随：当前句所在段落定位到视口上 1/3 处（平滑动画）
    function followSentence(index) {
        if (flick.restorePending || flick.contentHeight <= 0) return
        var pi = flick.paragraphForIndex(index)
        if (pi < 0) return
        var item = rep.itemAt(pi)
        if (!item) return
        var targetY = item.y - flick.height / 3
        var maxY = Math.max(0, flick.contentHeight - flick.height)
        followAnim.stop()
        followAnim.to = Math.max(0, Math.min(targetY, maxY))
        followAnim.start()
    }

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
        var it = rep.itemAt(flick.selParaIndex)
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
                                    flick.selSentenceIndex, flick.selText, color)
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
                                                                flick.defaultMarkerColor)
        noteDlg.open()
    }

    // 测试注入路径：模拟"选择了全局句 globalIdx 的 text"，走真实定位逻辑
    function simulateSelection(globalIdx, text) {
        var pi = flick.paragraphForIndex(globalIdx)
        if (pi < 0) return
        var it = rep.itemAt(pi)
        if (!it) return
        flick.showSelectionToolbar(it.children[0], globalIdx, text)
    }

    // C5：朗读游标/换章（setSentences 复位游标 0）驱动高亮与滚动
    Connections {
        target: Tts
        function onSentenceChanged(index) { flick.followSentence(index) }
    }

    NumberAnimation {
        id: followAnim
        target: flick
        property: "contentY"
        duration: 320
        easing.type: Easing.OutCubic
    }

    Column {
        id: col
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(flick.width * flick.pageWidthFactor(), flick.width - 48)
        spacing: 8
        Repeater {
            id: rep
            model: flick.chapter.paragraphs ?? []
            delegate: Item {
                id: para
                width: col.width
                // 纯图片段（html 去掉 img 标签后无其他内容）走 Image 分支等比缩放；
                // 混合段（如 "文本 <img> 文本"，EpubParser 对段内行内图同时填 html 与 imagePath）
                // 走 Text(RichText)——html 内 img src 为本地绝对路径，Qt 富文本可直接渲染。
                readonly property bool pureImage: !!modelData.imagePath
                    && (modelData.html ?? "").replace(/<img[^>]*>/gi, "").trim().length === 0
                // 解析器输出的行内图 src 为无 scheme 的本地绝对路径；QQuickText 会按文档 URL
                // （qrc 模块地址）解析导致加载失败，统一补 file:// 前缀（已有 scheme 的保持原样）
                readonly property string mixedHtml: para.pureImage ? "" : (modelData.html ?? "")
                    .replace(/src="([^"]*)"/g, function (m, p) {
                        return /^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(p) ? m : 'src="file://' + p + '"'
                    })
                // C5 逐句高亮：本段句子与全局起始索引
                readonly property var sentences: modelData.sentences ?? []
                readonly property int sentenceStart: (flick.sentenceStarts.length > index)
                    ? flick.sentenceStarts[index] : 0
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
                    font.family: flick.typography.fontFamily ?? "思源黑体 VF"
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
                Image {
                    id: imgPara
                    visible: para.pureImage
                    width: parent.width
                    // 按源图宽高比换算高度（implicit 尺寸即源尺寸）
                    height: imgPara.implicitWidth > 0 ? parent.width * imgPara.implicitHeight / imgPara.implicitWidth : 0
                    fillMode: Image.PreserveAspectFit
                    source: modelData.imagePath ? "file://" + modelData.imagePath : ""
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
                // 未划线且是朗读当前句 → TTS 黄底；跳转提示额外下划线
                function sentenceSpan(k, s) {
                    var mk = para.markerFor(k)
                    var isCur = para.inHighlightRange && k === para.hlInPara
                    var isFlash = (para.sentenceStart + k) === flick.flashIndex
                    var styles = []
                    if (mk && mk.color) {
                        styles.push("background-color:" + mk.color)
                        if (isCur) styles.push("text-decoration:underline")
                    } else if (isCur) {
                        styles.push("background-color:" + flick.highlightColor)
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
                        return para.escapeHtml(modelData.text ?? "")
                    }
                    // 富文本段：无法逐句定位 → 段内任一划线句整段背景（近似，取首个划线色）；
                    // 与朗读整段高亮叠加时以划线色为底（取舍：富文本段不做逐句，见 C7 报告）。
                    // 注意：外层必须用 <div>（块级）而非 <span>——Qt 富文本会丢弃包裹块级
                    // 元素的 span 背景（C5 富文本段高亮因此从未实际渲染，C7 顺带修复）。
                    var mc = para.paraMarkerColor()
                    if (mc.length > 0)
                        return "<div style='background-color:" + mc + "'>" + htmlSrc + "</div>"
                    if (para.inHighlightRange && htmlSrc.length > 0)
                        return "<div style='background-color:" + flick.highlightColor + "'>" + htmlSrc + "</div>"
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
    }

    // ---- C7：选择工具条（复制/划线/笔记），位于选中句上方 ----
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
                        Clipboard.text = flick.selText
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
                color: "#555555"
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
}
