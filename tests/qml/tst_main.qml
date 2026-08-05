import QtQuick
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
            loader.destroy()
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
        name: "ReaderSmoke"
        function test_readerLoads() {
            var loader = readerComp.createObject(root)
            verify(loader.item !== null, "ReaderPage 应能加载（含控制栏/目录 Dialog 编译检查）")
            loader.destroy()
        }
        // 本文件在 tst_e2e.qml 之后执行（文件名字典序），此时书库已有导入的 TXT 书
        function test_loadChapter() {
            if (Books.booksModel.length === 0)
                skip("书库为空，跳过章节加载验证")
            var loader = readerComp.createObject(root)
            var page = loader.item
            verify(page !== null, "ReaderPage 应能加载")
            page.book = Books.booksModel[0]
            page.loadChapter(0)
            verify(page.chapter !== null && page.chapter.paragraphs !== undefined,
                   "loadChapter 应返回带 paragraphs 的章节对象")
            verify(page.chapter.paragraphs.length > 0, "TXT 首章应有段落")
            compare(page.chapter.title, page.book.title, "TXT 首章标题应为书名")
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
            // RowLayout 子项顺序：0上一章 1目录 2spacer 3A− 4字号label 5A+ 6背景 7对齐 8页宽 9下一章
            var layout = ctl.children[1]
            var btnAplus = layout.children[5]
            btnAplus.clicked()
            compare(got, 19, "A+ 应发 changeFontSize(fontSize+1)")
            layout.children[3].clicked()
            compare(got, 17, "A− 应发 changeFontSize(fontSize-1)")
            loader.destroy()
        }
    }
}
