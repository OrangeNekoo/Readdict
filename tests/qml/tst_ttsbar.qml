import QtQuick
import QtTest
import Readdict.Backend

// C5 冒烟：TtsBar（信号/禁用/状态图标）与 ReaderContent 逐句高亮 + 滚动跟随。
// tst_qmlmain 注册的 Tts 初始无引擎；用例内切 openai 无 key（引擎存在但不可用）
// 后 play/next 只驱动高亮游标与 sentenceChanged，不发声。
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
            // 前置用例可能已把 Tts 热切换到系统引擎：play/next 会真实发声。
            // 显式切到 openai 无 key（引擎存在但不可用）→ play/next 不触发朗读。
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
            // D2：未朗读（state=0，游标复位 0）首句不应黄标——TTS 黄底仅朗读会话激活
            //（显式 stop 兜底：前置用例可能已把 state 置非 0）
            Tts.stop()
            wait(50)
            var tPre = c.paragraphRepeater.itemAt(0).children[0].text
            verify(tPre.toLowerCase().indexOf("#ffd54f") < 0,
                   "未朗读时首句不应出现 TTS 黄底（D2），实际 " + tPre)
            // play + 3×next 驱动游标到全局句 3 → 段 1 内第 2 句（"第二句！"）应包高亮 span
            Tts.play()
            Tts.next(); Tts.next(); Tts.next()
            wait(50)
            var d1 = c.paragraphRepeater.itemAt(1)
            verify(d1 !== undefined && d1.children[0] !== undefined, "段 1 委托应存在")
            var t1 = d1.children[0].text
            verify(t1.indexOf("background-color:#FFD54F") >= 0
                   || t1.indexOf("background-color:#ffd54f") >= 0,
                   "段 1 应含高亮 span，实际 " + t1)
            // 当前句应包高亮 span（C7 起段落用只读 TextEdit 渲染：text 返回序列化 HTML——
            // 双引号属性、颜色小写、分号结尾，语义不变：当前句带 #FFD54F 背景；
            // B3 复审起高亮 span 追加显式深色前景 color:#212121，浅底恒深字）
            var expectSpan = "<span style=\" color:#212121; background-color:#ffd54f;\">第二句！</span>"
            verify(t1.toLowerCase().indexOf(expectSpan) >= 0,
                   "当前句应包高亮 span，实际 " + t1)
            var t0 = c.paragraphRepeater.itemAt(0).children[0].text
            verify(t0.indexOf("FFD54F") < 0, "段 0 不应高亮，实际 " + t0)
            // 滚动跟随：游标推进到全局句 40（段 20）→ contentY 平滑滚到该段（动画 320ms）
            for (var k = 0; k < 37; k++) Tts.next()
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
        // U5：设置页 TTS 配置迁入子页——列表行（KdListItem 样式/chevron）→
        // push SettingsTtsPage → 驱动引擎/参数/语速档位 → 保存并应用 → reconfigure 生效
        function test_settingsTtsSaveAndReconfigure() {
            // 经真实 StackView 驱动子页导航（同 tst_syncpage/tst_statspage 模式）
            var stack = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; StackView { width: 1100; height: 720 }",
                root, "ttsStack")
            stack.push("qrc:/qt/qml/Readdict/ui/qml/SettingsPage.qml")
            var page = stack.currentItem
            verify(page !== null, "SettingsPage 应能加载（含 TTS 入口行）")
            // U5 列表结构：settingsLayout 直接子项 = 7 行 + 版本标签（children[0..7]）
            var layout = page.settingsLayout
            var ttsRow = layout.children[2]     // 0=深色 1=语言 2=朗读(TTS) …
            verify(ttsRow !== undefined, "TTS 列表行应存在")
            compare(ttsRow.text, "朗读（TTS）", "TTS 行主文案")
            compare(ttsRow.textLabel.font.pixelSize, 15, "列表项文字应为 fsListItem 15px（Kindle §7）")
            verify(ttsRow.chevronIcon.visible, "进入子页的行应显示右箭头 chevron")
            // 点击 TTS 行 → push SettingsTtsPage
            page.ttsEntryButton.clicked()
            var ttsPage = stack.currentItem
            verify(ttsPage !== page, "点击 TTS 行应推入 TTS 子页")
            compare(ttsPage.ttsEngineBox.currentIndex, 0, "默认引擎应为 system")
            // 切 OpenAI 并填参（假密钥：测试进程内存，不落源码/commit）
            ttsPage.ttsEngineBox.currentIndex = 1
            ttsPage.ttsUrlField.text = "https://api.openai.com/v1"
            ttsPage.ttsKeyField.text = "sk-test-fake-key"
            ttsPage.ttsModelField.text = "tts-1"
            ttsPage.ttsVoiceField.text = "nova"
            ttsPage.ttsSpeedField.text = "1.25"
            // U5：语速快速档位（KdSegmentedSlider）——选中 1.5 应回写字段
            verify(ttsPage.rateSlider !== undefined, "语速分段滑块句柄应存在")
            ttsPage.rateSlider.selectValue(1.5)
            compare(ttsPage.ttsSpeedField.text, "1.5", "段选择应写入语速字段")
            ttsPage.saveTts()
            compare(String(Settings.value("tts/engine")), "openai", "engine 应持久化")
            compare(String(Settings.value("tts/key")), "sk-test-fake-key", "key 应持久化到 settings.json")
            compare(Number(Settings.value("tts/rate")), 1.5, "语速 1.5 应持久化")
            verify(Tts.engineAvailable, "reconfigure 后 openai（有 key）引擎应可用")
            // 再切回系统引擎：reconfigure 换 SystemTTSEngine（无系统语音的宿主上
            // 不可用属正常，仅在存在语音时断言可用）
            ttsPage.ttsEngineBox.currentIndex = 0
            ttsPage.saveTts()
            compare(String(Settings.value("tts/engine")), "system")
            if (Tts.voices.length > 0)
                verify(Tts.engineAvailable, "有系统语音时引擎应可用")
            // 子页返回：goBack/返回按钮 → pop 回设置页
            ttsPage.backButton.clicked()
            verify(stack.currentItem === page, "TTS 子页返回应 pop 回设置页")
            stack.destroy()
        }
    }
}
