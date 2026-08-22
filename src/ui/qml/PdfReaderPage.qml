import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Pdf
import QtQuick.Window
import Readdict.Backend
import Readdict.UI 1.0

// PDF 阅读页（B9）：双方向视图——scroll 用 QtQuick.Pdf 的 PdfMultiPageView
//（多页连续竖向），paged 用 PdfScrollablePageView（单页横向分页），方向沿用
// EPUB 的 reading/pageMode 设置键。两视图常驻按方向切换可见性，TTS/进度/
// 书签/页码/缩放统一经 pdfView 代理访问活动视图。
// 注意：Qt 6.7 起 QML 模块由 QtPdf 更名为 QtQuick.Pdf，PdfScrollablePageView
// 不再自带 source，须外置 PdfDocument 绑定 document；缩放 API 由 scaleMode
// 枚举改为 scaleToWidth/scaleToPage 方法。
// 任务4：接入共享壳层 ReaderShell——顶栏/菜单/TtsBar/底部 Sheet 全部由壳层
// 持有（删除本页独立顶栏、KdDropdownMenu 与 TTS 条逻辑）；本页保留 Qt PDF
// 宽度适配、缩放（经壳层 Sheet 的 PDF 专属缩放面板）、页进度、文本提取朗读
// 与 renderSettled/requestClose 竞态防护。阅读进度独立键 progress/pdf_<bookId>
//（存页码），与文本书的 progress/<bookId>（存章节索引）区分——B10 进度恢复
// 按 format 分流读取；书签键 bookmarks/pdf_<bookId>（存页索引数组）。
Page {
    id: page
    // U2：沉浸页标识（Main 据此隐藏标签/底部导航；返回后恢复）
    property string navId: "pdf"
    // E4（PDF）：键盘路由前提是页面持有 activeFocus——与 ReaderPage 同模式：
    // 页面 focus:true 作为焦点候选，Component.onCompleted 与 StackView.onActivated
    // 分别补首次创建与从其它页返回（pop 回来）时的 focus 恢复；否则 Keys.onPressed
    // 收不到按键，A/D/方向键翻页失效。
    focus: true
    property var book: ({})
    property string theme: "auto"
    // false = 宽度适配（fitToWidth），true = 整页适配（fitToViewport）
    property bool fitPage: false
    // 任务1：PDF 双方向——scroll=PdfMultiPageView（多页连续竖向）/ paged=
    // PdfScrollablePageView（单页横向分页），沿用 EPUB 的 reading/pageMode
    // 设置键（SettingsBackgroundPage/ReaderPage 同键，双入口一致）。两视图常驻，
    // 按方向切换可见性，文档不销毁，TTS/书签/进度状态不重置。
    property string pageMode: {
        const m = String(Settings.value("reading/pageMode") || "")
        return (m === "scroll" || m === "paged") ? m : "scroll"
    }
    // 活动视图标识与对象句柄：multi=PdfMultiPageView，single=PdfScrollablePageView
    property string pdfViewKind: page.pageMode === "scroll" ? "multi" : "single"
    property var activePdfView: page.pageMode === "scroll" ? multiView : singleView
    // 方向切换待恢复页：setPageMode 先存当前页，切换活动视图后 goToPage 恢复
    property int pendingRestorePage: -1
    // 任务2：整页居中句柄——活动视图对称左右边距与内容/视口中心。
    // scroll 的 PdfMultiPageView 内部委托 anchors.centerIn 已居中且无 margin API，
    // 这些句柄在 paged 的 PdfScrollablePageView（Flickable）上产生非零值。
    property real pdfLeftMargin: page.pdfView.leftMargin
    property real pdfRightMargin: page.pdfView.rightMargin
    property real pdfHorizontalMargin: page.pdfLeftMargin
    property real pdfViewportCenter: page.pdfView.width / 2
    // 内容中心（视口坐标）= -contentX + contentWidth/2：Flickable 设边距后自动把
    // 子项 paper.x 置为 -contentX 且 contentX 钳制到 -leftMargin，因此内容中心
    // 恰为 leftMargin + contentWidth/2，无需再叠加 contentX（实测公式）。
    property real pdfContentCenter: {
        const v = page.activePdfView
        if (!v || v.contentX === undefined) return 0
        return -v.contentX + v.contentWidth / 2
    }
    // 暴露给测试/上层：文档状态、页数、页码跳转（B10 进度恢复经此 goToPage）；
    // pdfView 是统一活动视图代理（currentPage/goToPage/renderScale/status/边距）
    property alias pdfDocument: pdfDoc
    property alias pdfView: pdfViewProxy
    // 任务3：共享壳层与 PDF 适配器（统一契约，ReaderShell 只读此对象）；
    // 目录 Dialog 与 PDF 笔记 Dialog 句柄供宿主/回归测试使用。
    property alias readerShell: readerShell
    property alias readerAdapter: pdfReaderAdapter
    property alias tocDlg: tocDialog
    property alias pdfNotesDialog: pdfNotesDialog
    property alias pdfNoteDialog: pdfNoteDialog
    property alias pageLabel: pageLabel
    property alias retryButton: retryButton
    property alias errorLabel: errorLabel
    property alias loadingIndicator: loadingIndicator
    // 本属性透传壳层门控供 pdfView 锚点/页码指示/Toast 使用（ReaderPage 同款）
    property alias ttsBarVisible: readerShell.ttsBarVisible
    // B10：恢复完成前不写进度——Ready 后首次 currentPageChanged(0) 不得覆盖保存值
    property bool restoreDone: false
    // L9（P2#34）：翻页进度节流——currentPageChanged 只置 dirty，2s 合并 Timer 触发
    // 才写 Settings/DB（快翻不逐页落盘）；onDestruction 兜底 flush 不丢最后页码。
    property bool progressDirty: false
    // B10：关闭竞态防护——QPdfDocument 销毁（FPDF_DestroyLibrary）若撞上
    // QQuickPixmapReader 在途渲染（QPdfIOHandler 持文档指针）会 use-after-free 崩溃
    //（30MB 大 PDF 实测复现）。返回键先等渲染稳定（无在途读取）再 pop，
    // 慢渲染仅告警不强制销毁（强制销毁即复现该 UAF）。
    property bool closing: false
    property int closePollCount: 0

    // ---- 任务4：PDF 文本朗读会话状态 ----
    // 当前页句子（ReaderText.splitSentences 切分结果，仅供 TTS；只读模式保持只读）
    property var pdfSentences: []
    // 当前页是否可朗读（有文本层）：驱动适配器 canReadAloud 与壳层朗读项 enabled
    property bool pdfCanReadAloud: false
    // 活动会话归属：仅本页 startPdfReadAloud 启动、且未被手动翻页/目录跳转/返回/
    // Error/外部停止打断的朗读会话，才处理 Tts.chapterCompleted（防旧页继续发声）。
    property bool ttsSessionActive: false
    property int ttsSessionChapter: -1
    // 耗尽提示：末页读完后置位（Toast 显示"后续 PDF 页面无可朗读文本"），4s 自动消失
    property bool ttsExhaustedHint: false
    // state→0 且未收到 chapterCompleted 的过渡标记：外部停止（TtsBar ⏹）经 0ms
    // Timer 清理会话；chapterCompleted 同步到达时取消（续读路径不清理）。
    property bool ttsPendingStop: false
    // 书签（bookmarks/pdf_<bookId> 页索引数组，与文本书 bookmarks/<bookId> 区分）
    // 任务3：PDF 选区笔记仅使用本书 chapter 前缀为 pdf-page: 的行。
    property var pdfHighlights: []
    property string pendingPdfSelectionText: ""
    property int pendingPdfSelectionPage: -1
    // 当前选区是否已被消费（已据此建/改笔记）：为 true 时下次笔记入口进入无选区
    // 分支（打开列表）。页码变化/方向切换时经 resetPdfSelection 重置。multi 的
    // selectedText 是普通可写属性但由内部委托 textChanged 写回，single 是只读别名
    // ——都不在本页可靠清空，故用本标记统一判定"是否仍有未消费选区"，跨视图一致。
    property bool pdfSelectionConsumed: false
    property var pdfBookmarks: []
    property bool currentBookmarked: false
    // 任务1：PDF 书签管理展示模型（reloadBookmarkItems 从 pdfBookmarks 生成）——
    // 每项 { key: 页索引, pageIndex, label: 页码标签 }；非法/越界项忽略。
    property var bookmarkItems: []
    property alias bookmarksDialog: pdfBookmarksDialog

    PdfDocument {
        id: pdfDoc
        source: book.path ? "file://" + book.path : ""
        // 文档就绪后：先按可用阅读区宽度适配（否则默认 renderScale=1 窄页右侧留白），
        // 再跳转到保存页（progress/pdf_<bookId>），放开进度写入并提取首页文本；
        // 重试/重载（restoreDone 已 true）只刷新文本不重复恢复。
        onStatusChanged: (status) => {
            if (status === PdfDocument.Ready) {
                // 首次与重载统一按当前 fitPage 缩放活动视图（文档换源时两视图均
                // 内部 resetScale 回 1，需恢复适配；方向切换后也在 setPageMode 重算）
                page.applyFitModeToActiveView()
                if (!page.restoreDone && page.book.id) {
                    const saved = Number(Settings.value("progress/pdf_" + page.book.id)) || 0
                    // 方向切换待恢复页优先（先于文档就绪切换方向时不丢失目标页）
                    const target = page.pendingRestorePage >= 0 ? page.pendingRestorePage : saved
                    page.pendingRestorePage = -1
                    if (target > 0) page.pdfView.goToPage(target)
                    page.restoreDone = true
                    // 任务3（4.2）：恢复页完成后再次同步书签——恢复期首个
                    // currentPageChanged(0) 可能被 restoreDone 门控（见
                    // viewCurrentPageChanged），不在此补同步则图标停在未点亮。
                    page.syncPdfBookmarkState()
                    page.recordProgress()
                }
                page.refreshPageText()
                return
            }
            if (status === PdfDocument.Error) {
                page.stopPdfTts()          // Error 必须停止活动会话（旧页不得继续发声）
                page.pdfSentences = []
                page.pdfCanReadAloud = false
                return
            }
            // Loading/Unloading/Null：文本暂不可用；加载状态变化（如重试换源）必须
            // 停止活动会话（旧页不得在重载期间继续发声），并清空朗读能力。
            page.stopPdfTts()
            page.pdfSentences = []
            page.pdfCanReadAloud = false
        }
    }

    // 任务1：scroll 方向——PdfMultiPageView 多页连续竖向（官方组件，内部 TableView
    // 竖向滚动；窄页由委托 anchors.centerIn 自动居中，无需边距 API）。
    PdfMultiPageView {
        id: multiView
        visible: page.pageMode === "scroll"
        // 任务4：随壳层状态让位——Sheet 打开时顶栏 40px 下移正文；TtsBar 显示时
        // 底部 46px 上收（与 ReaderPage 对 ReaderContent 的锚定同语义）。
        anchors.top: parent.top
        anchors.topMargin: readerShell.sheetOpen ? readerShell.topToolbar.height : 0
        // 隐藏方向置 0×0：TableView 无视口不创建委托 → 不产生后台逐页渲染。
        width: page.pageMode === "scroll" ? parent.width : 0
        height: (page.pageMode === "scroll" ? parent.height : 0)
                - (page.ttsBarVisible ? readerShell.ttsBar.height : 0)
        document: pdfDoc
        // 阅读进度：当前页变化仅置 dirty，2s 合并 Timer 触发才写 settings.json 的
        // progress/pdf_<bookId> + books.progress（页码/总页数，含 last_read_at）；
        // 同时重提取当前页文本（朗读能力随页变化）并同步书签高亮。
        onCurrentPageChanged: page.viewCurrentPageChanged(this)
        // 任务2：窗口尺寸改变后重算居中（multi 无 margin API，内部已居中，空操作）
        onWidthChanged: page.updatePdfAlignment()
        // 轻点：切换壳层显隐状态（唤出顶栏/Sheet 或关闭——ReaderPage 同款交互）；
        // 页面上 Qt 内部 TapHandler（链接/文本选择）接管处例外，边缘/间隙仍可唤出。
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: readerShell.handleTap(0, 0)
        }
    }

    // 任务1：paged 方向——PdfScrollablePageView 单页横向分页（原单视图逻辑）。
    PdfScrollablePageView {
        id: singleView
        visible: page.pageMode === "paged"
        anchors.top: parent.top
        anchors.topMargin: readerShell.sheetOpen ? readerShell.topToolbar.height : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: page.ttsBarVisible ? readerShell.ttsBar.height : 0
        document: pdfDoc
        onCurrentPageChanged: page.viewCurrentPageChanged(this)
        // 任务2：视口尺寸/内容宽度（缩放）变化后重算整页居中边距
        onWidthChanged: page.updatePdfAlignment()
        onContentWidthChanged: page.updatePdfAlignment()
        // 单点：切换壳层显隐状态（唤出顶栏/Sheet 或关闭——ReaderPage 同款交互）；
        // 缩放切换由壳层 Sheet 的 PDF 专属缩放面板承担（旧双击切换收编，见 onZoom）。
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: readerShell.handleTap(0, 0)
        }
    }

    // 任务1：统一 PDF 视图代理——TTS/进度/书签/页码/缩放一律经此访问活动视图，
    // 不绑定具体视图 id。status 兼容两视图（single=Image status，multi=
    // currentPageRenderingStatus）；renderScale 双向透传（写回活动视图）；
    // contentWidth/contentX/边距供整页居中计算使用。
    QtObject {
        id: pdfViewProxy
        property var view: page.activePdfView
        property int currentPage: view && view.currentPage !== undefined ? view.currentPage : -1
        property real renderScale: view && view.renderScale !== undefined ? view.renderScale : 1
        onRenderScaleChanged: {
            // 写回透传：外部（测试/未来 UI）赋值代理 renderScale 时转发活动视图；
            // 活动视图自身缩放变化时二者相等，不构成回路。
            const v = page.activePdfView
            if (v && v.renderScale !== undefined && page.pdfView.renderScale !== v.renderScale)
                v.renderScale = page.pdfView.renderScale
        }
        property int status: {
            const v = page.activePdfView
            if (!v) return Image.Null
            return v.status !== undefined ? v.status : v.currentPageRenderingStatus
        }
        property real width: view ? view.width : 0
        property real height: view ? view.height : 0
        property real contentWidth: view && view.contentWidth !== undefined ? view.contentWidth : 0
        property real contentX: view && view.contentX !== undefined ? view.contentX : 0
        property real leftMargin: view && view.leftMargin !== undefined ? view.leftMargin : 0
        property real rightMargin: view && view.rightMargin !== undefined ? view.rightMargin : 0
        function goToPage(p) { if (page.activePdfView) page.activePdfView.goToPage(p) }
        function scaleToWidth(w, h) { if (page.activePdfView) page.activePdfView.scaleToWidth(w, h) }
        function scaleToPage(w, h) { if (page.activePdfView) page.activePdfView.scaleToPage(w, h) }
        function resetScale() { if (page.activePdfView) page.activePdfView.resetScale() }
    }

    // ---- 任务4：PDF 专属缩放面板（经壳层 Sheet 承载；壳层菜单"图书信息"
    // openInfo → 本面板）——宽度适配 / 整页适配 / 重置缩放，Ready 门控。
    Component {
        id: pdfZoomComp
        Column {
            width: parent ? parent.width : 0
            spacing: 0
            Repeater {
                model: [
                    { id: "fitWidth", text: qsTr("宽度适配") },
                    { id: "fitPage", text: qsTr("整页适配") },
                    { id: "reset", text: qsTr("重置缩放") }
                ]
                delegate: ItemDelegate {
                    required property var modelData
                    width: parent ? parent.width : 0
                    text: modelData.text
                    onClicked: page.onZoom(modelData.id)
                }
            }
        }
    }

    // ---- 任务4：页码目录（适配器 openContents）——页标签 + 跳转 ----
    Dialog {
        id: tocDialog
        title: qsTr("目录（页码）")
        modal: true
        standardButtons: Dialog.Close
        width: 380
        height: 480
        // 关闭完成（含退出动画）后把键盘焦点还给页面——模态弹层退出期间焦点
        // 不自动归还，否则目录跳转后方向键翻页失效（与 StackView.onActivated 同义）
        onClosed: page.forceActiveFocus()
        contentItem: ListView {
            anchors.fill: parent
            clip: true
            model: pdfDoc.pageCount
            delegate: ItemDelegate {
                required property int index
                width: ListView.view.width
                text: {
                    const label = pdfDoc.pageLabel(index)
                    return (label && label.length > 0)
                        ? label : qsTr("第 %1 页").arg(index + 1)
                }
                onClicked: page.goToPdfPage(index)
            }
        }
    }

    // 任务3：PDF 笔记管理——只显示当前书 pdf-page:<zero-based-page> 行。
    Dialog {
        id: pdfNotesDialog
        title: qsTr("PDF 笔记") + "（" + page.pdfHighlights.length + "）"
        modal: true
        standardButtons: Dialog.Close
        width: 500
        height: 540
        onOpened: page.reloadPdfHighlights()
        onClosed: page.forceActiveFocus()
        contentItem: ListView {
            id: pdfNotesList
            anchors.fill: parent
            clip: true
            model: page.pdfHighlights
            delegate: Rectangle {
                width: ListView.view.width
                height: pdfNoteBody.implicitHeight + 18
                color: index % 2 === 0 ? "#0A000000" : "transparent"
                Column {
                    id: pdfNoteBody
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Label {
                        text: qsTr("第 %1 页").arg(Number(String(modelData.chapter).slice(9)) + 1)
                        color: UITheme.textSecondary
                        font.pixelSize: 12
                    }
                    Label {
                        text: modelData.text || ""
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                        font.pixelSize: 14
                    }
                    Label {
                        text: modelData.note ? qsTr("笔记：") + modelData.note : qsTr("（无笔记）")
                        color: modelData.note ? UITheme.textSecondary : UITheme.textDisabled
                        wrapMode: Text.Wrap
                        font.pixelSize: 12
                    }
                    Row {
                        spacing: 12
                        Button {
                            text: qsTr("跳转")
                            onClicked: page.goToPdfHighlight(modelData)
                        }
                        Button {
                            text: qsTr("编辑")
                            onClicked: {
                                pdfNotesDialog.close()
                                page.openPdfNoteEditor(modelData.chapter, modelData.text, modelData.id,
                                                       modelData.note || "")
                            }
                        }
                        Button {
                            text: qsTr("删除")
                            onClicked: Highlights.removeHighlight(modelData.id)
                        }
                    }
                }
            }
            ScrollBar.vertical: ScrollBar {}
        }
    }

    // 任务1：PDF 书签管理 Dialog——列表项展示页码标签（pdfDoc.pageLabel 或
    // "第 N 页"），行内"跳转"关闭 Dialog 并翻页，"删除"立即移除并刷新列表/
    // 持久化/顶栏状态（标题计数随 bookmarkItems 绑定自动更新）。
    Dialog {
        id: pdfBookmarksDialog
        title: qsTr("书签") + "（" + page.bookmarkItems.length + "）"
        modal: true
        standardButtons: Dialog.Close
        width: 420
        height: 480
        contentItem: ListView {
            id: pdfBookmarksList
            clip: true
            model: page.bookmarkItems
            delegate: Rectangle {
                width: ListView.view.width
                height: 52
                color: index % 2 === 0 ? "#0A000000" : "transparent"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8
                    KdIcons {
                        name: "bookmarkFill"
                        size: 18
                        color: UITheme.textSecondary
                    }
                    Label {
                        text: modelData.label || ""
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.pixelSize: 14
                        color: UITheme.textPrimary
                    }
                    Button {
                        text: qsTr("跳转")
                        font.pixelSize: 12
                        onClicked: page.jumpToBookmark(modelData)
                    }
                    Button {
                        text: qsTr("删除")
                        font.pixelSize: 12
                        onClicked: page.removeBookmark(modelData)
                    }
                }
            }
            ScrollBar.vertical: ScrollBar {}
        }
        onOpened: page.reloadBookmarkItems()
        onClosed: page.forceActiveFocus()
    }

    // 任务3：PDF 选中文字笔记编辑；取消路径不触碰 Highlights。
    Dialog {
        id: pdfNoteDialog
        title: qsTr("PDF 选区笔记")
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        width: 420
        height: 300
        property int targetId: -1
        property alias noteArea: pdfNoteArea
        contentItem: ColumnLayout {
            spacing: 10
            Label {
                Layout.fillWidth: true
                text: qsTr("第 %1 页").arg(page.pendingPdfSelectionPage + 1)
                color: UITheme.textSecondary
            }
            Label {
                Layout.fillWidth: true
                text: page.pendingPdfSelectionText
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
            }
            TextArea {
                id: pdfNoteArea
                Layout.fillWidth: true
                Layout.fillHeight: true
                placeholderText: qsTr("写下你的想法…")
                wrapMode: TextEdit.Wrap
            }
        }
        onAccepted: {
            if (!page.book || !page.book.id || page.pendingPdfSelectionPage < 0) return
            if (pdfNoteDialog.targetId > 0)
                Highlights.updateNote(pdfNoteDialog.targetId, pdfNoteArea.text)
            else
                Highlights.addHighlight(page.book.id, "pdf-page:" + page.pendingPdfSelectionPage,
                                        0, page.pendingPdfSelectionText, "#FFEB3B", pdfNoteArea.text,
                                        page.pendingPdfSelectionPage + 1)
            page.reloadPdfHighlights()
            page.consumePdfSelection()   // 选区已消费：下次笔记入口打开列表而非编辑
        }
        onClosed: page.forceActiveFocus()
    }

    // 任务4：页码目录（适配器 openContents）——页标签 + 跳转
    // 任务2：Loading 反馈——避免加载期间白屏无反馈
    Rectangle {
        id: loadingIndicator
        anchors.fill: parent
        visible: pdfDoc.status === PdfDocument.Loading
        color: UITheme.bgPrimary
        Column {
            anchors.centerIn: parent
            spacing: 12
            BusyIndicator { anchors.horizontalCenter: parent.horizontalCenter; running: true }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("正在加载…")
                color: UITheme.lightTextPrimary
            }
        }
    }

    // 任务2：Error 反馈——显示 pdfDoc.error 与重试按钮
    Rectangle {
        id: errorOverlay
        anchors.fill: parent
        visible: pdfDoc.status === PdfDocument.Error
        color: UITheme.bgPrimary
        Column {
            anchors.centerIn: parent
            spacing: 16
            width: Math.min(parent.width - 48, 480)
            Label {
                id: errorLabel
                visible: pdfDoc.status === PdfDocument.Error
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                text: pdfDoc.status === PdfDocument.Error ? pdfDoc.error : ""
                color: UITheme.lightTextPrimary
            }
            Button {
                id: retryButton
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("重试")
                onClicked: page.retryLoad()
            }
        }
    }

    // 任务4：底部左下页码指示（壳层 Sheet 打开时隐藏，与 ReaderPage 进度标签同语义）
    Label {
        id: pageLabel
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.bottom: parent.bottom
        anchors.bottomMargin: (page.ttsBarVisible ? readerShell.ttsBar.height : 0) + 12
        visible: !readerShell.sheetOpen
        z: 10
        text: pdfDoc.pageCount > 0
              ? qsTr("第 %1 / %2 页").arg(pdfView.currentPage + 1).arg(pdfDoc.pageCount)
              : qsTr("第 - / - 页")
        color: UITheme.lightTextPrimary
        font.pixelSize: 12
    }

    // 任务4：耗尽提示 Toast——末页读完后显示"后续 PDF 页面无可朗读文本"，4s 消失。
    // 说明：壳层 TtsBar 仅在 Tts.state != 0 时可见，耗尽即 stop 后条不可见，
    // 故提示经本页 Toast 呈现（Shell 无独立 toast 通道，不得为提示改动壳层）。
    Rectangle {
        id: ttsExhaustToast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: (page.ttsBarVisible ? readerShell.ttsBar.height : 0) + 24
        visible: page.ttsExhaustedHint
        z: 40
        height: 36
        width: ttsExhaustLabel.implicitWidth + 32
        radius: 8
        color: UITheme.overlay
        Label {
            id: ttsExhaustLabel
            anchors.centerIn: parent
            text: qsTr("后续 PDF 页面无可朗读文本")
            color: "#FFFFFF"
            font.pixelSize: 13
        }
    }

    // 任务2：键盘路由——A/Left/PageUp 前一页，D/Right/PageDown 后一页；
    // 只在实际处理（Ready 且边界内）后接受键事件，否则交回 Flickable 处理滚动。
    // 带修饰键（Ctrl/Cmd/Shift/Alt）的事件一律不吞，交回上层/系统（如 Cmd+A 全选、
    // Cmd+D、Shift+方向键选区）；自动重复（isAutoRepeat）维持原行为逐次翻页。
    // 任务4（复审）：菜单/Sheet 打开时与 ReaderPage 同款门控——弹层期间不翻页。
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: (event) => {
        if (page.readerShell.sheetOpen || page.readerShell.menuOpen) return
        if (event.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.ShiftModifier | Qt.AltModifier))
            return
        let handled = false
        if (event.key === Qt.Key_Left || event.key === Qt.Key_PageUp || event.key === Qt.Key_A)
            handled = page.previousPage()
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_PageDown || event.key === Qt.Key_D)
            handled = page.nextPage()
        if (handled) event.accepted = true
    }

    // 任务1：方向切换——只接受 scroll/paged；先存当前页，写回 reading/pageMode，
    // 切换活动视图后恢复原页（两视图常驻不销毁文档，TTS/书签/进度状态不重置；
    // 手动切换按既有契约停止当前页朗读会话）。
    function setPageMode(mode) {
        if (mode !== "scroll" && mode !== "paged") return
        if (page.pageMode === mode) return
        page.pendingRestorePage = page.pdfView.currentPage >= 0 ? page.pdfView.currentPage : 0
        page.stopPdfTts()
        page.resetPdfSelection()   // 任务3（3.1）：方向切换清理过期选区状态
        Settings.setValue("reading/pageMode", mode)
        page.pageMode = mode
        page.applyFitModeToActiveView()
        page.restoreAfterSwitch()
    }

    // 按当前 fitPage 状态缩放活动视图；文档未就绪跳过，Ready 处理器与方向切换
    // 都会重算。缩放直接用文档页尺寸计算再写 renderScale，**不**走视图的
    // scaleToWidth/scaleToPage：PdfMultiPageView 的 scaleToWidth 依赖内部
    // firstPagePointSize 绑定，文档刚 Ready 时该绑定可能仍是 (1,1) 占位值
    //（绑定求值滞后于 onStatusChanged），会算出 renderScale=视图宽度 的巨值，
    // 页面渲染尺寸达数十万像素、永不完成（QQuickPixmapReader 卡死 → 销毁死锁）。
    function applyFitModeToActiveView() {
        const view = page.activePdfView
        if (!view || pdfDoc.status !== PdfDocument.Ready) return
        const pageSize = pdfDoc.pagePointSize(0)
        if (pageSize.width <= 0 || pageSize.height <= 0) return
        view.renderScale = page.fitPage
            ? Math.min(view.width / pageSize.width, view.height / pageSize.height)
            : view.width / pageSize.width
        page.updatePdfAlignment()
    }

    // 任务2：整页适配开关——fitPage=true 缩放并对称居中；false（宽度适配）清除边距。
    function setFitPage(v) {
        page.fitPage = !!v
        page.applyFitModeToActiveView()
    }

    // 任务2：整页居中——仅对带边距的 Flickable（paged 的 PdfScrollablePageView）设置
    // 对称 leftMargin/rightMargin，使内容中心对齐视口中心（窄页 contentWidth<width
    // 时默认 contentX=0 靠左）；宽度适配/重置缩放清除边距；scroll 的 PdfMultiPageView
    // 内部委托已居中且无 margin API，跳过。尺寸/缩放/方向/Ready 后都会重算（视图
    // onWidthChanged/onContentWidthChanged 与 applyFitModeToActiveView 调此函数）。
    function updatePdfAlignment() {
        const view = page.activePdfView
        if (!view || view.leftMargin === undefined) return
        const margin = page.fitPage ? Math.max(0, (view.width - view.contentWidth) / 2) : 0
        view.leftMargin = margin
        view.rightMargin = margin
    }

    // 切换活动视图后恢复保存页（文档未就绪时 PdfMultiPageView 走内部 pendingRow
    // 延迟跳转，Ready 后仍会落在目标页）。
    function restoreAfterSwitch() {
        const target = page.pendingRestorePage
        page.pendingRestorePage = -1
        if (target < 0) return
        page.pdfView.goToPage(target)
    }

    // 当前页变化分发：只响应活动视图（隐藏视图的页码变化不驱动进度/文本/书签），
    // Ready 前的恢复期不写进度（restoreDone 门控，防覆盖保存值）。
    // 注意：页码必须用视图自身的 view.currentPage——pdfView 代理是绑定属性，在
    // 信号处理器同步链内尚未重求值（读到旧页），而视图原始属性在 jump() 内已更新。
    function viewCurrentPageChanged(view) {
        if (view !== page.activePdfView) return
        if (!page.restoreDone) return
        const current = view.currentPage
        page.progressDirty = true
        progressFlush.restart()
        page.refreshPageText(current)
        page.syncPdfBookmarkState(current)
        page.resetPdfSelection()   // 任务3（3.1）：页码变化清理过期选区状态
    }

    // 任务2：前一页——仅 Ready 且非首页时 goToPage(currentPage-1)，成功返回 true；
    // 任务4：手动翻页必须停止本页活动朗读会话（旧页不得继续发声）。
    function previousPage() {
        if (pdfDoc.status !== PdfDocument.Ready || pdfView.currentPage <= 0) return false
        page.stopPdfTts()
        pdfView.goToPage(pdfView.currentPage - 1)
        return true
    }
    // 任务2：后一页——仅 Ready 且非末页时 goToPage(currentPage+1)，成功返回 true
    function nextPage() {
        if (pdfDoc.status !== PdfDocument.Ready
                || pdfView.currentPage >= pdfDoc.pageCount - 1) return false
        page.stopPdfTts()
        pdfView.goToPage(pdfView.currentPage + 1)
        return true
    }
    // 任务4：缩放面板动作——宽度适配 / 整页适配 / 重置缩放。
    // Ready 门控：Error/Loading 状态点中面板项不得触发缩放调用（缩放依赖已加载
    // 文档的 pagePointSize，非 Ready 调用无意义）。
    function onZoom(id) {
        if (pdfDoc.status !== PdfDocument.Ready) return
        if (id === "fitWidth") { page.fitPage = false; page.applyFitModeToActiveView() }
        else if (id === "fitPage") { page.fitPage = true; page.applyFitModeToActiveView() }
        else if (id === "reset") { page.pdfView.resetScale() }
    }
    // 任务2：重试——改变 source 值强制重新触发加载（PdfDocument 无公开 reload API，
    // QML 侧唯一重载入口是 source 属性，且值必须变化才会重载）。
    // 注意不能清空为 ""：空 URL 非法，QQuickPdfDocument::setSource 走 qmlWarning
    // "Cannot open: "（qquickpdfdocument.cpp 中 m_resolvedSource.isValid() 分支）。
    // 改用非空但不存在的占位 file URL：合法 URL → QPdfDocument::load 打开失败 →
    // 静默置 Error（QFile::open 失败路径无控制台警告），随后恢复真实 source 完成重载。
    function retryLoad() {
        const src = page.book.path ? "file://" + page.book.path : ""
        if (src.length === 0) return
        pdfDoc.source = "file:///__readdict_reload__"
        pdfDoc.source = src
    }

    // ---- 任务4：PDF 文本提取与朗读 ----
    // 整页文本提取项：QPdfDocument.getAllText 返回 C++ 值类型 QPdfSelection，
    // QML 引擎不支持该返回类型（实测报 "Unknown method return type: QPdfSelection"），
    // 故经 QtQuick.Pdf 的 PdfSelection 项（QQuickPdfSelection）selectAll() 取整页
    // 文本——同步数据操作（内部调 getAllText），不依赖渲染/可见性。
    PdfSelection {
        id: pdfTextSel
        document: pdfDoc
    }
    // 提取页句子：只在 Ready 时读取（依赖已加载文档），空/异常返回 []。
    // 句子切分复用 ReaderText.splitSentences（既有 SentenceSplitter 桥接，
    // 不重写语言规则）。
    function extractPageText(pageIndex) {
        if (pdfDoc.status !== PdfDocument.Ready
                || pageIndex < 0 || pageIndex >= pdfDoc.pageCount) return []
        try {
            pdfTextSel.page = pageIndex
            pdfTextSel.selectAll()
            const text = pdfTextSel.text ? String(pdfTextSel.text) : ""
            if (!text.trim()) return []
            return ReaderText.splitSentences(text)
        } catch (err) {
            return []
        }
    }
    // 刷新当前页句子/朗读能力：Ready 且页合法时提取，否则清空（非 Ready 不读文本）
    function refreshPageText(pageIndex) {
        const idx = (pageIndex !== undefined) ? pageIndex : page.pdfView.currentPage
        const s = page.extractPageText(idx)
        page.pdfSentences = s
        page.pdfCanReadAloud = s.length > 0
    }

    // 开始朗读：先验证文本可用（空文本绝不触碰 TTS），再装载句子并播放。
    function startPdfReadAloud() {
        if (pdfDoc.status !== PdfDocument.Ready || page.pdfSentences.length === 0) return
        page.ttsExhaustedHint = false
        Tts.setSentences(page.pdfSentences)
        Tts.setChapter(pdfView.currentPage)
        Tts.setCurrentIndex(0)
        page.ttsSessionActive = true
        page.ttsSessionChapter = pdfView.currentPage
        Tts.play()
    }
    // 停止本页活动会话：仅会话归属本页时 stop（不误杀下层文本书仍在播放的 TTS）；
    // 先清标志再 stop——stop 引发的 stateChanged(0) 不再触发会话清理路径。
    function stopPdfTts() {
        page.ttsPendingStop = false
        sessionCleanupTimer.stop()
        if (page.ttsSessionActive) {
            page.ttsSessionActive = false
            page.ttsSessionChapter = -1
            Tts.stop()
        }
    }
    // 页级续读：朗读越过当前页最后一句（chapterCompleted）→ 找下一含文本页，
    // 跳转、重提取、重新装载句子并续播；没有后续文本页时停 TTS 并显示提示。
    function continuePdfTtsToNextTextPage() {
        page.ttsPendingStop = false      // chapterCompleted 同步到达：取消待清理
        sessionCleanupTimer.stop()
        if (pdfDoc.status !== PdfDocument.Ready) { page.stopPdfTts(); return }
        for (let i = pdfView.currentPage + 1; i < pdfDoc.pageCount; ++i) {
            const s = page.extractPageText(i)
            if (s.length > 0) {
                pdfView.goToPage(i)      // 触发 currentPageChanged → refreshPageText
                Tts.setSentences(s)
                Tts.setChapter(i)
                Tts.setCurrentIndex(0)
                page.ttsSessionChapter = i
                Tts.play()
                return
            }
        }
        // 无后续文本页：停 TTS 并显示提示
        page.stopPdfTts()
        page.ttsExhaustedHint = true
        ttsExhaustHintTimer.restart()
    }

    // 任务3：刷新并过滤本书 PDF 笔记，避免正文笔记混入管理列表。
    function reloadPdfHighlights() {
        const all = page.book && page.book.id ? Highlights.highlightsForBook(page.book.id) : []
        const filtered = []
        for (const row of all) {
            if (row && String(row.chapter || "").indexOf("pdf-page:") === 0)
                filtered.push(row)
        }
        page.pdfHighlights = filtered
    }

    // 任务3 复审：划线增删改（removeHighlight/updateNote/addHighlight）后即时重载，
    // 驱动笔记列表与标题计数（（N））同步——删除按钮此前只 removeHighlight 不刷新，
    // 列表保留已删行直到 Dialog 重开。仅监听当前书，避免他书变更触发误刷新。
    Connections {
        target: Highlights
        function onHighlightsChanged(bookId) {
            if (page.book && bookId === page.book.id)
                page.reloadPdfHighlights()
        }
    }

    function openPdfNoteEditor(chapter, text, targetId, note) {
        const prefix = String(chapter || "")
        page.pendingPdfSelectionPage = Number(prefix.slice(9))
        page.pendingPdfSelectionText = String(text || "")
        pdfNoteDialog.targetId = Number(targetId) || -1
        pdfNoteArea.text = String(note || "")
        pdfNoteDialog.open()
    }

    function goToPdfHighlight(row) {
        const chapter = String(row && row.chapter || "")
        if (chapter.indexOf("pdf-page:") !== 0) return
        const idx = Number(chapter.slice(9))
        if (!Number.isInteger(idx) || idx < 0 || idx >= pdfDoc.pageCount) return
        page.goToPdfPage(idx)
    }

    function openPdfNotes() {
        const selected = activePdfView && activePdfView.selectedText !== undefined
            ? String(activePdfView.selectedText || "").trim() : ""
        if (selected.length > 0 && pdfDoc.status === PdfDocument.Ready
                && !page.pdfSelectionConsumed) {
            const current = activePdfView.currentPage
            const chapter = "pdf-page:" + current
            let target = -1
            let existingNote = ""
            const rows = page.book && page.book.id ? Highlights.highlightsForBook(page.book.id) : []
            for (const row of rows) {
                if (row.chapter === chapter && row.text === selected) {
                    target = Number(row.id)
                    existingNote = String(row.note || "")
                    break
                }
            }
            page.pendingPdfSelectionPage = current
            page.pendingPdfSelectionText = selected
            pdfNoteDialog.targetId = target
            pdfNoteArea.text = existingNote
            pdfNoteDialog.open()
        } else {
            page.reloadPdfHighlights()
            pdfNotesDialog.open()
        }
    }

    // 任务3（3.1）：编辑确认后消费当前选区——下次笔记入口进入无选区分支（列表）。
    function consumePdfSelection() {
        page.pdfSelectionConsumed = true
        page.pendingPdfSelectionText = ""
        page.pendingPdfSelectionPage = -1
    }
    // 页码变化/方向切换：重置选区消费状态（跨页/跨方向不保留旧选区），使新页
    // 上的新选区可重新进入编辑分支。
    function resetPdfSelection() {
        page.pdfSelectionConsumed = false
        page.pendingPdfSelectionText = ""
        page.pendingPdfSelectionPage = -1
    }

    function closeReaderShellLayers() {
        readerShell.menuOpen = false
        readerShell.sheetOpen = false
    }

    // 任务4：目录跳转（页码目录 openContents 目标）——关闭目录并停止会话
    function goToPdfPage(i) {
        if (pdfDoc.status !== PdfDocument.Ready) return
        tocDialog.close()
        pdfNotesDialog.close()
        page.stopPdfTts()
        if (i >= 0 && i < pdfDoc.pageCount) page.activePdfView.goToPage(i)
    }

    // ---- 任务3：书签（bookmarks/pdf_<bookId> 页索引数组）----
    function syncPdfBookmarkState(pageIndex) {
        const view = page.activePdfView
        const idx = (pageIndex !== undefined) ? pageIndex
            : (view && view.currentPage !== undefined ? view.currentPage : -1)
        page.currentBookmarked = page.pdfBookmarks.indexOf(idx) >= 0
    }
    function togglePdfBookmark() {
        const view = page.activePdfView
        if (!page.book || !page.book.id || pdfDoc.status !== PdfDocument.Ready || !view) return
        const idx = view.currentPage
        const list = page.pdfBookmarks.slice()
        const i = list.indexOf(idx)
        if (i >= 0) list.splice(i, 1)
        else list.push(idx)
        page.pdfBookmarks = list
        Settings.setValue("bookmarks/pdf_" + page.book.id, list)
        page.syncPdfBookmarkState(idx)
    }
    // 任务1：从 pdfBookmarks 生成展示模型——页索引数组映射为页码标签
    //（pdfDoc.pageLabel 优先，空/异常回退"第 N 页"）；非法/越界项忽略。
    function reloadBookmarkItems() {
        const items = []
        for (const idx of page.pdfBookmarks) {
            if (!Number.isInteger(idx) || idx < 0 || idx >= pdfDoc.pageCount) continue
            let label = ""
            try { label = pdfDoc.pageLabel(idx) || "" } catch (err) { label = "" }
            if (!label) label = qsTr("第 %1 页").arg(idx + 1)
            items.push({ key: idx, pageIndex: idx, label: label })
        }
        page.bookmarkItems = items
    }
    // 任务1：打开书签管理 Dialog——先释放壳层 Sheet/菜单（同 openContents 模式），
    // 再刷新展示模型并打开（onOpened 也会刷新，保证最新数据）。
    function openBookmarks() {
        page.closeReaderShellLayers()
        page.reloadBookmarkItems()
        pdfBookmarksDialog.open()
    }
    // 任务1：书签跳转——关闭 Dialog 后走 goToPdfPage（关目录/笔记、停朗读、
    // 钳制页范围并跳转）。
    function jumpToBookmark(item) {
        if (!item || !Number.isInteger(item.pageIndex) || item.pageIndex < 0) return
        pdfBookmarksDialog.close()
        page.goToPdfPage(item.pageIndex)
    }
    // 任务1：删除书签——按页索引过滤移除，写回 Settings 后刷新展示模型与顶栏
    // 收藏态（删除当前页书签立即熄灭）。
    function removeBookmark(item) {
        if (!item || item.key === undefined || !page.book || !page.book.id) return
        const list = page.pdfBookmarks.filter(function (v) { return v !== item.key })
        page.pdfBookmarks = list
        Settings.setValue("bookmarks/pdf_" + page.book.id, list)
        page.reloadBookmarkItems()
        page.syncPdfBookmarkState()
    }


    // 记录当前页：页码写 settings.json，百分比+last_read_at 写 books（书架进度条联动）
    function recordProgress() {
        if (!page.book.id || pdfDoc.status !== PdfDocument.Ready || pdfDoc.pageCount <= 0) return
        Settings.setValue("progress/pdf_" + page.book.id, pdfView.currentPage)
        Books.setProgress(page.book.id, (pdfView.currentPage + 1) / pdfDoc.pageCount)
    }
    // 兜底 flush：onDestruction 为同步时机，Timer 来不及触发，直接写最终页码
    function flushProgress() {
        if (!page.progressDirty) return
        page.progressDirty = false
        page.recordProgress()
    }

    // 无在途渲染：活动视图 status 为 Ready（渲染完成）/ Error / Null（无渲染任务）时
    // 安全（single=Image.status，multi=currentPageRenderingStatus，代理统一）。
    function renderSettled() {
        const views = [multiView, singleView]
        for (const v of views) {
            const s = v.status !== undefined ? v.status : v.currentPageRenderingStatus
            if (s !== Image.Ready && s !== Image.Error && s !== Image.Null) return false
        }
        return true
    }

    // 关闭阅读页：先停止本页朗读会话，再等渲染线程空闲 pop（文档销毁撞在途
    // 渲染 = UAF 崩溃）。渲染在途时持续轮询等待，**绝不**在渲染未稳定时强制销毁
    // 文档——慢渲染（大 PDF 高倍率重渲染可达数秒）超时强制 pop 会把 UAF 换一种
    // 方式放回来；超长渲染（>60s）仅告警，保持等待直到稳定（Ready 文档的渲染
    // 必然完成）。
    function requestClose() {
        page.stopPdfTts()
        if (page.closing) return
        page.closing = true
        page.closePollCount = 0
        if (page.renderSettled()) {
            const win = Window.window
            if (win && win.goBack) win.goBack()
            else page.StackView.view.pop()
        }
        closePoll.start()
    }

    Timer {
        id: closePoll
        interval: 50
        repeat: true
        onTriggered: {
            if (page.renderSettled()) {
                closePoll.stop()
                const win = Window.window
                if (win && win.goBack) win.goBack()
                else page.StackView.view.pop()
                return
            }
            // 轮询计数：50ms/次，1200 次 = 60s——用于 60s 告警与测试锁定轮询生效
            page.closePollCount += 1
            if (page.closePollCount === 1200) // 60s：仅告警，不强制销毁
                console.warn("PdfReaderPage: 渲染 60 秒未稳定，继续等待（书: " + page.book.title + "）")
        }
    }

    Timer {
        id: progressFlush
        interval: 2000
        repeat: false
        onTriggered: page.flushProgress()
    }

    // 任务4：会话清理——Tts.state 外部回到 0（如 TtsBar ⏹ 直接 stop）且未收到
    // chapterCompleted：0ms 后收回本页会话归属。chapterCompleted 是同步信号，先于
    // 本 Timer 到达（续读路径 cancel）；外部停止无后续信号，Timer 兜底清理。
    Timer {
        id: sessionCleanupTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (page.ttsSessionActive) {
                page.ttsSessionActive = false
                page.ttsSessionChapter = -1
            }
            page.ttsPendingStop = false
        }
    }

    // 任务4：耗尽提示 4s 后自动消失
    Timer {
        id: ttsExhaustHintTimer
        interval: 4000
        repeat: false
        onTriggered: page.ttsExhaustedHint = false
    }

    // 任务4：PDF 朗读会话专用 TTS 接线——只处理本页拥有的活动会话：
    //   · chapterCompleted：页级续读（找下一有文本页）或耗尽停止 + 提示；
    //   · state→0 且会话激活：启动 0ms 清理（外部 stop 时收回会话归属）。
    Connections {
        target: Tts
        function onStateChanged(state) {
            if (state === 0 && page.ttsSessionActive) {
                page.ttsPendingStop = true
                sessionCleanupTimer.restart()
            }
        }
        function onChapterCompleted(ch) {
            if (!page.ttsSessionActive) return
            if (ch !== page.ttsSessionChapter) return
            page.continuePdfTtsToNextTextPage()
        }
    }

    // ---- 任务4：PDF 阅读适配器（统一契约，ReaderShell 只读）----
    // 上一/下一项为页级 previousPage()/nextPage()，标签"上一页/下一页"；
    // 能力位：目录/书签开放（页码目录 + 页书签），搜索/笔记不开放；
    // 朗读能力随当前页是否有文本层实时派生（canReadAloud + 精确不可用原因）。
    QtObject {
        id: pdfReaderAdapter
        property string progressText: page.pageLabel.text
        property bool canGoPrevious: pdfDoc.status === PdfDocument.Ready
                                     && pdfView.currentPage > 0
        property bool canGoNext: pdfDoc.status === PdfDocument.Ready
                                 && pdfView.currentPage < pdfDoc.pageCount - 1
        property bool canReadAloud: page.pdfCanReadAloud
        // 不可用原因：就绪但无文本 → "当前 PDF 无可朗读文本"；未就绪（Loading/Error/
        // Null）→ 加载中文案（与测试契约一致，见 tst_main.qml 控制层用例）
        property string readAloudUnavailableReason:
            page.pdfCanReadAloud ? ""
                : (pdfDoc.status === PdfDocument.Ready
                   ? qsTr("当前 PDF 无可朗读文本") : qsTr("PDF 尚未加载完成"))
        property bool supportsContents: true
        property bool supportsSearch: false
        // 任务3：PDF 笔记开放——顶栏笔记按钮经 openNotes 分发（有选区→编辑，
        // 无选区→列表）；目录 openContents 先释放菜单/Sheet 再开 Dialog。
        property bool supportsNotes: true
        property bool supportsBookmarks: true
        property string previousLabel: qsTr("上一页")
        property string nextLabel: qsTr("下一页")
        function previous() { page.previousPage() }
        function next() { page.nextPage() }
        function startReadAloud() { page.startPdfReadAloud() }
        function stopReadAloud() { page.stopPdfTts() }
        function openContents() {
            page.closeReaderShellLayers()   // 先释放菜单/Sheet，再开目录
            tocDialog.open()
        }
        function openSearch() {}
        function openNotes() {
            page.closeReaderShellLayers()   // 先释放 Sheet，再按选区/无选区分发
            page.openPdfNotes()
        }
        function toggleBookmark() { page.togglePdfBookmark() }
        function openBookmarks() { page.openBookmarks() }
        function jumpToBookmark(item) { page.jumpToBookmark(item) }
        function removeBookmark(item) { page.removeBookmark(item) }
        // 壳层菜单"图书信息"→ PDF 专属缩放面板（Sheet 承载）
        function openInfo() {
            readerShell.sheetTab = "zoom"
            readerShell.sheetOpen = true
        }
    }

    // ---- 任务4：共享交互壳层（唯一顶栏/菜单/TtsBar/底部 Sheet/点击显隐状态机/
    // 焦点恢复）——本页注入正文宿主 pdfView 与 PDF 适配器；缩放面板经
    // sheetTabs/sheetPages 注入（onCompleted 赋值，面板创建上下文为本页）。
    // 声明在最后覆盖全页；声明时 pdfView 已创建，contentItem 绑定可解析。
    ReaderShell {
        id: readerShell
        anchors.fill: parent
        reader: pdfReaderAdapter
        // 任务1：正文宿主随方向切换（壳层仅对 contentItem 做 forceActiveFocus）
        contentItem: page.activePdfView
        bookmarked: page.currentBookmarked
        // 返回导航：停止朗读会话后走渲染安全关闭（requestClose 内含竞态防护）
        onBackRequested: page.requestClose()
    }

    Component.onCompleted: {
        if (page.book && page.book.id)
            Books.startTracking(page.book.id)  // 阅读计时开始
        // 任务4：注入壳层缩放面板（Sheet 单标签"缩放"，默认选中）
        readerShell.sheetTabs = [{ id: "zoom", text: qsTr("缩放") }]
        readerShell.sheetPages = [{ id: "zoom", source: pdfZoomComp }]
        readerShell.sheetTab = "zoom"
        // 任务4：恢复页书签（bookmarks/pdf_<bookId>）
        const saved = Settings.value("bookmarks/pdf_" + (page.book ? page.book.id : ""))
        page.pdfBookmarks = Array.isArray(saved) ? saved.slice() : []
        page.syncPdfBookmarkState()
        // E4（PDF）：首次创建即获得 activeFocus，方向键翻页立即可用（ReaderPage 同款）
        page.forceActiveFocus()
    }

    // E4（PDF）：从其它页面返回（StackView pop 回来）时补 focus——onCompleted 只在
    // 首次创建时执行，返回路径若不在此恢复，键盘路由将失效（ReaderPage 同款）
    StackView.onActivated: page.forceActiveFocus()

    Component.onDestruction: {
        page.stopPdfTts()      // 任务4：页面销毁收回朗读会话（防继续发声）
        page.flushProgress()   // L9（P2#34）：未落盘的翻页进度兜底写入
        Books.stopTracking()  // 结算阅读秒数
    }
}
