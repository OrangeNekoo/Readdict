import QtQuick
import QtQuick.Controls
import QtTest
import Readdict.Backend
import Readdict.Test 1.0

// C1：阅读页回归冒烟（P0 用户反馈：进入书后内容空白 + 无法返回）。
// 回归源（D7 引入）：ReaderControls 被包进 controlsHost 后，ttsBar.anchors.bottom
// 仍锚 `controls.top`——controls 变为 ttsBar 的"非父非兄弟"项，QML 丢弃该锚并告警
// "Cannot anchor to an item that isn't a parent or sibling"。后果：
//   · ttsBar 失去纵向定位 → y=0 骑在顶栏上（半透明白底盖住"返回"按钮、抢走点击）→ 无法返回
//   · content.anchors.bottom: ttsBar.top 解析为 0 → 内容区高度 = 0 → 内容空白
// 本用例锁定三条契约：真实书打开后内容区可见高度 > 0、段落真实渲染出内容高度、
// TtsBar 贴底不压顶栏、返回按钮点击 pop 回书架。
// 结构约定（与 tst_background 一致）：根为带尺寸的 Item，TestCase 是其子项；
// ReaderPage 经 StackView push（生产路径，供返回导航断言）。
Item {
    id: root
    width: 1100; height: 720

    TestCase {
        name: "ReaderNavSmoke"

        function initTestCase() {
            if (Books.booksModel.length === 0)
                for (let f of TestEnv.sourceFiles) Importer.doImport(f)
        }

        function findTxtBook() {
            for (let b of Books.booksModel)
                if ((b.format || "").toUpperCase() === "TXT") return b
            return null
        }

        function test_openBookShowsContentAndBack() {
            var book = findTxtBook()
            verify(book !== null, "测试书应已导入")
            var stack = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; StackView { anchors.fill: parent; }", root)
            verify(stack !== null, "测试 StackView 应能创建")
            // "书架"占位（pop 目标）：真实 ShelfPage 依赖 Books 模型与网格，占位 Item
            // 只验证返回导航链路（ReaderPage pop 回上一页），不重测书架页
            var shelfMarker = Qt.createQmlObject("import QtQuick; Item {}", root)
            verify(shelfMarker !== null)
            stack.push(shelfMarker)
            stack.push("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: book })
            var page = stack.currentItem
            verify(page !== null, "ReaderPage 应被 push 进 StackView")
            // 章节真实加载（loadChapter 经 Books 后端返回段落模型）
            tryVerify(function () {
                return page.chapter && page.chapter.paragraphs
                    && page.chapter.paragraphs.length > 0
            }, 3000, "打开书后应加载章节段落")
            // 内容区可见高度 > 0（内容空白回归锁定点）
            tryVerify(function () { return page.contentView.height > 0 }, 3000,
                      "内容区高度应 > 0，实际 " + page.contentView.height)
            // 段落真实渲染：内容总高 > 0（有可滚动内容）
            tryVerify(function () { return page.contentView.contentHeight > 0 }, 3000,
                      "内容总高度应 > 0，实际 " + page.contentView.contentHeight)
            // 回归源精确锁定：TtsBar 应贴底（y ≈ 高 - 52 控制栏 - 46 朗读条），
            // 而非 y=0 压住顶栏（锚失效回归，见 ttsBar 锚注释）
            verify(page.ttsBar !== undefined, "ReaderPage 应暴露 ttsBar 句柄")
            tryVerify(function () { return page.ttsBar.y > root.height * 0.5 }, 3000,
                      "TtsBar 应位于页面下部，实际 y=" + page.ttsBar.y + "（y=0 即锚失效回归）")
            // 返回链路：顶栏返回按钮可见可点 → pop 回书架
            verify(page.backButton !== undefined, "ReaderPage 应暴露返回按钮句柄")
            verify(page.backButton.visible && page.backButton.enabled,
                   "返回按钮应可见可用（被 TtsBar 遮挡即回归）")
            page.backButton.clicked()
            tryVerify(function () { return stack.currentItem === shelfMarker }, 3000,
                      "点击返回后应 pop 回书架")
            stack.destroy()
            shelfMarker.destroy()
        }
    }
}
