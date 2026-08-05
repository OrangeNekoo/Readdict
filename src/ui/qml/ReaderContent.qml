import QtQuick

// 章节内容渲染：Flickable + Column + Repeater。
// chapter:   {title, paragraphs:[{text, html, level, imagePath}]}（Books.loadChapter 返回）
// typography:{fontFamily, fontSize, lineHeight, align, pageWidth}
// 图片段落（imagePath 非空）用 Image 渲染，其余段落用 Text(RichText) 渲染；
// 标题级别由 html 内的 <h1..h6> 体现（Qt RichText 自带标题字号）。
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
    clip: true
    contentWidth: width
    contentHeight: col.implicitHeight

    // 翻章回到顶部：不继承上一章的滚动偏移（否则新章内容矮时被 Flickable 钳制到中间）
    onChapterChanged: flick.contentY = 0

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

    Column {
        id: col
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(flick.width * flick.pageWidthFactor(), flick.width - 48)
        spacing: 8
        Repeater {
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
                implicitHeight: para.pureImage ? imgPara.height : txt.implicitHeight
                Text {
                    id: txt
                    visible: !para.pureImage
                    width: parent.width
                    textFormat: Text.RichText
                    text: para.mixedHtml.length > 0 ? para.mixedHtml : (modelData.text ?? "")
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
            }
        }
    }

    function pageWidthFactor() {
        return {narrow: 0.55, normal: 0.7, wide: 0.85}[flick.typography.pageWidth ?? "normal"]
    }
}
