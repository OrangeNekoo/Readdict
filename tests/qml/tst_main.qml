import QtQuick
import QtQuick.Controls
import QtQuick.Pdf
import QtTest
import Readdict.Backend
import Readdict.Test 1.0

// 冒烟测试：真实 UI 组件可在测试进程中加载（Loader + qrc 资源路径，
// 单例由 tst_qmlmain.cpp 注册）。
Item {
    id: root
    width: 1100; height: 720
    Component {
        id: shelfComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/ShelfPage.qml" }
    }
    Component {
        id: mainComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/Main.qml" }
    }
    Component {
        id: cardComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/BookCard.qml" }
    }
    Component {
        id: readerComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml" }
    }
    Component {
        id: contentComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/ReaderContent.qml" }
    }
    Component {
        id: readerShellComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/ReaderShell.qml" }
    }
    Component {
        id: controlsComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/KdTopToolbar.qml" }
    }
    Component {
        id: pdfReaderComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/PdfReaderPage.qml" }
    }
    Component {
        id: settingsComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/SettingsPage.qml" }
    }
    TestCase {
        name: "PdfReaderSmoke"
        function test_pdfReaderLoads() {
            var loader = pdfReaderComp.createObject(root)
            verify(loader.item !== null, "PdfReaderPage 应能加载（QtQuick.Pdf import + PdfScrollablePageView 编译检查）")
            loader.destroy()
        }
        // 任务2 控制层测试（无需真实 PDF）：稳定句柄、页码指示、Loading/Error 覆盖。
        // 任务4：PDF 已接入共享壳层——顶栏/菜单/TtsBar 均为 ReaderShell 同一对象，
        // 上/下一项经适配器标签（"上一页/下一页"）；错误/重试/加载指示仍为本页句柄。
        function test_pdfReaderControlsExposeNavigationAndMenu() {
            var loader = pdfReaderComp.createObject(root)
            var page = loader.item
            verify(page !== null, "PdfReaderPage 应能加载")
            // 共享壳层：readerShell 暴露且顶栏/TtsBar/菜单为本页同一对象
            verify(page.readerShell !== undefined, "应暴露 readerShell")
            verify(page.readerShell.topToolbar !== undefined, "应暴露共享顶栏 topToolbar")
            verify(page.readerShell.ttsBar !== undefined, "应暴露共享 TtsBar ttsBar")
            verify(page.readerShell.menuItem("read") !== null, "共享菜单应有朗读项")
            verify(page.readerShell.menuItem("prev") !== null, "共享菜单应有上一项")
            verify(page.readerShell.menuItem("next") !== null, "共享菜单应有下一项")
            compare(page.readerShell.menuItem("prev").text, "上一页",
                    "prev 标签应为上一页（适配器提供，非固定章节文案）")
            compare(page.readerShell.menuItem("next").text, "下一页",
                    "next 标签应为下一页（适配器提供，非固定章节文案）")
            // 适配器句柄：统一契约成员可见（canReadAloud/原因/能力位/标签/动作）
            verify(page.readerAdapter !== undefined, "应暴露 readerAdapter")
            verify(page.readerAdapter.canReadAloud !== undefined, "适配器应有 canReadAloud")
            verify(page.readerAdapter.readAloudUnavailableReason !== undefined,
                   "适配器应有 readAloudUnavailableReason")
            verify(page.readerAdapter.previousLabel !== undefined, "适配器应有 previousLabel")
            // 未就绪（status Null）时不可用原因应为加载中文案（区别于就绪无文本）
            compare(page.readerAdapter.readAloudUnavailableReason, "PDF 尚未加载完成",
                    "未就绪时不可用原因应为'PDF 尚未加载完成'")
            // 错误/重试/加载指示句柄（任务4 保留，非顶栏/菜单/TTS 逻辑）
            verify(page.retryButton !== undefined, "应暴露 retryButton")
            verify(page.errorLabel !== undefined, "应暴露 errorLabel")
            verify(page.loadingIndicator !== undefined, "应暴露 loadingIndicator")
            verify(page.pageLabel.text.length > 0,
                   "页码指示应非空，实际 '" + page.pageLabel.text + "'")
            // 无文档（status Null）时 loading 与 error 都不应显示
            verify(!page.loadingIndicator.visible, "Null 状态不应显示 loading")
            verify(!page.errorLabel.visible, "Null 状态不应显示 error")
            // 菜单开关：openMenu() 打开，triggerMenuAction 关闭（共享壳层状态机）
            page.readerShell.openMenu()
            tryVerify(function () { return page.readerShell.menuOpen }, 3000, "openMenu() 应打开菜单")
            page.readerShell.triggerMenuAction("info")
            tryVerify(function () { return !page.readerShell.menuOpen }, 3000,
                      "triggerMenuAction 应关闭菜单")
            loader.destroy()
        }
        // 任务2 Error 状态：坏源进入 PdfDocument.Error，显示 pdfDoc.error 与重试按钮，
        // 重试保持同一 source 并重新触发加载。
        function test_pdfErrorShowsMessageAndRetry() {
            var loader = pdfReaderComp.createObject(root)
            var page = loader.item
            page.book = { id: 999004, title: "坏PDF", path: "/nonexistent/pdf.pdf" }
            var doc = page.pdfDocument
            tryVerify(function () { return doc.status === PdfDocument.Error }, 15000,
                      "坏源应进入 Error，实际 " + doc.status)
            verify(page.errorLabel.visible, "Error 时应显示错误信息")
            compare(page.errorLabel.text, doc.error, "错误文本应显示 pdfDoc.error")
            verify(page.retryButton.visible, "Error 时应显示重试按钮")
            var srcBefore = doc.source
            page.retryButton.clicked()
            compare(doc.source, srcBefore, "重试应保持同一 source")
            loader.destroy()
        }
        // 任务2 Loading 状态覆盖：坏源常瞬跳 Error，若捕获到 Loading 窗口则断言
        // loadingIndicator 可见；无真实 PDF 无法稳定捕获时记录观测状态（句柄已在
        // test_pdfReaderControlsExposeNavigationAndMenu 锁定，真实 Loading 由
        // test_pdfLoadsRealSource 在 READDICT_REAL_PDF 下覆盖）。
        function test_pdfLoadingStateCoverage() {
            var loader = pdfReaderComp.createObject(root)
            var page = loader.item
            var seenLoading = false
            page.book = { id: 999005, title: "加载PDF", path: "/nonexistent/pdf.pdf" }
            var doc = page.pdfDocument
            var log = []
            for (var i = 0; i < 25; ++i) {
                log.push(doc.status)
                if (doc.status === PdfDocument.Loading) { seenLoading = true; break }
                if (doc.status === PdfDocument.Error) break
                QTest.qWait(20)
            }
            if (seenLoading)
                verify(page.loadingIndicator.visible, "Loading 状态应显示 loadingIndicator")
            else
                console.log("未捕获 Loading 窗口，观测状态序列=" + log.join(","))
            loader.destroy()
        }
        // 真实 PDF 加载验证：TestEnv.pdfSource 为空（未设 READDICT_REAL_PDF）时跳过；
        // 否则加载真实文件并等待 PdfDocument Ready，确认 QtPdf 渲染管线可用
        function test_pdfLoadsRealSource() {
            var src = TestEnv.pdfSource
            if (src.length === 0)
                skip("未设置 READDICT_REAL_PDF，跳过真实 PDF 加载验证")
            // 真实 PDF 加载必须给 Loader 显式非零宽高：0×0 时 scaleToWidth 按
            // PdfScrollablePageView 内部 root.width 计算 renderScale=0（QML 源码
            // scaleToWidth 用 root.width 而非参数 width），页面渲染空白、相对变化
            // 断言失真——显式尺寸让适配按真实阅读区宽度计算（修复 renderScale=0 回归）
            // 注意：QPdfDocument::load(QString) 对本地文件是同步的——page.book 赋值
            // 即完成加载并触发 Ready（PdfScrollablePageView.onStatusChanged 同步执行
            // scaleToWidth）。因此默认 renderScale 必须在设置 book 之前捕获，
            // 否则捕获到的已是适配后的值，相对变化断言失去判别力。
            var loader = pdfReaderComp.createObject(root, { width: 800, height: 1000 })
            var page = loader.item
            verify(page !== null, "PdfReaderPage 应能加载")
            var initialScale = page.pdfView.renderScale // 默认 renderScale=1
            page.book = { id: 999001, title: "真实PDF", path: src }
            var doc = page.pdfDocument
            verify(doc !== null, "PdfReaderPage 应暴露 pdfDocument")
            tryVerify(function () { return doc.status === PdfDocument.Ready }, 15000,
                      "真实 PDF 应加载为 Ready，实际 " + doc.status)
            verify(doc.pageCount > 0, "加载的 PDF 应有页数")
            // 任务2：Ready 时应先 scaleToWidth 适配阅读区宽度（默认 renderScale=1 右侧留白）；
            // 断言 renderScale 相对 Ready 前默认值发生改变（适配后按页宽缩放）
            tryVerify(function () { return page.pdfView.renderScale !== initialScale }, 5000,
                      "Ready 后应 scaleToWidth 改变 renderScale，实际 " + page.pdfView.renderScale)
            // 任务2：页码指示应显示 第 1 / N 页
            tryVerify(function () {
                return page.pageLabel.text.indexOf("1 / " + doc.pageCount) >= 0
            }, 5000, "页码指示应显示 第 1 / N 页，实际 '" + page.pageLabel.text + "'")
            // 任务2：后一页/前一页可用性边界（第 0 页：前页禁用，后页可用）
            tryVerify(function () { return page.pdfView.currentPage === 0 }, 5000,
                      "初始应在第 0 页，实际 " + page.pdfView.currentPage)
            verify(page.readerAdapter.canGoPrevious === false, "第 0 页时上一页应禁用")
            verify(page.readerAdapter.canGoNext === true, "第 0 页时下一页应可用")
            // 任务4：下一页推进、上一页回退经共享壳层菜单 prev/next 动作（适配器分发）
            page.readerShell.triggerMenuAction("next")
            tryVerify(function () { return page.pdfView.currentPage === 1 }, 5000,
                      "菜单下一页应前进到第 1 页，实际 " + page.pdfView.currentPage)
            page.readerShell.triggerMenuAction("prev")
            tryVerify(function () { return page.pdfView.currentPage === 0 }, 5000,
                      "菜单上一页应回到第 0 页，实际 " + page.pdfView.currentPage)
            // 30MB 大 PDF 首帧渲染可能仍在进行：等渲染完成再销毁，避免 QtPdfQuick 拆除竞态崩溃
            tryVerify(function () { return page.pdfView.status === Image.Ready }, 15000,
                      "首页渲染应完成，实际 " + page.pdfView.status)
            loader.destroy()
        }
        // B10：PDF 进度恢复——Ready 后应先 goToPage(保存页)，且 Ready 时的
        // 首次 currentPageChanged(0) 不得覆盖保存值（restoreDone 标志门控写入）
        function test_pdfRestoresPage() {
            var src = TestEnv.pdfSource
            if (src.length === 0)
                skip("未设置 READDICT_REAL_PDF，跳过 PDF 进度恢复验证")
            var id = 999002 // 独立 bookId，避免与 test_pdfLoadsRealSource 的 999001 互相污染
            Settings.setValue("progress/pdf_" + id, 3)
            // 同 test_pdfLoadsRealSource：0×0 Loader 下 scaleToWidth 按 root.width=0
            // 计算 renderScale=0，页面渲染空白（Image.Ready 断言必然失败），须显式尺寸
            var loader = pdfReaderComp.createObject(root, { width: 800, height: 1000 })
            var page = loader.item
            page.book = { id: id, title: "真实PDF", path: src }
            tryVerify(function () { return page.pdfDocument.status === PdfDocument.Ready }, 15000,
                      "真实 PDF 应加载为 Ready")
            tryVerify(function () { return page.pdfView.currentPage === 3 }, 5000,
                      "恢复后应定位到保存页 3，实际 " + page.pdfView.currentPage)
            compare(Number(Settings.value("progress/pdf_" + id)), 3,
                    "恢复页不应被 Ready 时的初始页 0 覆盖")
            tryVerify(function () { return page.pdfView.status === Image.Ready }, 15000,
                      "恢复页渲染应完成再销毁，实际 " + page.pdfView.status)
            loader.destroy()
        }
        // B10：关闭竞态防护——真实 StackView 内 push PdfReaderPage，翻页后立即请求关闭：
        // requestClose 应只等渲染稳定（image.status Ready）后由 StackView 销毁页面，
        // 不撞在途渲染线程（QPdfDocument 销毁 vs QQuickPixmapReader 的 use-after-free）。
        // 注：quicktest harness 不推进 StackView 过渡动画（对普通 Rectangle push/pop 亦然），
        // depth 归零无法断言；此处断言可观测的安全属性——渲染稳定前页面必须存活。
        function test_pdfCloseWaitsRender() {
            var src = TestEnv.pdfSource
            if (src.length === 0)
                skip("未设置 READDICT_REAL_PDF，跳过关闭竞态验证")
            var stack = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; StackView { anchors.fill: parent; }", root)
            verify(stack !== null, "测试 StackView 应能创建")
            var id = 999003
            stack.push("qrc:/qt/qml/Readdict/ui/qml/PdfReaderPage.qml",
                       { book: { id: id, title: "真实PDF", path: src } })
            var page = stack.currentItem
            verify(page !== null, "PdfReaderPage 应被 push 进 StackView")
            tryVerify(function () { return page.pdfDocument.status === PdfDocument.Ready }, 15000,
                      "真实 PDF 应加载为 Ready")
            tryVerify(function () { return page.pdfView.status === Image.Ready }, 15000,
                      "初始页应渲染完成")
            // 触发重渲染并立即请求关闭：渲染进入在途（Loading）的瞬间调用 requestClose，
            // 锁定轮询等待真实生效——closePollCount 增长 + 渲染稳定前页面不被销毁。
            // 先等 goToPage 触发的渲染稳定，再单独触发高倍率重渲染：若两步在同一事件
            // 循环内连续执行，两次加载会合并/竞态，实测可能只剩 14ms 级小渲染——renderScale
            // 10（约 6120×7920px）的渲染未真正发生，closePoll（50ms）首个 tick 已见稳定态，
            // closePollCount 恒为 0 导致断言误报（该用例此前从未在真实 PDF 下运行）。
            // 待稳定后单独触发的 scale-10 渲染实测约 171ms，远大于 50ms tick 周期，窗口必然命中。
            page.pdfView.goToPage(5)
            tryVerify(function () { return page.pdfView.status === Image.Ready }, 15000,
                      "goToPage 渲染应先稳定，实际 " + page.pdfView.status)
            page.pdfView.renderScale = 10 // 高倍率重渲染，加大 Loading 窗口
            // Loading 窗口在 renderScale 同一事件循环内同步进入（实测稳定命中 status=Loading）；
            // 若渲染太快已 Ready 则测试失败而非跳过——轮询锁定必须是必然路径
            verify(page.pdfView.status !== Image.Ready,
                   "renderScale 后应立即进入 Loading 渲染窗口（status=" + page.pdfView.status + "）")
            page.requestClose()
            verify(page.closing === true, "requestClose 应置 closing 防重入")
            // 锁定等待逻辑真实生效：closePoll 轮询计数增长 + 渲染稳定前页面不被销毁
            tryVerify(function () { return page.closePollCount > 0 }, 5000,
                      "渲染在途时 requestClose 应启动轮询（closePollCount="
                      + page.closePollCount + "）")
            verify(stack.currentItem === page, "渲染稳定前页面应仍在栈顶（未被提前销毁）")
            // 渲染稳定前页面（含 QPdfDocument）不得被销毁——这是竞态防护的核心不变量
            tryVerify(function () { return page.pdfView.status === Image.Ready }, 20000,
                      "渲染应最终稳定，实际 " + page.pdfView.status)
            verify(page.pdfView !== undefined && page.pdfView.currentPage === 5,
                   "渲染稳定后页面仍应存活（未被提前销毁）")
            stack.destroy()
        }
        // E4（PDF）：生产键盘焦点链路——不直接调用 previousPage/nextPage，真实按键经
        // QtTest keyClick 走生产 Keys.onPressed 路由。前提是 push（生产路径）后页面
        // 持有 activeFocus（focus:true + Component.onCompleted forceActiveFocus，与
        // ReaderPage 同款）；无真实 PDF 明确 skip（与其它真实 PDF 用例一致）。
        // 同时覆盖审查项：带修饰键（Ctrl）的事件不吞——Ctrl+D 不得翻页。
        function test_pdfKeyNavChangesPageWithActiveFocus() {
            var src = TestEnv.pdfSource
            if (src.length === 0)
                skip("未设置 READDICT_REAL_PDF，跳过真实 PDF 键盘导航验证")
            var stack = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; StackView { anchors.fill: parent; }", root)
            verify(stack !== null, "测试 StackView 应能创建")
            var id = 999006 // 独立 bookId，避免与其它 PDF 用例互相污染
            stack.push("qrc:/qt/qml/Readdict/ui/qml/PdfReaderPage.qml",
                       { book: { id: id, title: "键盘PDF", path: src } })
            var page = stack.currentItem
            verify(page !== null, "PdfReaderPage 应被 push 进 StackView")
            tryVerify(function () { return page.pdfDocument.status === PdfDocument.Ready }, 15000,
                      "真实 PDF 应加载为 Ready")
            // 焦点前提：页面必须持有 activeFocus，生产 Keys.onPressed 才收得到按键
            tryVerify(function () { return page.activeFocus === true }, 3000,
                      "push 后 PdfReaderPage 应持有 activeFocus，实际 " + page.activeFocus)
            tryVerify(function () { return page.pdfView.currentPage === 0 }, 5000,
                      "初始应在第 0 页，实际 " + page.pdfView.currentPage)
            // 真实 D 键 → 下一页（生产按键链路，非函数直调）
            keyClick(Qt.Key_D)
            tryVerify(function () { return page.pdfView.currentPage === 1 }, 5000,
                      "真实 D 键应前进到第 1 页，实际 " + page.pdfView.currentPage)
            // 真实 A 键 → 上一页
            keyClick(Qt.Key_A)
            tryVerify(function () { return page.pdfView.currentPage === 0 }, 5000,
                      "真实 A 键应回到第 0 页，实际 " + page.pdfView.currentPage)
            // 方向键同链路
            keyClick(Qt.Key_Right)
            tryVerify(function () { return page.pdfView.currentPage === 1 }, 5000,
                      "真实 Right 应前进到第 1 页，实际 " + page.pdfView.currentPage)
            keyClick(Qt.Key_Left)
            tryVerify(function () { return page.pdfView.currentPage === 0 }, 5000,
                      "真实 Left 应回到第 0 页，实际 " + page.pdfView.currentPage)
            // 修饰键不吞：Ctrl+D 不应翻页（键盘路由放行带修饰键事件）
            keyClick(Qt.Key_D, Qt.ControlModifier)
            tryVerify(function () { return page.pdfView.currentPage === 0 }, 3000,
                      "Ctrl+D 不应翻页，实际 " + page.pdfView.currentPage)
            // 渲染稳定后销毁，避免 QtPdfQuick 拆除竞态崩溃
            tryVerify(function () { return page.pdfView.status === Image.Ready }, 15000,
                      "首页渲染应完成，实际 " + page.pdfView.status)
            stack.destroy()
        }
        // 任务1：PDF 双方向——scroll 使用 PdfMultiPageView（multi，多页连续竖向），
        // paged 使用 PdfScrollablePageView（single，单页横向分页）；setPageMode 写回
        // reading/pageMode，切换方向保留当前页。确定性文本 PDF 夹具（TestEnv.textPdfSource，
        // 两页 A4）任何环境可跑，不依赖 READDICT_REAL_PDF。
        function test_pdfSupportsVerticalAndHorizontalModes() {
            var stack = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; StackView { anchors.fill: parent; }", root)
            verify(stack !== null, "测试 StackView 应能创建")
            stack.push("qrc:/qt/qml/Readdict/ui/qml/PdfReaderPage.qml",
                       { book: { id: 999111, title: "双方向PDF", path: TestEnv.textPdfSource } })
            var page = stack.currentItem
            verify(page !== null, "PdfReaderPage 应被 push 进 StackView")
            var doc = page.pdfDocument
            tryVerify(function () { return doc.status === PdfDocument.Ready }, 15000,
                      "文本 PDF 应加载为 Ready，实际 " + doc.status)
            // scroll 方向：multi（PdfMultiPageView 连续竖向）
            page.setPageMode("scroll")
            tryVerify(function () { return page.pdfViewKind === "multi" }, 3000,
                      "scroll 应使用 multi（PdfMultiPageView），实际 " + page.pdfViewKind)
            tryVerify(function () { return page.pdfView.currentPage === 0 }, 3000,
                      "multi 初始应在第 0 页，实际 " + page.pdfView.currentPage)
            compare(String(Settings.value("reading/pageMode")), "scroll",
                    "setPageMode(scroll) 应写回 reading/pageMode")
            // multi 模式翻到第 1 页
            page.nextPage()
            tryVerify(function () { return page.pdfView.currentPage === 1 }, 5000,
                      "multi 下一页应到第 1 页，实际 " + page.pdfView.currentPage)
            // 切到 paged：single（PdfScrollablePageView 横向分页）且页码保留
            page.setPageMode("paged")
            tryVerify(function () { return page.pdfViewKind === "single" }, 3000,
                      "paged 应使用 single（PdfScrollablePageView），实际 " + page.pdfViewKind)
            tryVerify(function () { return page.pdfView.currentPage === 1 }, 5000,
                      "切到 paged 应保留第 1 页，实际 " + page.pdfView.currentPage)
            compare(String(Settings.value("reading/pageMode")), "paged",
                    "setPageMode(paged) 应写回 reading/pageMode")
            // 再切回 scroll：页码仍保留
            page.setPageMode("scroll")
            tryVerify(function () { return page.pdfViewKind === "multi" }, 3000,
                      "应能切回 multi，实际 " + page.pdfViewKind)
            tryVerify(function () { return page.pdfView.currentPage === 1 }, 5000,
                      "切回 scroll 应保留第 1 页，实际 " + page.pdfView.currentPage)
            // 渲染稳定后销毁，避免 QtPdfQuick 拆除竞态崩溃
            tryVerify(function () { return page.renderSettled() }, 15000,
                      "渲染应稳定再销毁，实际 status=" + page.pdfView.status)
            stack.destroy()
        }
        // 任务2：整页适配居中——paged 单页视图（PdfScrollablePageView，Flickable）在
        // fitPage 时设置对称左右边距，使内容中心 == 视口中心；宽度适配清除边距
        //（不强制居中）；视口尺寸改变后重新计算。确定性文本 PDF 夹具（两页 A4）。
        function test_fitPageCentersNarrowPdf() {
            var stack = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; StackView { anchors.fill: parent; }", root)
            verify(stack !== null, "测试 StackView 应能创建")
            stack.push("qrc:/qt/qml/Readdict/ui/qml/PdfReaderPage.qml",
                       { book: { id: 999112, title: "居中PDF", path: TestEnv.textPdfSource } })
            var page = stack.currentItem
            verify(page !== null, "PdfReaderPage 应被 push 进 StackView")
            tryVerify(function () { return page.pdfDocument.status === PdfDocument.Ready }, 15000,
                      "文本 PDF 应加载为 Ready，实际 " + page.pdfDocument.status)
            // 居中仅在 paged（PdfScrollablePageView，Flickable 可设左右边距）模式断言
            page.setPageMode("paged")
            tryVerify(function () { return page.pdfViewKind === "single" }, 3000,
                      "居中验证应在 paged（single）模式，实际 " + page.pdfViewKind)
            // 整页适配：窄页产生对称正边距，内容中心 == 视口中心
            page.setFitPage(true)
            tryVerify(function () { return page.pdfHorizontalMargin > 0 }, 3000,
                      "窄页整页适配应产生正边距，实际 " + page.pdfHorizontalMargin)
            compare(page.pdfLeftMargin, page.pdfRightMargin, "整页适配左右边距应对称")
            tryVerify(function () {
                return Math.abs(page.pdfContentCenter - page.pdfViewportCenter) < 1.0
            }, 3000, "整页适配内容中心应等于视口中心（内容 " + page.pdfContentCenter
                  + " vs 视口 " + page.pdfViewportCenter + "）")
            // 宽度适配：清除边距（不强制居中）
            page.setFitPage(false)
            tryVerify(function () { return page.pdfLeftMargin === 0 && page.pdfRightMargin === 0 }, 3000,
                      "宽度适配应清除居中边距，实际 L=" + page.pdfLeftMargin + " R=" + page.pdfRightMargin)
            // 视口尺寸改变后重新计算边距并保持居中
            page.setFitPage(true)
            tryVerify(function () { return page.pdfHorizontalMargin > 0 }, 3000,
                      "再次整页适配应产生边距")
            var marginBefore = page.pdfLeftMargin
            page.width = page.width + 200
            tryVerify(function () { return page.pdfViewportCenter > 0
                                            && page.pdfLeftMargin !== marginBefore }, 3000,
                      "视口变宽应重算边距，实际 " + page.pdfLeftMargin + "（原 " + marginBefore + "）")
            tryVerify(function () {
                return Math.abs(page.pdfContentCenter - page.pdfViewportCenter) < 1.0
            }, 3000, "尺寸改变后内容中心仍应等于视口中心")
            page.width = page.width - 200
            // 渲染稳定后销毁，避免 QtPdfQuick 拆除竞态崩溃
            tryVerify(function () { return page.renderSettled() }, 15000,
                      "渲染应稳定再销毁，实际 " + page.pdfView.status)
            stack.destroy()
        }
        // 任务4：文本 PDF 朗读——确定性夹具（TestEnv.textPdfSource，两页各两句）：
        // 生产 keyClick(D) 翻页、共享壳层菜单朗读、手动翻页停止 TTS 会话、
        // 读完一页自动续读下一有文本页、末页耗尽停 TTS 并显示提示。
        // 不依赖 READDICT_REAL_PDF，任何环境确定性可跑。
        function test_textPdfCanReadAloud() {
            Tts.stop()
            Tts.reconfigure("openai", "https://api.openai.com/v1", "", "tts-1", "nova", 1.0)
            var stack = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; StackView { anchors.fill: parent; }", root)
            verify(stack !== null, "测试 StackView 应能创建")
            stack.push("qrc:/qt/qml/Readdict/ui/qml/PdfReaderPage.qml",
                       { book: { id: 999101, title: "文本PDF", path: TestEnv.textPdfSource } })
            var page = stack.currentItem
            verify(page !== null, "PdfReaderPage 应被 push 进 StackView")
            var doc = page.pdfDocument
            tryVerify(function () { return doc.status === PdfDocument.Ready }, 15000,
                      "文本 PDF 应加载为 Ready，实际 " + doc.status)
            compare(doc.pageCount, 2, "文本 PDF 应为两页")
            tryVerify(function () { return page.readerAdapter.canReadAloud === true }, 3000,
                      "有文本页应可朗读，实际 " + page.readerAdapter.canReadAloud)
            compare(page.readerAdapter.readAloudUnavailableReason, "",
                    "有文本时不可用原因应为空")
            // 共享壳层顶栏/菜单对象存在（任务4 契约）
            verify(page.readerShell !== undefined, "应暴露 readerShell")
            verify(page.readerShell.topToolbar !== undefined, "应暴露共享顶栏")
            tryVerify(function () { return page.readerShell.menuItem("read").enabled === true },
                      3000, "有文本页朗读菜单项应可用")
            // 页码目录：菜单目录项打开页标签对话框（适配器 openContents），可关闭
            page.readerShell.triggerMenuAction("toc")
            tryVerify(function () { return page.tocDlg.visible }, 3000,
                      "目录菜单项应打开页码目录")
            page.tocDlg.close()
            tryVerify(function () { return !page.tocDlg.visible }, 3000,
                      "目录对话框应可关闭")
            // 生产 keyClick 翻页（E4 链路，不直调函数）
            tryVerify(function () { return page.activeFocus === true }, 3000,
                      "PDF 页应持有 activeFocus")
            keyClick(Qt.Key_D)
            tryVerify(function () { return page.pdfView.currentPage === 1 }, 5000,
                      "生产 D 键应前进到第 1 页，实际 " + page.pdfView.currentPage)
            keyClick(Qt.Key_A)
            tryVerify(function () { return page.pdfView.currentPage === 0 }, 5000,
                      "生产 A 键应回到第 0 页，实际 " + page.pdfView.currentPage)
            // 菜单/Sheet 打开时键盘翻页门控（与 ReaderPage 一致）：不翻页
            page.readerShell.openMenu()
            keyClick(Qt.Key_D)
            compare(page.pdfView.currentPage, 0, "菜单打开时 D 键不应翻页")
            page.readerShell.triggerMenuAction("info")   // 关菜单；Sheet 仍打开
            keyClick(Qt.Key_D)
            compare(page.pdfView.currentPage, 0, "Sheet 打开时 D 键不应翻页")
            page.readerShell.sheetOpen = false
            keyClick(Qt.Key_D)
            tryVerify(function () { return page.pdfView.currentPage === 1 }, 5000,
                      "关闭 Sheet 后 D 键应翻页")
            keyClick(Qt.Key_A)
            tryVerify(function () { return page.pdfView.currentPage === 0 }, 5000,
                      "A 键应回到第 0 页")
            // 菜单朗读：适配器经 Tts.setSentences/setChapter/setCurrentIndex/play 启动会话
            page.readerShell.triggerMenuAction("read")
            tryVerify(function () { return Tts.state === 1 }, 3000,
                      "菜单朗读应启动 TTS 会话，实际 state=" + Tts.state)
            verify(page.readerShell.ttsBar.visible, "朗读中应显示 TtsBar")
            // 手动翻页停止旧会话：朗读中 D 键翻页 → 页变且 TTS 停止、TtsBar 隐藏
            keyClick(Qt.Key_D)
            tryVerify(function () { return page.pdfView.currentPage === 1 }, 5000,
                      "朗读中 D 键应翻到第 1 页，实际 " + page.pdfView.currentPage)
            tryVerify(function () { return Tts.state === 0 }, 3000,
                      "手动翻页应停止 TTS，实际 state=" + Tts.state)
            tryVerify(function () { return !page.readerShell.ttsBar.visible }, 3000,
                      "停止后 TtsBar 应隐藏")
            // 目录跳转停止朗读会话：第 0 页朗读中经目录跳到第 1 页 → TTS 停止
            page.readerShell.triggerMenuAction("read")
            tryVerify(function () { return Tts.state === 1 }, 3000,
                      "第 0 页应可朗读，实际 state=" + Tts.state)
            page.readerShell.triggerMenuAction("toc")
            tryVerify(function () { return page.tocDlg.visible }, 3000,
                      "目录项应打开页码目录")
            var tocList = page.tocDlg.contentItem
            var page2Delegate = tocList.contentItem.children[1]   // 第 2 页条目
            verify(page2Delegate !== undefined, "目录应含第 2 页条目")
            page2Delegate.clicked()
            tryVerify(function () { return page.pdfView.currentPage === 1 }, 5000,
                      "目录跳转应到第 1 页，实际 " + page.pdfView.currentPage)
            tryVerify(function () { return Tts.state === 0 }, 3000,
                      "目录跳转应停止 TTS，实际 state=" + Tts.state)
            // 等目录关闭动画完成（模态弹层退出期间不归还键盘焦点）再按键
            tryVerify(function () { return !page.tocDlg.visible }, 3000,
                      "目录跳转后目录应关闭")
            tryVerify(function () { return page.activeFocus }, 3000,
                      "目录关闭后页面应恢复键盘焦点")
            // 回到第 0 页重新朗读：读完两句 → chapterCompleted → 自动续读下一有文本页
            keyClick(Qt.Key_A)
            tryVerify(function () { return page.pdfView.currentPage === 0 }, 5000,
                      "A 键应回到第 0 页")
            page.readerShell.triggerMenuAction("read")
            tryVerify(function () { return Tts.state === 1 }, 3000,
                      "第 0 页应可重新朗读，实际 state=" + Tts.state)
            // 读完第 0 页两句 → 自动续读第 1 页（有文本）→ 仍在播放
            Tts.next()
            Tts.next()
            tryVerify(function () { return page.pdfView.currentPage === 1 }, 5000,
                      "读完一页应自动续读下一页，实际 " + page.pdfView.currentPage)
            tryVerify(function () { return Tts.state === 1 }, 3000,
                      "续读页应继续播放，实际 state=" + Tts.state)
            // 末页耗尽：读完第 1 页两句 → 无后续文本页 → 停 TTS、不翻页、显示提示
            Tts.next()
            Tts.next()
            tryVerify(function () { return Tts.state === 0 }, 3000,
                      "末页读完应停 TTS，实际 state=" + Tts.state)
            compare(page.pdfView.currentPage, 1, "无后续文本页时不应再翻页")
            tryVerify(function () { return page.ttsExhaustedHint === true }, 3000,
                      "耗尽后应显示无可朗读文本提示")
            verify(!page.readerShell.ttsBar.visible, "停止后 TtsBar 应隐藏")
            // 加载状态变化停止会话：朗读中更换文档源（Loading/Error）→ TTS 停止
            page.readerShell.triggerMenuAction("read")
            tryVerify(function () { return Tts.state === 1 }, 3000,
                      "第 1 页应可朗读，实际 state=" + Tts.state)
            page.book = { id: 999101, title: "文本PDF", path: "/nonexistent/reload.pdf" }
            tryVerify(function () { return Tts.state === 0 }, 3000,
                      "更换文档源应停止 TTS，实际 state=" + Tts.state)
            stack.destroy()
        }
        // 任务4（复审）：三页 文本-图片-文本 PDF——页级自动续读必须跳过无文本页
        //（0 → 2），且中间图片页 canReadAloud=false、原因精确、菜单朗读项 disabled。
        function test_pdfReadAloudSkipsImagePage() {
            Tts.stop()
            Tts.reconfigure("openai", "https://api.openai.com/v1", "", "tts-1", "nova", 1.0)
            var stack = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; StackView { anchors.fill: parent; }", root)
            verify(stack !== null, "测试 StackView 应能创建")
            stack.push("qrc:/qt/qml/Readdict/ui/qml/PdfReaderPage.qml",
                       { book: { id: 999103, title: "图文图PDF", path: TestEnv.textImageTextPdfSource } })
            var page = stack.currentItem
            verify(page !== null, "PdfReaderPage 应被 push 进 StackView")
            var doc = page.pdfDocument
            tryVerify(function () { return doc.status === PdfDocument.Ready }, 15000,
                      "图文图 PDF 应加载为 Ready，实际 " + doc.status)
            compare(doc.pageCount, 3, "图文图 PDF 应为三页")
            tryVerify(function () { return page.readerAdapter.canReadAloud === true }, 3000,
                      "第 0 页有文本应可朗读，实际 " + page.readerAdapter.canReadAloud)
            // 中间图片页：不可朗读 + 精确原因 + 菜单项 disabled
            keyClick(Qt.Key_D)
            tryVerify(function () { return page.pdfView.currentPage === 1 }, 5000,
                      "D 键应到第 1 页（图片页）")
            tryVerify(function () { return page.readerAdapter.canReadAloud === false }, 3000,
                      "图片页不应可朗读，实际 " + page.readerAdapter.canReadAloud)
            compare(page.readerAdapter.readAloudUnavailableReason, "当前 PDF 无可朗读文本",
                    "图片页不可用原因应精确")
            tryVerify(function () { return page.readerShell.menuItem("read").enabled === false },
                      3000, "图片页朗读菜单项应 disabled")
            // 末页恢复可读
            keyClick(Qt.Key_D)
            tryVerify(function () { return page.pdfView.currentPage === 2 }, 5000,
                      "D 键应到第 2 页（末页）")
            tryVerify(function () { return page.readerAdapter.canReadAloud === true }, 3000,
                      "末页有文本应可朗读，实际 " + page.readerAdapter.canReadAloud)
            // 回到第 0 页朗读：读完两句 → 自动续读必须跳过图片页直接到第 2 页
            keyClick(Qt.Key_A)
            keyClick(Qt.Key_A)
            tryVerify(function () { return page.pdfView.currentPage === 0 }, 5000,
                      "A 键应回到第 0 页")
            page.readerShell.triggerMenuAction("read")
            tryVerify(function () { return Tts.state === 1 }, 3000,
                      "第 0 页应可朗读，实际 state=" + Tts.state)
            Tts.next()
            Tts.next()
            tryVerify(function () { return page.pdfView.currentPage === 2 }, 5000,
                      "读完一页应跳过图片页续读第 2 页，实际 " + page.pdfView.currentPage)
            tryVerify(function () { return Tts.state === 1 }, 3000,
                      "跳过续读应继续播放，实际 state=" + Tts.state)
            // 末页耗尽：无后续文本页 → 停 TTS、不翻页、显示提示
            Tts.next()
            Tts.next()
            tryVerify(function () { return Tts.state === 0 }, 3000,
                      "末页读完应停 TTS，实际 state=" + Tts.state)
            compare(page.pdfView.currentPage, 2, "无后续文本页时不应再翻页")
            tryVerify(function () { return page.ttsExhaustedHint === true }, 3000,
                      "耗尽后应显示无可朗读文本提示")
            stack.destroy()
        }
        // 任务4：图片 PDF 朗读禁用——确定性夹具（TestEnv.imagePdfSource，一页仅图片）：
        // canReadAloud=false、原因精确"当前 PDF 无可朗读文本"、朗读菜单项 disabled、
        // Tts 保持 idle、TtsBar 隐藏；triggerMenuAction("read") 不启动 TTS。
        function test_imagePdfDisablesReadAloud() {
            Tts.stop()
            Tts.reconfigure("openai", "https://api.openai.com/v1", "", "tts-1", "nova", 1.0)
            var loader = pdfReaderComp.createObject(root, { width: 800, height: 1000 })
            var page = loader.item
            verify(page !== null, "PdfReaderPage 应能加载")
            page.book = { id: 999102, title: "图片PDF", path: TestEnv.imagePdfSource }
            var doc = page.pdfDocument
            tryVerify(function () { return doc.status === PdfDocument.Ready }, 15000,
                      "图片 PDF 应加载为 Ready，实际 " + doc.status)
            compare(doc.pageCount, 1, "图片 PDF 应为一页")
            tryVerify(function () { return page.readerAdapter.canReadAloud === false }, 3000,
                      "仅图片页不应可朗读，实际 " + page.readerAdapter.canReadAloud)
            compare(page.readerAdapter.readAloudUnavailableReason, "当前 PDF 无可朗读文本",
                    "不可用原因应精确为'当前 PDF 无可朗读文本'")
            tryVerify(function () { return page.readerShell.menuItem("read").enabled === false },
                      3000, "朗读菜单项应 disabled")
            compare(Tts.state, 0, "图片 PDF 不应启动 TTS")
            verify(!page.readerShell.ttsBar.visible, "TtsBar 应隐藏")
            // 禁用朗读的 read 动作不得启动 TTS（壳层 capability 门控）
            page.readerShell.triggerMenuAction("read")
            compare(Tts.state, 0, "禁用朗读的 read 动作不应启动 TTS")
            verify(!page.readerShell.ttsBar.visible, "禁用朗读的 read 动作不应显示 TtsBar")
            // 单页 PDF：上一/下一页均不可用
            verify(page.readerAdapter.canGoPrevious === false, "单页时上一页应禁用")
            verify(page.readerAdapter.canGoNext === false, "单页时下一页应禁用")
            loader.destroy()
        }
    }
    TestCase {
        name: "ReaderShellSmoke"
        // 任务2：独立共享壳层契约——内联假适配器驱动。朗读禁用项必须 disabled 且
        // 带原因、不调 startReadAloud、不启动 TTS、不显示 TtsBar；上/下一项标签
        // 来自适配器（不硬编码"上一章/下一章"）；朗读可用时 triggerMenuAction 仅
        // 调用适配器。暴露 topToolbar/ttsBar/menuOpen/sheetOpen。
        function test_readerShellAdapterContract() {
            Tts.stop()
            var adapter = Qt.createQmlObject('import QtQuick; QtObject {
                property bool canReadAloud: false
                property string readAloudUnavailableReason: ""
                property bool canGoPrevious: true
                property bool canGoNext: true
                property string previousLabel: "上一页"
                property string nextLabel: "下一页"
                property bool supportsContents: true
                property bool supportsSearch: true
                property bool supportsNotes: true
                property bool supportsBookmarks: true
                property string progressText: ""
                property int readCalls: 0
                function startReadAloud() { readCalls += 1 }
                function stopReadAloud() {}
                function previous() {}
                function next() {}
                function openContents() {}
                function openSearch() {}
                function openNotes() {}
                function toggleBookmark() {}
            }', root)
            var loader = readerShellComp.createObject(root)
            var shell = loader.item
            verify(shell !== null, "ReaderShell 应能加载")
            verify(shell.topToolbar !== undefined, "应暴露 topToolbar")
            verify(shell.ttsBar !== undefined, "应暴露 ttsBar")
            verify(shell.menuOpen !== undefined, "应暴露 menuOpen")
            verify(shell.sheetOpen !== undefined, "应暴露 sheetOpen")
            shell.reader = adapter
            adapter.canReadAloud = false
            adapter.readAloudUnavailableReason = "当前 PDF 无可朗读文本"
            shell.openMenu()
            verify(shell.menuOpen, "openMenu() 应打开菜单")
            var readItem = shell.menuItem("read")
            verify(readItem !== null, "menuItem('read') 应存在")
            verify(readItem.enabled === false, "朗读不可用时应禁用 read 菜单项")
            compare(readItem.disabledReason, adapter.readAloudUnavailableReason,
                    "read 菜单项应携带不可用原因")
            verify(Tts.state === 0, "禁用朗读不应启动 TTS")
            verify(!shell.ttsBar.visible, "朗读不可用不应显示 TtsBar")
            // 禁用朗读时 triggerMenuAction("read") 不调用适配器、不启动 TTS
            shell.triggerMenuAction("read")
            compare(adapter.readCalls, 0, "禁用朗读不应调用 startReadAloud")
            verify(Tts.state === 0, "禁用朗读的 read 动作不应启动 TTS")
            // 上/下一项标签来自适配器，而非固定章节文案
            compare(shell.menuItem("prev").text, adapter.previousLabel,
                    "prev 标签应来自适配器 previousLabel")
            compare(shell.menuItem("next").text, adapter.nextLabel,
                    "next 标签应来自适配器 nextLabel")
            verify(shell.menuItem("prev").text !== "上一章",
                   "prev 标签不应硬编码为上一章")
            // 朗读可用时 triggerMenuAction("read") 仅调用适配器
            adapter.canReadAloud = true
            shell.triggerMenuAction("read")
            compare(adapter.readCalls, 1, "朗读可用时应调用一次 startReadAloud")
            // info 项应可点击（enabled 不得为 undefined/假值）
            verify(!!shell.menuItem("info").enabled, "info 菜单项应可点击（enabled）")
            // 上/下一项标签应随适配器动态更新（非一次性快照）
            adapter.previousLabel = "上一节"
            adapter.nextLabel = "下一节"
            compare(shell.menuItem("prev").text, "上一节",
                    "prev 标签应随适配器 previousLabel 动态更新")
            compare(shell.menuItem("next").text, "下一节",
                    "next 标签应随适配器 nextLabel 动态更新")
            adapter.previousLabel = "上一页"
            adapter.nextLabel = "下一页"
            // contentItem 赋值后应延迟恢复焦点（正文持有 activeFocus）
            shell.menuOpen = false
            shell.sheetOpen = false
            var focusTarget = Qt.createQmlObject('import QtQuick; Item {}', root)
            shell.contentItem = focusTarget
            tryVerify(function () { return focusTarget.activeFocus }, 2000,
                      "contentItem 应在赋值后获得 activeFocus")
            // TtsBar：语速持久化到设置、背景随 ttsBgMode
            var prevRate = Settings.value("tts/rate")
            shell.ttsBar.rateChanged(1.25)
            compare(Settings.value("tts/rate"), 1.25, "语速应持久化到设置")
            shell.ttsBgMode = "dark"
            compare(shell.ttsBar.bgMode, "dark", "TtsBar 背景应随 ttsBgMode 更新")
            shell.ttsBgMode = "light"
            Settings.setValue("tts/rate", prevRate === undefined ? 1.0 : prevRate)
            loader.destroy()
            adapter.destroy()
        }
        // 关闭路径与自动隐藏：菜单/sheet 的多种关闭方式 + 超时自动隐藏回退。
        function test_readerShellClosePathsAndAutoHide() {
            Tts.stop()
            var adapter = Qt.createQmlObject('import QtQuick; QtObject {
                property bool canReadAloud: false
                property string readAloudUnavailableReason: ""
                property bool canGoPrevious: true
                property bool canGoNext: true
                property string previousLabel: "上一页"
                property string nextLabel: "下一页"
                function startReadAloud() {}
                function stopReadAloud() {}
                function previous() {}
                function next() {}
            }', root)
            var loader = readerShellComp.createObject(root)
            var shell = loader.item
            shell.reader = adapter
            // 关闭路径：triggerMenuAction 关闭菜单
            shell.openMenu()
            verify(shell.menuOpen, "openMenu() 应打开菜单")
            shell.triggerMenuAction("info")
            verify(!shell.menuOpen, "triggerMenuAction 应关闭菜单")
            // 内容点击：菜单+sheet 同时关闭
            shell.openMenu()
            shell.handleTap(200, 100)
            verify(!shell.menuOpen && !shell.sheetOpen,
                   "内容点击应同时关闭菜单与 sheet")
            // 内容点击：sheet 打开时关闭
            shell.sheetOpen = true
            shell.handleTap(200, 100)
            verify(!shell.sheetOpen, "sheet 打开时内容点击应关闭")
            // 隐藏态内容点击唤出 sheet（ReaderPage 唤出语义）
            shell.handleTap(200, 100)
            verify(shell.sheetOpen, "隐藏态内容点击应唤出 sheet")
            verify(shell.controlsVisible, "唤出应置 controlsVisible")
            // 底部 Sheet 遮罩点击关闭
            shell.bottomSheet.maskClicked()
            verify(!shell.sheetOpen, "sheet 遮罩点击应关闭")
            // 自动隐藏：关闭后计时重启，超时回退隐藏态（controlsVisible=false）
            shell.controlsHideDelay = 100
            shell.sheetOpen = true
            shell.handleTap(200, 100)
            verify(shell.controlsVisible, "关闭后 controlsVisible 应保持")
            wait(300)
            verify(!shell.controlsVisible, "超时后应自动隐藏（controlsVisible=false）")
            loader.destroy()
            adapter.destroy()
        }
    }
    TestCase {
        name: "ShelfSmoke"
        function test_shelfLoads() {
            var loader = shelfComp.createObject(root)
            verify(loader.item !== null, "ShelfPage 应能加载")
            loader.destroy()
        }
    }
    TestCase {
        name: "CardSmoke"
        function test_cardLoads() {
            var loader = cardComp.createObject(root)
            verify(loader.item !== null, "BookCard 应能加载（含右键菜单与分类 Dialog 编译检查）")
            loader.item.book = { id: 1, title: "测试书", cover: "", progress: 0.5 }
            loader.destroy()
        }
    }
    TestCase {
        name: "DeleteSmoke"
        // B1：删除书籍冒烟——requestDelete 打开确认对话框 → 勾选删文件 accept →
        // 书从 booksModel 消失、书库文件被删、共享占位封面保留。
        // 专属书源（delme.txt）由 TestEnv 生成，删它不影响共享的 zeta/alpha/mike。
        // U6：跨用例搜索/筛选残留复位（同 tst_readerpage/tst_shelf 约定）——
        // 本文件 FulltextSmoke 的顶部搜索残留会把 booksModel 过滤为空，
        // 不复位则 delme 导入成功后 findDeleteBook 仍找不到（全量套件失败源）。
        function initTestCase() {
            Books.doSearch("")
            Books.setFilter("")
            Books.setSort(0)
        }
        function findDeleteBook() {
            for (let b of Books.booksModel)
                if (b.title === "delme") return b
            return null
        }
        function test_deleteDialogRemovesBookAndFiles() {
            Importer.doImport(TestEnv.deleteSource)
            tryVerify(function () { return findDeleteBook() !== null }, 3000, "delme 书应导入")
            var book = findDeleteBook()
            var path = book.path
            var cover = book.cover
            verify(TestEnv.fileExists(path), "导入的书文件应在书库")
            verify(cover.length > 0, "TXT 导入应生成占位封面")

            // 对话框是 Popup，需真实 Window 才能打开；Loader 必须创建在 Window 内
            var win = Qt.createQmlObject('import QtQuick; Window { width: 800; height: 600; visible: true }', root)
            verify(win !== null, "测试 Window 应能创建")
            var loader = cardComp.createObject(win)
            var card = loader.item
            verify(card !== null, "BookCard 应能加载")
            card.book = book
            wait(50)

            card.requestDelete()
            tryVerify(function () { return card.deleteDialog.opened === true }, 2000,
                      "requestDelete 应打开确认对话框")
            compare(card.deleteFilesCheck.checked, false, "默认不勾选删文件（防误触）")
            verify((card.deleteDialog.title || "").indexOf("delme") >= 0,
                   "对话框标题应含书名，实际 " + card.deleteDialog.title)
            verify((card.deleteWarning.text || "").length > 0, "应有警告文案")

            card.deleteFilesCheck.checked = true
            card.deleteDialog.accept()
            wait(100)
            verify(card.deleteDialog.opened === false, "accept 后对话框应关闭")
            tryVerify(function () { return findDeleteBook() === null }, 3000, "书应从 booksModel 消失")
            verify(!TestEnv.fileExists(path), "书库文件应被删除")
            verify(TestEnv.fileExists(cover), "共享占位封面应保留（不随单本删除）")
            win.destroy()
        }
    }
    TestCase {
        name: "FulltextSmoke"
        function initTestCase() {
            Books.doSearch("")
            Books.setFilter("")
            Books.setSort(0)
            var hasSourceBook = false
            for (let b of Books.booksModel)
                if (b.title === "zeta") { hasSourceBook = true; break }
            if (!hasSourceBook) Importer.doImport(TestEnv.sourceFiles[0])
        }
        function test_shelfFulltextHits() {
            var loader = mainComp.createObject(root)
            loader.width = root.width
            loader.height = root.height
            var win = loader.item
            verify(win !== null, "Main.qml 应能加载")
            tryVerify(function () { return win.navStack.currentItem !== null }, 3000,
                      "Main 初始页应加载")
            win.navigateTo("shelf")
            tryVerify(function () {
                return win.navStack.currentItem && win.navStack.currentItem.navId === "shelf"
            }, 3000, "Main 应能导航到书架")
            var shelf = win.navStack.currentItem
            shelf.filterSheet.scopeList.currentIndex = 1 // 全文范围
            win.topSearchBar.text = "第二行内容"
            tryVerify(function () { return shelf.fulltextList.model.length > 0 }, 5000,
                      "Main 顶部搜索应驱动全文命中，实际 " + shelf.fulltextList.model.length)
            var hit = shelf.fulltextList.model[0]
            verify(Number(hit.bookId) > 0, "命中应带 bookId")
            verify((hit.snippet || "").length > 0, "命中应带 snippet，实际 " + hit.snippet)
            shelf.filterSheet.scopeList.currentIndex = 0
            verify(shelf.fulltextList.visible === false, "切回元数据后全文结果列表应隐藏")
            // U6：还原顶部搜索——text 驱动 Books.doSearch，不还原会把 booksModel
            // 过滤为空，污染同文件后序 DeleteSmoke 与后续 tst_nav 的书目查找
            win.topSearchBar.text = ""
            win.visible = false
            loader.destroy()
        }
    }
    TestCase {
        name: "ReaderSmoke"
        function test_readerLoads() {
            var loader = readerComp.createObject(root)
            verify(loader.item !== null, "ReaderPage 应能加载（含控制栏/目录 Dialog 编译检查）")
            loader.destroy()
        }
        // 本文件在 tst_e2e.qml 之后执行（文件名字典序），此时书库已有导入的 TXT 书；
        // B10 新增的 EPUB/长文本书导入会改变 booksModel 首位，故按 format 显式找 TXT
        function test_loadChapter() {
            var book = null
            for (let b of Books.booksModel)
                if ((b.format || "").toUpperCase() === "TXT") { book = b; break }
            if (!book)
                skip("书库无 TXT 书，跳过章节加载验证")
            var loader = readerComp.createObject(root)
            var page = loader.item
            verify(page !== null, "ReaderPage 应能加载")
            page.book = book
            page.loadChapter(0)
            verify(page.chapter !== null && page.chapter.paragraphs !== undefined,
                   "loadChapter 应返回带 paragraphs 的章节对象")
            verify(page.chapter.paragraphs.length > 0, "TXT 首章应有段落")
            compare(page.chapter.title, page.book.title, "TXT 首章标题应为书名")
            // C5：打开书应把拍平的句子喂给 Tts（游标复位首句）
            compare(Tts.currentIndex, 0, "打开书后朗读游标应复位到 0")
            // D2：未朗读（loadChapter 已 Tts.stop() → state=0）游标 0 落在首段但**不黄标**
            wait(50)
            var t0 = page.contentView.paragraphRepeater.itemAt(0).children[0].text
            verify(t0.toLowerCase().indexOf("#ffd54f") < 0,
                   "未朗读时首句不应黄标（D2），实际 " + t0)
            // 朗读会话激活（openai 无 key 桩：play 只驱动 state 0→1 不发声）→ 首句黄标恢复
            Tts.reconfigure("openai", "https://api.openai.com/v1", "", "tts-1", "nova", 1.0)
            Tts.play()
            tryVerify(function () {
                return page.contentView.paragraphRepeater.itemAt(0).children[0].text.toLowerCase()
                       .indexOf("#ffd54f") >= 0
            }, 3000, "朗读会话激活后首句应恢复黄标")
            loader.destroy()
        }
    }
    TestCase {
        name: "ReaderPageSmoke"
        // 任务3：文本阅读页接入共享壳层——ReaderPage 必须暴露 readerShell，且顶栏/
        // TtsBar/底部 Sheet 为 ReaderShell 的同一对象（不得保留双份壳层）；菜单朗读
        // 经适配器 startReadAloud 启动 TTS 会话；上一/下一章经适配器 previous()/next()
        // 推进章节（不直接调 loadChapter，壳层只经统一适配器契约调用）。
        function initTestCase() {
            Books.doSearch("")
            Books.setFilter("")
            Books.setSort(0)
            if (!findBook("multibook")) Importer.doImport(TestEnv.multiSource)
        }
        function cleanupTestCase() {
            // 同 tst_e4_keys 约定：清理本用例导入的多章书，避免污染后续用例
            //（tst_highlightsui 的 findTxtBook() 取最新 TXT 会拿到它）
            for (let b of Books.booksModel)
                if (b.title === "multibook")
                    Books.removeBookWithFiles(b.id, true)
        }
        function findBook(title) {
            for (let b of Books.booksModel)
                if (b.title === title) return b
            return null
        }
        function test_readerUsesSharedShell() {
            var book = findBook("multibook")
            verify(book !== null, "multibook 应已导入")
            Tts.stop()
            Tts.reconfigure("openai", "https://api.openai.com/v1", "", "tts-1", "nova", 1.0)
            var stack = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; StackView { anchors.fill: parent; }", root)
            verify(stack !== null, "测试 StackView 应能创建")
            stack.push("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: book })
            var page = stack.currentItem
            verify(page !== null, "ReaderPage 应被 push 进 StackView")
            tryVerify(function () {
                return page.chapter && page.chapter.paragraphs
                    && page.chapter.paragraphs.length > 0
            }, 3000, "打开书后应加载章节段落")
            Books.currentChapter = 0
            page.loadChapter(0)
            // 共享壳层：readerShell 暴露且顶栏为同一对象（无重复顶栏/朗读条/Sheet）
            verify(page.readerShell !== undefined, "ReaderPage 应暴露 readerShell")
            verify(page.readerShell.topToolbar === page.topToolbar,
                   "顶栏应为 ReaderShell 同一对象")
            verify(page.readerShell.ttsBar === page.ttsBar,
                   "TtsBar 应为 ReaderShell 同一对象")
            verify(page.readerShell.bottomSheet === page.bottomSheet,
                   "底部 Sheet 应为 ReaderShell 同一对象")
            // 菜单朗读：经适配器 startReadAloud → TTS 会话激活（state=1）
            page.readerShell.triggerMenuAction("read")
            tryVerify(function () { return Tts.state === 1 }, 3000,
                      "菜单朗读应经适配器启动 TTS 会话，实际 state=" + Tts.state)
            Tts.stop()
            // 下一章：经适配器 next() 推进（Books.currentChapter 0→1）
            page.readerShell.triggerMenuAction("next")
            tryVerify(function () { return Books.currentChapter === 1 }, 3000,
                      "菜单下一章应经适配器推进到第 1 章，实际 " + Books.currentChapter)
            // 上一章：经适配器 previous() 回退（1→0）
            page.readerShell.triggerMenuAction("prev")
            tryVerify(function () { return Books.currentChapter === 0 }, 3000,
                      "菜单上一章应经适配器回到第 0 章，实际 " + Books.currentChapter)
            stack.destroy()
        }
    }
    TestCase {
        name: "ContentSmoke"
        // 直接实例化 ReaderContent：运行期验证段落委托（Text 与图片分支）不报错、
        // 排版参数生效、内容高度随段落增长
        function test_rendersParagraphs() {
            var loader = contentComp.createObject(root)
            loader.width = 800
            loader.height = 600
            var c = loader.item
            verify(c !== null, "ReaderContent 应能加载")
            c.typography = { fontFamily: "Source Han Sans VF", fontSize: 18, lineHeight: 1.6,
                             align: "left", pageWidth: "normal" }
            c.chapter = { title: "测试章", paragraphs: [
                { text: "正文段", html: "<p>正文段</p>", level: 0, imagePath: "" },
                { text: "", html: "", level: 0, imagePath: "/nonexistent/b8.png" },
                { text: "前文 图 后文", html: "<p>前文 <img src=\"/nonexistent/b8.png\"> 后文</p>", level: 0, imagePath: "/nonexistent/b8.png" },
                { text: "标题", html: "<h2>标题</h2>", level: 2, imagePath: "" }
            ]}
            wait(50)
            // Flickable 会把声明子项重挂到 contentItem；Repeater 在 positioner（Column）内
            // 又会把委托重挂到 Column，故 col.children[0..3] 依次是 4 个段落委托
            var col = c.contentItem.children[0]        // Column
            var dPure = col.children[1]                // 纯图段委托
            var dMixed = col.children[2]               // 混合段委托
            verify(dPure !== undefined && dPure.pureImage === true,
                   "纯图段应走 Image 分支（pureImage=true）")
            verify(dMixed !== undefined && dMixed.pureImage === false,
                   "混合段应走 Text 分支（html 含 img 之外的正文）")
            var mixedTxt = dMixed.children[0]          // 委托内 Text
            verify(mixedTxt.text.indexOf("前文") >= 0 && mixedTxt.text.indexOf("<img") >= 0
                   && mixedTxt.text.indexOf("file://") >= 0,
                   "混合段 Text 应保留正文、行内图且 src 补 file://，实际 " + mixedTxt.text)
            // 隐式高度依赖布局 polish，轮询等待而非一次性 wait
            tryVerify(function () { return c.contentHeight > 0 }, 2000,
                      "内容高度应随段落增长，实际 " + c.contentHeight)
            // 页宽三档 + 对齐切换应无运行时错误且宽度变化生效
            c.typography = { fontFamily: "Source Han Sans VF", fontSize: 20, lineHeight: 1.8,
                             align: "center", pageWidth: "wide" }
            tryVerify(function () { return c.contentHeight > 0 }, 2000,
                      "切换排版后内容高度仍应大于 0")
            loader.destroy()
        }
    }
    TestCase {
        name: "ToolbarSmoke"
        function test_toolbarShapeAndSignals() {
            var loader = controlsComp.createObject(root)
            var toolbar = loader.item
            verify(toolbar !== null, "KdTopToolbar 应能加载")
            compare(toolbar.height, 40, "Kindle 顶栏应为 40px")
            verify(toolbar.backBtn !== undefined && toolbar.menuBtn !== undefined,
                   "顶栏应暴露返回/菜单句柄")
            var got = []
            toolbar.back.connect(function () { got.push("back") })
            toolbar.notes.connect(function () { got.push("notes") })
            toolbar.bookmark.connect(function () { got.push("bookmark") })
            toolbar.search.connect(function () { got.push("search") })
            toolbar.menu.connect(function () { got.push("menu") })
            var row = toolbar.children[1]
            verify(row !== undefined && row.children.length === 5, "顶栏应有 5 项按钮")
            for (var i = 0; i < row.children.length; ++i)
                row.children[i].clicked()
            compare(got.join(","), "back,notes,bookmark,search,menu",
                    "五个按钮应按返回、笔记、书签、搜索、更多顺序发出操作")
            toolbar.bookmarked = true
            verify(row.children[2].contentItem.name === "bookmarkFill", "已收藏态应使用实心书签")
            toolbar.bookmarked = false
            verify(row.children[2].contentItem.name === "bookmark", "未收藏态应使用空心书签")
            toolbar.width = 240
            tryVerify(function () { return toolbar.backBtn.width >= 44 }, 2000,
                      "窄宽度下返回按钮仍应保留 44px 命中区")
            verify(!toolbar.backBtn.contentItem.children[0].children[1].visible,
                   "窄宽度下书库文字应隐藏而非压缩按钮命中区")
            loader.destroy()
        }
    }
    TestCase {
        // 顶栏书签按钮保持独立动作；字体控制仅位于底部 Sheet。
        function test_toolbarBookmarkButton() {
            var loader = controlsComp.createObject(root)
            var toolbar = loader.item
            verify(toolbar !== null, "KdTopToolbar 应能加载")
            var got = 0
            toolbar.bookmark.connect(function () { ++got })
            toolbar.children[1].children[2].clicked()
            compare(got, 1, "书签按钮应发 bookmark 信号")
            toolbar.bookmarked = true
            verify(toolbar.children[1].children[2].contentItem.name === "bookmarkFill",
                   "书签信号后可由宿主切换实心图标")
            loader.destroy()
        }
        // 阅读页内切换 4 字体即时生效：写 Settings → 重组合 typography → 正文 font.family
        function test_readerFontSwitchApplies() {
            var book = null
            for (let b of Books.booksModel)
                if ((b.format || "").toUpperCase() === "TXT") { book = b; break }
            if (!book) skip("书库无 TXT 书，跳过阅读页字体切换验证")
            var loader = readerComp.createObject(root)
            var page = loader.item
            verify(page !== null, "ReaderPage 应能加载")
            page.book = book
            page.loadChapter(0)
            tryVerify(function () { return page.contentView.paragraphRepeater.itemAt(0) !== null }, 3000,
                      "首段应渲染完成")
            page.sheetTab = "font"
            page.sheetOpen = true
            var panel = page.bottomSheet.contentLoader.item
            tryVerify(function () { return panel && panel.objectName === "fontSheetPanel" }, 3000,
                      "Sheet 应加载字体面板")
            var tokens = ["思源宋体 VF", "思源黑体 VF", "SourceHanSansHW-VF", "得意黑"]
            for (var i = 0; i < tokens.length; ++i) {
                tryVerify(function () { return panel.fontItems.itemAt(i) !== null }, 2000,
                          "字体项应就绪")
                panel.setFontFamily(tokens[i])
                compare(String(Settings.value("typography/fontFamily")), tokens[i],
                        "选择后 typography/fontFamily 应写入 token（第 " + i + " 项）")
                compare(page.typography.fontFamily, Books.resolveFontFamily(tokens[i]),
                        "正文应使用选中的字族（第 " + i + " 项）")
            }
            Settings.setValue("typography/fontFamily", "思源宋体 VF")
            loader.destroy()
        }
        // D4：设置页外观卡字体项已移除（避免与阅读界面双入口）；
        // U5：设置页卡片分组 → 全屏列表——首行为深色模式（KdToggle 开关行），无字体行
        function test_settingsPageNoFontEntry() {
            var loader = settingsComp.createObject(root)
            var page = loader.item
            verify(page !== null, "SettingsPage 应能加载")
            verify(page.fontBox === undefined, "设置页不应再暴露字体下拉句柄（已移入阅读界面）")
            // U5 全屏列表：children[0]=深色模式行（KdListItem），其后语言/TTS/背景/
            // 刷新封面/同步/统计 + 版本标签（共 7 行 + 1 标签）
            var layout = page.settingsLayout
            var first = layout.children[0]
            verify(first !== undefined, "首行应存在")
            compare(first.text, "深色模式", "首行应为深色模式（KdListItem）")
            compare(first.textLabel.font.pixelSize, 15, "列表项文字应为 fsListItem 15px（Kindle §7）")
            verify(first.chevronIcon !== undefined && !first.chevronIcon.visible,
                   "开关行（内嵌三态 radio）不应显示 chevron")
            verify(page.themeModeGrid !== undefined, "设置页应暴露深色三态 radio 网格句柄")
            compare(layout.children.length, 8,
                    "列表应为 7 行 + 版本标签（无字体行），实际 " + layout.children.length)
            loader.destroy()
        }
    }
    TestCase {
        name: "ReaderRestore"
        // B10：进度恢复与阅读计时端到端冒烟——真实 ReaderPage 组件生命周期
        // （onCompleted 恢复章节/滚动/计时，onDestruction 保存滚动/结算计时）。
        // 多章节 EPUB fixture（sample.epub，2 章）验证章节恢复；长文本书验证滚动恢复。
        function initTestCase() {
            // 本组断言连续滚动高度与锚点；显式复位，不能依赖其它测试的 Settings 残留。
            Settings.setValue("reading/pageMode", "scroll")
            if (TestEnv.epubFixture.length > 0)
                Importer.doImport(TestEnv.epubFixture)
            if (TestEnv.longSource.length > 0)
                Importer.doImport(TestEnv.longSource)
            if (TestEnv.multiSource.length > 0)
                Importer.doImport(TestEnv.multiSource) // 规格 §7：章末自动续章冒烟书
        }
        function findBook(fmt, titlePart) {
            for (let b of Books.booksModel)
                if ((b.format || "").toUpperCase() === fmt && (titlePart === "" || b.title.indexOf(titlePart) >= 0))
                    return b
            return null
        }
        // 打开阅读页（模拟生产 StackView.push(…, {book})）：setSource 初始属性在
        // onCompleted 前应用，保证章节加载/滚动恢复/计时都在 book 就绪后执行。
        // 任务3 审查回归修复：ReaderPage 的锚定布局在无头测试环境高度不可靠
        //（同 test_scrollAutoNextSignal 注释）——Loader 不设尺寸则 ReaderPage 为
        // 0×0，正文列宽公式收敛到 0，scroll 模式 contentHeight（=列隐式高）塌陷为
        // 0，恢复/搜索跳转断言全部失效。显式给 Loader 真实视口（800×600，同
        // ContentSmoke/test_scrollAutoNextSignal 约定），恢复/跳转才有真实内容高度。
        function openReader(book) {
            var loader = readerComp.createObject(root)
            loader.width = 800
            loader.height = 600
            loader.setSource("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: book })
            var page = loader.item
            verify(page !== null, "ReaderPage 应能加载")
            return loader
        }
        function test_chapterRestore() {
            var book = findBook("EPUB", "")
            if (!book) skip("未导入 EPUB fixture")
            // 打开 → 翻到第 2 章 → 销毁（模拟退出）→ 重开应恢复到第 2 章
            var loader = openReader(book)
            var page = loader.item
            tryVerify(function () { return page.chapter.paragraphs && page.chapter.paragraphs.length > 0 }, 5000,
                      "打开应加载章节")
            page.loadChapter(1)
            compare(page.chapter.title, "第二章", "翻到第二章")
            loader.destroy()
            wait(100) // QML destroy() 延迟到事件循环：等 onDestruction 的保存先落地
            var loader2 = openReader(book)
            var page2 = loader2.item
            tryVerify(function () { return page2.chapter.paragraphs && page2.chapter.paragraphs.length > 0 }, 5000,
                      "重开应加载章节")
            compare(page2.chapter.title, "第二章", "重开应恢复到第二章")
            loader2.destroy()
        }
        // L6（P1#13）：书架进度百分比联动——进度由 reportProgress 上报（前进才刷新）；
        // loadChapter 不再直接写 books.progress（阅读页加载成功后显式上报），回翻不回退
        function test_progressPercent() {
            var book = findBook("EPUB", "")
            if (!book) skip("未导入 EPUB fixture")
            Books.reportProgress(book.id, 2, Books.chapterCount(book.id))
            var cur = findBook("EPUB", "")
            verify(cur !== null && Math.abs(cur.progress - 1.0) < 0.01,
                   "第 2 章 / 共 2 章 进度应为 1.0，实际 " + (cur ? cur.progress : "?"))
            Books.loadChapter(book.id, 0)
            cur = findBook("EPUB", "")
            verify(cur !== null && Math.abs(cur.progress - 1.0) < 0.01,
                   "loadChapter 不再改进度，回翻应保持 1.0 不回退，实际 " + (cur ? cur.progress : "?"))
        }
        function test_scrollRestore() {
            var book = findBook("TXT", "longbook")
            if (!book) skip("未导入长文本书")
            var loader = openReader(book)
            var page = loader.item
            // 任务3 审查回归：阅读页必须有真实视口——无头环境 Loader 不设尺寸时
            // ReaderPage 为 0×0，正文列宽收敛为 0、contentHeight 塌陷（历史回归源）
            verify(page.contentView.width > 100, "阅读页应有真实视口宽度，实际 " + page.contentView.width)
            tryVerify(function () { return page.contentView.contentHeight > 2000 }, 5000,
                      "长文本书内容高度应远大于视口")
            page.contentView.contentY = 400
            // 恢复应用走 200ms 高度收敛定时器：先耗尽窗口（避免其覆盖手动滚动），
            // 再重设并读取实际生效值——保证 onDestruction 保存的是 400
            wait(350)
            page.contentView.contentY = 400
            var savedY = page.contentView.contentY
            verify(savedY > 300, "滚动值应生效，实际 " + savedY)
            loader.destroy() // onDestruction 保存 scroll_<bookId>
            wait(100) // 等延迟销毁完成、滚动位置写入 settings.json
            var loader2 = openReader(book)
            var page2 = loader2.item
            tryVerify(function () {
                return Math.abs(page2.contentView.contentY - savedY) < 1
            }, 5000, "重开应恢复到保存的滚动位置 " + savedY + "，实际 " + page2.contentView.contentY)
            loader2.destroy()
        }
        // BUG3：连续阅读持久化稳定段落锚点。复开后段落相对视口的偏移必须保持，
        // 不能仅落到同一段落顶部（否则用户会感到跳动）。
        function test_scrollAnchorRestoreKeepsRelativeOffset() {
            var book = findBook("TXT", "longbook")
            if (!book) skip("未导入长文本书")
            Settings.removeValue("progress/anchor_" + book.id)
            var loader = openReader(book)
            var page = loader.item
            tryVerify(function () { return page.contentView.contentHeight > 2000 }, 5000,
                      "长文本书内容高度应就绪")
            // 先耗尽本次打开由旧滚动位置触发的恢复计时器；随后才模拟用户主动滚动。
            // 否则初始恢复会覆盖 700，测试保存的是错误的顶端锚点。
            wait(350)
            page.contentView.contentY = 700
            wait(100)
            var saved = page.contentView.scrollAnchor()
            verify(saved !== null && saved.offsetY > 0,
                   "保存时应取得含正偏移的稳定段落锚点")
            loader.destroy()
            wait(100)
            var loader2 = openReader(book)
            var page2 = loader2.item
            tryVerify(function () {
                var restored = page2.contentView.scrollAnchor()
                return restored !== null
                    && restored.chapterIndex === saved.chapterIndex
                    && restored.paragraphIndex === saved.paragraphIndex
                    && Math.abs(restored.offsetY - saved.offsetY) < 2
            }, 5000, "重开后应恢复到同一段落与相对偏移")
            loader2.destroy()
        }
        // 规格 §7：章末自动续章——滚动接近底部触发 requestNextChapter（ReaderContent 信号层）。
        // 独立实例化 ReaderContent 并显式设置宽高（HighlightSmoke 同模式；ReaderPage 的锚定
        // 布局在无头测试环境高度不可靠），避免环境布局差异。覆盖：顶部不触发、距底阈值内
        // 触发、同章去重、maxY<=阈值（短章）不触发、阈值带精确。
        function test_scrollAutoNextSignal() {
            var loader = contentComp.createObject(root)
            loader.width = 800
            loader.height = 600
            var c = loader.item
            c.typography = { fontFamily: "Source Han Sans VF", fontSize: 18, lineHeight: 1.6,
                             align: "left", pageWidth: "normal" }
            var paras = []
            for (var i = 0; i < 80; i++)
                paras.push({ text: "第" + i + "段第一句。",
                             html: "第" + i + "段第一句。",
                             level: 0, imagePath: "",
                             sentences: ["第" + i + "段第一句。"] })
            c.chapter = { title: "章", paragraphs: paras }
            tryVerify(function () { return c.contentHeight > c.height + 400 }, 5000,
                      "内容高度应远大于视口，实际 " + c.contentHeight)
            var fires = 0
            c.requestNextChapter.connect(function () { fires++ })
            // 顶部（contentY=0）不触发
            c.contentY = 0
            wait(100)
            compare(fires, 0, "顶部滚动不应触发 requestNextChapter")
            // BUG5：距底 50px 仍有内容未展示，不应提前换章；只有真实底边界才触发。
            c.contentY = Math.max(0, c.contentHeight - c.height - 50)
            wait(100)
            compare(fires, 0, "距底 50px 尚未到边界，不应触发")
            c.contentY = 10
            wait(50)
            c.contentY = Math.max(0, c.contentHeight - c.height)
            tryVerify(function () { return fires >= 1 }, 3000,
                      "滚动到真实底边界应触发 requestNextChapter，实际 " + fires)
            compare(fires, 1, "同一章内 requestNextChapter 应只触发一次")
            // 短章语义：maxY<=0 时停在顶部不触发。
            c.nextChapterRequested = false
            c.autoNextThreshold = 10000
            c.contentY = 0
            wait(100)
            compare(fires, 1, "短章顶部不应触发")
            loader.destroy()
        }

        // 规格 §7 门控：TTS 朗读会话活动（播放 state==1 或暂停 state==2）期间滚动触底
        // 不触发自动续章——暂停会话若被滚动换章打断，loadChapter 的 Tts.stop() 会丢弃
        // 暂停进度且不续读；停止（state==0）后滚动续章恢复。
        function test_scrollAutoNextTtsPauseGate() {
            var loader = contentComp.createObject(root)
            loader.width = 800
            loader.height = 600
            var c = loader.item
            c.typography = { fontFamily: "Source Han Sans VF", fontSize: 18, lineHeight: 1.6,
                             align: "left", pageWidth: "normal" }
            var paras = []
            for (var i = 0; i < 80; i++)
                paras.push({ text: "第" + i + "段第一句。",
                             html: "第" + i + "段第一句。",
                             level: 0, imagePath: "",
                             sentences: ["第" + i + "段第一句。"] })
            c.chapter = { title: "章", paragraphs: paras }
            tryVerify(function () { return c.contentHeight > c.height + 400 }, 5000,
                      "内容高度应远大于视口，实际 " + c.contentHeight)
            var fires = 0
            c.requestNextChapter.connect(function () { fires++ })
            // TTS 暂停（state==2）：滚动触底不触发（暂停会话不应被丢弃）
            Tts.pause()
            c.contentY = Math.max(0, c.contentHeight - c.height)
            wait(150)
            compare(fires, 0, "TTS 暂停中滚动触底不应触发 requestNextChapter")
            // TTS 停止（state==0）：滚动续章恢复；必须到真实底边界。
            Tts.stop()
            c.contentY = 10
            wait(50)
            c.contentY = Math.max(0, c.contentHeight - c.height)
            tryVerify(function () { return fires >= 1 }, 3000,
                      "TTS 停止后滚动触底应触发 requestNextChapter")
            loader.destroy()
        }

        // 规格 §7 门控：程序化/动画滚动（搜索跳转 scrollToParagraph、朗读跟随
        // followSentence）不触发自动续章——目标在底部阈值带内时动画中途换章会毁掉
        // 跳转上下文。动画结束停在章末也不触发（无用户滚动）；随后用户手动滚动才触发。
        function test_scrollAutoNextProgrammaticScroll() {
            var loader = contentComp.createObject(root)
            loader.width = 800
            loader.height = 600
            var c = loader.item
            c.typography = { fontFamily: "Source Han Sans VF", fontSize: 18, lineHeight: 1.6,
                             align: "left", pageWidth: "normal" }
            var paras = []
            for (var i = 0; i < 80; i++)
                paras.push({ text: "第" + i + "段第一句。",
                             html: "第" + i + "段第一句。",
                             level: 0, imagePath: "",
                             sentences: ["第" + i + "段第一句。"] })
            c.chapter = { title: "章", paragraphs: paras }
            tryVerify(function () { return c.contentHeight > c.height + 400 }, 5000,
                      "内容高度应远大于视口，实际 " + c.contentHeight)
            var fires = 0
            c.requestNextChapter.connect(function () { fires++ })
            // 朗读跟随动画滚向章末（末段目标被钳制在 maxY 阈值带内）：
            // 动画进行中（contentY 途经阈值带）与结束后（停在带内）都不触发
            c.followSentence(79)
            wait(600) // 动画 320ms + 余量，期间每帧 contentY 变化都会进 checkAutoNext
            compare(fires, 0, "动画滚动到章末不应触发 requestNextChapter")
            // 用户手动滚动（先上移再回到底部）→ 触发；真实底边界前不换章。
            c.contentY = Math.max(0, c.contentHeight - c.height - 100)
            wait(50)
            c.contentY = Math.max(0, c.contentHeight - c.height)
            tryVerify(function () { return fires >= 1 }, 3000,
                      "用户手动滚动到章末应触发 requestNextChapter")
            loader.destroy()
        }
        // onRequestNextChapter 绑定调用 autoNextChapter 换章（断绑则滚动续章静默失效）。
        // 直接 emit 信号（QML 信号可作方法调用）锁定该一行绑定，不依赖无头环境的锚定布局。
        function test_scrollAutoNextBinding() {
            var book = findBook("TXT", "multibook")
            if (!book) skip("未导入多章节长书")
            var loader = openReader(book)
            var page = loader.item
            tryVerify(function () { return page.chapter.paragraphs && page.chapter.paragraphs.length > 0 }, 5000,
                      "打开应加载章节")
            page.loadChapter(0) // 显式定位首章（此前测试可能已保存其他章节）
            tryVerify(function () { return page.chapter.paragraphs.length === 100 }, 5000,
                      "首章应加载 100 段")
            compare(Books.currentChapter, 0, "初始应在第 1 章")
            page.contentView.requestNextChapter()
            tryVerify(function () { return Books.currentChapter === 1 }, 3000,
                      "requestNextChapter 应经绑定触发 autoNextChapter 换章，实际 " + Books.currentChapter)
            compare(page.chapter.title, "第二章")
            loader.destroy()
        }

        // 规格 §7：ReaderPage 接线层——autoNextChapter / continueReadingFromTts 的换章逻辑
        //（非末章换下一章、末章不再自动、换章后 Tts 游标复位并继续朗读）。
        // 滚动信号→autoNextChapter 的 QML 绑定由 test_scrollAutoNextSignal（信号侧）与
        // 本用例（处理侧）共同锁定；chapterCompleted→continueReadingFromTts 的绑定由
        // test_ttsChapterCompletedAutoNext 锁定。
        function test_autoNextPageWiring() {
            var book = findBook("TXT", "multibook")
            if (!book) skip("未导入多章节长书")
            var loader = openReader(book)
            var page = loader.item
            tryVerify(function () { return page.chapter.paragraphs && page.chapter.paragraphs.length > 0 }, 5000,
                      "打开应加载章节")
            page.loadChapter(0) // 显式定位首章（本用例即后续用例的 saved 章节基准）
            tryVerify(function () { return page.chapter.paragraphs.length === 100 }, 5000,
                      "首章应加载 100 段")
            // 滚动续章入口：非末章 → 换下一章
            page.autoNextChapter()
            compare(Books.currentChapter, 1, "autoNextChapter 应换到下一章")
            compare(page.chapter.title, "第二章")
            // 末章：不再自动（停在末章，不被 loadChapter 钳制拽回开头）
            page.loadChapter(2)
            page.autoNextChapter()
            compare(Books.currentChapter, 2, "末章滚动不应再换章")
            compare(page.chapter.title, "第三章")
            // 朗读续章入口：非末章 → 换章并继续朗读（无引擎桩下 play() 以 errorOccurred 体现）
            var errors = []
            var errHandler = function (m) { errors.push(m) }
            Tts.errorOccurred.connect(errHandler)
            page.loadChapter(0)
            Tts.setSentences(["仅此一句"])
            Tts.setChapter(0)
            page.continueReadingFromTts(0)
            compare(Books.currentChapter, 1, "continueReadingFromTts 应换到下一章")
            compare(Tts.chapter, 1, "Tts 章节应同步")
            compare(Tts.currentIndex, 0, "新章游标应复位到首句")
            verify(errors.length > 0, "continueReadingFromTts 应调用 Tts.play()")
            Tts.errorOccurred.disconnect(errHandler)
            // 末章朗读结束：不再自动
            page.loadChapter(2)
            Tts.setSentences(["仅此一句"])
            Tts.setChapter(2)
            var before = errors.length
            page.continueReadingFromTts(2)
            compare(Books.currentChapter, 2, "末章朗读结束不应再换章")
            compare(errors.length, before, "末章不应调用 Tts.play()")
            loader.destroy()
        }

        // 规格 §7：Tts.chapterCompleted → 自动 loadChapter(next) 并继续朗读；
        // 末章朗读结束不再自动（无下一章）。
        function test_ttsChapterCompletedAutoNext() {
            var book = findBook("TXT", "multibook")
            if (!book) skip("未导入多章节长书")
            var loader = openReader(book)
            var page = loader.item
            tryVerify(function () { return page.chapter.paragraphs && page.chapter.paragraphs.length > 0 }, 5000,
                      "打开应加载章节")
            page.loadChapter(0)
            // 强制单句章：Tts.next() 一次即越过章末 → chapterCompleted(0)
            Tts.setSentences(["仅此一句"])
            Tts.setChapter(0)
            var errors = []
            var errHandler = function (m) { errors.push(m) }
            Tts.errorOccurred.connect(errHandler)
            Tts.next()
            tryVerify(function () { return Books.currentChapter === 1 }, 3000,
                      "朗读到章末应自动加载下一章，实际 " + Books.currentChapter)
            compare(page.chapter.title, "第二章")
            compare(Tts.chapter, 1, "Tts 章节应同步到新章")
            compare(Tts.currentIndex, 0, "新章句子应已装载且游标复位")
            // Tts 桩无引擎：play() 的唯一可观测效果是 errorOccurred——证明自动续读
            // 调用了 Tts.play()（真实引擎下为发声继续）
            verify(errors.length > 0, "自动续读应调用 Tts.play()，实际错误 " + errors.join(";"))
            Tts.errorOccurred.disconnect(errHandler)
            loader.destroy()
        }

        // C8：书内搜索跳转——搜索 Dialog 可打开；jumpToChapterParagraph 应滚动到
        // 视口下方的目标段（长文本书 300 段，contentY 远大于 0）。
        // 注：test_scrollRestore 已保存滚动偏移 400，本用例的 loadChapter 会重置
        // restorePending（ReaderContent.onChapterChanged），跳转不受恢复干扰。
        function test_searchJumpScrolls() {
            var book = findBook("TXT", "longbook")
            if (!book) skip("未导入长文本书，跳过书内搜索跳转验证")
            var loader = openReader(book)
            var page = loader.item
            tryVerify(function () { return page.chapter.paragraphs && page.chapter.paragraphs.length === 300 }, 5000,
                      "长文本书应加载 300 段")
            // 书内搜索 Dialog 打开/关闭
            page.searchDialog.open()
            tryVerify(function () { return page.searchDialog.visible === true }, 2000,
                      "书内搜索 Dialog 应打开")
            page.searchDialog.close()
            // 跳转定位：第 250 段（内容远在视口之下）
            page.jumpToChapterParagraph(0, 250)
            tryVerify(function () { return page.contentView.contentY > 500 }, 5000,
                      "跳转后应滚动到第 250 段附近，实际 contentY=" + page.contentView.contentY)
            loader.destroy()
        }
        // 阅读计时：打开页面 mock 阅读 1.2 秒，销毁后 read_seconds 应增加（后端 QElapsedTimer 实测）
        function test_readSeconds() {
            var book = findBook("TXT", "longbook")
            if (!book) skip("未导入长文本书")
            var before = book.readSeconds
            var loader = openReader(book)
            wait(1200)
            loader.destroy() // onDestruction → stopTracking 结算
            wait(100) // 等延迟销毁完成、read_seconds 写入数据库
            var after = 0
            for (let b of Books.booksModel)
                if (b.id === book.id) { after = b.readSeconds; break }
            verify(after >= before + 1, "阅读 1.2 秒后 read_seconds 应至少 +1，实际增加 " + (after - before))
        }
        // 真实书验证（READDICT_REAL_EPUB 门控，未设置跳过）：导入 → 翻到第 3 章 → 重开断言恢复
        function test_realEpubChapterRestore() {
            var src = TestEnv.realEpubSource
            if (src.length === 0)
                skip("未设置 READDICT_REAL_EPUB，跳过真实书恢复验证")
            Importer.doImport(src)
            var book = findBook("EPUB", "从零")
            if (!book) skip("真实 EPUB 未导入")
            var loader = openReader(book)
            var page = loader.item
            tryVerify(function () { return page.chapter.paragraphs && page.chapter.paragraphs.length > 0 }, 8000,
                      "真实 EPUB 应能打开并加载章节")
            page.loadChapter(2) // 第 3 章（索引 2）
            var t3 = page.chapter.title
            verify(t3.length > 0, "第 3 章应有标题")
            loader.destroy()
            var loader2 = openReader(book)
            var page2 = loader2.item
            tryVerify(function () { return page2.chapter.paragraphs && page2.chapter.paragraphs.length > 0 }, 8000,
                      "重开应加载章节")
            compare(page2.chapter.title, t3, "重开应恢复到第 3 章（" + t3 + "）")
            loader2.destroy()
        }
    }
    TestCase {
        name: "CoverSmoke"
        // B2：BookCard 空封面/加载失败兜底——封面图与品牌色占位互斥显示。
        // 注意 Image 无 source 时 status 为 Null 而非 Error：空 cover 走「cover 为空」
        // 分支，坏路径走 Image.Error 分支，两种状态都必须落入占位。
        function test_placeholderStates() {
            var loader = cardComp.createObject(root)
            var card = loader.item
            verify(card !== null, "BookCard 应能加载")
            // 空 cover：占位可见、Image 隐藏、首字取自书名
            card.book = { id: 101, title: "空封面书", cover: "", progress: 0 }
            compare(card.showPlaceholder, true, "空 cover 应显示占位")
            verify(card.coverPlaceholder.visible === true, "空 cover 占位块应可见")
            verify(card.coverImage.visible === false, "空 cover 封面图应隐藏")
            compare(card.coverLetterText.text, "空", "占位首字应为书名首字，实际 " + card.coverLetterText.text)
            // cover 指向不存在文件：Image 异步进入 Error → 占位可见
            card.book = { id: 102, title: "坏封面书", cover: "/nonexistent/definitely_missing.png", progress: 0 }
            tryVerify(function () { return card.showPlaceholder === true }, 3000,
                      "坏封面应显示占位（Image.Error），实际 status=" + card.coverImage.status)
            verify(card.coverPlaceholder.visible === true, "坏封面占位块应可见")
            verify(card.coverImage.visible === false, "坏封面封面图应隐藏")
            loader.destroy()
        }
        // C5：Kindle 主页封面墙——作者行（封面下 标题+作者 双行）有作者显示/无作者隐藏
        function test_authorLine() {
            var loader = cardComp.createObject(root)
            var card = loader.item
            verify(card !== null, "BookCard 应能加载")
            verify(card.authorLabel !== undefined, "作者行应暴露句柄 authorLabel")
            // 有作者：显示且文本即作者
            card.book = { id: 103, title: "测试书", author: "测试作者", cover: "", progress: 0 }
            compare(card.authorLabel.visible, true, "有作者时作者行应显示")
            compare(card.authorLabel.text, "测试作者", "作者行文本应为作者，实际 " + card.authorLabel.text)
            // 无作者：隐藏（不占位）
            card.book = { id: 104, title: "无作者书", cover: "", progress: 0 }
            compare(card.authorLabel.visible, false, "无作者时作者行应隐藏")
            loader.destroy()
        }
        // 任务4：出版社行——有出版社显示、无出版社隐藏；作者为空时出版社紧跟标题不悬空
        function test_publisherLine() {
            var loader = cardComp.createObject(root)
            var card = loader.item
            verify(card !== null, "BookCard 应能加载")
            verify(card.publisherLabel !== undefined, "出版社行应暴露句柄 publisherLabel")
            // 有出版社：显示且文本即出版社
            card.book = { id: 105, title: "测试书", author: "测试作者", publisher: "测试出版社", cover: "", progress: 0 }
            compare(card.publisherLabel.visible, true, "有出版社时出版社行应显示")
            compare(card.publisherLabel.text, "测试出版社", "出版社行文本应为出版社，实际 " + card.publisherLabel.text)
            // 无出版社：隐藏
            card.book = { id: 106, title: "无出版社书", cover: "", progress: 0 }
            compare(card.publisherLabel.visible, false, "无出版社时出版社行应隐藏")
            loader.destroy()
        }
        // BUG3：出版社行不被进度条遮挡——标准书（title+author+publisher）出版社底部
        // 必须不越过进度条顶部；author-only / publisher-only 场景同样成立；进度条与
        // 出版社都完整落在卡片内。
        function test_publisherNotCoveredByProgressLine() {
            var loader = cardComp.createObject(root)
            var card = loader.item
            verify(card !== null, "BookCard 应能加载")
            verify(card.progressLine !== undefined, "进度条应暴露句柄 progressLine")
            verify(card.publisherLabel !== undefined, "出版社行应暴露句柄 publisherLabel")
            verify(card.authorLabel !== undefined, "作者行应暴露句柄 authorLabel")
            // 标准书：title+author+publisher 全有（原几何中进度条 y=283..286 压在出版社底部）
            card.book = { id: 201, title: "标准书", author: "作者甲", publisher: "出版社乙", cover: "", progress: 0.5 }
            wait(50)
            verify(card.publisherLabel.visible, "有出版社时出版社行应显示")
            var pubBottom = card.publisherLabel.y + card.publisherLabel.height
            verify(pubBottom <= card.progressLine.y,
                   "出版社底部(" + pubBottom + ")不应越过进度条顶部(" + card.progressLine.y + ")")
            verify(pubBottom <= card.height,
                   "出版社应完整落在卡片内：底部 " + pubBottom + " 超出卡片高 " + card.height)
            verify(card.progressLine.y + card.progressLine.height <= card.height,
                   "进度条应完整落在卡片内：y=" + card.progressLine.y + " h=" + card.progressLine.height
                   + " 超出卡片高 " + card.height)
            // author-only：无出版社——进度条不得压作者行
            card.book = { id: 202, title: "仅作者书", author: "作者丙", cover: "", progress: 0.5 }
            wait(20)
            verify(!card.publisherLabel.visible, "无出版社时出版社行应隐藏")
            var authBottom = card.authorLabel.y + card.authorLabel.height
            verify(authBottom <= card.progressLine.y,
                   "仅作者时作者底部(" + authBottom + ")不应越过进度条顶部(" + card.progressLine.y + ")")
            // publisher-only：无作者——出版社紧跟标题，进度条不得压出版社
            card.book = { id: 203, title: "仅出版社书", publisher: "出版社丁", cover: "", progress: 0.5 }
            wait(20)
            verify(!card.authorLabel.visible, "无作者时作者行应隐藏")
            verify(card.publisherLabel.visible, "publisher-only 时出版社行应显示")
            var pubBottom2 = card.publisherLabel.y + card.publisherLabel.height
            verify(pubBottom2 <= card.progressLine.y,
                   "publisher-only 时出版社底部(" + pubBottom2 + ")不应越过进度条顶部(" + card.progressLine.y + ")")
            loader.destroy()
        }
        // BUG3：compact（HomePage 横排）卡片不显示作者/出版社/进度条，标题不越界
        function test_compactCardNoOverlap() {
            var loader = cardComp.createObject(root)
            var card = loader.item
            verify(card !== null, "BookCard 应能加载")
            card.compact = true
            card.book = { id: 204, title: "紧凑书", author: "作者戊", publisher: "出版社己", cover: "", progress: 0.5 }
            wait(50)
            compare(card.authorLabel.visible, false, "compact 卡片不应显示作者行")
            compare(card.publisherLabel.visible, false, "compact 卡片不应显示出版社行")
            compare(card.progressLine.visible, false, "compact 卡片不应显示进度条")
            verify(card.cardTitle.y + card.cardTitle.height <= card.height,
                   "compact 标题应完整落在卡片内：底部 "
                   + (card.cardTitle.y + card.cardTitle.height) + " 超出卡片高 " + card.height)
            loader.destroy()
        }
        // BUG3：书架网格 cell 与卡片尺寸一致——800x600 与 1100x720 下真实渲染的
        // 卡片内容不互相覆盖（cell 预留呼吸空间 + 网格内出版社不被进度条遮挡）
        function test_gridCellFitsCard() {
            var cardLoader = cardComp.createObject(root)
            var card = cardLoader.item
            verify(card !== null, "BookCard 应能加载")
            card.book = { id: 205, title: "网格书", author: "作者庚", publisher: "出版社辛", cover: "", progress: 0.5 }
            wait(50)
            var sizes = [[800, 600], [1100, 720]]
            for (var i = 0; i < sizes.length; i++) {
                var loader = shelfComp.createObject(root)
                loader.width = sizes[i][0]
                loader.height = sizes[i][1]
                var shelf = loader.item
                verify(shelf !== null, "ShelfPage 应能加载")
                verify(shelf.grid !== undefined, "ShelfPage 应暴露 grid 句柄")
                var grid = shelf.grid
                verify(grid.cellWidth >= card.width + 8,
                       "cellWidth(" + grid.cellWidth + ") 应大于卡片宽(" + card.width + ")，窗口 "
                       + sizes[i][0] + "x" + sizes[i][1])
                verify(grid.cellHeight >= card.height + 8,
                       "cellHeight(" + grid.cellHeight + ") 应大于卡片高(" + card.height + ")，窗口 "
                       + sizes[i][0] + "x" + sizes[i][1])
                // 真实 delegate 渲染：模型替换为固定数据，网格内卡片不得互相覆盖
                grid.model = [{ id: 205, title: "网格书", author: "作者庚", publisher: "出版社辛", cover: "", progress: 0.5 }]
                var delegate = null
                tryVerify(function () {
                    var ch = grid.contentItem.children
                    for (var j = 0; j < ch.length; j++)
                        if (ch[j].book && ch[j].book.title === "网格书") { delegate = ch[j]; return true }
                    return false
                }, 2000, "网格应实例化卡片 delegate")
                verify(delegate !== null, "网格内应能找到卡片 delegate")
                var pb = delegate.publisherLabel.y + delegate.publisherLabel.height
                verify(pb <= delegate.progressLine.y,
                       "网格内出版社底部(" + pb + ")不应越过进度条顶部(" + delegate.progressLine.y + ")")
                verify(delegate.progressLine.y + delegate.progressLine.height <= delegate.height,
                       "网格内进度条应完整落在卡片内")
                loader.destroy()
            }
            cardLoader.destroy()
        }
    }
    TestCase {
        name: "RefreshCoversSmoke"
        // B2：封面刷新数据流——设置页按钮 → Importer.refreshCovers() →
        // coversRefreshed → Books.booksChanged → booksModel 恢复真实封面。
        // fixture：TestEnv 合成带封面 EPUB（OPF 声明红图）。任务4 起标题取 OPF
        // dc:title（"封面刷新书"），不再回退文件名 coverepub。
        function findCoverBook() {
            for (let b of Books.booksModel)
                if (b.title === "封面刷新书") return b
            return null
        }
        function test_refreshCoversDataFlow() {
            if (TestEnv.coverEpubSource.length === 0)
                skip("coverEpubSource 未生成，跳过封面刷新冒烟")
            Importer.doImport(TestEnv.coverEpubSource)
            tryVerify(function () { return findCoverBook() !== null }, 3000, "封面书应导入")
            var book = findCoverBook()
            verify((book.cover || "").indexOf("cover_") >= 0,
                   "导入后应有真实封面，实际 " + book.cover)
            // 模拟早期导入：cover 改回占位（空串）→ 卡片应显示占位
            Books.updateCover(book.id, "")
            tryVerify(function () { return (findCoverBook().cover || "") === "" }, 3000, "cover 应已清空")
            var cardLoader = cardComp.createObject(root)
            var card = cardLoader.item
            card.book = findCoverBook()
            tryVerify(function () { return card.showPlaceholder === true }, 3000,
                      "空 cover 卡片应显示占位，实际 " + card.showPlaceholder)
            // 设置页按钮触发刷新 → 恢复真实封面 + 提示文案
            var settingsLoader = settingsComp.createObject(root)
            var page = settingsLoader.item
            verify(page !== null, "SettingsPage 应能加载")
            verify(page.refreshCoversButton !== undefined, "刷新封面按钮应暴露句柄")
            page.refreshCoversButton.clicked()
            tryVerify(function () { return (findCoverBook().cover || "").indexOf("cover_") >= 0 }, 5000,
                      "按钮点击后 cover 应恢复为真实封面")
            var hint = page.refreshCoversHint.text || ""
            verify(hint.indexOf("已刷新") >= 0, "提示应含已刷新本数，实际 " + hint)
            // 卡片同步回到真实封面（占位隐藏）
            card.book = findCoverBook()
            tryVerify(function () { return card.showPlaceholder === false }, 3000,
                      "真实封面恢复后占位应隐藏")
            verify(card.coverImage.visible === true, "真实封面恢复后封面图应可见")
            cardLoader.destroy()
            settingsLoader.destroy()
        }
    }
}
