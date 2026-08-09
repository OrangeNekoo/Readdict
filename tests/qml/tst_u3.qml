import QtQuick
import QtQuick.Controls
import QtTest
import Readdict.Backend
import Readdict.UI 1.0

// U3 冒烟：书架页 Kindle 化——封面网格（3:4 无圆角/轻投影 shadowBook/无边框/
// 标题 fsListItem）、搜索胶囊（bgSearch 全圆角 + 内嵌图标）、分类入口（工具栏
// catFilter 下拉替代原 160px 左侧栏：选分类 → Books.setFilter 生效、选"全部"复位）。
// 既有后端接口（Books.setFilter/setCategory）与功能行为不变，仅 UI 迁移。
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
        name: "CardKindleSmoke"
        // U3：封面网格 Kindle 化样式断言——无圆角、轻投影 shadowBook、无卡片边框、
        // 封面 3:4、标题 15px（fsListItem）、作者 textSecondary
        function test_kindleCardStyle() {
            var loader = cardComp.createObject(root)
            verify(loader.item !== null, "BookCard 应能加载")
            var card = loader.item
            card.book = { id: 1, title: "测试书", author: "作者", cover: "", progress: 0.5 }
            wait(50)
            // 无圆角（Kindle 封面直角）
            compare(card.coverClip.radius, 0, "封面剪裁块应无圆角")
            compare(card.cardChrome.radius, 0, "卡片底应无圆角")
            // 无卡片边框
            verify(card.cardChrome.border.color.a === 0,
                   "卡片不应有边框（border 透明），实际 alpha=" + card.cardChrome.border.color.a)
            // 轻投影：shadowBook rgba(0,0,0,0.08)
            compare(card.coverShadow.color, UITheme.shadowBook,
                    "封面投影色应为 UITheme.shadowBook")
            // 封面 3:4
            var ratio = card.coverClip.height / card.coverClip.width
            verify(Math.abs(ratio - 4 / 3) < 0.01,
                   "封面应为 3:4（实际 " + ratio.toFixed(3) + "，" +
                   card.coverClip.width + "x" + card.coverClip.height + "）")
            // 标题下置 15px（fsListItem Token）
            compare(card.cardTitle.font.pixelSize, UITheme.fsListItem,
                    "标题字号应为 fsListItem")
            loader.destroy()
        }
    }

    TestCase {
        name: "SearchBoxSmoke"
        // U3：搜索胶囊——全圆角（~20px 即高度一半）+ bgSearch 浅灰底 + 内嵌放大镜图标
        function test_searchPillStyle() {
            var loader = shelfComp.createObject(root)
            var shelf = loader.item
            verify(shelf !== null, "ShelfPage 应能加载")
            verify(shelf.searchBox !== undefined, "ShelfPage 应暴露 searchBox 句柄")
            compare(shelf.searchBox.color, UITheme.bgSearch, "搜索框底色应为 bgSearch")
            compare(shelf.searchBox.radius, 18, "搜索框应全圆角（高度 36 → radius 18）")
            compare(shelf.searchIcon.text, "⌕", "搜索框应内嵌放大镜图标")
            // 输入路径仍可用（FulltextSmoke 依赖 searchField 句柄）
            shelf.searchField.text = "zeta"
            compare(shelf.searchField.text, "zeta", "searchField 输入应正常")
            loader.destroy()
        }
    }

    TestCase {
        name: "CategoryEntrySmoke"
        // U3：分类入口（工具栏下拉替代原左侧栏）——分类选中 → Books.setFilter 过滤网格、
        // "全部"复位；Books.setFilter 接口行为不变
        function test_categoryFilterViaToolbar() {
            var loader = shelfComp.createObject(root)
            var shelf = loader.item
            verify(shelf !== null, "ShelfPage 应能加载")
            verify(shelf.catFilter !== undefined, "ShelfPage 应暴露 catFilter 句柄")
            var all = Books.booksModel.length
            if (all === 0)
                skip("书库为空，跳过分类入口验证")
            var book = Books.booksModel[0]
            Books.setCategory(book.id, "U3分类")
            // categoriesModel 派生刷新 → 下拉模型应出现该分类（绑定随 booksChanged 重算）
            tryVerify(function () { return shelf.catFilter.model.indexOf("U3分类") >= 0 }, 3000,
                      "新建分类应出现在分类下拉，实际模型 " + JSON.stringify(shelf.catFilter.model))
            var idx = shelf.catFilter.model.indexOf("U3分类")
            shelf.catFilter.currentIndex = idx
            shelf.catFilter.activated(idx) // 同 tst_language 模式：信号调用触发 onActivated
            tryVerify(function () {
                return Books.booksModel.length === 1
                       && Books.booksModel[0].category === "U3分类"
            }, 3000, "选中分类后网格应只剩该分类的书，实际 "
                     + Books.booksModel.length + " 本")
            // 复位"全部"：清筛选恢复全量
            shelf.catFilter.currentIndex = 0
            shelf.catFilter.activated(0)
            tryVerify(function () { return Books.booksModel.length === all }, 3000,
                      "选全部后应恢复全部书籍，实际 " + Books.booksModel.length + "/" + all)
            // 清理：移除分类，避免污染后续用例
            Books.setCategory(book.id, "")
            loader.destroy()
        }
        // L9 复审修复回归（P1#17）：catFilter 重算按值取索引——onBooksChanged 重算
        // 后 currentIndex 不得漂移；选中模型最后一项也不得越界（旧实现 indexOf+1
        // 双重偏移：选后 booksChanged 位移一格，选末项越界 displayText 变空）
        function test_catFilterIndexStableAcrossBooksChanged() {
            var loader = shelfComp.createObject(root)
            var shelf = loader.item
            verify(shelf !== null, "ShelfPage 应能加载")
            if (Books.booksModel.length < 2) { loader.destroy(); skip("书库不足 2 本，跳过") }
            var ids = [Books.booksModel[0].id, Books.booksModel[1].id]
            // 两个有序分类名 → 模型至少 3 项（全部 + 2），末项越界才有观测意义
            //（SQLite BINARY 排序按 UTF-8 字节序，两分类先后不定，用例不假设次序）
            Books.setCategory(ids[0], "U3甲类")
            Books.setCategory(ids[1], "U3乙类")
            tryVerify(function () {
                return shelf.catFilter.model.indexOf("U3甲类") >= 0
                       && shelf.catFilter.model.indexOf("U3乙类") >= 0
            }, 3000, "两个分类应入模型，实际 " + JSON.stringify(shelf.catFilter.model))
            // 末项：选中后 booksChanged 重算不得越界（旧 bug：indexOf+1 超出模型）
            var last = shelf.catFilter.model.length - 1
            var lastName = shelf.catFilter.model[last]
            shelf.catFilter.currentIndex = last
            shelf.catFilter.activated(last)
            compare(shelf.currentCategory, lastName, "选末项应写值 " + lastName)
            Books.doSearch("") // 触发 booksChanged
            tryVerify(function () { return shelf.catFilter.currentIndex === last }, 3000,
                      "末项选中后 booksChanged 重算应保持索引 " + last + "，实际 "
                      + shelf.catFilter.currentIndex)
            compare(shelf.catFilter.displayText, lastName, "末项不得越界（displayText 应非空）")
            // 非末分类：选中后 booksChanged 重算不得漂移（旧 bug：重算推到 idx+1）
            var idx = 1 // 模型 [全部, X, Y]，索引 1 即非末项分类
            var firstCat = shelf.catFilter.model[idx]
            shelf.catFilter.currentIndex = idx
            shelf.catFilter.activated(idx)
            compare(shelf.currentCategory, firstCat, "选首分类应写值 " + firstCat)
            Books.doSearch("")
            tryVerify(function () { return shelf.catFilter.currentIndex === idx }, 3000,
                      "booksChanged 重算后索引应保持 " + idx + "，实际 "
                      + shelf.catFilter.currentIndex)
            compare(shelf.catFilter.model[shelf.catFilter.currentIndex], firstCat,
                    "currentIndex 应指回 " + firstCat + "（无双重偏移）")
            shelf.catFilter.activated(0)
            Books.setCategory(ids[0], "")
            Books.setCategory(ids[1], "")
            loader.destroy()
        }
    }
}
