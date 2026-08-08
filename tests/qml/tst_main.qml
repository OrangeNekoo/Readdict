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
        id: controlsComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/ReaderControls.qml" }
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
        // 真实 PDF 加载验证：TestEnv.pdfSource 为空（未设 READDICT_REAL_PDF）时跳过；
        // 否则加载真实文件并等待 PdfDocument Ready，确认 QtPdf 渲染管线可用
        function test_pdfLoadsRealSource() {
            var src = TestEnv.pdfSource
            if (src.length === 0)
                skip("未设置 READDICT_REAL_PDF，跳过真实 PDF 加载验证")
            var loader = pdfReaderComp.createObject(root)
            var page = loader.item
            verify(page !== null, "PdfReaderPage 应能加载")
            page.book = { id: 999001, title: "真实PDF", path: src }
            var doc = page.pdfDocument
            verify(doc !== null, "PdfReaderPage 应暴露 pdfDocument")
            tryVerify(function () { return doc.status === PdfDocument.Ready }, 15000,
                      "真实 PDF 应加载为 Ready，实际 " + doc.status)
            verify(doc.pageCount > 0, "加载的 PDF 应有页数")
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
            var loader = pdfReaderComp.createObject(root)
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
            // 注：30MB PDF 单页渲染在本机 <100ms，先 goToPage 再在同一事件循环内调
            // requestClose 可稳定命中 Loading 窗口（status 非 Ready 即进入轮询分支）。
            page.pdfView.goToPage(5)
            page.pdfView.renderScale = 6 // 高倍率重渲染，加大 Loading 窗口
            // Loading 窗口在 goToPage 同一事件循环内同步进入（实测稳定命中 status=Loading）；
            // 若渲染太快已 Ready 则测试失败而非跳过——轮询锁定必须是必然路径
            verify(page.pdfView.status !== Image.Ready,
                   "goToPage 后应立即进入 Loading 渲染窗口（status=" + page.pdfView.status + "）")
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
        // C8：书架全文搜索——e2e 已导入含"第二行内容"的 TXT 书（本文件在其后执行），
        // 切到"全文"模式输入词，应命中并带 snippet。
        function test_shelfFulltextHits() {
            var loader = shelfComp.createObject(root)
            var shelf = loader.item
            verify(shelf !== null, "ShelfPage 应能加载")
            shelf.searchModeBox.currentIndex = 1 // 全文
            shelf.searchField.text = "第二行内容"
            tryVerify(function () { return shelf.fulltextList.model.length > 0 }, 5000,
                      "全文搜索应命中已导入 TXT 书，实际 " + shelf.fulltextList.model.length)
            var hit = shelf.fulltextList.model[0]
            verify(Number(hit.bookId) > 0, "命中应带 bookId")
            verify((hit.snippet || "").length > 0, "命中应带 snippet，实际 " + hit.snippet)
            // 切回元数据模式：结果列表隐藏、网格恢复过滤语义
            shelf.searchModeBox.currentIndex = 0
            verify(shelf.fulltextList.visible === false, "切回元数据后全文结果列表应隐藏")
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
        name: "ControlsSmoke"
        // 锁定字号按钮接线（回归：A+ 曾误调 fontSize 属性的自动变更信号导致只减不增）
        function test_fontButtons() {
            var loader = controlsComp.createObject(root)
            var ctl = loader.item
            verify(ctl !== null, "ReaderControls 应能加载")
            ctl.fontSize = 18
            var got = -1
            ctl.changeFontSize.connect(function (s) { got = s })
            // RowLayout 子项顺序：0上一章 1目录 2spacer 3A− 4字号label 5A+ 6背景 7对齐
            // 8页宽 9下一章 10笔记 11搜索 12朗读 13字体（D4 追加行尾，0..12 索引不变）
            var layout = ctl.children[1]
            var btnAplus = layout.children[5]
            btnAplus.clicked()
            compare(got, 19, "A+ 应发 changeFontSize(fontSize+1)")
            layout.children[3].clicked()
            compare(got, 17, "A− 应发 changeFontSize(fontSize-1)")
            loader.destroy()
        }
        // C5：Kindle 式底部进度细条——children[2]（[0]=分隔线 [1]=RowLayout 索引不变），
        // 宽度 = chapterProgress × 全宽，超界钳制；细条 2px 贴底。
        function test_progressStrip() {
            var loader = controlsComp.createObject(root)
            var ctl = loader.item
            verify(ctl !== null, "ReaderControls 应能加载")
            ctl.width = 200
            verify(ctl.children[0] !== undefined && ctl.children[1] !== undefined,
                   "分隔线与 RowLayout 索引应保持（children[0]/[1]）")
            var strip = ctl.children[2]
            verify(strip !== undefined, "进度细条应存在（children[2]）")
            compare(strip.height, 2, "进度细条应为 2px")
            var fill = strip.children[0]
            ctl.chapterProgress = 0.5
            compare(Math.round(fill.width), 100, "进度 0.5 时细条填充应为半宽，实际 " + fill.width)
            ctl.chapterProgress = 0
            compare(fill.width, 0, "进度 0 时细条填充应为 0")
            ctl.chapterProgress = 1.25
            compare(fill.width, 200, "进度超 1 应钳制到全宽，实际 " + fill.width)
            loader.destroy()
        }
    }
    TestCase {
        name: "FontPickerSmoke"
        // D4：字体切换移入阅读界面——控制栏字体按钮（行尾 children[13]）+ 弹层 4 项
        //（宋体/黑体/HW/得意黑，value 为存储 token）；阅读页内选择即时生效
        //（Settings/typography/正文 font.family 同步）；设置页外观卡不再有字体项。
        function test_controlsFontButton() {
            var loader = controlsComp.createObject(root)
            var ctl = loader.item
            verify(ctl !== null, "ReaderControls 应能加载")
            ctl.fontSize = 18
            ctl.fontFamily = "思源宋体 VF"
            var layout = ctl.children[1]
            var fontBtn = layout.children[13]
            verify(fontBtn !== undefined, "字体按钮应存在（children[13]）")
            var got = []
            ctl.setFontFamily.connect(function (v) { got.push(v) })
            fontBtn.clicked()
            tryVerify(function () { return ctl.fontPopup.visible }, 2000,
                      "点击字体按钮应打开弹层")
            var list = ctl.fontList
            verify(list !== undefined, "字体列表应暴露句柄")
            compare(list.count, 4, "字体列表应为 4 项（宋体/黑体/HW/得意黑）")
            compare(list.model[0].value, "思源宋体 VF")
            compare(list.model[1].value, "思源黑体 VF")
            compare(list.model[2].value, "SourceHanSansHW-VF")
            compare(list.model[3].value, "得意黑")
            // 选择第 3 项（HW）→ 发 setFontFamily(token) 并关闭弹层
            tryVerify(function () { return list.itemAtIndex(2) !== null }, 2000,
                      "弹层委托应就绪")
            list.itemAtIndex(2).clicked()
            compare(got.join(","), "SourceHanSansHW-VF", "选择应发 setFontFamily(token)")
            tryVerify(function () { return !ctl.fontPopup.visible }, 2000,
                      "选择后弹层应关闭")
            // 当前项高亮：fontFamily 与列表 value 匹配
            ctl.fontFamily = "得意黑"
            tryVerify(function () { return list.itemAtIndex(3).highlighted }, 2000,
                      "当前字体项应高亮")
            loader.destroy()
        }
        // 阅读页内切换 4 字体即时生效：写 Settings → 重组合 typography → 正文 font.family
        function test_readerFontSwitchApplies() {
            var book = null
            for (let b of Books.booksModel)
                if ((b.format || "").toUpperCase() === "TXT") { book = b; break }
            if (!book)
                skip("书库无 TXT 书，跳过阅读页字体切换验证")
            var loader = readerComp.createObject(root)
            var page = loader.item
            verify(page !== null, "ReaderPage 应能加载")
            page.book = book
            page.loadChapter(0)
            tryVerify(function () { return page.contentView.paragraphRepeater.itemAt(0) !== null }, 3000,
                      "首段应渲染完成")
            var tokens = ["思源宋体 VF", "思源黑体 VF", "SourceHanSansHW-VF", "得意黑"]
            for (var i = 0; i < tokens.length; ++i) {
                page.fontPopup.open()
                tryVerify(function () { return page.fontPopup.visible }, 2000, "弹层应打开")
                tryVerify(function () { return page.fontList.itemAtIndex(i) !== null }, 2000,
                          "委托应就绪")
                page.fontList.itemAtIndex(i).clicked()
                compare(String(Settings.value("typography/fontFamily")), tokens[i],
                        "选择后 typography/fontFamily 应写入存储 token（第 " + i + " 项）")
                compare(page.typography.fontFamily, Books.resolveFontFamily(tokens[i]),
                        "阅读页 typography.fontFamily 应为解析后的字族（第 " + i + " 项）")
                tryVerify(function () {
                    var edit = page.contentView.paragraphRepeater.itemAt(0).children[0]
                    return edit !== null && edit.font.family === page.typography.fontFamily
                }, 2000, "正文段 font.family 应绑定 typography.fontFamily（第 " + i + " 项）")
            }
            // 恢复默认字体，避免影响后续用例（共享 Settings 单例）
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
                   "开关行（内嵌 KdToggle）不应显示 chevron")
            verify(page.themeModeToggle !== undefined, "设置页应暴露深色模式 KdToggle 句柄")
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
        // onCompleted 前应用，保证章节加载/滚动恢复/计时都在 book 就绪后执行
        function openReader(book) {
            var loader = readerComp.createObject(root)
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
            // 距底部 50px（< autoNextThreshold 200px）→ 触发
            c.contentY = Math.max(0, c.contentHeight - c.height - 50)
            tryVerify(function () { return fires >= 1 }, 3000,
                      "滚动接近底部应触发 requestNextChapter，实际 " + fires)
            // 去重：同一章内反复滚到章末不再重复触发
            c.contentY = 10
            wait(50)
            c.contentY = Math.max(0, c.contentHeight - c.height - 50)
            wait(100)
            compare(fires, 1, "同一章内 requestNextChapter 应只触发一次")
            // 短章语义：maxY <= 阈值带（内容仅超出视口 1..200px）时任何 contentY>0
            // 都落在带内——不得触发（否则首个小滚动即误换章、连翻多章）
            c.nextChapterRequested = false
            c.autoNextThreshold = 10000   // 阈值大于 maxY → 模拟短章
            c.contentY = 10
            wait(50)
            c.contentY = Math.max(0, c.contentHeight - c.height - 50)
            wait(100)
            compare(fires, 1, "maxY 小于等于阈值时滚动触底不应触发")
            // 阈值带精确：阈值 10px → 距底 50px（带外）不触发、距底 5px（带内）触发
            c.nextChapterRequested = false
            c.autoNextThreshold = 10
            c.contentY = 10
            wait(50)
            c.contentY = Math.max(0, c.contentHeight - c.height - 50)
            wait(100)
            compare(fires, 1, "距底超过阈值不应触发")
            c.contentY = 10
            wait(50)
            c.contentY = Math.max(0, c.contentHeight - c.height - 5)
            wait(100)
            compare(fires, 2, "距底 5px（小于阈值 10px）应触发")
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
            c.contentY = Math.max(0, c.contentHeight - c.height - 50)
            wait(150)
            compare(fires, 0, "TTS 暂停中滚动触底不应触发 requestNextChapter")
            // TTS 停止（state==0）：滚动续章恢复
            Tts.stop()
            c.contentY = 10
            wait(50)
            c.contentY = Math.max(0, c.contentHeight - c.height - 50)
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
            // 用户手动滚动（先上移再回到底部）→ 触发
            c.contentY = Math.max(0, c.contentHeight - c.height - 100)
            wait(50)
            c.contentY = Math.max(0, c.contentHeight - c.height - 20)
            tryVerify(function () { return fires >= 1 }, 3000,
                      "用户手动滚动到章末应触发 requestNextChapter")
            loader.destroy()
        }

        // 规格 §7 端到端绑定：ReaderContent 的 requestNextChapter 信号必须经 ReaderPage 的
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
    }
    TestCase {
        name: "RefreshCoversSmoke"
        // B2：封面刷新数据流——设置页按钮 → Importer.refreshCovers() →
        // coversRefreshed → Books.booksChanged → booksModel 恢复真实封面。
        // fixture：TestEnv 合成带封面 EPUB（标题 coverepub，OPF 声明红图）。
        function findCoverBook() {
            for (let b of Books.booksModel)
                if (b.title === "coverepub") return b
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
