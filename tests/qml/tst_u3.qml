import QtQuick
import QtQuick.Controls
import QtTest
import Readdict.Backend
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
            Books.setCategory(id, "")
            tryVerify(function () { return shelf.currentCategory === "" }, 2000,
                      "分类删除后应清空无效筛选")
            compare(String(Settings.value("shelf/category")), "")
            compare(shelf.filterSheet.catList.currentIndex, 0,
                    "分类删除后应选中全部")
            loader.destroy()
        }
    }
}
