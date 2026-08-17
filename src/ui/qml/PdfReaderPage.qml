import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Pdf
import QtQuick.Window
import Readdict.Backend
import Readdict.UI 1.0

// PDF 阅读页（B9）：QtQuick.Pdf 的 PdfScrollablePageView 单页滚动视图。
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
    // 暴露给测试/上层：文档状态、页数、页码跳转（B10 进度恢复经此 goToPage）
    property alias pdfDocument: pdfDoc
    property alias pdfView: pdfView
    // 任务4：共享壳层与 PDF 适配器（统一契约，ReaderShell 只读此对象）；
    // 目录 Dialog（页码目录）与底部左下页码指示句柄。
    property alias readerShell: readerShell
    property alias readerAdapter: pdfReaderAdapter
    property alias tocDlg: tocDialog
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
    property var pdfBookmarks: []
    property bool currentBookmarked: false

    PdfDocument {
        id: pdfDoc
        source: book.path ? "file://" + book.path : ""
        // 文档就绪后：先按可用阅读区宽度适配（否则默认 renderScale=1 窄页右侧留白），
        // 再跳转到保存页（progress/pdf_<bookId>），放开进度写入并提取首页文本；
        // 重试/重载（restoreDone 已 true）只刷新文本不重复恢复。
        onStatusChanged: (status) => {
            if (status === PdfDocument.Ready) {
                if (!page.restoreDone && page.book.id) {
                    pdfView.scaleToWidth(pdfView.width, pdfView.height)
                    const saved = Number(Settings.value("progress/pdf_" + page.book.id)) || 0
                    if (saved > 0) pdfView.goToPage(saved)
                    page.restoreDone = true
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

    PdfScrollablePageView {
        id: pdfView
        // 任务4：随壳层状态让位——Sheet 打开时顶栏 40px 下移正文；TtsBar 显示时
        // 底部 46px 上收（与 ReaderPage 对 ReaderContent 的锚定同语义）。
        anchors.top: parent.top
        anchors.topMargin: readerShell.sheetOpen ? readerShell.topToolbar.height : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: page.ttsBarVisible ? readerShell.ttsBar.height : 0
        document: pdfDoc
        // 阅读进度：当前页变化仅置 dirty，2s 合并 Timer 触发才写 settings.json 的
        // progress/pdf_<bookId> + books.progress（页码/总页数，含 last_read_at）；
        // 同时重提取当前页文本（朗读能力随页变化）并同步书签高亮。
        onCurrentPageChanged: {
            if (!page.restoreDone) return
            page.progressDirty = true
            progressFlush.restart()
            page.refreshPageText()
            page.syncPdfBookmarkState()
        }
        // 单点：切换壳层显隐状态（唤出顶栏/Sheet 或关闭——ReaderPage 同款交互）；
        // 缩放切换由壳层 Sheet 的 PDF 专属缩放面板承担（旧双击切换收编，见 onZoom）。
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: readerShell.handleTap(0, 0)
        }
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
        if (id === "fitWidth") { page.fitPage = false; pdfView.scaleToWidth(pdfView.width, pdfView.height) }
        else if (id === "fitPage") { page.fitPage = true; pdfView.scaleToPage(pdfView.width, pdfView.height) }
        else if (id === "reset") { pdfView.resetScale() }
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
    function refreshPageText() {
        const s = page.extractPageText(pdfView.currentPage)
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

    // ---- 任务4：目录跳转（页码目录 openContents 目标）——关闭目录并停止会话 ----
    function goToPdfPage(i) {
        if (pdfDoc.status !== PdfDocument.Ready) return
        tocDialog.close()                // 先释放模态焦点，否则后续键盘事件留在弹层
        page.stopPdfTts()                // 目录跳转属于手动跳转：停止活动会话
        if (i >= 0 && i < pdfDoc.pageCount) pdfView.goToPage(i)
    }

    // ---- 任务4：书签（bookmarks/pdf_<bookId> 页索引数组）----
    function syncPdfBookmarkState() {
        page.currentBookmarked = page.pdfBookmarks.indexOf(pdfView.currentPage) >= 0
    }
    function togglePdfBookmark() {
        if (!page.book || !page.book.id || pdfDoc.status !== PdfDocument.Ready) return
        const list = page.pdfBookmarks.slice()
        const i = list.indexOf(pdfView.currentPage)
        if (i >= 0) list.splice(i, 1)
        else list.push(pdfView.currentPage)
        page.pdfBookmarks = list
        Settings.setValue("bookmarks/pdf_" + page.book.id, list)
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

    // 无在途渲染：image.status 为 Ready（渲染完成）/ Error / Null（无渲染任务）时安全
    function renderSettled() {
        const s = pdfView.status
        return s === Image.Ready || s === Image.Error || s === Image.Null
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
        property bool supportsNotes: false
        property bool supportsBookmarks: true
        property string previousLabel: qsTr("上一页")
        property string nextLabel: qsTr("下一页")
        function previous() { page.previousPage() }
        function next() { page.nextPage() }
        function startReadAloud() { page.startPdfReadAloud() }
        function stopReadAloud() { page.stopPdfTts() }
        function openContents() { tocDialog.open() }
        function openSearch() {}
        function openNotes() {}
        function toggleBookmark() { page.togglePdfBookmark() }
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
        contentItem: pdfView
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
