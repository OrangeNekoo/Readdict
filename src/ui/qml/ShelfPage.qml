import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs
import QtQuick.Layouts
import Readdict.Backend

Page {
    id: shelf
    property string toastText: ""
    // C8：全文搜索结果（Search.searchAllModel 返回：bookId/chapterIndex/paragraphIndex/
    // chapterTitle/snippet）；空数组表示无结果或未在全文模式。测试经此读模型。
    property var searchResults: []
    // C8：测试/外部句柄（QML 冒烟经此驱动模式切换与输入）
    property alias searchModeBox: searchMode
    property alias searchField: searchEdit
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

    // 导入失败 SnackBar 风格提示（成功导入由书籍网格出现新卡片体现，无需提示）
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
            Layout.margins: 12
            spacing: 8

            TextField {
                id: searchEdit
                Layout.fillWidth: true
                placeholderText: qsTr("搜索书名/作者…")
                // C8：元数据模式过滤书架网格（Books.doSearch）；全文模式查 FTS5
                //（防抖：输入停止 250ms 后才搜，避免逐键触发 FTS 查询）
                onTextChanged: {
                    if (searchMode.currentIndex === 1)
                        ftSearchTimer.restart()
                    else
                        Books.doSearch(text)
                }
            }

            // C8：搜索范围切换——元数据（书名/作者，保持原书架过滤）或全文
            //（全书内容命中，结果列在搜索框下方，点击跳转到对应段落）。
            // 进入全文模式时清空网格的元数据过滤（Books.doSearch("")），
            // 避免残留旧搜索词把网格卡在过滤态。
            ComboBox {
                id: searchMode
                Layout.preferredWidth: 96
                model: [qsTr("元数据"), qsTr("全文")]
                onActivated: {
                    if (index === 1) {
                        Books.doSearch("")
                        ftSearchTimer.restart()
                    } else {
                        Books.doSearch(searchEdit.text)
                    }
                }
            }

            // C8：全文搜索防抖（输入停止 250ms 后执行）
            Timer {
                id: ftSearchTimer
                interval: 250
                repeat: false
                onTriggered: {
                    shelf.searchResults = Search.searchAllModel(searchEdit.text)
                }
            }

            ComboBox {
                id: sortBox
                model: [qsTr("最近添加"), qsTr("作者"), qsTr("出版社"), qsTr("类型"), qsTr("最近阅读")]
                onActivated: Books.setSort(index)
            }

            Button {
                text: qsTr("导入")
                onClicked: fileDialog.open()
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

            // D3：设置入口（设置页含 WebDAV 同步页导航）
            Button {
                text: qsTr("设置")
                onClicked: shelf.StackView.view.push("SettingsPage.qml")
            }
        }

        // C8：全文搜索结果列表（书名/章节/摘要，点击打开对应书与段落）
        ListView {
            id: ftList
            Layout.fillWidth: true
            Layout.preferredHeight: 300
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            visible: searchMode.currentIndex === 1 && searchEdit.text.length > 0
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
                        color: "#666666"
                        elide: Text.ElideRight
                    }
                }
            }
            ScrollBar.vertical: ScrollBar {}
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            ListView {
                id: catList
                Layout.preferredWidth: 160
                Layout.fillHeight: true
                model: Books.categoriesModel
                delegate: ItemDelegate {
                    width: ListView.view.width
                    text: modelData
                    highlighted: ListView.isCurrentItem
                    onClicked: {
                        Books.setFilter(modelData)
                        catList.currentIndex = index
                    }
                }
                header: ItemDelegate {
                    text: qsTr("全部")
                    highlighted: catList.currentIndex < 0
                    onClicked: {
                        Books.setFilter("")
                        catList.currentIndex = -1
                    }
                }
            }

            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: 200
                cellHeight: 300
                model: Books.booksModel
                delegate: BookCard {
                    book: modelData
                    // 文本格式进入阅读页；PDF 进入 PDF 阅读页（B9，按 format 分流）
                    onClicked: {
                        const fmt = (modelData.format ?? "").toUpperCase()
                        if (fmt === "PDF") {
                            shelf.StackView.view.push("PdfReaderPage.qml", { book: modelData })
                        } else {
                            shelf.StackView.view.push("ReaderPage.qml", { book: modelData })
                        }
                    }
                }
                ScrollBar.vertical: ScrollBar {}
            }
        }
    }

    // ---- C8：全文搜索结果辅助 ----
    function bookById(id) {
        for (let b of Books.booksModel)
            if (b.id === id) return b
        return null
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
        if (fmt === "PDF") return  // PDF 无段落模型，不建全文索引，也不会命中
        // 打开书 → 定位章节 → 滚动到命中段（ReaderPage 的 initialChapter/initialParagraph）
        shelf.StackView.view.push("ReaderPage.qml", {
            book: book,
            initialChapter: hit.chapterIndex,
            initialParagraph: hit.paragraphIndex
        })
    }
}
