import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Pdf
import Readdict.Backend

// PDF 阅读页（B9）：QtQuick.Pdf 的 PdfScrollablePageView 单页滚动视图。
// 注意：Qt 6.7 起 QML 模块由 QtPdf 更名为 QtQuick.Pdf，PdfScrollablePageView
// 不再自带 source，须外置 PdfDocument 绑定 document；缩放 API 由 scaleMode
// 枚举改为 scaleToWidth/scaleToPage 方法（双击在两者间切换）。
// 阅读进度独立键 progress/pdf_<bookId>（存页码），与文本书的
// progress/<bookId>（存章节索引）区分——B10 进度恢复按 format 分流读取。
Page {
    id: page
    // U2：沉浸页标识（Main 据此隐藏标签/底部导航；返回后恢复）
    property string navId: "pdf"
    property var book: ({})
    property string theme: "auto"
    // false = 宽度适配（fitToWidth），true = 整页适配（fitToViewport）
    property bool fitPage: false
    // 暴露给测试/上层：文档状态、页数、页码跳转（B10 进度恢复经此 goToPage）
    property alias pdfDocument: pdfDoc
    property alias pdfView: pdfView
    // B10：恢复完成前不写进度——Ready 后首次 currentPageChanged(0) 不得覆盖保存值
    property bool restoreDone: false
    // B10：关闭竞态防护——QPdfDocument 销毁（FPDF_DestroyLibrary）若撞上
    // QQuickPixmapReader 在途渲染（QPdfIOHandler 持文档指针）会 use-after-free 崩溃
    //（30MB 大 PDF 实测复现）。返回键先等渲染稳定（无在途读取）再 pop，
    // 慢渲染仅告警不强制销毁（强制销毁即复现该 UAF）。
    property bool closing: false
    property int closePollCount: 0

    PdfDocument {
        id: pdfDoc
        source: book.path ? "file://" + book.path : ""
        // 文档就绪后：先跳转到保存页（progress/pdf_<bookId>），再放开进度写入
        onStatusChanged: (status) => {
            if (status !== PdfDocument.Ready || page.restoreDone || !page.book.id) return
            const saved = Number(Settings.value("progress/pdf_" + page.book.id)) || 0
            if (saved > 0) pdfView.goToPage(saved)
            page.restoreDone = true
            page.recordProgress()
        }
    }

    PdfScrollablePageView {
        id: pdfView
        anchors.fill: parent
        anchors.topMargin: 44
        document: pdfDoc
        // 阅读进度：当前页变化 → settings.json 的 progress/pdf_<bookId>（写时持久化）
        // + books.progress 百分比（页码/总页数，含 last_read_at）
        onCurrentPageChanged: {
            if (page.restoreDone)
                page.recordProgress()
        }
        // 双击切换宽度适配 / 整页适配
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: if (tapCount === 2) page.toggleFit()
        }
    }

    // 顶部栏：返回 + 书名（与 ReaderPage 同模式）
    Rectangle {
        id: topBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 44
        color: "#E6FFFFFF"
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: "#1A000000"
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 12
            spacing: 8
            ToolButton {
                text: qsTr("返回")
                onClicked: page.requestClose()
            }
            Label {
                Layout.fillWidth: true
                text: page.book.title ?? ""
                elide: Text.ElideRight
                font.bold: true
                color: "#1A1A1A"
            }
        }
    }

    function toggleFit() {
        page.fitPage = !page.fitPage
        if (page.fitPage)
            pdfView.scaleToPage(pdfView.width, pdfView.height)
        else
            pdfView.scaleToWidth(pdfView.width, pdfView.height)
    }

    // 记录当前页：页码写 settings.json，百分比+last_read_at 写 books（书架进度条联动）
    function recordProgress() {
        if (!page.book.id || pdfDoc.status !== PdfDocument.Ready || pdfDoc.pageCount <= 0) return
        Settings.setValue("progress/pdf_" + page.book.id, pdfView.currentPage)
        Books.setProgress(page.book.id, (pdfView.currentPage + 1) / pdfDoc.pageCount)
    }

    // 无在途渲染：image.status 为 Ready（渲染完成）/ Error / Null（无渲染任务）时安全
    function renderSettled() {
        const s = pdfView.status
        return s === Image.Ready || s === Image.Error || s === Image.Null
    }

    // 关闭阅读页：等渲染线程空闲再 pop（文档销毁撞在途渲染 = UAF 崩溃）。
    // 渲染在途时持续轮询等待，**绝不**在渲染未稳定时强制销毁文档——慢渲染
    //（大 PDF 高倍率重渲染可达数秒）超时强制 pop 会把 UAF 换一种方式放回来；
    // 超长渲染（>60s）仅告警，保持等待直到稳定（Ready 文档的渲染必然完成）。
    function requestClose() {
        if (page.closing) return
        page.closing = true
        page.closePollCount = 0
        if (page.renderSettled()) {
            page.StackView.view.pop()
            return
        }
        closePoll.start()
    }

    Timer {
        id: closePoll
        interval: 50
        repeat: true
        onTriggered: {
            ++page.closePollCount
            if (page.renderSettled()) {
                closePoll.stop()
                page.StackView.view.pop()
                return
            }
            if (page.closePollCount === 1200) // 60s：仅告警，不强制销毁
                console.warn("PdfReaderPage: 渲染 60 秒未稳定，继续等待（书: " + page.book.title + "）")
        }
    }

    Component.onCompleted: {
        if (page.book && page.book.id)
            Books.startTracking(page.book.id)  // 阅读计时开始
    }

    Component.onDestruction: {
        Books.stopTracking()  // 结算阅读秒数
    }
}
