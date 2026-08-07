import QtQuick
import QtTest
import Readdict.Backend
import Readdict.Test 1.0

// B3：深色背景阅读文字切换为浅色——ReaderContent.textColor 默认深字 #212121，
// ReaderPage 按 bgMode 传色（dark → 浅色 #E0E0E0，light/paper/image → 深字，
// B5：eink → 墨色 #3A3A3A）。
// B5：eink 图片类纸化——纯图段叠加 MultiEffect 降饱和/对比度（见 test_05）。
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

        // dark 下高亮句对比度（B3 复审）：高亮底恒浅色板（划线黄绿粉 / TTS 黄），
        // span 必须追加显式深色前景 color:#212121——否则继承 #E0E0E0 浅字浅底。
        // 覆盖两条路径：划线句（marker）与朗读当前句（TTS 黄底）。
        function test_04_darkHighlightContrast() {
            // 前置用例可能已把 Tts 热切到系统引擎（seekTo 真实发声）：切 openai 无 key
            //（引擎存在但不可用）→ seekTo 仅驱动高亮游标不触发朗读（同 tst_ttsbar 模式）
            Tts.reconfigure("openai", "https://api.openai.com/v1", "", "tts-1", "nova", 1.0)
            var loader = contentComp.createObject(root)
            loader.width = 800; loader.height = 600
            var c = loader.item
            verify(c !== null, "ReaderContent 应能加载")
            c.typography = { fontFamily: "Source Han Sans VF", fontSize: 18, lineHeight: 1.6,
                             align: "left", pageWidth: "normal" }
            c.chapter = root.makeChapter()
            tryVerify(function () { return root.paraEdit(c, 0) !== null }, 2000,
                      "段落委托应渲染完成")
            c.textColor = "#E0E0E0"   // dark 模式：文档默认前景浅色
            // 路径 A：划线句（段 1 全局句 1）→ 高亮 span 应含显式深色前景
            c.highlights = [
                { id: 31, bookId: 1, chapter: "章", sentenceIndex: 1, text: "标题", color: "#A5D6A7", note: "" }
            ]
            wait(50)
            var t1 = root.paraEdit(c, 1).text.toLowerCase()
            verify(t1.indexOf("background-color:#a5d6a7") >= 0 && t1.indexOf("color:#212121") >= 0,
                   "dark 下划线句 span 应含 background-color 与显式 color:#212121，实际 " + t1)
            // 路径 B：朗读当前句（段 0 全局句 0）→ TTS 黄底 span 应含深色前景
            Tts.setSentences(["第一段正文。", "标题", "粗体句。"])
            Tts.seekTo(0)
            wait(50)
            var t0 = root.paraEdit(c, 0).text.toLowerCase()
            verify(t0.indexOf("background-color:#ffd54f") >= 0 && t0.indexOf("color:#212121") >= 0,
                   "dark 下朗读当前句 span 应含 background-color:#ffd54f 与 color:#212121，实际 " + t0)
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
            // B5：eink（彩色墨水屏）→ 墨色 #3A3A3A（类纸文字），段落 TextEdit.color 同步
            page.bgMode = "eink"
            compare(String(cv.textColor), "#3a3a3a", "eink 背景 textColor 应为墨色 #3A3A3A")
            tryVerify(function () {
                return String(root.paraEdit(cv, 1).color) === "#3a3a3a"
            }, 2000, "eink 下富文本段 TextEdit.color 应为 #3A3A3A，实际 "
                     + String(root.paraEdit(cv, 1).color))
            // 再回 dark：绑定持续生效
            page.bgMode = "dark"
            compare(String(cv.textColor), "#e0e0e0", "再切 dark textColor 应回到浅色")
            loader.destroy()
        }

        // B5：eink 图片类纸化——纯图段（imagePath 非空）在 eink 态下叠加 MultiEffect
        // 降饱和 + 对比度（委托 children[2]=imgFx）；非 eink 态效果层隐藏，源图原样显示。
        function test_05_einkImagePaperization() {
            var loader = contentComp.createObject(root)
            loader.width = 800; loader.height = 600
            var c = loader.item
            verify(c !== null, "ReaderContent 应能加载")
            c.typography = { fontFamily: "Source Han Sans VF", fontSize: 18, lineHeight: 1.6,
                             align: "left", pageWidth: "normal" }
            // 纯图段 + 混合段（真实图片文件，TestEnv.backgroundImage 保证可解码；
            // 该值为 file:// URL，ReaderContent 的 Image 会补 file:// 前缀，故取无 scheme 本地路径）
            var img = TestEnv.backgroundImage
            img = img.indexOf("file://") === 0 ? img.slice(7) : img
            c.chapter = { title: "图章", paragraphs: [
                { text: "纯图", html: "", level: 0, imagePath: img, sentences: [] },
                { text: "前文 <img src=\"file://" + img + "\"> 后文。", html: "前文 <img src=\"file://" + img + "\"> 后文。",
                  level: 0, imagePath: img, sentences: ["前文 后文。"] }
            ]}
            tryVerify(function () {
                var d0 = c.paragraphRepeater.itemAt(0)
                return d0 && d0.children[1] !== undefined && d0.children[2] !== undefined
            }, 2000, "纯图段委托应含 Image 与效果层")
            var d0 = c.paragraphRepeater.itemAt(0)
            var d1 = c.paragraphRepeater.itemAt(1)
            verify(d0.pureImage === true, "纯图段 pureImage 应为 true")
            verify(d1.pureImage === false, "混合段 pureImage 应为 false（RichText 渲染）")
            // 默认 light：效果层隐藏（源图原样）
            compare(c.bgMode, "light")
            verify(d0.children[2].visible === false, "非 eink 态效果层应隐藏")
            // eink：效果层可见 + 降饱和/对比度参数
            c.bgMode = "eink"
            verify(d0.children[2].visible === true, "eink 态纯图段效果层应可见")
            compare(String(d0.children[2].saturation), "-0.55", "eink 应降饱和 -0.55")
            compare(String(d0.children[2].contrast), "0.12", "eink 应加对比度 0.12")
            wait(80)   // 渲染若干帧（MultiEffect 在帧上执行），不崩即通过
            // 切回 light：效果层隐藏
            c.bgMode = "light"
            verify(d0.children[2].visible === false, "切回 light 后效果层应隐藏")
            loader.destroy()
        }
    }
}
