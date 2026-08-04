import QtQuick
import QtTest
import Readdict.Backend

// 冒烟测试：真实 UI 组件可在测试进程中加载（Loader + qrc 资源路径，
// 单例由 tst_qmlmain.cpp 注册）。
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
    TestCase {
        name: "ShelfSmoke"
        function test_shelfLoads() {
            var loader = shelfComp.createObject(root)
            verify(loader.item !== null, "ShelfPage 应能加载")
            loader.destroy()
        }
    }
    TestCase {
        name: "CardSmoke"
        function test_cardLoads() {
            var loader = cardComp.createObject(root)
            verify(loader.item !== null, "BookCard 应能加载（含右键菜单与分类 Dialog 编译检查）")
            loader.item.book = { id: 1, title: "测试书", cover: "", progress: 0.5 }
            loader.destroy()
        }
    }
}
