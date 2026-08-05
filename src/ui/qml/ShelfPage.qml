import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs
import QtQuick.Layouts
import Readdict.Backend

Page {
    id: shelf
    property string toastText: ""

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
                id: searchField
                Layout.fillWidth: true
                placeholderText: qsTr("搜索书名/作者…")
                onTextChanged: Books.doSearch(text)
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
}
