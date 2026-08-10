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
    // 任务 1 复审修复（fixture 隔离）：cleanup 只删除本用例实际导入的
    // alpha/delme（按 id 记录，绝不删除测试前已存在的书），并恢复 alpha 原分类
    //（不再无条件清空）；宽度测试按 model 稳定定位 delegate，断言文本
    // contentItem 实际/隐式宽度——仅 delegate.width>0 不足以证明文字可见。
    TestCase {
        name: "FilterSheetBehavior"

        // 本用例实际导入的 fixture 书 id：cleanup 只删这些，绝不触碰测试前
        // 已存在的书（共享 alpha 被 tst_e2e/tst_readerpage 等依赖，删它会破坏
        // 后续用例；残留的 delme 则会被 findTxtBook 类用例误取为最新 TXT）。
        property var createdBookIds: []
        // alpha 在本用例被改分类前的原值；null = 本用例未修改过（无需恢复）。
        property var alphaCategoryBefore: null

        function titles() {
            return Books.booksModel.map(function (b) { return b.title })
        }

        function findBook(title) {
            for (let b of Books.booksModel)
                if (b.title === title) return b
            return null
        }

        function findBookById(id) {
            for (let b of Books.booksModel)
                if (b.id === id) return b
            return null
        }

        // 每个用例前显式复位：搜索残留（FulltextSmoke 的顶部搜索会把 booksModel
        // 过滤为空）、分类筛选、排序，以及 Settings 的 shelf 分区（筛选面板
        // onCompleted 按 Settings 恢复并写回 Books）。
        function init() {
            createdBookIds = []
            alphaCategoryBefore = null
            Books.doSearch("")
            Books.setFilter("")
            Books.setSort(0)
            Settings.setValue("shelf/category", "")
            Settings.setValue("shelf/sort", 0)
            Settings.setValue("shelf/scope", 0)
        }

        // 每个用例后复原（断言失败也会执行）：先清搜索/筛选，再恢复 alpha 原
        // 分类（本用例改过才恢复），再按 id 删除本用例实际创建的 fixture（若
        // 行已消失则跳过——至少已恢复数据库字段且不留专用 delme），最后复位
        // 排序与 Settings（最后写保证终态不被面板 onBooksChanged 覆盖）。
        function cleanup() {
            Books.doSearch("")
            Books.setFilter("")
            if (alphaCategoryBefore !== null) {
                var alpha = findBook("alpha")
                if (alpha) Books.setCategory(alpha.id, alphaCategoryBefore)
            }
            for (var k = 0; k < createdBookIds.length; k++) {
                var created = findBookById(createdBookIds[k])
                if (created) Books.removeBookWithFiles(created.id, true)
            }
            createdBookIds = []
            alphaCategoryBefore = null
            Books.setSort(0)
            Settings.setValue("shelf/category", "")
            Settings.setValue("shelf/sort", 0)
            Settings.setValue("shelf/scope", 0)
        }

        // 判别书 alpha 与 delme：
        // - alpha：共享书（tst_e2e/tst_readerpage 等依赖其存在），任何测试都不删；
        //   缺失时本用例补导入并把新 id 记入 createdBookIds（cleanup 只删本用例
        //   导入的），已存在则原样使用。
        // - delme：专用测试书（TestEnv.deleteSource 生成，无真实书语义）。可能被
        //   DeleteSmoke 删行+删文件，也可能因外部测试执行顺序而残留；残留先清除
        //   再重导入，保证本用例内 delme 为最新导入 → “最近添加”序的首位由本
        //   用例自控，不依赖外部测试的执行顺序；新 id 记入 createdBookIds，
        //   cleanup 删除后不留专用 delme。
        // mike 不可用：tst_e2e 删行后书库文件副本残留，BookImporter 按
        // “同名文件已存在于书库”拒绝重导入。
        function ensureDiscriminantBooks() {
            Books.doSearch("")
            Books.setFilter("")
            if (findBook("alpha") === null) {
                Importer.doImport(TestEnv.sourceFiles[1])
                var t0 = new Date().getTime()
                while (findBook("alpha") === null && new Date().getTime() - t0 < 5000)
                    wait(50)
                var alpha = findBook("alpha")
                if (alpha) createdBookIds.push(alpha.id)
            }
            var delme = findBook("delme")
            if (delme) Books.removeBookWithFiles(delme.id, true)
            Importer.doImport(TestEnv.deleteSource)
            var t1 = new Date().getTime()
            while (findBook("delme") === null && new Date().getTime() - t1 < 5000)
                wait(50)
            delme = findBook("delme")
            if (delme) createdBookIds.push(delme.id)
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
            var alpha = findBook("alpha")
            verify(alpha !== null, "应能找到 alpha 测试书")
            // 记录原分类，cleanup 恢复——不再无条件清空（alpha 可能是共享书，
            // 测试前已存在的分类属于外部状态，不得销毁）。
            alphaCategoryBefore = alpha.category ?? ""
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
            // alpha 原分类由 cleanup 按 alphaCategoryBefore 恢复，此处不再清空。
            loader.destroy()
        }

        // 布局修复实证：分类/排序/范围列表非零宽度，且每个 delegate 的文本
        // contentItem 实际/隐式宽度 > 0——仅 delegate.width>0 不足以证明文字可见。
        // 按 model 稳定定位真实 delegate（RadioButton）：contentItem.children 含
        // 内部定位 QQuickItem，按 string text 过滤跳过；不硬编码中文文案，
        // 以 list.model 为稳定索引交叉校验每行都有对应 delegate。
        function verifyListDelegatesVisible(sheet, listName) {
            var list = sheet[listName]
            var delegates = []
            tryVerify(function () {
                delegates = []
                var ch = list.contentItem.children
                for (var i = 0; i < ch.length; i++)
                    if (typeof ch[i].text === "string")
                        delegates.push(ch[i])
                return delegates.length === list.count
            }, 3000, listName + " 应实例化全部 " + list.count + " 行 delegate")
            var texts = []
            for (var m = 0; m < delegates.length; m++) {
                var del = delegates[m]
                texts.push(del.text)
                verify(del.width > 0, listName + " delegate 宽度应大于 0，实际 " + del.width)
                verify(del.visible, listName + " delegate 应可见")
                var ci = del.contentItem
                verify(ci !== null, listName + " delegate 应有文本 contentItem")
                verify(ci.width > 0 || ci.implicitWidth > 0,
                       listName + " delegate 文本实际/隐式宽度应大于 0（width=" + ci.width
                       + ", implicitWidth=" + ci.implicitWidth + "）")
            }
            for (var m2 = 0; m2 < list.count; m2++)
                verify(texts.indexOf(list.model[m2]) >= 0,
                       listName + " model 行 " + m2 + " 应存在对应 delegate")
        }

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
            verifyListDelegatesVisible(shelf.filterSheet, "catList")
            verifyListDelegatesVisible(shelf.filterSheet, "sortList")
            verifyListDelegatesVisible(shelf.filterSheet, "scopeList")
            loader.destroy()

            // 800x600（验收窗口）下重新加载，列表与 delegate 文本宽度同样非零
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
            verifyListDelegatesVisible(shelf2.filterSheet, "catList")
            verifyListDelegatesVisible(shelf2.filterSheet, "sortList")
            verifyListDelegatesVisible(shelf2.filterSheet, "scopeList")
            loader2.destroy()
        }
    }
}
