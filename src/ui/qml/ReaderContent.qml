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
                width: col.width
                implicitHeight: imgPara.visible ? imgPara.height : txt.implicitHeight
                Text {
                    id: txt
                    visible: !imgPara.visible
                    width: parent.width
                    textFormat: Text.RichText
                    text: modelData.html ?? modelData.text ?? ""
                    font.family: flick.typography.fontFamily ?? "思源黑体 VF"
                    font.pixelSize: flick.typography.fontSize ?? 18
                    lineHeight: flick.typography.lineHeight ?? 1.6
                    horizontalAlignment: flick.typography.align === "center" ? Text.AlignHCenter
                                        : (flick.typography.align === "right" ? Text.AlignRight : Text.AlignLeft)
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }
                Image {
                    id: imgPara
                    visible: !!modelData.imagePath
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
