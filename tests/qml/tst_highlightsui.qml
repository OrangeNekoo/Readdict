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

    // 30 段 × 2 句：内容高度远大于视口，供工具条滚动定位测试
    function makeTallChapter() {
        var paras = []
        for (var i = 0; i < 30; i++)
            paras.push({ text: "第" + i + "段第一句。第二句！",
                         html: "第" + i + "段第一句。第二句！",
                         level: 0, imagePath: "",
                         sentences: ["第" + i + "段第一句。", "第二句！"] })
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
            // 无引擎桩（openai 无 key）：play/next 只驱动游标不发声
            Tts.reconfigure("openai", "https://api.openai.com/v1", "", "tts-1", "nova", 1.0)
            var all = []
            for (var p of c.chapter.paragraphs)
                for (var s of p.sentences) all.push(s)
            Tts.setSentences(all)
            c.highlights = [{ id: 21, bookId: 1, chapter: "章", sentenceIndex: 2,
                              text: "第1段第一句。", color: "#A5D6A7", note: "" }]
            wait(50)
            // 游标 2（段 1 首句）= 划线句：划线色为底 + 下划线叠加（两类信息都可见）
            Tts.play(); Tts.next(); Tts.next()
            wait(50)
            var t1 = c.paragraphRepeater.itemAt(1).children[0].text.toLowerCase()
            verify(t1.indexOf("background-color:#a5d6a7") >= 0, "划线色应保留，实际 " + t1)
            // 序列化格式：text-decoration 后带空格（Qt 归一化）
            verify(t1.indexOf("text-decoration: underline") >= 0, "朗读游标应以下划线叠加，实际 " + t1)
            // 游标 3（段 1 次句）= 未划线当前句：TTS 黄底
            Tts.next()
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
                  level: 0, imagePath: "", sentences: [] },
                // 多块文档且**末块**为非默认块格式（居中）——applyLineSpacing 若以
                // 末段 blockFormat 为 merge 基础会把居中对齐污染到前一默认块，
                // 序列化后 align="center" 出现 2 次；修复后应保持 1 次（只改行距）
                { text: "默认对齐块。居中块粗体。",
                  html: "<p>默认对齐块。</p><p align=\"center\">居中块<b>粗体</b>。</p>",
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
            // C7 复审：行距 merge 不得覆盖各块自身块格式——居中块的对齐保持，
            // 默认块不被末块格式污染（align="center" 序列化应恰出现 1 次）
            tryVerify(function () { return c.paragraphRepeater.itemAt(1) !== null }, 2000,
                      "多块段落应完成布局")
            var t1 = c.paragraphRepeater.itemAt(1).children[0].text
            var centers = t1.split('align="center"').length - 1
            compare(centers, 1,
                    "行距应用后仅居中块保持对齐（默认块不被污染），实际 align=\"center\" 出现 "
                    + centers + " 次：\n" + t1)
            var t0 = c.paragraphRepeater.itemAt(0).children[0].text
            verify(t0.split('align="center"').length - 1 === 0,
                   "默认段不应被任何块格式污染：\n" + t0)
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
        // C7 复审：工具条视口固定——滚动后仍应在可见区内（selBar 是 contentItem 子项，
        // x/y 绑定叠加 contentY 实现视口固定）
        function test_toolbarStaysInViewportAfterScroll() {
            var loader = contentComp.createObject(root)
            loader.width = 800; loader.height = 600
            var c = loader.item
            c.typography = { fontFamily: "Source Han Sans VF", fontSize: 18, lineHeight: 1.6,
                             align: "left", pageWidth: "normal" }
            c.chapter = root.makeTallChapter()
            wait(50)
            c.contentY = 0
            c.simulateSelection(2, "第1段第一句。")
            verify(c.selectionToolbar.visible, "选择后工具条应出现")
            var tb = c.selectionToolbar
            var vy0 = tb.y - c.contentY
            verify(vy0 >= 0 && vy0 <= c.height - tb.height,
                   "工具条应位于视口内（vy0=" + vy0 + "）")
            c.contentY = 150
            wait(50)
            var vy1 = tb.y - c.contentY
            verify(vy1 >= 0 && vy1 <= c.height - tb.height,
                   "滚动后工具条应仍在视口内（y=" + tb.y + ", contentY=" + c.contentY + "）")
            verify(Math.abs(vy1 - vy0) < 2,
                   "工具条应固定在视口内位置（vy0=" + vy0 + ", vy1=" + vy1 + "）")
            loader.destroy()
        }
        // C7 复审：划线色板展开在工具条正下方（视口固定同步），再点收起
        function test_colorBarPositionedUnderToolbar() {
            var loader = contentComp.createObject(root)
            loader.width = 800; loader.height = 600
            var c = loader.item
            c.typography = { fontFamily: "Source Han Sans VF", fontSize: 18, lineHeight: 1.6,
                             align: "left", pageWidth: "normal" }
            c.chapter = root.makeTallChapter()
            wait(50)
            c.contentY = 0
            c.simulateSelection(2, "第1段第一句。")
            c.toggleColorBar()
            verify(c.colorToolbar.visible, "点划线后色板应展开")
            var cb = c.colorToolbar
            verify(Math.abs(cb.x - c.selectionToolbar.x) < 2,
                   "色板 x 应对齐工具条（cb.x=" + cb.x + ", selBar.x=" + c.selectionToolbar.x + "）")
            verify(cb.y >= c.selectionToolbar.y + c.selectionToolbar.height
                   && cb.y - c.contentY <= c.height - cb.height,
                   "色板应位于工具条下方且在视口内（cb.y=" + cb.y + "）")
            c.toggleColorBar()
            verify(!c.colorToolbar.visible, "再点划线应收起色板")
            loader.destroy()
        }
        // C7 复审：同句重复划线 → 复用行 id 更新颜色，不产生重复行
        function test_duplicateHighlightUpdatesColor() {
            var loader = contentComp.createObject(root)
            loader.width = 800; loader.height = 600
            var c = loader.item
            c.typography = { fontFamily: "Source Han Sans VF", fontSize: 18, lineHeight: 1.6,
                             align: "left", pageWidth: "normal" }
            c.chapter = root.makeChapter()
            c.bookId = 9005
            wait(50)
            c.simulateSelection(2, "第1段第一句。")
            c.doAddHighlight("#FFEB3B")
            var list1 = Highlights.highlightsForBook(9005)
            compare(list1.length, 1)
            // 同句再划另一色 → updateColor 复用行
            c.simulateSelection(2, "第1段第一句。")
            c.doAddHighlight("#F8BBD0")
            var list2 = Highlights.highlightsForBook(9005)
            compare(list2.length, 1, "同句重复划线不应产生重复行")
            compare(list2[0].id, list1[0].id, "应复用原行 id")
            compare(list2[0].color, "#F8BBD0", "颜色应更新为第二次选择")
            Highlights.removeHighlight(list2[0].id)
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
        // C7 二次复审：顶部空间不足（选中句贴近视口顶）→ 工具条翻到选中内容下方，
        // 不再钳到 0 覆盖所选文字；中部选择仍在上方（不回归）
        function test_toolbarFlipsBelowAtTop() {
            var loader = contentComp.createObject(root)
            loader.width = 800; loader.height = 600
            var c = loader.item
            c.typography = { fontFamily: "Source Han Sans VF", fontSize: 18, lineHeight: 1.6,
                             align: "left", pageWidth: "normal" }
            c.chapter = root.makeChapter()
            wait(50)
            c.contentY = 0
            // 首段首句位于视口顶端 → 上方放不下工具条
            c.simulateSelection(0, "第0段第一句。")
            verify(c.selectionToolbar.visible, "选择后工具条应出现")
            var t0 = c.paragraphRepeater.itemAt(0).children[0]
            var txtTopVp = t0.mapToItem(c, 0, 0).y
            verify(c.selBarVpY >= txtTopVp + 6,
                   "顶部无空间时工具条应位于选中内容下方（selBarVpY=" + c.selBarVpY
                   + ", txtTopVp=" + txtTopVp + "）")
            // 中部选择（上方有空间）→ 工具条仍在选中内容上方（既有行为）
            c.chapter = root.makeTallChapter()
            wait(50)
            c.simulateSelection(20, "第10段第一句。")
            var t10 = c.paragraphRepeater.itemAt(10).children[0]
            var txt10TopVp = t10.mapToItem(c, 0, 0).y
            verify(c.selBarVpY <= txt10TopVp - 6,
                   "中部选择工具条应在选中内容上方（selBarVpY=" + c.selBarVpY
                   + ", txt10TopVp=" + txt10TopVp + "）")
            loader.destroy()
        }
        // C7 二次复审：视口底部空间不足 → 色板翻到工具条上方，不与工具条重叠。
        // 说明：真实鼠标拖选无法在 quicktest 合成（选择起点必为段落首字符 → 段落顶
        // ≤ 视口底 - 行高，色板下方恒有空间）；直接构造"工具条贴近视口底"的几何
        // 验证色板翻转绑定公式（selBarVpX/Y 是公开属性，y 绑定依赖它们）。
        function test_colorBarFlipsAboveAtBottom() {
            var loader = contentComp.createObject(root)
            loader.width = 800; loader.height = 600
            var c = loader.item
            c.typography = { fontFamily: "Source Han Sans VF", fontSize: 18, lineHeight: 1.6,
                             align: "left", pageWidth: "normal" }
            c.chapter = root.makeTallChapter()
            wait(50)
            c.selBarVpX = 100
            c.selBarVpY = c.height - 30   // 底部仅剩 30px，放不下 32px 色板 + 4 间距
            c.toggleColorBar()
            verify(c.colorToolbar.visible, "点划线后色板应展开")
            var cb = c.colorToolbar
            var tb = c.selectionToolbar
            verify(cb.y + cb.height <= tb.y + 1,
                   "底部空间不足时色板应翻到工具条上方（cb.y=" + cb.y + ", tb.y=" + tb.y + "）")
            verify(cb.y - c.contentY >= 0 && cb.y + cb.height - c.contentY <= c.height + 1,
                   "色板应整体在视口内（cb.y=" + cb.y + ", contentY=" + c.contentY + "）")
            // 中部工具条：下方空间充足 → 色板仍在工具条下方（既有行为不回归）
            c.selBarVpY = 100
            wait(50)
            verify(cb.y >= tb.y + tb.height && cb.y + cb.height - c.contentY <= c.height,
                   "中部工具条色板应在下方且不超视口（cb.y=" + cb.y + ", tb.y=" + tb.y + "）")
            loader.destroy()
        }
        // C7 二次复审：笔记 Dialog 取消 → 自动创建的默认色划线回滚删除（无残留）；
        // 已有划线时取消 → 原划线保留
        function test_noteDialogCancelRollsBackAutoMarker() {
            var loader = contentComp.createObject(root)
            loader.width = 800; loader.height = 600
            var c = loader.item
            c.typography = { fontFamily: "Source Han Sans VF", fontSize: 18, lineHeight: 1.6,
                             align: "left", pageWidth: "normal" }
            c.chapter = root.makeChapter()
            c.bookId = 9006
            wait(50)
            // 场景 1：无原有划线 → 打开笔记 Dialog（自动建默认色划线）→ 取消 → 回滚
            c.simulateSelection(3, "第二句！")
            c.openNoteDialog()
            verify(c.noteDialog.visible, "笔记 Dialog 应打开")
            compare(Highlights.highlightsForBook(9006).length, 1, "打开 Dialog 应先建默认色划线")
            c.noteDialog.reject()
            tryVerify(function () { return !c.noteDialog.visible }, 2000, "取消后 Dialog 应收起")
            compare(Highlights.highlightsForBook(9006).length, 0,
                    "取消后自动创建的划线应回滚删除（无残留）")
            // 场景 2：已有划线 → 打开笔记 Dialog（不自动创建）→ 取消 → 原划线保留
            c.simulateSelection(2, "第1段第一句。")
            c.doAddHighlight("#FFEB3B")
            compare(Highlights.highlightsForBook(9006).length, 1)
            c.simulateSelection(2, "第1段第一句。")
            c.openNoteDialog()
            c.noteDialog.reject()
            tryVerify(function () { return !c.noteDialog.visible }, 2000, "取消后 Dialog 应收起")
            var rows = Highlights.highlightsForBook(9006)
            compare(rows.length, 1, "已有划线时取消应保留原划线")
            compare(rows[0].color, "#FFEB3B")
            Highlights.removeHighlight(rows[0].id)
            loader.destroy()
        }
        // C7 二次复审：重复 h2 标题章跨章同句索引不再碰撞——章 1 划线不串染章 2 渲染、
        // 章 2 同句划线新建独立行、updateColor 只改本章行（Books 兜底 "第N章"）
        function test_dupTitleChaptersDoNotCollide() {
            if (TestEnv.dupTitlesSource.length === 0) skip("无重复标题书，跳过")
            Importer.doImport(TestEnv.dupTitlesSource)
            var book = null
            for (let b of Books.booksModel)
                if (b.title === "duptitles") { book = b; break }
            if (!book) skip("重复标题书未导入")
            var loader = readerComp.createObject(root)
            loader.setSource("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: book })
            var page = loader.item
            verify(page !== null, "ReaderPage 应能加载")
            tryVerify(function () { return page.chapter.paragraphs && page.chapter.paragraphs.length > 0 }, 5000,
                      "打开应加载章节")
            var cv = page.contentView
            // 章 1（h2 "第一章"）：划线句 1 黄色
            page.loadChapter(1)
            tryVerify(function () { return page.chapter.title === "第一章" }, 3000,
                      "第 2 章标题应为 第一章（首个 h2 保留），实际 " + page.chapter.title)
            tryVerify(function () { return cv.paragraphRepeater.itemAt(1) !== null }, 3000,
                      "章 1 段落应渲染完成")
            cv.simulateSelection(1, "这是第一章的第一段正文。")
            cv.doAddHighlight("#FFEB3B")
            var list1 = Highlights.highlightsForBook(book.id)
            compare(list1.length, 1)
            compare(list1[0].chapter, "第一章")
            compare(list1[0].sentenceIndex, 1)
            // 章 2（重复 h2 → Books 兜底 "第3章"）：同句索引，渲染不得串染章 1 划线色
            page.loadChapter(2)
            tryVerify(function () { return page.chapter.title === "第3章" }, 3000,
                      "重复 h2 章标题应兜底为 第3章，实际 " + page.chapter.title)
            tryVerify(function () {
                var d = cv.paragraphRepeater.itemAt(1)
                return d && d.children[0].text.toLowerCase().indexOf("#ffeb3b") < 0
            }, 3000, "章 2 不应渲染章 1 的划线色（跨章串染）")
            // 章 2 同句再划粉色 → 应新建独立行（而非 updateColor 误改章 1 行）
            cv.simulateSelection(1, "这是第二章的第一段正文。")
            cv.doAddHighlight("#F8BBD0")
            var list2 = Highlights.highlightsForBook(book.id)
            compare(list2.length, 2, "跨章同句应产生两条独立划线行")
            var ch1row = null, ch2row = null
            for (let h of list2) {
                if (h.chapter === "第一章") ch1row = h
                if (h.chapter === "第3章") ch2row = h
            }
            verify(ch1row !== null && ch2row !== null,
                   "两章应各有自己的划线行，实际 " + JSON.stringify(list2))
            compare(ch1row.color, "#FFEB3B", "doAddHighlight 不得误改他章行的颜色")
            compare(ch2row.color, "#F8BBD0")
            verify(ch1row.id !== ch2row.id, "两章行 id 应不同")
            // 显式 updateColor 章 2 行 → 章 1 行颜色不受影响
            Highlights.updateColor(ch2row.id, "#A5D6A7")
            var list3 = Highlights.highlightsForBook(book.id)
            for (let h of list3) {
                if (h.chapter === "第一章") compare(h.color, "#FFEB3B", "updateColor 只改本章行")
                if (h.chapter === "第3章") compare(h.color, "#A5D6A7")
            }
            // 清理：划线 + 书（后续 findTxtBook 用例依赖原有 3 本 TXT）
            for (let h of Highlights.highlightsForBook(book.id)) Highlights.removeHighlight(h.id)
            tryVerify(function () { return Highlights.highlightsForBook(book.id).length === 0 }, 3000,
                      "删除划线后应清空")
            Books.removeBook(book.id)
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
