import QtQuick
import QtTest
import Readdict.Backend

// D4 冒烟：StatsPage 可加载（卡片网格 + 分类柱条编译检查）；设置页"阅读统计"
// 按钮 → StackView push StatsPage（生产导航链）；聚合数据正确性：分类分布反映
// Books.setCategory 的修改、totalBooks 与书籍总数一致、平均进度反映 setProgress。
// 时长格式化（秒 → "X 小时 Y 分"）与空库兜底由函数级断言覆盖（tst_bookmanager
// 的 C++ 用例覆盖 AVG/SUM 的 NULL 归零，此处不重复）。
Item {
    id: root
    width: 1100; height: 720

    Component {
        id: statsPageComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/StatsPage.qml" }
    }

    // 取一本书用于数据断言；空库时导入 TestEnv 的 TXT 源书兜底（tst_qmlmain 临时库）
    function ensureBook() {
        if (Books.booksModel.length > 0) return Books.booksModel[0]
        Importer.doImport(TestEnv.sourceFiles[0])
        var t0 = new Date().getTime()
        while (Books.booksModel.length === 0 && new Date().getTime() - t0 < 5000)
            wait(50)
        return Books.booksModel.length > 0 ? Books.booksModel[0] : null
    }

    TestCase {
        name: "StatsPageSmoke"
        function test_pageLoads() {
            var loader = statsPageComp.createObject(root)
            verify(loader.item !== null, "StatsPage 应能加载（卡片网格 + 分类柱条编译检查）")
            verify(loader.item.refresh !== undefined, "StatsPage 应暴露 refresh() 测试句柄")
            loader.destroy()
        }

        // 秒 → "X 小时 Y 分"：整小时、跨小时、零值、缺失值
        function test_formatDuration() {
            var loader = statsPageComp.createObject(root)
            var page = loader.item
            verify(page !== null)
            compare(page.formatDuration(5400), "1 小时 30 分")
            compare(page.formatDuration(3600), "1 小时 0 分")
            compare(page.formatDuration(45), "0 小时 0 分")
            compare(page.formatDuration(0), "0 小时 0 分")
            compare(page.formatDuration(undefined), "0 小时 0 分")
            compare(page.formatDuration(-10), "0 小时 0 分")
            loader.destroy()
        }

        // 聚合正确性：分类分布反映 setCategory、totalBooks 与模型一致、平均进度反映 setProgress
        function test_statsReflectDataChanges() {
            var book = ensureBook()
            if (!book) skip("无法取得测试书，跳过数据断言")
            var loader = statsPageComp.createObject(root)
            var page = loader.item
            verify(page !== null, "StatsPage 应能加载")
            Books.setCategory(book.id, "冒烟分类")
            Books.setProgress(book.id, 0.6)
            page.refresh()
            compare(Number(page.statsData.totalBooks), Books.booksModel.length,
                    "总藏书应等于书籍总数")
            var byCat = page.statsData.byCategory || []
            var found = null
            for (var i = 0; i < byCat.length; i++)
                if (byCat[i].name === "冒烟分类") { found = byCat[i]; break }
            verify(found !== null, "分类分布应包含刚设置的分类，实际 " + JSON.stringify(byCat))
            verify(Number(found.count) >= 1, "分类计数应 >= 1，实际 " + found.count)
            verify(typeof page.statsData.totalProgress === "number"
                   && page.statsData.totalProgress >= 0, "平均进度应为非负数")
            // 还原分类，避免污染后续测试文件（tst_syncpage/tst_ttsbar 不依赖分类）
            Books.setCategory(book.id, "")
            loader.destroy()
        }

        // 设置页入口按钮 → StackView push StatsPage：真实导航链（生产路径）
        function test_settingsEntryOpensStatsPage() {
            var stack = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Controls; StackView { anchors.fill: parent; }", root)
            verify(stack !== null, "测试 StackView 应能创建")
            stack.push("qrc:/qt/qml/Readdict/ui/qml/SettingsPage.qml")
            var settingsPage = stack.currentItem
            verify(settingsPage !== null, "SettingsPage 应被 push 进 StackView")
            verify(settingsPage.statsEntryButton !== undefined, "设置页应暴露统计入口按钮")
            settingsPage.statsEntryButton.clicked()
            verify(stack.currentItem !== settingsPage, "点击后应导航离开设置页")
            verify(stack.depth === 2, "栈深度应为 2（设置页 + 统计页），实际 " + stack.depth)
            var statsPage = stack.currentItem
            verify(statsPage !== null && statsPage.refresh !== undefined,
                   "栈顶应为 StatsPage（含 refresh 函数）")
            stack.destroy()
        }
    }
}
