import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs
import Readdict.Backend
import Readdict.UI 1.0

ApplicationWindow {
    id: root
    width: 1100
    height: 720
    minimumWidth: 800
    minimumHeight: 600
    visible: true
    title: qsTr("Readdict")

    // 主题三态：auto 跟随系统、light 浅色、dark 深色；持久化于 Settings 的 theme/mode。
    property string theme: "auto"
    function applyTheme(mode) { root.theme = mode }

    Material.theme: root.theme === "dark" ? Material.Dark
                   : root.theme === "light" ? Material.Light
                   : Material.System
    property bool effectiveDark: root.theme === "dark"
        || (root.theme === "auto" && Qt.styleHints.colorScheme === Qt.ColorScheme.Dark)

    Component.onCompleted: {
        UITheme.isDark = Qt.binding(function () { return root.effectiveDark })
        const mode = Settings.value("theme/mode")
        root.theme = (mode === "auto" || mode === "light" || mode === "dark") ? mode : "auto"
    }

    Material.background: UITheme.bgPrimary
    Material.foreground: UITheme.textPrimary
    background: Rectangle { anchors.fill: parent; color: UITheme.bgPrimary }

    // 主导航兼容句柄：tabBar/bottomNav 均指向新的底部文字标签组件；navStack 保留。
    property alias navStack: stack
    property alias tabBar: bottomTabs
    property alias bottomNav: bottomTabs
    property alias topSearchBar: searchBar
    property alias searchBar: searchBar
    property alias shelfMenu: shelfMenu
    property alias fileDialog: fileDialog
    property alias aboutDialog: aboutDialog

    property string currentNavId: ""
    property bool navVisible: true
    property var currentReading: root.recentReading()

    function recentReading() {
        const recent = Books.recentBooks(1)
        return recent && recent.length ? recent[0] : null
    }

    Connections {
        target: Books
        function onBooksChanged() { root.currentReading = root.recentReading() }
    }

    function syncNav() {
        const top = stack.currentItem
        root.currentNavId = top ? (top.navId || "") : ""
        root.navVisible = top !== null && top.navId !== "reader" && top.navId !== "pdf"
    }

    readonly property var navPages: {
        "home": "HomePage.qml",
        "shelf": "ShelfPage.qml",
        "settings": "SettingsPage.qml",
        "stats": "StatsPage.qml",
        "sync": "SyncPage.qml"
    }

    function navigateTo(navId) {
        if (!root.navPages[navId]) return
        const top = stack.currentItem
        if (top && top.navId === navId) return
        for (let i = stack.depth; i > 1; --i)
            stack.pop(null, StackView.Immediate)
        if (stack.currentItem && stack.currentItem.navId === navId) return
        stack.push(root.navPages[navId])
    }

    // 顶部搜索栏仅在主页/图书馆可见；主页输入搜索词时自动切到图书馆。
    KdTopSearchBar {
        id: searchBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        visible: root.navVisible && (root.currentNavId === "home" || root.currentNavId === "shelf")
        height: visible ? 44 : 0
        onTextChanged: {
            if (root.currentNavId !== "shelf" && text.length > 0)
                root.navigateTo("shelf")
            Books.doSearch(text)
        }
        onMenuClicked: shelfMenu.open()
    }

    KdDropdownMenu {
        id: shelfMenu
        z: 100
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
        anchors.left: parent.left
        anchors.right: parent.right
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

    function resumeReading() {
        const b = root.currentReading
        if (!b) return
        const fmt = (b.format ?? "").toUpperCase()
        stack.push(fmt === "PDF" ? "PdfReaderPage.qml" : "ReaderPage.qml", { book: b })
    }

    function onShelfMenu(id) {
        if (id === "import") fileDialog.open()
        else if (id === "stats") stack.push("StatsPage.qml")
        else if (id === "sync") stack.push("SyncPage.qml")
        else if (id === "settings") stack.push("SettingsPage.qml")
        else if (id === "about") aboutDialog.open()
    }

    FileDialog {
        id: fileDialog
        title: qsTr("导入电子书")
        fileMode: FileDialog.OpenFiles
        nameFilters: ["电子书 (*.epub *.pdf *.mobi *.azw3 *.txt *.md *.fb2)"]
        onAccepted: {
            for (let f of selectedFiles)
                Importer.doImport(f)
        }
    }

    Dialog {
        id: aboutDialog
        title: qsTr("关于")
        modal: true
        width: 360
        contentItem: Label {
            text: qsTr("Readdict 1.0\nQt 6.11 · GPL（libmobi）· zlib 许可（minizip）")
            color: UITheme.textPrimary
            padding: 20
        }
        standardButtons: Dialog.Ok
    }
}
