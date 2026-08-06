import QtQuick
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
    property color highlightColor: "#FFD54F"   // 当前句高亮底色（黄）
    property alias paragraphRepeater: rep
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
    }

    onRestoreScrollYChanged: {
        if (flick.restoreScrollY >= 0) {
            flick.restorePending = true
            flick.restoreApplied = false
            flick.scheduleRestore()
        }
    }
    onContentHeightChanged: flick.scheduleRestore()

    Timer {
        id: restoreTimer
        interval: 200
        repeat: false
        onTriggered: flick.applyRestore()
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
                Text {
                    id: txt
                    visible: !para.pureImage
                    width: parent.width
                    textFormat: Text.RichText
                    text: para.buildText()
                    font.family: flick.typography.fontFamily ?? "思源黑体 VF"
                    font.pixelSize: flick.typography.fontSize ?? 18
                    lineHeight: flick.typography.lineHeight ?? 1.6
                    horizontalAlignment: flick.typography.align === "center" ? Text.AlignHCenter
                                        : (flick.typography.align === "right" ? Text.AlignRight : Text.AlignLeft)
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
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
                // 显示用富文本：纯文本段每句独立 span（当前句包高亮）；富文本段整体包高亮
                function buildText() {
                    if (para.pureImage) return ""
                    var htmlSrc = para.mixedHtml
                    var plain = htmlSrc.length === 0 || !para.hasMarkup(htmlSrc)
                    var hl = para.hlInPara
                    if (plain) {
                        var parts = []
                        for (var k = 0; k < para.sentenceCount; k++) {
                            var s = para.escapeHtml(para.sentences[k])
                            if (para.inHighlightRange && k === hl)
                                s = "<span style='background-color:" + flick.highlightColor + "'>" + s + "</span>"
                            parts.push(s)
                        }
                        if (parts.length > 0) return parts.join("")
                        // 无句子（如解析器未分句）→ 回退原文（纯文本按字面转义）
                        return para.escapeHtml(modelData.text ?? "")
                    }
                    if (para.inHighlightRange && htmlSrc.length > 0)
                        return "<span style='background-color:" + flick.highlightColor + "'>" + htmlSrc + "</span>"
                    return htmlSrc
                }
            }
        }
    }

    function pageWidthFactor() {
        return {narrow: 0.55, normal: 0.7, wide: 0.85}[flick.typography.pageWidth ?? "normal"]
    }
}
