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
    clip: true
    contentWidth: width
    contentHeight: col.implicitHeight

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
