import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Readdict.Backend
import Readdict.UI 1.0

Page {
    id: shelf
    property string navId: "shelf"
    property string toastText: ""
    property var searchResults: []
    // 顶部搜索已经由 Main/KdTopSearchBar 提供；此属性在独立测试中也可直接赋值。
    property string searchText: Window.window && Window.window.topSearchBar
                                ? Window.window.topSearchBar.text : ""
    property string currentCategory: filterSheet.currentCategory
    property alias filterSheet: filterSheet
    property alias filterButton: filterButton
    property alias filterIcon: filterIcon
    property alias fulltextList: ftList

    Connections {
        target: Importer
        function onImportFailed(message, fileName) {
            shelf.toastText = message + "：" + fileName
            toastTimer.restart()
        }
    }

    Timer {
        id: toastTimer
        interval: 4000
        onTriggered: shelf.toastText = ""
    }

    function isNew(addedAt) {
        return !!addedAt && (Date.now() - new Date(addedAt).getTime()) < 7 * 86400000
    }

    function refreshFulltextSearch() {
        if (filterSheet.currentScope !== 1 || shelf.searchText.length === 0) {
            shelf.searchResults = []
            return
        }
        shelf.searchResults = Search.searchAllModel(shelf.searchText)
    }

    onSearchTextChanged: shelf.refreshFulltextSearch()

    // 全文范围切换即时生效；元数据范围交回 Main 的 Books.doSearch 搜索路径。
    Connections {
        target: filterSheet
        function onScopeChanged(scope) {
            if (scope === 1) {
                Books.doSearch("")
            } else {
                Books.doSearch(shelf.searchText)
            }
            shelf.refreshFulltextSearch()
        }
    }

    Label {
        id: toast
        visible: shelf.toastText.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.margins: 24
        z: 100
        text: shelf.toastText
        color: "white"
        padding: 10
        background: Rectangle { color: "#E6323232"; radius: 4 }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            Layout.leftMargin: 12
            spacing: 8

            ToolButton {
                id: filterButton
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                contentItem: KdIcons {
                    id: filterIcon
                    name: "filter"
                    size: 24
                    color: UITheme.textPrimary
                }
                onClicked: filterSheet.open()
            }
        }

        // 全文命中列表仍位于搜索栏下方；搜索词来自 Main 的顶部 KdTopSearchBar。
        ListView {
            id: ftList
            Layout.fillWidth: true
            Layout.preferredHeight: 300
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            visible: filterSheet.currentScope === 1 && shelf.searchText.length > 0
            clip: true
            model: shelf.searchResults
            delegate: ItemDelegate {
                width: ListView.view.width
                onClicked: shelf.openSearchResult(modelData)
                contentItem: Column {
                    spacing: 2
                    Label {
                        text: shelf.bookTitleFor(modelData.bookId)
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Label {
                        text: (modelData.chapterTitle || "")
                              + (modelData.chapterTitle ? " · " : "")
                              + (modelData.snippet || "")
                        font.pixelSize: 12
                        color: UITheme.textSecondary
                        elide: Text.ElideRight
                    }
                }
            }
            ScrollBar.vertical: ScrollBar {}
        }

        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            cellWidth: 190
            cellHeight: 306
            model: Books.booksModel
            delegate: BookCard {
                book: modelData
                onClicked: {
                    const fmt = (modelData.format ?? "").toUpperCase()
                    if (fmt === "PDF")
                        shelf.StackView.view.push("PdfReaderPage.qml", { book: modelData })
                    else
                        shelf.StackView.view.push("ReaderPage.qml", { book: modelData })
                }
            }
            ScrollBar.vertical: ScrollBar {}
        }
    }

    Label {
        anchors.centerIn: parent
        text: qsTr("导入你的第一本书")
        font.pixelSize: 22
        color: UITheme.textDisabled
        visible: Books.booksModel.length === 0
                 && shelf.searchText.length === 0
                 && shelf.currentCategory === ""
    }

    KdFilterSheet {
        id: filterSheet
        z: 20
    }

    function bookById(id) {
        const m = Books.bookByIdModel(id)
        return m && m.id !== undefined ? m : null
    }

    function bookTitleFor(id) {
        const b = shelf.bookById(id)
        return b ? b.title : qsTr("未知书籍")
    }

    function openSearchResult(hit) {
        if (!hit || hit.bookId === undefined) return
        const book = shelf.bookById(hit.bookId)
        if (!book) return
        const fmt = (book.format ?? "").toUpperCase()
        if (fmt === "PDF") return
        shelf.StackView.view.push("ReaderPage.qml", {
            book: book,
            initialChapter: hit.chapterIndex,
            initialParagraph: hit.paragraphIndex
        })
    }
}
