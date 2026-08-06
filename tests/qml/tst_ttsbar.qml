import QtQuick
import QtTest
import Readdict.Backend

// C5 冒烟：TtsBar（信号/禁用/状态图标）与 ReaderContent 逐句高亮 + 滚动跟随。
// tst_qmlmain 注册的 Tts 为无引擎桩：engineAvailable=false（测试不发声），
// setSentences/seekTo 仍驱动高亮游标与 sentenceChanged。
Item {
    id: root
    width: 1100; height: 720

    Component {
        id: ttsBarComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/TtsBar.qml" }
    }
    Component {
        id: contentComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/ReaderContent.qml" }
    }
    Component {
        id: settingsComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/SettingsPage.qml" }
    }

    TestCase {
        name: "TtsBarSmoke"
        function test_barLoadsDisablesPlayWithoutEngine() {
            // 用例按名称字母序运行：前置用例可能已把 Tts 热切换到真实引擎，
            // 这里显式置为不可用状态（openai 无 key）保证断言确定。
            Tts.reconfigure("openai", "https://api.openai.com/v1", "", "tts-1", "nova", 1.0)
            var loader = ttsBarComp.createObject(root)
            verify(loader.item !== null, "TtsBar 应能加载")
            var bar = loader.item
            bar.bgMode = "light"
            // 根 Rectangle：children[0]=顶部分隔线, children[1]=RowLayout
            var layout = bar.children[1]
            var playBtn = layout.children[1]
            verify(playBtn !== undefined, "播放按钮应存在")
            // 无引擎（openai 未配置 key → engineAvailable=false）→ 播放禁用，状态提示可见
            verify(!Tts.engineAvailable, "未配置 key 的 openai 引擎应不可用")
            compare(playBtn.enabled, false, "引擎不可用时播放按钮应禁用")
            var statusLabel = layout.children[7]
            verify(statusLabel.text.indexOf("不可用") >= 0, "应有引擎不可用提示，实际 " + statusLabel.text)
            // playing 状态切换按钮图标 ⏸/▶
            bar.playing = false
            compare(playBtn.text, "▶")
            bar.playing = true
            compare(playBtn.text, "⏸")
            // 信号接线：点击上一句/下一句/停止应冒泡对应信号
            var got = []
            bar.prevClicked.connect(function () { got.push("prev") })
            bar.nextClicked.connect(function () { got.push("next") })
            layout.children[0].clicked()
            layout.children[3].clicked()
            compare(got.join(","), "prev,next")
            loader.destroy()
        }
    }

    TestCase {
        name: "HighlightSmoke"
        // 40 段 × 2 句：验证 sentenceStarts 计算、逐句高亮 span、滚动跟随
        function makeChapter() {
            var paras = []
            for (var i = 0; i < 40; i++)
                paras.push({ text: "第" + i + "段第一句。第二句！",
                             html: "第" + i + "段第一句。第二句！",
                             level: 0, imagePath: "",
                             sentences: ["第" + i + "段第一句。", "第二句！"] })
            return { title: "章", paragraphs: paras }
        }
        function test_highlightAndScroll() {
            // 前置用例可能已把 Tts 热切换到系统引擎：seekTo 会真实发声。
            // 显式切到 openai 无 key（引擎存在但不可用）→ seekTo 不触发朗读。
            Tts.reconfigure("openai", "https://api.openai.com/v1", "", "tts-1", "nova", 1.0)
            var loader = contentComp.createObject(root)
            loader.width = 800
            loader.height = 600
            var c = loader.item
            c.typography = { fontFamily: "Source Han Sans VF", fontSize: 18, lineHeight: 1.6,
                             align: "left", pageWidth: "normal" }
            c.chapter = makeChapter()
            wait(50)
            // 句子拍平与 ReaderPage 一致：40 段 × 2 句
            var all = []
            for (var p of c.chapter.paragraphs)
                for (var s of p.sentences) all.push(s)
            Tts.setSentences(all)
            compare(c.sentenceStarts.length, 40, "应计算 40 个段落起始索引")
            compare(c.sentenceStarts[1], 2, "第 2 段起始句子索引应为 2")
            compare(c.totalSentences, 80)
            // seekTo(3)：全局句 3 → 段 1 内第 2 句（"第二句！"）应包高亮 span
            Tts.seekTo(3)
            wait(50)
            var d1 = c.paragraphRepeater.itemAt(1)
            verify(d1 !== undefined && d1.children[0] !== undefined, "段 1 委托应存在")
            var t1 = d1.children[0].text
            verify(t1.indexOf("background-color:#FFD54F") >= 0
                   || t1.indexOf("background-color:#ffd54f") >= 0,
                   "段 1 应含高亮 span，实际 " + t1)
            // 当前句应包高亮 span（Qt 富文本会归一化颜色为小写）
            var expectSpan = "<span style='background-color:#ffd54f'>第二句！</span>"
            verify(t1.toLowerCase().indexOf(expectSpan.toLowerCase()) >= 0,
                   "当前句应包高亮 span，实际 " + t1)
            var t0 = c.paragraphRepeater.itemAt(0).children[0].text
            verify(t0.indexOf("FFD54F") < 0, "段 0 不应高亮，实际 " + t0)
            // 滚动跟随：seekTo(40)（段 20）→ contentY 平滑滚到该段（动画 320ms）
            Tts.seekTo(40)
            var item = c.paragraphRepeater.itemAt(20)
            var expected = Math.max(0, Math.min(item.y - c.height / 3,
                                                Math.max(0, c.contentHeight - c.height)))
            tryVerify(function () { return Math.abs(c.contentY - expected) < 2 }, 3000,
                      "应滚动到当前段位置（expected=" + expected + "，实际 " + c.contentY + "）")
            loader.destroy()
        }
    }
    TestCase {
        name: "SettingsTtsSmoke"
        // 设置页 TTS 配置区：选 OpenAI → 填参 → 保存并应用 → Tts.reconfigure 生效
        function test_settingsTtsSaveAndReconfigure() {
            var loader = settingsComp.createObject(root)
            var page = loader.item
            verify(page !== null, "SettingsPage 应能加载（含 TTS 配置区）")
            var layout = page.contentItem.children[0]  // ColumnLayout
            var engineRow = layout.children[5]     // 朗读(TTS) 分区：引擎行
            var engineBox = engineRow.children[1]
            verify(engineBox !== undefined, "引擎 ComboBox 应存在")
            compare(engineBox.currentIndex, 0, "默认引擎应为 system")
            // 切 OpenAI 并填参（假密钥：测试进程内存，不落源码/commit）
            engineBox.currentIndex = 1
            var openaiCol = layout.children[6]
            verify(openaiCol.visible, "OpenAI 配置区应展开")
            openaiCol.children[0].children[1].text = "https://api.openai.com/v1"
            openaiCol.children[1].children[1].text = "sk-test-fake-key"
            openaiCol.children[2].children[1].text = "tts-1"
            openaiCol.children[3].children[1].text = "nova"
            openaiCol.children[4].children[1].text = "1.25"
            page.saveTts()
            compare(String(Settings.value("tts/engine")), "openai", "engine 应持久化")
            compare(String(Settings.value("tts/key")), "sk-test-fake-key", "key 应持久化到 settings.json")
            verify(Tts.engineAvailable, "reconfigure 后 openai（有 key）引擎应可用")
            // 再切回系统引擎：reconfigure 换 SystemTTSEngine
            engineBox.currentIndex = 0
            page.saveTts()
            compare(String(Settings.value("tts/engine")), "system")
            verify(Tts.engineAvailable, "系统引擎应可用")
            loader.destroy()
        }
    }
}
