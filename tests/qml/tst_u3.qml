import QtQuick
import QtQuick.Controls
import QtTest
import Readdict.Backend
import Readdict.Test
import Readdict.UI 1.0

// U3 冒烟：筛选面板按值持久化、顶部搜索迁移后的全文范围、以及书卡角标。
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

    function cleanup() {
        Settings.setValue("shelf/category", "")
        Settings.setValue("shelf/sort", 0)
        Settings.setValue("shelf/scope", 0)
        Books.setFilter("")
        Books.setSort(0)
        Books.doSearch("")
    }

    TestCase {
        name: "CardKindleSmoke"
        function test_kindleCardStyleAndBadges() {
            var loader = cardComp.createObject(root)
            verify(loader.item !== null, "BookCard 应能加载")
            var card = loader.item
            card.book = {
                id: 1, title: "测试书", author: "作者", cover: "",
                progress: 0.5, addedAt: "2020-01-01T00:00:00Z"
            }
            wait(50)
            compare(card.coverClip.radius, 0, "封面剪裁块应无圆角")
            compare(card.cardChrome.radius, 0, "卡片底应无圆角")
            verify(card.cardChrome.border.color.a === 0, "卡片不应有边框")
            compare(card.coverShadow.color, UITheme.shadowBook)
            var ratio = card.coverClip.height / card.coverClip.width
            verify(Math.abs(ratio - 4 / 3) < 0.01, "封面应为 3:4")
            compare(card.cardTitle.font.pixelSize, UITheme.fsListItem)
            verify(card.progressBadge.visible, "未读完书应显示进度角标")
            compare(card.progressBadgeLabel.text, "50%")
            card.book = { id: 1, title: "新书", progress: 0,
                          addedAt: new Date(Date.now() - 2 * 86400000).toISOString() }
            wait(20)
            verify(card.newBadge.visible, "七天内且未读的书应显示新书角标")
            verify(!card.progressBadge.visible, "新书不应同时显示进度角标")
            loader.destroy()
        }
    }

    TestCase {
        name: "FilterSheetSmoke"
        function cleanup() {
            Settings.setValue("shelf/category", "")
            Settings.setValue("shelf/sort", 0)
            Settings.setValue("shelf/scope", 0)
            Books.setFilter("")
            Books.setSort(0)
            Books.doSearch("")
        }

        function test_filterButtonAndValuePersistence() {
            var loader = shelfComp.createObject(root)
            loader.width = root.width
            loader.height = root.height
            var shelf = loader.item
            verify(shelf !== null, "ShelfPage 应能加载")
            verify(shelf.filterSheet !== undefined, "ShelfPage 应暴露 filterSheet")
            verify(shelf.filterSheet.catList !== undefined, "应暴露分类列表句柄")
            verify(shelf.filterSheet.sortList !== undefined, "应暴露排序列表句柄")
            verify(shelf.filterSheet.scopeList !== undefined, "应暴露搜索范围列表句柄")
            shelf.filterSheet.open()
            verify(shelf.filterSheet.visible, "筛选面板应能打开")
            shelf.filterSheet.scopeList.currentIndex = 1
            shelf.filterSheet.sortList.currentIndex = 2
            compare(String(Settings.value("shelf/scope")), "1")
            compare(Number(Settings.value("shelf/sort")), 2)
            shelf.filterSheet.close()
            verify(!shelf.filterSheet.visible, "close 应隐藏面板")
            loader.destroy()

            var loader2 = shelfComp.createObject(root)
            loader2.width = root.width
            loader2.height = root.height
            var shelf2 = loader2.item
            tryVerify(function () {
                return shelf2.filterSheet.currentScope === 1
                       && shelf2.filterSheet.currentSort === 2
            }, 2000, "重开页面应恢复排序与搜索范围")
            loader2.destroy()
        }

        function test_categoryPersistenceAndInvalidation() {
            if (Books.booksModel.length === 0)
                skip("书库为空，跳过分类按值回归")
            const id = Books.booksModel[0].id
            Books.setCategory(id, "U3持久分类")
            Settings.setValue("shelf/category", "U3持久分类")
            var loader = shelfComp.createObject(root)
            loader.width = root.width
            loader.height = root.height
            var shelf = loader.item
            tryVerify(function () { return shelf.currentCategory === "U3持久分类" }, 2000,
                      "重开页面应按值恢复分类")
            tryVerify(function () {
                return shelf.filterSheet.catList.currentIndex
                       === Books.categoriesModel.indexOf("U3持久分类") + 1
            }, 2000, "分类模型变化后索引应按值定位")
            Books.setCategory(id, "")
            tryVerify(function () { return shelf.currentCategory === "" }, 2000,
                      "分类删除后应清空无效筛选")
            compare(String(Settings.value("shelf/category")), "")
            compare(shelf.filterSheet.catList.currentIndex, 0,
                    "分类删除后应选中全部")
            loader.destroy()
        }
    }

    // 任务 1：筛选面板真实行为——排序选择改变 booksModel 顺序、分类选择过滤
    // booksModel 内容、排序/范围选项 delegate 宽度非零（布局修复的实证）。
    // 任务 1 复审修复：用例级 init/cleanup 显式复位 Books/Settings 状态（排序/
    // 分类用例不再依赖全量套件的执行顺序）；排序/分类选择经真实 delegate 点击
    // 触发（覆盖用户点击路径而非直接赋 currentIndex）。
    TestCase {
        name: "FilterSheetBehavior"

        function titles() {
            return Books.booksModel.map(function (b) { return b.title })
        }

        // 每个用例前显式复位：搜索残留（FulltextSmoke 的顶部搜索会把 booksModel
        // 过滤为空）、分类筛选、排序，以及 Settings 的 shelf 分区（筛选面板
        // onCompleted 按 Settings 恢复并写回 Books）。
        function init() {
            Books.doSearch("")
            Books.setFilter("")
            Books.setSort(0)
            Settings.setValue("shelf/category", "")
            Settings.setValue("shelf/sort", 0)
            Settings.setValue("shelf/scope", 0)
        }

        // 每个用例后复原（断言失败也会执行）：先清搜索/筛选，再清本用例可能
        // 残留的测试分类，最后复位排序与 Settings。
        function cleanup() {
            Books.doSearch("")
            Books.setFilter("")
            for (let b of Books.booksModel)
                if (b.category === "筛选行为测试分类")
                    Books.setCategory(b.id, "")
            Books.setSort(0)
            Settings.setValue("shelf/category", "")
            Settings.setValue("shelf/sort", 0)
            Settings.setValue("shelf/scope", 0)
        }

        // 判别书 alpha 与 delme：
        // - alpha：任何测试都不删除（行+书库文件均存活）；缺失时补导入，已有则跳过。
        // - delme：可能被 DeleteSmoke 删行+删文件（可直接重导入），也可能因外部
        //   测试执行顺序而残留（先 removeBookWithFiles 删行+删文件再重导入）。
        //   两种情况下 delme 都是本用例内最新导入的书 → “最近添加”序的首位由
        //   本用例自控，不依赖外部测试的执行顺序。
        // mike 不可用：tst_e2e 删行后书库文件副本残留，BookImporter 按
        // “同名文件已存在于书库”拒绝重导入。
        function ensureDiscriminantBooks() {
            Books.doSearch("")
            Books.setFilter("")
            if (titles().indexOf("alpha") < 0) {
                Importer.doImport(TestEnv.sourceFiles[1])
                var t0 = new Date().getTime()
                while (titles().indexOf("alpha") < 0 && new Date().getTime() - t0 < 5000)
                    wait(50)
            }
            var delme = null
            for (let b of Books.booksModel)
                if (b.title === "delme") { delme = b; break }
            if (delme) Books.removeBookWithFiles(delme.id, true)
            Importer.doImport(TestEnv.deleteSource)
            var t1 = new Date().getTime()
            while (titles().indexOf("delme") < 0 && new Date().getTime() - t1 < 5000)
                wait(50)
        }

        // 选择排序后 booksModel 顺序真实改变：delme 由 ensureDiscriminantBooks 在
        // 本用例内重导入，必为“最近添加”序首位（alpha 在其后，由本用例自控，
        // 不依赖外部执行顺序）；经真实 delegate 点击“作者”（author 全空 →
        // ORDER BY author,title 升序）→ alpha 排到 delme 之前。
        function test_sortSelectionReordersBooksModel() {
            ensureDiscriminantBooks()
            var t0 = titles()
            verify(t0.indexOf("alpha") >= 0 && t0.indexOf("delme") >= 0,
                   "判别书应就绪，实际 " + t0.join(","))
            verify(t0.indexOf("delme") < t0.indexOf("alpha"),
                   "本用例重导入的 delme 应为最近添加（在 alpha 之前），实际 " + t0.join(","))
            var loader = shelfComp.createObject(root)
            loader.width = root.width
            loader.height = root.height
            var shelf = loader.item
            verify(shelf !== null, "ShelfPage 应能加载")
            shelf.filterSheet.open()
            // ListView.contentItem.children 含一个内部 QQuickItem（位置不固定）
            // 且 delegate 渐进实例化，不能按下标映射；按文本轮询定位“作者”
            // delegate，再经 clicked() 真实触发选择（覆盖用户点击路径）。
            var authorDelegate = null
            tryVerify(function () {
                var ch = shelf.filterSheet.sortList.contentItem.children
                for (var i = 0; i < ch.length; i++)
                    if (ch[i].text === "作者") { authorDelegate = ch[i]; return true }
                return false
            }, 3000, "排序列表应含“作者”delegate")
            authorDelegate.clicked()
            tryVerify(function () {
                var t = titles()
                return t.indexOf("alpha") < t.indexOf("delme")
            }, 3000, "选择作者排序后 alpha 应排在 delme 之前，实际 " + titles().join(","))
            compare(Number(Settings.value("shelf/sort")), 1, "排序选择应持久化")
            loader.destroy()
        }

        // 选择分类后 booksModel 只含该分类的书（Books.setFilter 真实过滤）。
        // 先清空搜索/筛选残留（防 titles() 被外部残留过滤），并经真实 delegate
        // 的 clicked() 触发选择（覆盖用户点击路径），再断言 booksModel。
        function test_categorySelectionFiltersBooksModel() {
            Books.doSearch("")
            Books.setFilter("")
            ensureDiscriminantBooks()
            var alpha = null
            for (let b of Books.booksModel)
                if (b.title === "alpha") { alpha = b; break }
            verify(alpha !== null, "应能找到 alpha 测试书")
            Books.setCategory(alpha.id, "筛选行为测试分类")
            var loader = shelfComp.createObject(root)
            loader.width = root.width
            loader.height = root.height
            var shelf = loader.item
            verify(shelf !== null, "ShelfPage 应能加载")
            shelf.filterSheet.open()
            var catIdx = Books.categoriesModel.indexOf("筛选行为测试分类") + 1
            verify(catIdx > 0, "分类应出现在 categoriesModel")
            // 同排序列表：children 含内部 QQuickItem 且 delegate 渐进实例化，
            // 按文本轮询定位“筛选行为测试分类”delegate 再经 clicked() 触发选择。
            var categoryDelegate = null
            tryVerify(function () {
                var ch = shelf.filterSheet.catList.contentItem.children
                for (var i = 0; i < ch.length; i++)
                    if (ch[i].text === "筛选行为测试分类") { categoryDelegate = ch[i]; return true }
                return false
            }, 3000, "分类列表应含“筛选行为测试分类”delegate")
            categoryDelegate.clicked()
            tryVerify(function () {
                var t = titles()
                return t.length === 1 && t[0] === "alpha"
            }, 3000, "选择分类后 booksModel 应只含该分类的书，实际 " + titles().join(","))
            Books.setCategory(alpha.id, "")
            Books.setFilter("")
            loader.destroy()
        }

        // 布局修复实证：分类/排序/范围列表非零宽度，delegate 宽度跟随列表（>0）。
        function test_sortAndScopeDelegatesHaveVisibleWidth() {
            var loader = shelfComp.createObject(root)
            loader.width = root.width
            loader.height = root.height
            var shelf = loader.item
            verify(shelf !== null, "ShelfPage 应能加载")
            shelf.filterSheet.open()
            tryVerify(function () {
                return shelf.filterSheet.catList.width > 0
                       && shelf.filterSheet.sortList.width > 0
                       && shelf.filterSheet.scopeList.width > 0
            }, 3000, "分类/排序/范围列表宽度应非零")
            var names = ["catList", "sortList", "scopeList"]
            for (var n = 0; n < names.length; n++) {
                var list = shelf.filterSheet[names[n]]
                var children = list.contentItem.children
                verify(children.length > 0, names[n] + " 应有 delegate 实例")
                for (var i = 0; i < children.length; i++)
                    verify(children[i].width > 0,
                           names[n] + " 选项 delegate 宽度应大于 0，实际 " + children[i].width)
            }
            loader.destroy()

            // 800x600（验收窗口）下重新加载，列表与 delegate 宽度同样非零
            var loader2 = shelfComp.createObject(root)
            loader2.width = 800
            loader2.height = 600
            var shelf2 = loader2.item
            verify(shelf2 !== null, "800x600 下 ShelfPage 应能加载")
            shelf2.filterSheet.open()
            tryVerify(function () {
                return shelf2.filterSheet.catList.width > 0
                       && shelf2.filterSheet.sortList.width > 0
                       && shelf2.filterSheet.scopeList.width > 0
            }, 3000, "800x600 下分类/排序/范围列表宽度应非零")
            for (var n2 = 0; n2 < names.length; n2++) {
                var list2 = shelf2.filterSheet[names[n2]]
                var children2 = list2.contentItem.children
                verify(children2.length > 0, names[n2] + " 800x600 下应有 delegate 实例")
                for (var j = 0; j < children2.length; j++)
                    verify(children2[j].width > 0,
                           names[n2] + " 800x600 下选项 delegate 宽度应大于 0，实际 " + children2[j].width)
            }
            loader2.destroy()
        }
    }
}
