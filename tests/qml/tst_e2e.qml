import QtQuick
import QtTest
import Readdict.Backend
import Readdict.Test 1.0

// 端到端数据流自动化：真实 UI 组件（Books/Importer 后端单例 + 真实 SQLite 临时库）
// 覆盖 导入 → 搜索 → 排序 → 分类 → 删除。
// QML TestCase 按函数名字母序执行（非声明序），故用数字前缀保证流程顺序；
// 每个用例开头防御性复位搜索/筛选，避免相互污染。
TestCase {
    name: "EndToEnd"

    function initTestCase() {
        // TestEnv.sourceFiles 已是 file:// URL 字符串
        for (let f of TestEnv.sourceFiles)
            Importer.doImport(f)
    }

    function test_01_importCount() {
        compare(Books.booksModel.length, 3, "应导入 3 本 TXT 书")
        let titles = []
        for (let b of Books.booksModel) titles.push(b.title)
        verify(titles.indexOf("zeta") >= 0 && titles.indexOf("alpha") >= 0 && titles.indexOf("mike") >= 0,
               "标题应来自文件名：zeta/alpha/mike，实际 " + titles.join(","))
    }

    function test_02_search() {
        Books.doSearch("alp")
        compare(Books.booksModel.length, 1, "搜索 alp 应命中 1 本")
        compare(Books.booksModel[0].title, "alpha", "命中应为 alpha")
        Books.doSearch("") // 清空搜索，恢复全部
        compare(Books.booksModel.length, 3)
    }

    function test_03_sort() {
        Books.setSort(1) // 作者 → author 相同则按 title 升序
        compare(Books.booksModel[0].title, "alpha", "作者排序首本应为 alpha")
        compare(Books.booksModel[2].title, "zeta", "作者排序末本应为 zeta")
        Books.setSort(0) // 最近添加 → added_at DESC, id DESC → mike, alpha, zeta
        compare(Books.booksModel[0].title, "mike", "最近添加首本应为 mike")
        compare(Books.booksModel[2].title, "zeta", "最近添加末本应为 zeta")
    }

    function test_04_category() {
        Books.setFilter("") // 复位筛选
        // 找到 alpha 的 id
        let id = -1
        for (let b of Books.booksModel)
            if (b.title === "alpha") { id = b.id; break }
        verify(id > 0, "应能找到 alpha 的书籍 id")
        Books.setCategory(id, "科幻")
        verify(Books.categoriesModel.indexOf("科幻") >= 0, "分类列表应包含新建分类“科幻”")
        Books.setFilter("科幻")
        compare(Books.booksModel.length, 1, "筛选科幻应剩 1 本")
        compare(Books.booksModel[0].title, "alpha", "科幻分类下应为 alpha")
        compare(Books.booksModel[0].category, "科幻")
        Books.setFilter("") // 复位分类筛选
        compare(Books.booksModel.length, 3)
    }

    function test_05_remove() {
        Books.doSearch("") // 复位搜索
        Books.setFilter("")
        let before = Books.booksModel.length
        verify(before > 0)
        let id = Books.booksModel[0].id
        Books.removeBook(id)
        compare(Books.booksModel.length, before - 1, "删除后书籍数应减一")
        for (let b of Books.booksModel)
            verify(b.id !== id, "被删除的 id=" + id + " 不应再出现")
    }
}
