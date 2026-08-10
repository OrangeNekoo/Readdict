import QtQuick
import QtTest
import Readdict.Backend
import Readdict.Test 1.0

// B3：深色背景阅读文字切换为浅色——ReaderContent.textColor 默认深字（U1 起随
// Token lightTextPrimary #1A1A1A），ReaderPage 按 bgMode 传色（dark → Kindle 深色系
// 浅字 darkTextPrimary #E8E8E3，light/paper/image → 深字 #1A1A1A；E1：旧 eink 值在
// ReaderPage 无分支，按浅底深字处理）。
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

        // 审查修复：任务5 用例级 cleanup——失败路径也复位背景分区，避免污染
        // Settings（background/mode、imagePath、textColor 为任务5读写键）。
        function cleanup() {
            Settings.setValue("background/mode", "light")
            Settings.setValue("background/imagePath", "")
            Settings.setValue("background/textColor", "")
        }

        // 默认浅色：ReaderContent.textColor 默认深字（Token #1A1A1A），段落 TextEdit.color 跟随
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
            compare(String(c.textColor), "#1a1a1a", "默认 textColor 应为深字 #1A1A1A（Token）")
            for (var i = 0; i < 3; i++) {
                var t = root.paraEdit(c, i)
                compare(String(t.color), "#1a1a1a",
                        "段落 " + i + " TextEdit.color 应默认 #1A1A1A，实际 " + String(t.color))
            }
            loader.destroy()
        }

        // 传浅色：textColor 改为 #E8E8E3 后纯文本/富文本段 TextEdit.color 同步更新
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
            c.textColor = "#E8E8E3"
            compare(String(c.textColor), "#e8e8e3", "textColor 应更新为浅色")
            tryVerify(function () {
                for (var i = 0; i < 3; i++) {
                    var t = root.paraEdit(c, i)
                    if (!t || String(t.color) !== "#e8e8e3") return false
                }
                return true
            }, 2000, "纯文本与富文本（含 <h1>）段落 TextEdit.color 都应随 textColor 更新")
            // 切回深字：绑定是双向响应式的
            c.textColor = "#1A1A1A"
            tryVerify(function () {
                return String(root.paraEdit(c, 1).color) === "#1a1a1a"
            }, 2000, "textColor 切回深字后富文本段应同步")
            loader.destroy()
        }

        // dark 下高亮句对比度（B3 复审）：高亮底恒浅色板（划线黄绿粉 / TTS 黄），
        // span 必须追加显式深色前景 color:#212121——否则继承 #E8E8E3 浅字浅底。
        // 覆盖两条路径：划线句（marker）与朗读当前句（TTS 黄底）。
        function test_04_darkHighlightContrast() {
            // 前置用例可能已把 Tts 热切到系统引擎（play 真实发声）：切 openai 无 key
            //（引擎存在但不可用）→ play 仅驱动高亮游标不触发朗读（同 tst_ttsbar 模式）
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
            c.textColor = "#E8E8E3"   // dark 模式：文档默认前景浅色（Token darkTextPrimary）
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
            Tts.play()
            wait(50)
            var t0 = root.paraEdit(c, 0).text.toLowerCase()
            verify(t0.indexOf("background-color:#ffd54f") >= 0 && t0.indexOf("color:#212121") >= 0,
                   "dark 下朗读当前句 span 应含 background-color:#ffd54f 与 color:#212121，实际 " + t0)
            loader.destroy()
        }

        // 任务5：ReaderPage 从 Settings 恢复 background/textColor 并注入正文——
        // 合法值使用（纯文本与富文本一致），非法/缺失回退浅色默认；light/paper/dark
        // 模式不被自定义色污染。
        function test_05_imageTextColorRestoreAndFallback() {
            // 路径 A：image + 合法自定义色 → 恢复并注入
            Settings.setValue("background/mode", "image")
            Settings.setValue("background/textColor", "#FFFFFF")
            var loader = readerComp.createObject(root)
            loader.setSource("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: {} })
            var page = loader.item
            verify(page !== null, "ReaderPage 应能加载")
            page.chapter = root.makeChapter()
            var cv = page.contentView
            tryVerify(function () { return root.paraEdit(cv, 0) !== null }, 2000,
                      "ReaderPage 内段落委托应渲染完成")
            compare(page.bgTextColor, "#FFFFFF", "应从 Settings 恢复自定义文字色")
            compare(String(cv.textColor), "#ffffff", "image 模式 textColor 应使用自定义色")
            tryVerify(function () {
                return String(root.paraEdit(cv, 0).color) === "#ffffff"
                    && String(root.paraEdit(cv, 1).color) === "#ffffff"
            }, 2000, "纯文本与富文本段都应使用自定义色 #FFFFFF")
            loader.destroy()
            // 路径 B：非法值（非安全预设）→ 回退浅色默认
            Settings.setValue("background/textColor", "#ZZZZZZ")
            loader = readerComp.createObject(root)
            loader.setSource("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: {} })
            page = loader.item
            cv = page.contentView
            compare(page.bgTextColor, "", "非法文字色应回退（bgTextColor 置空）")
            compare(String(cv.textColor), "#1a1a1a", "非法文字色应回退浅字 #1A1A1A")
            loader.destroy()
            // 路径 C：缺失值 → 回退浅色默认
            Settings.setValue("background/textColor", "")
            loader = readerComp.createObject(root)
            loader.setSource("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: {} })
            page = loader.item
            cv = page.contentView
            compare(page.bgTextColor, "", "缺失文字色应回退（bgTextColor 置空）")
            compare(String(cv.textColor), "#1a1a1a", "缺失文字色应回退浅字 #1A1A1A")
            loader.destroy()
            // 路径 D：自定义色恢复但不污染其它模式
            Settings.setValue("background/textColor", "#FFFFFF")
            Settings.setValue("background/mode", "light")
            loader = readerComp.createObject(root)
            loader.setSource("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: {} })
            page = loader.item
            cv = page.contentView
            compare(page.bgTextColor, "#FFFFFF", "light 模式仍恢复自定义色（仅存储）")
            compare(String(cv.textColor), "#1a1a1a", "light 模式不被自定义色污染（默认深字）")
            loader.destroy()
            Settings.setValue("background/mode", "paper")
            loader = readerComp.createObject(root)
            loader.setSource("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: {} })
            page = loader.item
            compare(String(page.contentView.textColor), "#1a1a1a",
                    "paper 模式不被自定义色污染（默认深字）")
            loader.destroy()
            Settings.setValue("background/mode", "dark")
            loader = readerComp.createObject(root)
            loader.setSource("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: {} })
            page = loader.item
            compare(String(page.contentView.textColor), "#e8e8e3",
                    "dark 模式不被自定义色污染（默认浅字）")
            loader.destroy()
            // 清理
            Settings.setValue("background/mode", "light")
            Settings.setValue("background/textColor", "")
        }

        // ReaderPage 绑定：bgMode=dark → textColor #E8E8E3；light/paper → 深字；
        // image → 自定义色（background/textColor 恢复值，bgTextColor 属性），
        // 缺失/非法回退浅字；自定义色不污染其它模式（任务5）。
        function test_03_readerPageBgModeBinding() {
            // 隔离：确保无残留自定义色（image 无自定义色 → 回退默认）
            Settings.setValue("background/textColor", "")
            var loader = readerComp.createObject(root)
            loader.setSource("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: {} })
            var page = loader.item
            verify(page !== null, "ReaderPage 应能加载")
            page.chapter = root.makeChapter()
            var cv = page.contentView
            tryVerify(function () { return root.paraEdit(cv, 0) !== null }, 2000,
                      "ReaderPage 内段落委托应渲染完成")
            // 默认浅色
            compare(String(cv.textColor), "#1a1a1a", "默认（light）textColor 应为深字")
            // dark → 浅色，段落 TextEdit.color 同步
            page.bgMode = "dark"
            compare(String(cv.textColor), "#e8e8e3", "dark 背景 textColor 应为浅色 #E8E8E3")
            tryVerify(function () {
                return String(root.paraEdit(cv, 1).color) === "#e8e8e3"
            }, 2000, "dark 下富文本段 TextEdit.color 应为 #E8E8E3，实际 "
                     + String(root.paraEdit(cv, 1).color))
            // paper（米白浅底）→ 深字
            page.bgMode = "paper"
            compare(String(cv.textColor), "#1a1a1a", "paper 背景 textColor 应为深字")
            // image 且无自定义色 → 回退深字（浅色处理取舍）
            page.bgMode = "image"
            compare(String(cv.textColor), "#1a1a1a", "image 无自定义色时应回退深字 #1A1A1A")
            tryVerify(function () {
                return String(root.paraEdit(cv, 0).color) === "#1a1a1a"
            }, 2000, "image 下纯文本段 TextEdit.color 应为 #1A1A1A")
            // image + 合法自定义色（background/textColor 恢复值）→ 使用该色
            page.bgTextColor = "#FFFFFF"
            compare(String(cv.textColor), "#ffffff", "image 有自定义色时 textColor 应使用该色")
            tryVerify(function () {
                return String(root.paraEdit(cv, 0).color) === "#ffffff"
                    && String(root.paraEdit(cv, 1).color) === "#ffffff"
            }, 2000, "自定义色应同时注入纯文本与富文本段（TextEdit.color #FFFFFF）")
            // 自定义色不污染其它模式：切 light/paper/dark 仍用各自默认色
            page.bgMode = "light"
            compare(String(cv.textColor), "#1a1a1a", "自定义色不应污染 light（默认深字）")
            page.bgMode = "dark"
            compare(String(cv.textColor), "#e8e8e3", "自定义色不应污染 dark（默认浅字）")
            page.bgMode = "image"
            compare(String(cv.textColor), "#ffffff", "回 image 应恢复自定义色")
            // E1：旧 eink 值在 ReaderPage 无分支 → 按浅底深字处理（textColor #1A1A1A）
            page.bgMode = "eink"
            compare(String(cv.textColor), "#1a1a1a", "旧 eink 值应回退浅底深字 #1A1A1A")
            tryVerify(function () {
                return String(root.paraEdit(cv, 1).color) === "#1a1a1a"
            }, 2000, "旧 eink 值下富文本段 TextEdit.color 应为 #1A1A1A，实际 "
                     + String(root.paraEdit(cv, 1).color))
            // 再回 dark：绑定持续生效
            page.bgMode = "dark"
            compare(String(cv.textColor), "#e8e8e3", "再切 dark textColor 应回到浅色")
            loader.destroy()
        }

        // C5：Kindle 默认衬线感 + 书本栏宽——未指定 typography.fontFamily 时正文回退
        // 思源宋体（衬线）；正文列宽有 700px 上限（宽窗口保持书本比例，居中于窗口）。
        function test_06_kindleSerifDefault() {
            var loader = contentComp.createObject(root)
            loader.width = 1400; loader.height = 600
            var c = loader.item
            verify(c !== null, "ReaderContent 应能加载")
            // 不设 typography（保持默认 {}）→ fontFamily 缺省回退衬线
            c.chapter = root.makeChapter()
            tryVerify(function () { return root.paraEdit(c, 0) !== null }, 2000,
                      "段落委托应渲染完成")
            var t0 = root.paraEdit(c, 0)
            compare(t0.font.family, "思源宋体 VF",
                    "未指定字体时正文应回退思源宋体（Kindle 衬线感），实际 " + t0.font.family)
            // 列宽钳制：1400 宽 × normal(0.7) = 980 > 700 → 应钳到 700 并居中
            var col = c.contentItem.children[0]   // Column（Flickable contentItem 首子项）
            tryVerify(function () { return Math.abs(col.width - 700) < 1 }, 2000,
                      "正文列宽应钳制在 normal 档 700px 上限，实际 " + col.width)
            verify(Math.abs(col.x + col.width / 2 - c.width / 2) < 1,
                   "正文列应水平居中于窗口")
            // C5 复审：档位上限递增（520/700/880）——宽窗下三档仍可区分（页宽切换不失效）
            c.typography = { fontFamily: "思源宋体 VF", fontSize: 18, lineHeight: 1.6,
                             align: "left", pageWidth: "wide" }
            tryVerify(function () { return Math.abs(col.width - 880) < 1 }, 2000,
                      "wide 档应钳到 880px，实际 " + col.width)
            c.typography = { fontFamily: "思源宋体 VF", fontSize: 18, lineHeight: 1.6,
                             align: "left", pageWidth: "narrow" }
            tryVerify(function () { return Math.abs(col.width - 520) < 1 }, 2000,
                      "narrow 档应钳到 520px，实际 " + col.width)
            loader.destroy()
        }
    }
}
