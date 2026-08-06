import QtQuick
import QtTest
import Readdict.Backend
import Readdict.Test 1.0

// C7 冒烟：划线数据流（Highlights 单例 CRUD + 变更信号）+ 逐句/富文本划线渲染标记
// + 选择工具条交互链路（simulateSelection 注入，与真实鼠标路径共用同一状态与动作函数；
// 真实选择无法在 quicktest harness 可靠合成——Text selectByMouse 需合成按下-拖动，走手动清单）。
Item {
    id: root
    width: 1100; height: 720

    Component {
        id: contentComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/ReaderContent.qml" }
    }
    Component {
        id: readerComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml" }
    }

    // 3 纯文本段（各 2 句，共 6 句）+ 1 富文本段（含 <b>，2 句）
    function makeChapter() {
        var paras = []
        for (var i = 0; i < 3; i++)
            paras.push({ text: "第" + i + "段第一句。第二句！",
                         html: "第" + i + "段第一句。第二句！",
                         level: 0, imagePath: "",
                         sentences: ["第" + i + "段第一句。", "第二句！"] })
        paras.push({ text: "粗体句。普通句。", html: "<p><b>粗体句。</b>普通句。</p>",
                     level: 0, imagePath: "", sentences: ["粗体句。", "普通句。"] })
        return { title: "章", paragraphs: paras }
    }

    TestCase {
        name: "HighlightBackend"
        // 独立 bookId（900x）防与其他用例互相污染
        function test_crudFlow() {
            var id = Highlights.addHighlight(9001, "第一章", 3, "这是高亮文本", "#FFEB3B", "笔记内容")
            verify(id > 0, "addHighlight 应返回行 id")
            var list = Highlights.highlightsForBook(9001)
            compare(list.length, 1)
            compare(list[0].chapter, "第一章")
            compare(list[0].sentenceIndex, 3)
            compare(list[0].text, "这是高亮文本")
            compare(list[0].color, "#FFEB3B")
            compare(list[0].note, "笔记内容")
            compare(list[0].id, id)
            Highlights.updateNote(id, "新笔记")
            list = Highlights.highlightsForBook(9001)
            compare(list[0].note, "新笔记")
            compare(list[0].text, "这是高亮文本", "仅改 note，其余字段不变")
            Highlights.removeHighlight(id)
            compare(Highlights.highlightsForBook(9001).length, 0, "删除后应清空")
        }
        function test_changedSignalOnEveryWrite() {
            var got = []
            Highlights.highlightsChanged.connect(function (b) { got.push(b) })
            var id = Highlights.addHighlight(9002, "ch", 0, "t", "#FFF", "")
            Highlights.updateNote(id, "n")
            Highlights.removeHighlight(id)
            compare(got.length, 3, "增/改/删都应发 highlightsChanged")
            compare(got[0], 9002)
            compare(got[1], 9002)
            compare(got[2], 9002)
        }
    }

    TestCase {
        name: "HighlightRender"
        function test_rendersMarkerSpans() {
            var loader = contentComp.createObject(root)
            loader.width = 800; loader.height = 600
            var c = loader.item
            verify(c !== null, "ReaderContent 应能加载")
            c.typography = { fontFamily: "Source Han Sans VF", fontSize: 18, lineHeight: 1.6,
                             align: "left", pageWidth: "normal" }
            c.chapter = root.makeChapter()
            wait(50)
            // 划线：全局句 2（段 1 首句）绿色；全局句 5（段 2 次句）粉色
            c.highlights = [
                { id: 11, bookId: 1, chapter: "章", sentenceIndex: 2, text: "第1段第一句。", color: "#A5D6A7", note: "" },
                { id: 12, bookId: 1, chapter: "章", sentenceIndex: 5, text: "第二句！", color: "#F8BBD0", note: "n" }
            ]
            wait(50)
            var d0 = c.paragraphRepeater.itemAt(0)
            var t0 = d0.children[0].text.toLowerCase()
            // 段 0 无划线（Tts 游标可能命中首句产生黄底，只断言无划线色）
            verify(t0.indexOf("#a5d6a7") < 0 && t0.indexOf("#f8bbd0") < 0 && t0.indexOf("#ffeb3b") < 0,
                   "段 0 无划线不应有划线色 span，实际 " + t0)
            var d1 = c.paragraphRepeater.itemAt(1)
            var t1 = d1.children[0].text.toLowerCase()
            verify(t1.indexOf("background-color:#a5d6a7") >= 0, "段 1 首句应带绿色划线 span，实际 " + t1)
            verify(t1.indexOf("第1段第一句。") >= 0)
            var d2 = c.paragraphRepeater.itemAt(2)
            var t2 = d2.children[0].text.toLowerCase()
            verify(t2.indexOf("background-color:#f8bbd0") >= 0, "段 2 次句应带粉色划线 span，实际 " + t2)
            // 富文本段：段内划线句 → 整段背景近似（保留 <b> 标记）
            c.highlights = c.highlights.concat([
                { id: 13, bookId: 1, chapter: "章", sentenceIndex: 6, text: "粗体句。", color: "#FFEB3B", note: "" }
            ])
            wait(50)
            var d3 = c.paragraphRepeater.itemAt(3)
            var t3 = d3.children[0].text.toLowerCase()
            // 富文本段整段包划线色（div 块级包裹才保留背景）；<b> 序列化为 font-weight span
            verify(t3.indexOf("background-color:#ffeb3b") >= 0 && t3.indexOf("font-weight:700") >= 0,
                   "富文本段应整段包划线色并保留粗体，实际 " + t3)
            // 换章（标题不同）→ 本书划线不串章。注意 Tts 游标是跨用例全局状态，
            // 可能落在"另一章"某句上产生 TTS 黄底——契约是**划线色**不泄漏，故只断言无划线色
            c.chapter = { title: "另一章", paragraphs: root.makeChapter().paragraphs }
            wait(50)
            var t1b = c.paragraphRepeater.itemAt(1).children[0].text.toLowerCase()
            verify(t1b.indexOf("#a5d6a7") < 0 && t1b.indexOf("#f8bbd0") < 0 && t1b.indexOf("#ffeb3b") < 0,
                   "其他章节不应渲染本书划线色，实际 " + t1b)
            loader.destroy()
        }
        function test_markerPlusTtsCursorOverlay() {
            var loader = contentComp.createObject(root)
            loader.width = 800; loader.height = 600
            var c = loader.item
            c.typography = { fontFamily: "Source Han Sans VF", fontSize: 18, lineHeight: 1.6,
                             align: "left", pageWidth: "normal" }
            c.chapter = root.makeChapter()
            wait(50)
            // 无引擎桩：seekTo 只驱动游标不发声
            Tts.reconfigure("openai", "https://api.openai.com/v1", "", "tts-1", "nova", 1.0)
            var all = []
            for (var p of c.chapter.paragraphs)
                for (var s of p.sentences) all.push(s)
            Tts.setSentences(all)
            c.highlights = [{ id: 21, bookId: 1, chapter: "章", sentenceIndex: 2,
                              text: "第1段第一句。", color: "#A5D6A7", note: "" }]
            wait(50)
            // 游标 2（段 1 首句）= 划线句：划线色为底 + 下划线叠加（两类信息都可见）
            Tts.seekTo(2)
            wait(50)
            var t1 = c.paragraphRepeater.itemAt(1).children[0].text.toLowerCase()
            verify(t1.indexOf("background-color:#a5d6a7") >= 0, "划线色应保留，实际 " + t1)
            // 序列化格式：text-decoration 后带空格（Qt 归一化）
            verify(t1.indexOf("text-decoration: underline") >= 0, "朗读游标应以下划线叠加，实际 " + t1)
            // 游标 3（段 1 次句）= 未划线当前句：TTS 黄底
            Tts.seekTo(3)
            wait(50)
            var t2 = c.paragraphRepeater.itemAt(1).children[0].text.toLowerCase()
            verify(t2.indexOf("background-color:#ffd54f") >= 0, "未划线当前句应 TTS 黄底，实际 " + t2)
            loader.destroy()
        }
    }

    TestCase {
        name: "LineSpacingHelper"
        // C7：段落改 TextEdit 渲染（Text 在 Qt 6.7+ 移除选择 API），行距经
        // ReaderText.applyLineSpacing 施加到文档——验证 helper 与 delegate 集成都生效。
        // 注意：RichText 解析会折叠裸 \n，多行用显式 <br/>。
        function test_helperChangesLineHeight() {
            var edit = Qt.createQmlObject(
                'import QtQuick; TextEdit { textFormat: TextEdit.RichText; ' +
                'text: "第一行文字。<br/>第二行文字。<br/>第三行文字。"; font.pixelSize: 18; width: 300; visible: false }',
                root)
            verify(edit !== null, "测试 TextEdit 应能创建")
            wait(50)
            var h1 = edit.implicitHeight
            verify(h1 > 40, "3 行文档高度应大于单行（h1=" + h1 + "）")
            ReaderText.applyLineSpacing(edit, 2.5)
            wait(50)
            var h2 = edit.implicitHeight
            verify(h2 > h1 * 1.5, "行距 2.5 应明显高于默认（h1=" + h1 + ", h2=" + h2 + "）")
            edit.destroy()
        }
        function test_delegateAppliesLineSpacing() {
            var loader = contentComp.createObject(root)
            loader.width = 800; loader.height = 600
            var c = loader.item
            c.typography = { fontFamily: "Source Han Sans VF", fontSize: 18, lineHeight: 1.0,
                             align: "left", pageWidth: "normal" }
            c.chapter = { title: "章", paragraphs: [
                { text: "第一行文字。\n第二行文字。\n第三行文字。",
                  html: "第一行文字。<br/>第二行文字。<br/>第三行文字。",
                  level: 0, imagePath: "", sentences: [] }
            ]}
            tryVerify(function () {
                return c.paragraphRepeater.itemAt(0) && c.paragraphRepeater.itemAt(0).children[0].implicitHeight > 40
            }, 2000, "多行段落应完成布局")
            var h1 = c.paragraphRepeater.itemAt(0).children[0].implicitHeight
            c.typography = { fontFamily: "Source Han Sans VF", fontSize: 18, lineHeight: 2.5,
                             align: "left", pageWidth: "normal" }
            tryVerify(function () {
                var h2 = c.paragraphRepeater.itemAt(0).children[0].implicitHeight
                return h2 > h1 * 1.5
            }, 3000, "行距 2.5 应明显高于 1.0（h1=" + h1 + "）")
            loader.destroy()
        }
    }

    TestCase {
        name: "HighlightInteraction"
        function initTestCase() {
            if (Books.booksModel.length === 0)
                for (let f of TestEnv.sourceFiles) Importer.doImport(f)
        }
        function findTxtBook() {
            for (let b of Books.booksModel)
                if ((b.format || "").toUpperCase() === "TXT") return b
            return null
        }
        // 选择 → 划线：模拟选择全局句 2 → 工具条出现 → doAddHighlight 落库
        function test_selectionToolbarAndAdd() {
            var loader = contentComp.createObject(root)
            loader.width = 800; loader.height = 600
            var c = loader.item
            c.typography = { fontFamily: "Source Han Sans VF", fontSize: 18, lineHeight: 1.6,
                             align: "left", pageWidth: "normal" }
            c.chapter = root.makeChapter()
            c.bookId = 9003
            wait(50)
            c.simulateSelection(2, "第1段第一句。")
            verify(c.selectionToolbar.visible, "选择后工具条应出现")
            compare(c.selSentenceIndex, 2)
            c.doAddHighlight("#FFEB3B")
            var list = Highlights.highlightsForBook(9003)
            verify(list.length === 1 && list[0].sentenceIndex === 2 && list[0].color === "#FFEB3B",
                   "划线应落库（章节/句索引/颜色），实际 " + JSON.stringify(list))
            compare(list[0].chapter, "章")
            verify(!c.selectionToolbar.visible, "划线后工具条应收起")
            loader.destroy()
        }
        // 笔记入口：无划线 → 先建默认色划线，Dialog 填 note → accept → updateNote
        function test_noteDialogAddsNote() {
            var loader = contentComp.createObject(root)
            loader.width = 800; loader.height = 600
            var c = loader.item
            c.typography = { fontFamily: "Source Han Sans VF", fontSize: 18, lineHeight: 1.6,
                             align: "left", pageWidth: "normal" }
            c.chapter = root.makeChapter()
            c.bookId = 9004
            wait(50)
            c.simulateSelection(3, "第二句！")
            c.openNoteDialog()
            verify(c.noteDialog.visible, "笔记 Dialog 应打开")
            c.noteTextArea.text = "好句！"
            c.noteDialog.accept()
            var list = Highlights.highlightsForBook(9004)
            verify(list.length === 1, "笔记入口应先建划线")
            compare(list[0].note, "好句！", "accept 应把笔记写入 updateNote")
            compare(list[0].sentenceIndex, 3)
            loader.destroy()
        }
        // 阅读页集成：笔记列表打开 → 跳转（换章 + 闪烁目标句）→ 划线重载链路
        function test_notesListJump() {
            var book = findTxtBook()
            if (!book) skip("书库无 TXT 书，跳过跳转验证")
            var loader = readerComp.createObject(root)
            loader.setSource("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: book })
            var page = loader.item
            verify(page !== null, "ReaderPage 应能加载")
            tryVerify(function () { return page.chapter.paragraphs && page.chapter.paragraphs.length > 0 }, 5000,
                      "打开应加载章节")
            var hlId = Highlights.addHighlight(book.id, page.chapter.title, 1, "第二行内容", "#FFEB3B", "跳转测试")
            // highlightsChanged → ReaderPage 重载 → content.highlights 注入
            tryVerify(function () {
                var list = Highlights.highlightsForBook(book.id)
                return list.length === 1
            }, 3000)
            page.notesDialog.open()
            verify(page.notesDialog.visible, "笔记列表 Dialog 应打开")
            page.jumpToHighlight({ chapter: page.chapter.title, sentenceIndex: 1 })
            // Dialog 关闭是动画过程，visible 在动画结束前保持 true
            tryVerify(function () { return !page.notesDialog.visible }, 2000,
                      "跳转后笔记列表应收起")
            tryVerify(function () { return page.contentView.flashIndex === 1 }, 3000,
                      "跳转应闪烁目标句，实际 " + page.contentView.flashIndex)
            verify(page.chapter.title === book.title, "跳转后章节应仍为该书章节")
            Highlights.removeHighlight(hlId)
            tryVerify(function () { return Highlights.highlightsForBook(book.id).length === 0 }, 3000,
                      "删除划线后应清空")
            loader.destroy()
        }
    }
}
