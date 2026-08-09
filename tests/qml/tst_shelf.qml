import QtQuick
import QtTest
import Readdict.Backend

Item {
    id: root
    width: 1100
    height: 720

    Component {
        id: shelfComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/ShelfPage.qml" }
    }

    TestCase {
        name: "ShelfFilterPersistence"

        function cleanup() {
            Settings.setValue("shelf/category", "")
            Settings.setValue("shelf/sort", 0)
            Settings.setValue("shelf/scope", 0)
            Books.setFilter("")
            Books.setSort(0)
            Books.doSearch("")
        }

        function test_filterValuesSurviveReopen() {
            Settings.setValue("shelf/category", "")
            Settings.setValue("shelf/sort", 3)
            Settings.setValue("shelf/scope", 1)
            var first = shelfComp.createObject(root)
            first.width = root.width
            first.height = root.height
            verify(first.item !== null)
            compare(first.item.currentCategory, "")
            compare(first.item.filterSheet.currentSort, 3)
            compare(first.item.filterSheet.currentScope, 1)
            first.destroy()

            var second = shelfComp.createObject(root)
            second.width = root.width
            second.height = root.height
            verify(second.item !== null)
            compare(second.item.currentCategory, "")
            compare(second.item.filterSheet.currentSort, 3)
            compare(second.item.filterSheet.currentScope, 1)
            second.destroy()
        }
    }
}
