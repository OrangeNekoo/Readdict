# Readdict Kindle 化 UI 对齐（U+R 阶段）实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 按规格 `2026-08-08-readdict-kindle-ui2-design.md` §4/§6/§7 将 UI 全面对齐真实 Kindle 参考图（`~/Desktop/kindel界面参考/` 10 张）：重做导航体系、阅读页顶栏、书库细节、布局图标卡、新增主页。前置：L 阶段计划（`2026-08-08-readdict-logic-fix.md`）已完成。

**架构：** 纯 QML（QuickControls2）+ 现有 C++ 单例；后端仅最小适配（BookManager 增 `recentBooks`）。设计 Token 全部走 `UITheme`（Theme.qml），组件复用 Kd* 库。

**技术栈：** Qt 6.11.1 QuickControls2、Qt Test + QML 冒烟（tst_qml）。

**构建/测试命令（通用）：**
- 构建：`cmake --build build --parallel`
- QML 冒烟：`ctest --test-dir build -R tst_qml --output-on-failure`
- 全量：`ctest --test-dir build --output-on-failure`
- 启动冒烟：`./build/Readdict.app/Contents/MacOS/Readdict`（仓库根 CWD，命中 fronts/）

**commit 约定：** 简体中文，`feat:`/`style:`/`test:` 前缀。

**CMake 资源清单维护约定：** 每新建/删除 QML 文件，同步更新 `src/CMakeLists.txt` 的 `QML_FILES`（生产模块）与 `tests/CMakeLists.txt` 的 `qt_add_resources(tst_qml "qml_ui" ...)` 列表（两者前缀不同，逐文件列出）。

---

## 文件结构

| 文件 | 职责 |
|---|---|
| 新建 `src/ui/qml/KdTopSearchBar.qml` | 全宽圆角搜索栏 + 右侧 ⋮ 按钮 |
| 新建 `src/ui/qml/KdDropdownMenu.qml` | ⋮ 下拉菜单（遮罩 + 实色面板 + 线性图标项 + 分割线） |
| 新建 `src/ui/qml/KdBottomTabs.qml` | 底部 2 文字标签 + 中间悬浮迷你封面 |
| 新建 `src/ui/qml/HomePage.qml` | 最近阅读横排 + 阅读统计摘要 |
| 新建 `src/ui/qml/KdFilterSheet.qml` | 筛选+排序底部面板（分类/排序 radio 列表） |
| 新建 `src/ui/qml/KdIconCard.qml` | 圆角描边图标卡（选中加粗边） |
| 新建 `src/ui/qml/KdTopToolbar.qml` | 阅读页顶栏 7 项 |
| 重做 `src/ui/qml/Main.qml` | 导航体系换 KdTopSearchBar + KdBottomTabs |
| 重做 `src/ui/qml/ShelfPage.qml` | 图书馆页：筛选图标/角标/⋮；搜索栏上移 Main |
| 修改 `src/ui/qml/ReaderPage.qml` | 顶栏换 KdTopToolbar；删 ReaderControls；书签/图书信息 |
| 修改 `src/ui/qml/LayoutSheet.qml` | 三组分段 → KdIconCard 图标卡 |
| 修改 `src/ui/qml/MoreSheet.qml` | 删功能菜单（迁顶栏 ⋮），留 Toggle + 阅读进度行 |
| 删除 `KdBottomNav.qml`、`ReaderControls.qml` | 被新组件替代（**KdTabBar 保留**：KdBottomSheet 的 Aa 面板标签栏内部复用，形态与参考图面板标签一致） |
| 修改 `src/core/BookManager.h/.cpp` | 增 `recentBooks(limit)` |
| `tests/qml/*` | 导航句柄适配 + 新组件冒烟 |

---

### 任务 U1：BookManager.recentBooks + Kd 新组件三件（搜索栏/下拉菜单/底部标签）

**文件：**
- 修改：`src/core/BookManager.h/.cpp`、`src/CMakeLists.txt`、`tests/CMakeLists.txt`
- 新建：`src/ui/qml/KdTopSearchBar.qml`、`KdDropdownMenu.qml`、`KdBottomTabs.qml`
- 测试：`tests/tst_bookmanager.cpp`、`tests/qml/tst_kdcomponents.qml`（新建）

- [ ] **步骤 1：recentBooks 测试**

`tests/tst_bookmanager.cpp` 追加：

```cpp
    void recentBooksFiltersAndLimits() {
        BookManager m(dbPath, "readdict_bm_r1");
        const qint64 a = addSampleBook(m, "", 0.5, "2026-08-01T10:00:00"); // 有进度
        const qint64 b = addSampleBook(m, "", 0.0, "2026-08-02T10:00:00"); // 无进度
        const QVariantList r = m.recentBooks(5);
        QCOMPARE(r.size(), 1);                       // 仅 progress>0
        QCOMPARE(r.first().toMap().value("id").toLongLong(), a);
    }
```

（辅助 addSampleBook 按文件既有签名补 progress/lastReadAt 参数重载；若既有夹具不支持则直接 SQL INSERT 两行。）

- [ ] **步骤 2：实现 recentBooks**

`BookManager.h` 追加 `Q_INVOKABLE QVariantList recentBooks(int limit) const;`
`BookManager.cpp`：

```cpp
QVariantList BookManager::recentBooks(int limit) const {
    const QVector<Book> list = selectBooks("progress > 0 AND last_read_at IS NOT NULL",
                                           " ORDER BY last_read_at DESC, id DESC");
    QVariantList out;
    for (int i = 0; i < list.size() && out.size() < limit; ++i)
        out.append(bookToMap(list.at(i)));   // bookToMap 为 L6 抽取的私有静态
    return out;
}
```

- [ ] **步骤 3：KdTopSearchBar.qml**

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.UI 1.0

// Kindle 顶部全宽搜索栏：全圆角浅灰底 + 放大镜 + 占位；右侧 ⋮ 按钮。
// 接口：text（双向）、placeholderText；信号 menuClicked。
// 测试句柄：field / menuButton。
Rectangle {
    id: bar
    height: 44
    color: "transparent"
    property alias text: field.text
    property string placeholderText: qsTr("搜索 Readdict")
    signal menuClicked()
    property alias field: field
    property alias menuButton: menuBtn

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 10
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            radius: 18
            color: UITheme.bgSearch
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 6
                KdIcons { name: "search"; size: 18; color: UITheme.textSecondary }
                TextField {
                    id: field
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    placeholderText: bar.placeholderText
                    background: Rectangle { color: "transparent" }
                    color: UITheme.textPrimary
                    font.pixelSize: UITheme.fsListItem
                }
            }
        }
        ToolButton {
            id: menuBtn
            text: "⋮"
            font.pixelSize: 18
            contentItem.color: UITheme.textPrimary
            onClicked: bar.menuClicked()
        }
    }
}
```

- [ ] **步骤 4：KdDropdownMenu.qml**

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.UI 1.0

// Kindle ⋮ 下拉菜单：遮罩 rgba(0,0,0,0.3) + 实色面板（无圆角/极小圆角），
// 线性图标 + 文字项，divider 元素渲染分割线。锚定右上角（anchorRight=true）。
// 接口：items=[{id,icon,text} | {divider:true}]；open()/close()；信号 itemClicked(id)。
// 测试句柄：overlay / itemRepeater。
Item {
    id: menu
    anchors.fill: parent
    visible: false
    property var items: []
    signal itemClicked(string id)
    property alias overlay: mask
    property alias itemRepeater: rep

    function open() { menu.visible = true }
    function close() { menu.visible = false }

    Rectangle {
        id: mask
        anchors.fill: parent
        color: UITheme.overlay
        MouseArea { anchors.fill: parent; onClicked: menu.close() }
    }
    Rectangle {
        id: panel
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 4
        anchors.rightMargin: 8
        width: Math.max(220, parent.width * 0.45)
        height: col.height + 8
        color: UITheme.bgPrimary
        border.color: UITheme.borderDefault
        border.width: 1
        Column {
            id: col
            anchors.top: parent.top
            anchors.topMargin: 4
            anchors.left: parent.left
            anchors.right: parent.right
            Repeater {
                id: rep
                model: menu.items
                delegate: Loader {
                    width: col.width
                    sourceComponent: modelData.divider ? dividerComp : itemComp
                    required property var modelData
                }
            }
        }
    }
    Component {
        id: dividerComp
        Rectangle { height: 9; color: "transparent"
            Rectangle { anchors.centerIn: parent; width: parent.width - 16; height: 1; color: UITheme.divider }
        }
    }
    Component {
        id: itemComp
        Rectangle {
            height: 48
            color: ma.containsMouse ? "#0A000000" : "transparent"
            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                onClicked: { menu.close(); menu.itemClicked(modelData.id) }
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12
                KdIcons { name: modelData.icon || "dot"; size: 22; color: UITheme.textPrimary }
                Label {
                    text: modelData.text
                    font.pixelSize: UITheme.fsListItem
                    color: UITheme.textPrimary
                    Layout.fillWidth: true
                }
            }
        }
    }
}
```

（KdIcons 需含 `search`/`dot` 等名；缺的图标在 KdIcons.qml 补齐：import/stats/sync/settings/info/bookmark/bookmarkFill/toc/prev/next/read/filter/dot。）

- [ ] **步骤 5：KdBottomTabs.qml**

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.UI 1.0

// Kindle 底部导航：2 等宽文字标签（选中加粗 + 3px 下划线）+ 中间悬浮迷你封面
//（当前阅读书，上凸越过分隔线；null 时隐藏占位保持等宽）。
// 接口：currentId；currentBook（var，含 cover/title）；信号 tabClicked(id)/coverClicked()。
// 测试句柄：homeTab/libraryTab/miniCover。
Rectangle {
    id: tabs
    height: 52
    color: UITheme.bgPrimary
    property string currentId: "home"
    property var currentBook: null
    signal tabClicked(string id)
    signal coverClicked()
    property alias homeTab: homeTab
    property alias libraryTab: libraryTab
    property alias miniCover: miniCover

    Rectangle { // 顶部分隔线
        anchors.top: parent.top
        width: parent.width
        height: 2
        color: UITheme.textPrimary
    }
    RowLayout {
        anchors.fill: parent
        spacing: 0
        Item { Layout.fillWidth: true; Layout.fillHeight: true
            Label {
                id: homeTab
                anchors.centerIn: parent
                text: qsTr("主页")
                font.pixelSize: UITheme.fsTabNav
                font.bold: tabs.currentId === "home"
                color: tabs.currentId === "home" ? UITheme.textPrimary : UITheme.textSecondary
            }
            Rectangle { // 下划线
                anchors.top: homeTab.bottom
                anchors.topMargin: 2
                anchors.horizontalCenter: homeTab.horizontalCenter
                width: homeTab.width
                height: 3
                color: UITheme.borderActive
                visible: tabs.currentId === "home"
            }
            MouseArea { anchors.fill: parent; onClicked: tabs.tabClicked("home") }
        }
        Item { // 中间悬浮封面占位
            Layout.preferredWidth: 56
            Layout.fillHeight: true
            Image {
                id: miniCover
                width: 40; height: 54
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                visible: tabs.currentBook !== null
                source: tabs.currentBook ? tabs.currentBook.cover : ""
                fillMode: Image.PreserveAspectCrop
                border.color: UITheme.borderDefault
                border.width: 1
                layer.enabled: true
            }
            Rectangle { // 轻投影
                anchors.fill: miniCover
                anchors.margins: -1
                visible: miniCover.visible
                color: "transparent"
                border.color: UITheme.shadowBook
                border.width: 2
                z: -1
            }
            MouseArea {
                anchors.fill: parent
                enabled: tabs.currentBook !== null
                onClicked: tabs.coverClicked()
            }
        }
        Item { Layout.fillWidth: true; Layout.fillHeight: true
            Label {
                id: libraryTab
                anchors.centerIn: parent
                text: qsTr("图书馆")
                font.pixelSize: UITheme.fsTabNav
                font.bold: tabs.currentId === "shelf"
                color: tabs.currentId === "shelf" ? UITheme.textPrimary : UITheme.textSecondary
            }
            Rectangle {
                anchors.top: libraryTab.bottom
                anchors.topMargin: 2
                anchors.horizontalCenter: libraryTab.horizontalCenter
                width: libraryTab.width
                height: 3
                color: UITheme.borderActive
                visible: tabs.currentId === "shelf"
            }
            MouseArea { anchors.fill: parent; onClicked: tabs.tabClicked("shelf") }
        }
    }
}
```

- [ ] **步骤 6：组件冒烟 tst_kdcomponents.qml**

新建 `tests/qml/tst_kdcomponents.qml`（QuickTest TestCase 模式，沿用 tests/qml 既有用例结构）：

```qml
import QtQuick
import QtTest
import Readdict.UI 1.0

TestCase {
    name: "KdComponents"
    KdBottomTabs {
        id: tabs
        width: 400; height: 52
        currentId: "home"
        currentBook: ({ cover: "", title: "x" })
    }
    function test_tab_underline_follows() {
        compare(tabs.currentId, "home")
        tabs.currentId = "shelf"
        compare(tabs.currentId, "shelf")
    }
    function test_mini_cover_visibility() {
        verify(tabs.miniCover.visible)
        tabs.currentBook = null
        verify(!tabs.miniCover.visible)
    }
    KdDropdownMenu {
        id: menu
        width: 400; height: 300
        items: [{ id: "a", icon: "dot", text: "A" }, { divider: true }, { id: "b", icon: "dot", text: "B" }]
    }
    function test_menu_open_close_and_click() {
        menu.open()
        verify(menu.visible)
        var clicked = ""
        menu.itemClicked.connect(function (id) { clicked = id })
        // 点击第一项委托
        mouseClick(menu.itemRepeater.itemAt(0))
        compare(clicked, "a")
        verify(!menu.visible) // 点击后自动关闭
    }
    function mouseClick(item) {
        var p = mapFromItem(item, item.width / 2, item.height / 2)
        mouseClick(menu, p.x, p.y)
    }
}
```

（`mouseClick` 辅助按 QuickTest 坐标映射实现；若 itemAt 委托为 Loader 则取其 item。）

- [ ] **步骤 7：CMake 清单 + 运行 + Commit**

`src/CMakeLists.txt` QML_FILES 追加三个新组件；`tests/CMakeLists.txt` qml_ui 资源列表追加；tst_qml 的 QUICK_TEST_SOURCE_DIR 自动发现新用例文件。

```bash
cmake --build build --parallel && ctest --test-dir build -R "tst_bookmanager|tst_qml" --output-on-failure
git commit -m "feat: Kindle 顶搜索栏/⋮ 下拉/底部文字标签组件与 recentBooks（U1）"
```

---

### 任务 U2：Main.qml 导航体系重做 + HomePage

**文件：**
- 重做：`src/ui/qml/Main.qml`
- 新建：`src/ui/qml/HomePage.qml`
- 删除：`src/ui/qml/KdBottomNav.qml`（CMake 清单同步移除；KdTabBar 保留）
- 测试：`tests/qml/tst_nav.qml`（适配新句柄）

- [ ] **步骤 1：HomePage.qml**

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.Backend
import Readdict.UI 1.0

// Kindle 主页：最近阅读横排 + 阅读统计摘要行（点击进 StatsPage）。
Page {
    id: home
    property string navId: "home"
    background: Rectangle { color: UITheme.bgPrimary }

    ScrollView {
        anchors.fill: parent
        contentWidth: parent.width
        ColumnLayout {
            width: parent.width
            spacing: UITheme.sectionGap

            Label {
                text: qsTr("最近阅读")
                font.pixelSize: UITheme.fsSectionTitle
                font.bold: true
                color: UITheme.textPrimary
                Layout.margins: UITheme.pageMargin
                Layout.bottomMargin: 0
            }
            Row {
                spacing: 12
                leftPadding: UITheme.pageMargin
                Repeater {
                    model: Books.recentBooks(6)
                    delegate: Column {
                        spacing: 4
                        width: 96
                        BookCard { book: modelData; compact: true; width: 96
                            onClicked: home.openBook(modelData) }
                    }
                }
            }
            Label {
                text: qsTr("阅读统计")
                font.pixelSize: UITheme.fsSectionTitle
                font.bold: true
                color: UITheme.textPrimary
                Layout.margins: UITheme.pageMargin
                Layout.bottomMargin: 0
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: UITheme.pageMargin
                Layout.rightMargin: UITheme.pageMargin
                height: 56
                color: "transparent"
                MouseArea {
                    anchors.fill: parent
                    onClicked: home.StackView.view.push("StatsPage.qml")
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
                    Label {
                        id: statsSummary
                        text: home.statsText()
                        font.pixelSize: UITheme.fsListItem
                        color: UITheme.textSecondary
                        Layout.fillWidth: true
                    }
                    Label { text: "›"; color: UITheme.textSecondary }
                }
            }
        }
    }

    function statsText() {
        const s = Books.stats()
        const secs = s.totalReadSeconds || 0
        const hours = Math.floor(secs / 3600)
        const mins = Math.floor((secs % 3600) / 60)
        return qsTr("累计 %1 小时 %2 分 · 共 %3 本书")
            .arg(hours).arg(mins).arg(s.totalBooks || 0)
    }
    function openBook(b) {
        const fmt = (b.format ?? "").toUpperCase()
        home.StackView.view.push(fmt === "PDF" ? "PdfReaderPage.qml" : "ReaderPage.qml", { book: b })
    }
}
```

（BookCard 增 `property bool compact: false`：compact 时隐藏作者行/进度条、宽自适应——小改 BookCard.qml。）

- [ ] **步骤 2：Main.qml 重做**

保留：theme/effectiveDark/UITheme 绑定、navPages 机制、navigateTo 清栈逻辑、navStack 别名。替换导航组件：

```qml
    // 顶部搜索栏（仅 home/shelf 可见）；⋮ 菜单项：导入/统计/同步/设置/关于
    KdTopSearchBar {
        id: searchBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        visible: root.navVisible && (root.currentNavId === "home" || root.currentNavId === "shelf")
        height: visible ? 44 : 0
        onTextChanged: {
            if (root.currentNavId !== "shelf" && text.length > 0)
                root.navigateTo("shelf")     // 主页输入切图书馆
            Books.doSearch(text)
        }
        onMenuClicked: shelfMenu.open()
    }
    KdDropdownMenu {
        id: shelfMenu
        items: [
            { id: "import", icon: "import", text: qsTr("导入书籍") },
            { id: "stats", icon: "stats", text: qsTr("阅读统计") },
            { id: "sync", icon: "sync", text: qsTr("同步") },
            { id: "settings", icon: "settings", text: qsTr("设置") },
            { divider: true },
            { id: "about", icon: "info", text: qsTr("关于") }
        ]
        onItemClicked: (id) => root.onShelfMenu(id)
    }
    StackView {
        id: stack
        anchors.top: searchBar.bottom
        anchors.bottom: bottomTabs.top
        initialItem: "HomePage.qml"
        onCurrentItemChanged: root.syncNav()
        Component.onCompleted: root.syncNav()
    }
    KdBottomTabs {
        id: bottomTabs
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.navVisible ? 52 : 0
        visible: root.navVisible
        currentId: root.currentNavId === "shelf" ? "shelf" : "home"
        currentBook: root.navVisible ? root.currentReading : null
        onTabClicked: (id) => root.navigateTo(id)
        onCoverClicked: root.resumeReading()
    }
    property var currentReading: {
        const r = Books.recentBooks(1)
        return r.length ? r[0] : null
    }
    function resumeReading() {
        const b = root.currentReading
        if (b) stack.push(b.format === "PDF" ? "PdfReaderPage.qml" : "ReaderPage.qml", { book: b })
    }
    function onShelfMenu(id) {
        if (id === "import") fileDialog.open()
        else if (id === "stats") stack.push("StatsPage.qml")
        else if (id === "sync") stack.push("SyncPage.qml")
        else if (id === "settings") stack.push("SettingsPage.qml")
        else if (id === "about") aboutDialog.open()
    }
    // 导入对话框（从 ShelfPage 迁入）+ 关于对话框（版本/技术栈/许可）
    FileDialog { id: fileDialog; fileMode: FileDialog.OpenFiles
        nameFilters: ["电子书 (*.epub *.pdf *.mobi *.azw3 *.txt *.md *.fb2)"]
        onAccepted: { for (let f of selectedFiles) Importer.doImport(f) } }
    Dialog { id: aboutDialog; title: qsTr("关于")
        Label { text: qsTr("Readdict 1.0\nQt 6.11 · GPL（libmobi）· zlib 许可（minizip）") }
        standardButtons: Dialog.Ok }
    // 测试句柄迁移
    property alias tabBar: bottomTabs      // 旧别名保留指向新组件（tst 适配期）
    property alias bottomNav: bottomTabs
```

`navigateTo` 的 navPages 增 `"home": "HomePage.qml"`；syncNav 的沉浸判定不变（reader/pdf 隐藏）。

- [ ] **步骤 3：tst_nav.qml 适配**

旧用例对 `root.tabBar.tabs`/`root.bottomNav.items` 的断言改为：`root.tabBar`（KdBottomTabs）的 `currentId` 切换、`homeTab/libraryTab` 点击；删除 4 图标断言；新增「悬浮封面点击恢复阅读」用例（recentBooks 注入临时库）。

- [ ] **步骤 4：CMake 清单（删 KdBottomNav，加 HomePage；KdTabBar 保留）+ 运行 + Commit**

```bash
ctest --test-dir build -R tst_qml --output-on-failure
git commit -m "feat: 导航体系重做——顶搜索栏+底部文字标签+悬浮封面+主页（U2）"
```

---

### 任务 U3：图书馆页（筛选面板 + 角标 + 搜索上移）

**文件：**
- 重做：`src/ui/qml/ShelfPage.qml`
- 新建：`src/ui/qml/KdFilterSheet.qml`
- 修改：`src/ui/qml/BookCard.qml`（进度 % 角标 + 新角标）
- 测试：`tests/qml/tst_shelf.qml`（适配）

- [ ] **步骤 1：KdFilterSheet.qml**

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.Backend
import Readdict.UI 1.0

// 筛选+排序底部面板：分类 radio 列表（全部 + categoriesModel）+ 排序 radio 列表 +
// 搜索范围 radio（元数据/全文）。按值维护，选择即生效即持久化（Settings）。
// 独立实现（遮罩 + 底部滑出面板、无标签栏，故不复用 KdBottomSheet；样式同其 Token）。
// 接口：currentCategory（string）/currentSort（int）/currentScope（int）；open()/close()。
// 测试句柄：catList / sortList / scopeList。
Item {
    id: sheet
    anchors.fill: parent
    visible: false
    property string currentCategory: ""
    property int currentSort: 0
    property int currentScope: 0
    signal scopeChanged(int scope)
    function open() { sheet.visible = true }
    function close() { sheet.visible = false }
    property alias catList: catList
    property alias sortList: sortList
    property alias scopeList: scopeList

    Rectangle {
        anchors.fill: parent
        color: UITheme.overlay
        visible: sheet.visible
        MouseArea { anchors.fill: parent; onClicked: sheet.close() }
    }
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        height: parent.height * 0.55
        y: sheet.visible ? parent.height - height : parent.height
        Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        color: UITheme.bgPrimary
        ScrollView {
            anchors.fill: parent
            anchors.margins: 16
            ColumnLayout {
                width: parent.width
                spacing: 8
                Label { text: qsTr("分类"); font.bold: true; color: UITheme.textPrimary }
                ListView {
                    id: catList
                    Layout.fillWidth: true
                    Layout.preferredHeight: contentHeight
                    interactive: false
                    model: [qsTr("全部")].concat(Books.categoriesModel)
                    delegate: RadioButton {
                        width: catList.width
                        text: modelData
                        checked: sheet.currentCategory === (index === 0 ? "" : modelData)
                        onClicked: {
                            sheet.currentCategory = index === 0 ? "" : modelData
                            Books.setFilter(sheet.currentCategory)
                            Settings.setValue("shelf/category", sheet.currentCategory)
                        }
                    }
                }
                Label { text: qsTr("排序"); font.bold: true; color: UITheme.textPrimary }
                ListView {
                    id: sortList
                    Layout.fillWidth: true
                    Layout.preferredHeight: contentHeight
                    interactive: false
                    model: [qsTr("最近添加"), qsTr("作者"), qsTr("出版社"), qsTr("类型"), qsTr("最近阅读")]
                    delegate: RadioButton {
                        width: sortList.width
                        text: modelData
                        checked: index === sheet.currentSort
                        onClicked: {
                            sheet.currentSort = index
                            Books.setSort(index)
                            Settings.setValue("shelf/sort", index)
                        }
                    }
                }
                Label { text: qsTr("搜索范围"); font.bold: true; color: UITheme.textPrimary }
                ListView {
                    id: scopeList
                    Layout.fillWidth: true
                    Layout.preferredHeight: contentHeight
                    interactive: false
                    model: [qsTr("元数据"), qsTr("全文")]
                    delegate: RadioButton {
                        width: scopeList.width
                        text: modelData
                        checked: index === sheet.currentScope
                        onClicked: {
                            sheet.currentScope = index
                            Settings.setValue("shelf/scope", index)
                            sheet.scopeChanged(index)
                        }
                    }
                }
            }
        }
    }
    Component.onCompleted: {
        currentCategory = Settings.value("shelf/category").toString("")
        currentSort = Settings.value("shelf/sort").toInt(0)
        currentScope = Settings.value("shelf/scope").toInt(0)
        Books.setFilter(currentCategory)
        Books.setSort(currentSort)
    }
}

- [ ] **步骤 2：ShelfPage 重做**

- 删除顶部 RowLayout（搜索栏已迁 Main）；保留 navId "shelf"。
- 搜索栏下左对齐筛选图标按钮（KdIcons `filter`，24px），点击 `filterSheet.open()`。
- 删除 catFilter/sortBox ComboBox 与导入 Button/FileDialog（迁 Main）。
- GridView 不变；delegate BookCard 增角标。
- 全文搜索列表保留；searchMode ComboBox 删除，范围切换迁 KdFilterSheet 的 scopeList（ShelfPage 绑定 `filterSheet.currentScope === 1` 显示全文列表，scopeChanged 触发即时搜索）。
- openSearchResult 的 bookById 已在 L6 改 bookByIdModel。
- 空状态 Label 的 catFilter.currentIndex 条件改 `shelf.currentCategory === ""`。

- [ ] **步骤 3：BookCard 角标**

`BookCard.qml` 封面 Rectangle 内追加：

```qml
        // 进度 % 角标（黑底白字小旗，右上；0<progress<1 时显示）
        Rectangle {
            anchors.top: coverImage.top
            anchors.right: coverImage.right
            visible: book.progress > 0 && book.progress < 1
            color: UITheme.textPrimary
            width: pctLabel.width + 8
            height: 18
            Label {
                id: pctLabel
                anchors.centerIn: parent
                text: Math.round(book.progress * 100) + "%"
                font.pixelSize: 11
                color: UITheme.bgPrimary
            }
        }
        // 「新」角标：added_at 7 天内且未读（progress==0）
        Rectangle {
            anchors.top: coverImage.top
            anchors.right: coverImage.right
            visible: book.progress === 0 && shelf.isNew(book.addedAt)
            color: UITheme.textPrimary
            width: 22; height: 18
            Label { anchors.centerIn: parent; text: qsTr("新")
                font.pixelSize: 11; color: UITheme.bgPrimary }
        }
```

ShelfPage 增 `function isNew(addedAt) { return addedAt && (Date.now() - new Date(addedAt).getTime()) < 7*86400000 }`。

- [ ] **步骤 4：tst_shelf 适配 + 运行 + Commit**

旧 catFilter 断言改 filterSheet 句柄；新增「筛选按值持久化」用例（重开页面 currentCategory 恢复）。

```bash
ctest --test-dir build -R tst_qml --output-on-failure
git commit -m "feat: 图书馆筛选面板、进度/新角标与搜索上移（U3）"
```

---

### 任务 U4：阅读页顶栏 + ⋮ 功能菜单 + 书签/图书信息

**文件：**
- 新建：`src/ui/qml/KdTopToolbar.qml`
- 修改：`src/ui/qml/ReaderPage.qml`（删 ReaderControls 引用、顶栏替换、书签、图书信息 Dialog）
- 删除：`src/ui/qml/ReaderControls.qml`
- 测试：`tests/qml/tst_reader.qml`（适配）

- [ ] **步骤 1：KdTopToolbar.qml**

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.UI 1.0

// Kindle 阅读页顶栏（唤出态）：← 书库 | Aa | 布局 | 笔记 | 书签 | 搜索 | ⋮
// 接口：bookmarked（bool，书签两态）；信号 back/aa/layout/notes/bookmark/search/menu。
// 测试句柄：各按钮别名。
Rectangle {
    id: bar
    height: 40
    color: "transparent"
    property bool bookmarked: false
    signal back(); signal aa(); signal layout(); signal notes()
    signal bookmark(); signal search(); signal menu()
    property alias backBtn: backBtn
    property alias menuBtn: menuBtn

    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: UITheme.divider }
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 12
        spacing: 0
        ToolButton { id: backBtn; Layout.fillWidth: true; contentItem: RowLayout { spacing: 4
                Label { text: "←"; color: UITheme.textPrimary }
                Label { text: qsTr("书库"); color: UITheme.textPrimary; font.pixelSize: UITheme.fsListItem } }
            onClicked: bar.back() }
        ToolButton { Layout.fillWidth: true; Text { text: "Aa"; color: UITheme.textPrimary; font.pixelSize: 15 } ; onClicked: bar.aa() }
        ToolButton { Layout.fillWidth: true; Text { text: qsTr("布局"); color: UITheme.textPrimary; font.pixelSize: UITheme.fsListItem }; onClicked: bar.layout() }
        ToolButton { Layout.fillWidth: true; KdIcons { name: "notes"; size: 20; color: UITheme.textPrimary }; onClicked: bar.notes() }
        ToolButton { Layout.fillWidth: true; KdIcons { name: bar.bookmarked ? "bookmarkFill" : "bookmark"; size: 20; color: UITheme.textPrimary }; onClicked: bar.bookmark() }
        ToolButton { Layout.fillWidth: true; KdIcons { name: "search"; size: 20; color: UITheme.textPrimary }; onClicked: bar.search() }
        ToolButton { id: menuBtn; Layout.fillWidth: true; Text { text: "⋮"; color: UITheme.textPrimary; font.pixelSize: 16 }; onClicked: bar.menu() }
    }
}
```

- [ ] **步骤 2：ReaderPage 顶栏替换**

- 删除旧 topBar Rectangle（99-147 行）与 `controls`（ReaderControls 实例）及其全部别名（controlsBar/bgPopup/alignList/fontPopup/readAloudButton 等）；保留 backBtn 别名指向新顶栏 backBtn。
- 插入 `KdTopToolbar { id: topToolbar; visible: page.sheetOpen; ... }`，信号接线：back→pop；aa→`sheetOpen=true; sheetTab="theme"`；layout→`sheetTab="layout"`；notes→notesDlg.open()；bookmark→`page.toggleBookmark()`；search→searchDlg.open()；menu→readerMenu 的 items 改 `[{id:"read",...朗读},{id:"toc",目录},{id:"prev",上一章},{id:"next",下一章},{divider:true},{id:"info",图书信息}]`。
- 点屏幕中部 handleContentTap 维持「切换 sheetOpen」，顶栏与 Sheet 同显同隐；hideControlsTimer 逻辑保留仅作用于 sheetOpen。
- 朗读启动入口改 readerMenu "read" → 原 controls.readAloudBtn 的启动逻辑（抽为 page 函数 startReadAloud()）。

- [ ] **步骤 3：书签最小实现**

ReaderPage 追加：

```qml
    property var bookmarks: []
    Component.onCompleted: { page.bookmarks = Settings.value("bookmarks/" + page.book.id) || [] }
    function toggleBookmark() {
        const ch = Books.currentChapter
        var list = page.bookmarks.slice()
        const i = list.indexOf(ch)
        if (i >= 0) list.splice(i, 1); else list.push(ch)
        page.bookmarks = list
        Settings.setValue("bookmarks/" + page.book.id, list)
        topToolbar.bookmarked = list.indexOf(Books.currentChapter) >= 0
    }
```

（currentChapter 变化时同步 bookmarked。）

- [ ] **步骤 4：图书信息 Dialog**

```qml
    Dialog {
        id: infoDialog
        title: qsTr("图书信息")
        Label {
            text: qsTr("书名：%1\n作者：%2\n出版社：%3\n格式：%4\n进度：%5%")
                .arg(page.book.title).arg(page.book.author || "")
                .arg(page.book.publisher || "").arg(page.book.format)
                .arg(Math.round((page.book.progress || 0) * 100))
        }
        standardButtons: Dialog.Ok
    }
```

- [ ] **步骤 5：tst_reader 适配 + 运行 + Commit**

旧 controlsBar 索引点击用例改 topToolbar 按钮别名；朗读启动用例改经 readerMenu；新增书签两态用例。CMake 删 ReaderControls.qml。

```bash
ctest --test-dir build -R tst_qml --output-on-failure
git commit -m "feat: 阅读页 Kindle 顶栏（7 项）+ ⋮ 功能菜单 + 书签/图书信息（U4）"
```

---

### 任务 U5：LayoutSheet 图标卡 + MoreSheet 瘦身

**文件：**
- 新建：`src/ui/qml/KdIconCard.qml`
- 修改：`src/ui/qml/LayoutSheet.qml`、`src/ui/qml/MoreSheet.qml`
- 测试：`tests/qml/tst_sheets.qml`（适配）

- [ ] **步骤 1：KdIconCard.qml**

```qml
import QtQuick
import Readdict.UI 1.0

// Kindle 布局图标卡：圆角矩形描边 + 内绘横线示意（线数/密度由 lines/密度参数决定）；
// 选中 = 加粗黑边。接口：selected/lines（3|4|5）/dense（bool，竖排示意）；信号 clicked。
Rectangle {
    id: card
    width: 72; height: 52
    radius: 8
    color: "transparent"
    border.color: card.selected ? UITheme.borderActive : UITheme.borderDefault
    border.width: card.selected ? 2.5 : 1
    property bool selected: false
    property int lines: 4
    property string glyph: "h"   // h 横线示意 / v 竖排示意 / m1 m2 m3 边距示意
    signal clicked()
    MouseArea { anchors.fill: parent; onClicked: card.clicked() }
    Column {
        anchors.centerIn: parent
        spacing: card.glyph === "loose" ? 6 : card.glyph === "tight" ? 2 : 4
        Repeater {
            model: card.lines
            Rectangle {
                width: card.glyph === "narrow" ? 34 : card.glyph === "wide" ? 52 : 44
                height: 2
                color: UITheme.textPrimary
            }
        }
    }
}
```

- [ ] **步骤 2：LayoutSheet 三组改图标卡**

保留接口与信号（setPageMode/setPageWidth/setLineHeight）与测试句柄名（modeItems/marginItems/lineItems 改指向三个 Row 的 Repeater）。每组渲染：

```qml
        Row {
            spacing: 10
            Repeater {
                id: modeRepeater
                model: [ { glyph: "v", value: "scroll" }, { glyph: "h", value: "paged" } ]
                KdIconCard {
                    required property var modelData
                    selected: modelData.value === layoutSheet.pageMode
                    glyph: modelData.glyph
                    onClicked: layoutSheet.setPageMode(modelData.value)
                }
            }
        }
```

marginModel 三卡 glyph narrow/normal/wide（横线宽度 34/44/52 递增示意）；lineModel 三卡 glyph tight/normal/loose（Column spacing 2/4/6）。分组标题 Label 保留（方向/页边距/行间距），2 列网格布局对齐参考图（Row of Columns）。对齐分段滑块保留（KdSegmentedSlider，置于行间距组下方）。

- [ ] **步骤 3：MoreSheet 瘦身**

删除 menuModel/Repeater 与六个 request* 信号（功能已迁顶栏 ⋮，P2#20）；保留 autoContinue/darkFollow Toggle；追加「阅读进度」行：

```qml
        RowLayout {
            Layout.fillWidth: true
            Label { text: qsTr("阅读进度"); font.pixelSize: 15; color: UITheme.textPrimary }
            Item { Layout.fillWidth: true }
            Label { text: qsTr("书中位置"); font.pixelSize: UITheme.fsCaption; color: UITheme.textSecondary }
            Label { text: "›"; color: UITheme.textSecondary }
            MouseArea { anchors.fill: parent; onClicked: moreSheet.requestToc() }
        }
```

保留 `signal requestToc()`（宿主接线打开目录 Dialog 跳章）。

- [ ] **步骤 4：运行 + Commit**

```bash
ctest --test-dir build -R tst_qml --output-on-failure
git commit -m "style: 布局标签图标卡与更多标签瘦身（U5）"
```

---

### 任务 U6：R 阶段——i18n、Token 审计、全量回归

**文件：** `src/ui/i18n/*.ts`、全部 UI 文件

- [ ] **步骤 1：i18n 三语 0 unfinished**

运行 lupdate（`cmake --build build --target Readdict_lupdate` 或 qt6 lupdate 命令，沿用 D6 流程）；新串用 `.superpowers/sdd/d6_fill_translations.py` 同模式补 zh_CN/zh_TW/en；`Readdict_lrelease` 后 grep `.ts` 无 `type="unfinished"`。

- [ ] **步骤 2：Token 一致性审计**

```bash
grep -rn "Material.primary\|Material.accent\|#3D5AFE\|#536DFE" src/ui/qml || true
grep -rn "#[0-9A-Fa-f]\{6\}" src/ui/qml | grep -v "Theme.qml\|ReaderBackground.qml\|Kd" || true
```
残留硬编码色收编进 Theme.qml Token 或确认属遮罩/投影常量。

- [ ] **步骤 3：删除文件清单确认**

确认 `KdBottomNav.qml`/`ReaderControls.qml` 已删且 CMake 两处清单无残留引用；`grep -rn "KdBottomNav\|ReaderControls" src tests` 无命中（KdTabBar 保留，消费者仅 KdBottomSheet）。

- [ ] **步骤 4：全量构建 + ctest + 启动冒烟**

```bash
cmake --build build --parallel
ctest --test-dir build --output-on-failure
./build/Readdict.app/Contents/MacOS/Readdict &   # 5 秒观察零 QML 错误后退出
```

- [ ] **步骤 5：Commit**

```bash
git commit -m "style: U+R 回归——i18n 三语、Token 审计与全量绿（U6）"
```

---

**验收标准：** 主界面 = 顶全宽搜索栏 + ⋮、底「主页|图书馆」+ 悬浮迷你封面；主页 = 最近阅读 + 统计摘要；图书馆 = 封面网格 + 进度/新角标 + 筛选面板；阅读页 = 顶栏 7 项 + 底部 Aa 四标签（布局图标卡）；⋮ 菜单承载导入/统计/同步/设置/关于与朗读/目录/上章/下章/图书信息；tst_qml 与 ctest 全绿；三语 0 unfinished；Token 无硬编码残留。
