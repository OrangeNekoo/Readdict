import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs
import QtQuick.Layouts
import Readdict.Backend

Page {
    id: shelf

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
                    // 阅读页 ReaderPage 属计划 B；当前点击仅记录日志，避免跳转到不存在的页面
                    onClicked: console.log("书架: 点击书籍 id=" + modelData.id + " 标题=" + modelData.title + "（阅读页将在计划 B 接入）")
                }
                ScrollBar.vertical: ScrollBar {}
            }
        }
    }
}
