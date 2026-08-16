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
// 枚举改为 scaleToWidth/scaleToPage 方法（双击在两者间切换）。
// 阅读进度独立键 progress/pdf_<bookId>（存页码），与文本书的
// progress/<bookId>（存章节索引）区分——B10 进度恢复按 format 分流读取。
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
    // 任务2：暴露给测试的稳定句柄——QML 原生 id 仅组件内词法可见，
    // 外部测试须经 alias 才能以 page.<handle> 访问。
    property alias previousPageButton: previousPageButton
    property alias nextPageButton: nextPageButton
    property alias menuButton: menuButton
    property alias pageLabel: pageLabel
    property alias pdfMenu: pdfMenu
    property alias retryButton: retryButton
    property alias errorLabel: errorLabel
    property alias loadingIndicator: loadingIndicator
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

    PdfDocument {
        id: pdfDoc
        source: book.path ? "file://" + book.path : ""
        // 文档就绪后：先按可用阅读区宽度适配（否则默认 renderScale=1 窄页右侧留白），
        // 再跳转到保存页（progress/pdf_<bookId>），最后放开进度写入
        onStatusChanged: (status) => {
            if (status !== PdfDocument.Ready || page.restoreDone || !page.book.id) return
            pdfView.scaleToWidth(pdfView.width, pdfView.height)
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
        // 阅读进度：当前页变化仅置 dirty，2s 合并 Timer 触发才写 settings.json 的
        // progress/pdf_<bookId> + books.progress（页码/总页数，含 last_read_at）
        onCurrentPageChanged: {
            if (!page.restoreDone) return
            page.progressDirty = true
            progressFlush.restart()
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
                // U6：Token 审计——原 #1A1A1A 与 lightTextPrimary 同值，收编为 Token
                color: UITheme.lightTextPrimary
            }
            // 任务2：上一页（仅 Ready 且非首页可用）
            // 图标经 contentItem 替换按钮默认内容（仓库惯例同 SettingsPage/StatsPage
            // 的 contentItem: KdIcons），否则图标作为裸子项不参与按钮居中布局
            ToolButton {
                id: previousPageButton
                contentItem: KdIcons { name: "prev"; size: 20; color: UITheme.lightTextPrimary }
                enabled: pdfDoc.status === PdfDocument.Ready && pdfView.currentPage > 0
                onClicked: page.previousPage()
            }
            // 任务2：页码指示（无文档时显示占位，保持非空）
            Label {
                id: pageLabel
                text: pdfDoc.pageCount > 0
                      ? qsTr("第 %1 / %2 页").arg(pdfView.currentPage + 1).arg(pdfDoc.pageCount)
                      : qsTr("第 - / - 页")
                color: UITheme.lightTextPrimary
            }
            // 任务2：下一页（仅 Ready 且非末页可用）
            ToolButton {
                id: nextPageButton
                contentItem: KdIcons { name: "next"; size: 20; color: UITheme.lightTextPrimary }
                enabled: pdfDoc.status === PdfDocument.Ready
                         && pdfView.currentPage < pdfDoc.pageCount - 1
                onClicked: page.nextPage()
            }
            // 任务2：更多菜单入口（非 Ready 时禁用——Error/Loading 下不应打开缩放菜单）
            ToolButton {
                id: menuButton
                contentItem: KdIcons { name: "more"; size: 20; color: UITheme.lightTextPrimary }
                enabled: pdfDoc.status === PdfDocument.Ready
                onClicked: pdfMenu.open()
            }
        }
    }

    // 任务2：更多缩放菜单——宽度适配 / 整页适配 / 重置缩放；锚定右上角，
    // 面板不覆盖左上角返回键；点击遮罩关闭
    KdDropdownMenu {
        id: pdfMenu
        z: 100
        items: [
            { id: "fitWidth", icon: "image", text: qsTr("宽度适配") },
            { id: "fitPage", icon: "layout", text: qsTr("整页适配") },
            { divider: true },
            { id: "reset", icon: "toc", text: qsTr("重置缩放") }
        ]
        onItemClicked: (id) => page.onMenu(id)
    }

    // 任务2：Loading 反馈——避免加载期间白屏无反馈
    Rectangle {
        id: loadingIndicator
        anchors.top: topBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
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
        anchors.top: topBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
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

    // 任务2：键盘路由——A/Left/PageUp 前一页，D/Right/PageDown 后一页；
    // 只在实际处理（Ready 且边界内）后接受键事件，否则交回 Flickable 处理滚动。
    // 带修饰键（Ctrl/Cmd/Shift/Alt）的事件一律不吞，交回上层/系统（如 Cmd+A 全选、
    // Cmd+D、Shift+方向键选区）；自动重复（isAutoRepeat）维持原行为逐次翻页。
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: (event) => {
        if (event.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.ShiftModifier | Qt.AltModifier))
            return
        let handled = false
        if (event.key === Qt.Key_Left || event.key === Qt.Key_PageUp || event.key === Qt.Key_A)
            handled = page.previousPage()
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_PageDown || event.key === Qt.Key_D)
            handled = page.nextPage()
        if (handled) event.accepted = true
    }

    function toggleFit() {
        page.fitPage = !page.fitPage
        if (page.fitPage)
            pdfView.scaleToPage(pdfView.width, pdfView.height)
        else
            pdfView.scaleToWidth(pdfView.width, pdfView.height)
    }

    // 任务2：前一页——仅 Ready 且非首页时 goToPage(currentPage-1)，成功返回 true
    function previousPage() {
        if (pdfDoc.status !== PdfDocument.Ready || pdfView.currentPage <= 0) return false
        pdfView.goToPage(pdfView.currentPage - 1)
        return true
    }
    // 任务2：后一页——仅 Ready 且非末页时 goToPage(currentPage+1)，成功返回 true
    function nextPage() {
        if (pdfDoc.status !== PdfDocument.Ready
                || pdfView.currentPage >= pdfDoc.pageCount - 1) return false
        pdfView.goToPage(pdfView.currentPage + 1)
        return true
    }
    // 任务2：缩放菜单动作——宽度适配 / 整页适配 / 重置缩放。
    // Ready 门控：Error/Loading 状态点中菜单项不得触发缩放调用（缩放依赖已加载
    // 文档的 pagePointSize，非 Ready 调用无意义；按钮 enabled 已拦截，此处防御）
    function onMenu(id) {
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

    // 关闭阅读页：等渲染线程空闲再 pop（文档销毁撞在途渲染 = UAF 崩溃）。
    // 渲染在途时持续轮询等待，**绝不**在渲染未稳定时强制销毁文档——慢渲染
    //（大 PDF 高倍率重渲染可达数秒）超时强制 pop 会把 UAF 换一种方式放回来；
    // 超长渲染（>60s）仅告警，保持等待直到稳定（Ready 文档的渲染必然完成）。
    function requestClose() {
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

    Component.onCompleted: {
        if (page.book && page.book.id)
            Books.startTracking(page.book.id)  // 阅读计时开始
        // E4（PDF）：首次创建即获得 activeFocus，方向键翻页立即可用（ReaderPage 同款）
        page.forceActiveFocus()
    }

    // E4（PDF）：从其它页面返回（StackView pop 回来）时补 focus——onCompleted 只在
    // 首次创建时执行，返回路径若不在此恢复，键盘路由将失效（ReaderPage 同款）
    StackView.onActivated: page.forceActiveFocus()

    Component.onDestruction: {
        page.flushProgress()   // L9（P2#34）：未落盘的翻页进度兜底写入
        Books.stopTracking()  // 结算阅读秒数
    }
}
