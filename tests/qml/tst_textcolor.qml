import QtQuick
import QtTest
import Readdict.Backend
import Readdict.Test 1.0

// B3：深色背景阅读文字切换为浅色——ReaderContent.textColor 默认深字 #212121，
// ReaderPage 按 bgMode 传色（dark → 浅色 #E0E0E0，light/paper/image → 深字）。
// 富文本标题（<h1>）渲染色无法直接断言（继承 QTextDocument 默认前景色），
// 此处断言 TextEdit.color 属性（即文档默认前景色源）；h1 渲染行为另在报告中记录。
// 结构约定（与 tst_background/tst_highlightsui 一致）：根为带尺寸的 Item，
// TestCase 是其子项，组件经 createObject(root) 挂到该 Item 下。
Item {
    id: root
    width: 1100; height: 720

    Component { id: contentComp; Loader { source: "qrc:/qt/qml/Readdict/ui/qml/ReaderContent.qml" } }
    Component { id: readerComp; Loader { source: "qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml" } }

    // 纯文本段 + 富文本段（<h1> 标题 + <b>）：两种分支都应跟随 textColor
    function makeChapter() {
        return { title: "章", paragraphs: [
            { text: "第一段正文。", html: "第一段正文。", level: 0, imagePath: "",
              sentences: ["第一段正文。"] },
            { text: "标题", html: "<h1>标题</h1>", level: 1, imagePath: "",
              sentences: ["标题"] },
            { text: "粗体句。", html: "<p><b>粗体句。</b></p>", level: 0, imagePath: "",
              sentences: ["粗体句。"] }
        ]}
    }

    // 段落委托内首个 TextEdit（委托结构：Item > TextEdit，同 tst_highlightsui）
    function paraEdit(c, i) {
        var d = c.paragraphRepeater.itemAt(i)
        return (d && d.children[0]) ? d.children[0] : null
    }

    TestCase {
        id: testCase
        name: "TextColorSmoke"

        // 默认浅色：ReaderContent.textColor 默认 #212121，段落 TextEdit.color 跟随
        function test_01_defaultLight() {
            var loader = contentComp.createObject(root)
            loader.width = 800; loader.height = 600
            var c = loader.item
            verify(c !== null, "ReaderContent 应能加载")
            c.typography = { fontFamily: "Source Han Sans VF", fontSize: 18, lineHeight: 1.6,
                             align: "left", pageWidth: "normal" }
            c.chapter = root.makeChapter()
            tryVerify(function () { return root.paraEdit(c, 0) !== null }, 2000,
                      "段落委托应渲染完成")
            compare(String(c.textColor), "#212121", "默认 textColor 应为深字 #212121")
            for (var i = 0; i < 3; i++) {
                var t = root.paraEdit(c, i)
                compare(String(t.color), "#212121",
                        "段落 " + i + " TextEdit.color 应默认 #212121，实际 " + String(t.color))
            }
            loader.destroy()
        }

        // 传浅色：textColor 改为 #E0E0E0 后纯文本/富文本段 TextEdit.color 同步更新
        function test_02_darkTextColor() {
            var loader = contentComp.createObject(root)
            loader.width = 800; loader.height = 600
            var c = loader.item
            verify(c !== null, "ReaderContent 应能加载")
            c.typography = { fontFamily: "Source Han Sans VF", fontSize: 18, lineHeight: 1.6,
                             align: "left", pageWidth: "normal" }
            c.chapter = root.makeChapter()
            tryVerify(function () { return root.paraEdit(c, 0) !== null }, 2000,
                      "段落委托应渲染完成")
            c.textColor = "#E0E0E0"
            compare(String(c.textColor), "#e0e0e0", "textColor 应更新为浅色")
            tryVerify(function () {
                for (var i = 0; i < 3; i++) {
                    var t = root.paraEdit(c, i)
                    if (!t || String(t.color) !== "#e0e0e0") return false
                }
                return true
            }, 2000, "纯文本与富文本（含 <h1>）段落 TextEdit.color 都应随 textColor 更新")
            // 切回深字：绑定是双向响应式的
            c.textColor = "#212121"
            tryVerify(function () {
                return String(root.paraEdit(c, 1).color) === "#212121"
            }, 2000, "textColor 切回深字后富文本段应同步")
            loader.destroy()
        }

        // ReaderPage 绑定：bgMode=dark → textColor #E0E0E0；light/paper/image → 深字
        function test_03_readerPageBgModeBinding() {
            var loader = readerComp.createObject(root)
            loader.setSource("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: {} })
            var page = loader.item
            verify(page !== null, "ReaderPage 应能加载")
            page.chapter = root.makeChapter()
            var cv = page.contentView
            tryVerify(function () { return root.paraEdit(cv, 0) !== null }, 2000,
                      "ReaderPage 内段落委托应渲染完成")
            // 默认浅色
            compare(String(cv.textColor), "#212121", "默认（light）textColor 应为深字")
            // dark → 浅色，段落 TextEdit.color 同步
            page.bgMode = "dark"
            compare(String(cv.textColor), "#e0e0e0", "dark 背景 textColor 应为浅色 #E0E0E0")
            tryVerify(function () {
                return String(root.paraEdit(cv, 1).color) === "#e0e0e0"
            }, 2000, "dark 下富文本段 TextEdit.color 应为 #E0E0E0，实际 "
                     + String(root.paraEdit(cv, 1).color))
            // paper（米白浅底）→ 深字
            page.bgMode = "paper"
            compare(String(cv.textColor), "#212121", "paper 背景 textColor 应为深字")
            // image（自定义图片背景，内容区透明露出图片，按浅色处理）→ 深字
            page.bgMode = "image"
            compare(String(cv.textColor), "#212121", "image 背景 textColor 应为深字（浅色处理取舍）")
            tryVerify(function () {
                return String(root.paraEdit(cv, 0).color) === "#212121"
            }, 2000, "image 下纯文本段 TextEdit.color 应为 #212121")
            // 再回 dark：绑定持续生效
            page.bgMode = "dark"
            compare(String(cv.textColor), "#e0e0e0", "再切 dark textColor 应回到浅色")
            loader.destroy()
        }
    }
}
