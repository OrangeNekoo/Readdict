import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.Backend

// 阅读页主组件：背景三态 + 章节渲染 + 底部控制栏 + 目录 Dialog。
// typography 由 Settings 的 typography/ 分区组合（QML 侧组合，避免跨单例依赖），
// 章节进度经 Books.currentChapter 持久化到 settings.json 的 progress/<bookId>。
Page {
    id: page
    property var book: ({})
    property var chapter: ({})
    property var typography: ({})
    property string bgMode: "light"
    property var tocTitles: []

    ReaderBackground {
        anchors.fill: parent
        mode: page.bgMode
    }

    // 顶部章节条：返回 + 当前章名
    Rectangle {
        id: topBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 44
        color: page.bgMode === "dark" ? "#E6121212" : "#E6FFFFFF"
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: page.bgMode === "dark" ? "#33FFFFFF" : "#1A000000"
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 12
            spacing: 8
            ToolButton {
                text: qsTr("返回")
                onClicked: page.StackView.view.pop()
            }
            Label {
                id: topBarTitle
                Layout.fillWidth: true
                text: page.chapter.title ?? ""
                elide: Text.ElideRight
                font.bold: true
                color: page.bgMode === "dark" ? "#E6E6E6" : "#1A1A1A"
            }
        }
    }

    ReaderContent {
        id: content
        anchors.top: topBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: controls.top
        chapter: page.chapter
        typography: page.typography
    }

    ReaderControls {
        id: controls
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        bgMode: page.bgMode
        fontSize: page.typography.fontSize ?? 18
        onPrevChapter: page.loadChapter(Books.currentChapter - 1)
        onNextChapter: page.loadChapter(Books.currentChapter + 1)
        onChangeFontSize: (size) => page.setFontSize(size)
        onToggleBackground: page.cycleBackground()
        onToggleAlign: page.cycleAlign()
        onTogglePageWidth: page.cyclePageWidth()
        onOpenToc: tocDialog.open()
    }

    Dialog {
        id: tocDialog
        title: qsTr("目录")
        modal: true
        standardButtons: Dialog.Close
        width: 380
        height: 480
        contentItem: ListView {
            id: tocList
            clip: true
            model: page.tocTitles
            delegate: ItemDelegate {
                width: ListView.view.width
                text: modelData
                highlighted: ListView.isCurrentItem
                onClicked: {
                    page.loadChapter(index)
                    tocDialog.close()
                }
            }
            ScrollBar.vertical: ScrollBar {}
        }
        onOpened: {
            page.tocTitles = Books.chapterTitles(page.book.id)
            tocList.currentIndex = Books.currentChapter
        }
    }

    // 从 Settings 组合排版参数；fontFamily 经 Books.resolveFontFamily 映射到已安装字族
    function typographyFromSettings() {
        return {
            fontFamily: Books.resolveFontFamily(Settings.value("typography/fontFamily") || "思源黑体 VF"),
            fontSize: Settings.value("typography/fontSize") || 18,
            lineHeight: Settings.value("typography/lineHeight") || 1.6,
            align: Settings.value("typography/align") || "left",
            pageWidth: Settings.value("typography/pageWidth") || "normal"
        }
    }

    function loadChapter(i) {
        if (!page.book || !page.book.id) return
        const titles = Books.chapterTitles(page.book.id)
        if (!titles || titles.length === 0) return
        i = Math.max(0, Math.min(i, titles.length - 1))
        page.chapter = Books.loadChapter(page.book.id, i)
        Books.currentChapter = i   // 写时持久化 progress/<bookId>
    }

    function setFontSize(size) {
        size = Math.max(12, Math.min(32, size))
        Settings.setValue("typography/fontSize", size)
        page.typography = page.typographyFromSettings()
    }

    function cycleAlign() {
        const order = ["left", "center", "right"]
        const cur = Math.max(0, order.indexOf(page.typography.align ?? "left"))
        Settings.setValue("typography/align", order[(cur + 1) % order.length])
        page.typography = page.typographyFromSettings()
    }

    function cyclePageWidth() {
        const order = ["narrow", "normal", "wide"]
        const cur = Math.max(0, order.indexOf(page.typography.pageWidth ?? "normal"))
        Settings.setValue("typography/pageWidth", order[(cur + 1) % order.length])
        page.typography = page.typographyFromSettings()
    }

    function cycleBackground() {
        const order = ["light", "paper", "dark"]
        const cur = Math.max(0, order.indexOf(page.bgMode))
        page.bgMode = order[(cur + 1) % order.length]
        Settings.setValue("reader/background", page.bgMode)
    }

    Component.onCompleted: {
        page.typography = page.typographyFromSettings()
        const bg = Settings.value("reader/background")
        page.bgMode = (bg === "light" || bg === "paper" || bg === "dark") ? bg : "light"
        page.loadChapter(Books.lastChapter(page.book.id))
    }
}
