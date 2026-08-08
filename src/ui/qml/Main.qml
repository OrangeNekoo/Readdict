import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import Readdict.Backend
import Readdict.UI 1.0

ApplicationWindow {
    id: root
    width: 1100; height: 720
    // C4：最小窗口尺寸——800 宽保证书架工具栏（搜索胶囊 + 范围/分类/排序下拉 +
    // 导入）+ 封面网格（单元格 190，至少 1 列）在窗口内可读（U3 分类侧栏已移除，
    // 网格占满整行）；600 高保证设置页分组卡片（外观/语言/TTS/背景/同步/统计）
    // 顶部内容可见，超高部分由 SettingsPage 的 ScrollView 滚动兜底（最小尺寸取值
    // 与各页滚动方案见 .superpowers/sdd/task-C4-report.md）
    minimumWidth: 800
    minimumHeight: 600
    visible: true
    title: qsTr("Readdict")

    // 主题三态：auto 跟随系统、light 浅色、dark 深色；持久化于 Settings 的 theme/mode
    property string theme: "auto"
    // U1 复审：applyTheme 只写 root.theme——UITheme.isDark 由下方顶层绑定跟随
    // effectiveDark（命令式赋值在 Qt.styleHints.colorScheme 运行中变化时不会重跑，
    // auto 模式系统切换深浅将不同步 Token；绑定与 Material.theme 同模式，实时派生）。
    function applyTheme(mode) { root.theme = mode }

    Material.theme: root.theme === "dark" ? Material.Dark
                   : root.theme === "light" ? Material.Light
                   : Material.System

    // effectiveDark 取实际生效的深色：显式 dark，或 auto 且系统为深色
    //（Qt.styleHints.colorScheme 跟随系统实时变化，auto 模式换肤即时生效）。
    property bool effectiveDark: root.theme === "dark"
        || (root.theme === "auto" && Qt.styleHints.colorScheme === Qt.ColorScheme.Dark)

    // U1 复审：Kindle Token 深浅与 effectiveDark 建立实时绑定——auto 模式下系统深浅
    // 切换（Qt.styleHints.colorScheme 变化）即时同步 UITheme.isDark。注意不能写成对象级
    // 语法 `UITheme.isDark: ...`：单例类型在对象声明里会被解析为附加属性
    //（"Non-existent attached object"），须经 Qt.binding 在 onCompleted 安装绑定
    //（依赖 effectiveDark，与 Material.theme 同模式实时派生；命令式赋值在系统切换时
    // 不会重跑）。applyTheme 只写 root.theme，由本绑定转发。
    Component.onCompleted: {
        UITheme.isDark = Qt.binding(function () { return root.effectiveDark })
        const mode = Settings.value("theme/mode")
        root.theme = (mode === "auto" || mode === "light" || mode === "dark") ? mode : "auto"
    }

    // U1：去 Material 靛蓝（原 #3D5AFE/#536DFE 主色/accent 删除，UI 不再引用
    // Material.primary/accent——BookCard/StatsPage 的 accent 用法已改 Token）。
    // Material 框架仍需保留（QtQuick.Controls 控件样式），但颜色全走 Kindle Token：
    // background/foreground 附加属性让默认控件底色/文字随 UITheme 深浅（暖白近黑
    // ↔ Kindle 深色系），窗口底色由下方 background 显式 Rectangle 兜底。
    Material.background: UITheme.bgPrimary
    Material.foreground: UITheme.textPrimary
    background: Rectangle { anchors.fill: parent; color: UITheme.bgPrimary }

    // ---- U2：Kindle 导航体系（顶部标签 + 底部线性图标导航）----
    // 页面语义：书库（ShelfPage 兼主页/书库——仓库无独立主页页）、设置两套主标签；
    // 统计/同步为独立页（原经设置页入口推入，现底部导航直达）。阅读页（reader/pdf）
    // 为沉浸页：push 时隐藏标签与底部导航（正文占满窗口），返回后恢复。
    // 测试/外部句柄：navStack（StackView）、tabBar/bottomNav（两个导航组件）。
    property alias navStack: stack
    property alias tabBar: tabBar
    property alias bottomNav: bottomNav

    // 当前顶层页 id（由栈顶页面 navId 派生；无 navId 的页面按非导航页处理）
    property string currentNavId: ""
    // 沉浸判定：栈顶为阅读页（reader/pdf）时隐藏两套导航，正文占满窗口
    property bool navVisible: true

    // 导航状态同步：StackView 的 currentItem 变化（push/pop/replace）时由
    // onCurrentItemChanged/onCompleted 驱动，避免构造期绑定引用未创建子对象。
    function syncNav() {
        const top = stack.currentItem
        root.currentNavId = top ? (top.navId || "") : ""
        root.navVisible = top !== null && top.navId !== "reader" && top.navId !== "pdf"
    }

    // 导航页注册表：navId → 页面资源（Main.qml 同目录相对路径）
    readonly property var navPages: {
        "shelf": "ShelfPage.qml",
        "settings": "SettingsPage.qml",
        "stats": "StatsPage.qml",
        "sync": "SyncPage.qml"
    }

    // 导航切换：已在目标页（含经设置页入口推入的统计/同步）则不动；否则先清掉
    // 推入页（阅读页/设置子页，Immediate 同步）回到单根书库。根本就是目标页
    //（如从子页回书库）→ 不再 push——保留根 ShelfPage 实例（搜索/筛选/滚动状态），
    // 避免 [Shelf, Shelf] 重复页；否则推入目标页。根始终是 ShelfPage，任意导航页
    // 的返回链都回到书库。
    function navigateTo(navId) {
        const top = stack.currentItem
        if (top && top.navId === navId) return
        for (let i = stack.depth; i > 1; --i)
            stack.pop(null, StackView.Immediate)
        if (stack.currentItem && stack.currentItem.navId === navId) return
        stack.push(navPages[navId])
    }

    KdTabBar {
        id: tabBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.navVisible ? 44 : 0
        visible: root.navVisible
        tabs: [
            { id: "shelf", text: qsTr("书库") },
            { id: "settings", text: qsTr("设置") }
        ]
        currentId: root.currentNavId
        onTabClicked: (id) => root.navigateTo(id)
    }

    StackView {
        id: stack
        anchors.top: tabBar.bottom
        anchors.bottom: bottomNav.top
        anchors.left: parent.left
        anchors.right: parent.right
        initialItem: "ShelfPage.qml"
        // U2：导航联动——currentItem 变化（push/pop）时同步标签/底部导航高亮与沉浸隐藏
        onCurrentItemChanged: root.syncNav()
        Component.onCompleted: root.syncNav()
    }

    KdBottomNav {
        id: bottomNav
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.navVisible ? 56 : 0
        visible: root.navVisible
        // U4：图标为 KdIcons 线性描边图标名（shelf/stats/sync/settings）
        items: [
            { id: "shelf", icon: "shelf", text: qsTr("书库") },
            { id: "stats", icon: "stats", text: qsTr("统计") },
            { id: "sync", icon: "sync", text: qsTr("同步") },
            { id: "settings", icon: "settings", text: qsTr("设置") }
        ]
        currentId: root.currentNavId
        onItemClicked: (id) => root.navigateTo(id)
    }
}
