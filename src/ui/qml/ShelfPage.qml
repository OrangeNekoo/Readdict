import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs
import QtQuick.Layouts
import Readdict.Backend
import Readdict.UI 1.0

Page {
    id: shelf
    // U2：导航页标识（Main 据此联动顶部标签/底部导航高亮与沉浸隐藏）
    property string navId: "shelf"
    property string toastText: ""
    // C8：全文搜索结果（Search.searchAllModel 返回：bookId/chapterIndex/paragraphIndex/
    // chapterTitle/snippet）；空数组表示无结果或未在全文模式。测试经此读模型。
    property var searchResults: []
    // C8：测试/外部句柄（QML 冒烟经此驱动模式切换与输入）
    property alias searchModeBox: searchMode
    property alias searchField: searchEdit
    property alias fulltextList: ftList
    // U3：Kindle 化样式/入口测试句柄——搜索胶囊（bgSearch+全圆角）、搜索图标、
    // 分类下拉（替代原 160px 左侧栏）
    property alias searchBox: searchBox
    property alias searchIcon: searchIcon
    property alias catFilter: catFilter
    // L9（P1#17）：分类筛选按值维护——onActivated 只记分类名，currentIndex 在
    // booksChanged（模型重排/增删）后按值重算，索引漂移不再串选。
    property string currentCategory: ""

    Connections {
        target: Importer
        function onImportFailed(message, fileName) {
            shelf.toastText = message + "：" + fileName
            toastTimer.restart()
        }
    }
    Connections {
        target: Books
        // 分类模型随 booksChanged 重算——按值找回选中项索引（model 已含首项"全部"，
        // indexOf 返回值即 ComboBox 索引，无额外偏移）；分类消失（书被删/改类）则
        // 回"全部"并清值
        function onBooksChanged() {
            const idx = catFilter.model.indexOf(shelf.currentCategory)
            if (idx < 0) {
                shelf.currentCategory = ""
                catFilter.currentIndex = 0
            } else {
                catFilter.currentIndex = idx
            }
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

            // U3：Kindle 搜索胶囊——全圆角（~20px）浅灰底（bgSearch #E8E8E3）+
            // 内嵌放大镜图标 + 占位文字。TextField 自身去边框透明，套在胶囊内。
            Rectangle {
                id: searchBox
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: 18
                color: UITheme.bgSearch
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 6
                    spacing: 6
                    Label {
                        id: searchIcon
                        text: "⌕"
                        color: UITheme.textSecondary
                        font.pixelSize: 15
                    }
                    TextField {
                        id: searchEdit
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        placeholderText: qsTr("搜索书名/作者…")
                        background: Rectangle { color: "transparent" }
                        // C8：元数据模式过滤书架网格（Books.doSearch）；全文模式查 FTS5
                        //（防抖：输入停止 250ms 后才搜，避免逐键触发 FTS 查询）
                        onTextChanged: {
                            if (searchMode.currentIndex === 1)
                                ftSearchTimer.restart()
                            else
                                Books.doSearch(text)
                        }
                    }
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

            // U3：分类入口（Kindle 下拉形式，替代原 160px 左侧分类侧栏）——
            // 首项"全部"（清筛选，Books.setFilter("")），其后为 categoriesModel
            // 实时派生（booksChanged 触发绑定重算，新建/清除分类即时反映）。
            ComboBox {
                id: catFilter
                Layout.preferredWidth: 110
                model: [qsTr("全部")].concat(Books.categoriesModel)
                onActivated: {
                    shelf.currentCategory = catFilter.currentIndex === 0
                        ? "" : catFilter.model[catFilter.currentIndex]
                    Books.setFilter(shelf.currentCategory)
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
                        color: UITheme.textSecondary
                        elide: Text.ElideRight
                    }
                }
            }
            ScrollBar.vertical: ScrollBar {}
        }

        // U3：分类侧栏（160px ListView）移除——分类筛选迁至工具栏 catFilter 下拉；
        // 网格占满整行宽度（Books.setFilter 接口不变，功能行为一致）。
        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            // U3：Kindle 封面网格——封面主导，单元格贴合卡片尺寸（180×296，
            // 卡 180×296 + 边距 → 190×306，横向间距 10px 接近 Kindle 主页封面墙）
            cellWidth: 190
            cellHeight: 306
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

    // D7：空状态——书库无书（且无搜索词/分类筛选）时居中提示。
    // 用 booksModel.length（过滤后）判断空网格，但仅当无搜索词且无筛选时
    // 才显示"导入第一本书"文案，避免搜索 0 命中时出现误导性提示。
    Label {
        anchors.centerIn: parent
        text: qsTr("导入你的第一本书")
        font.pixelSize: 22
        color: UITheme.textDisabled
        visible: Books.booksModel.length === 0
                 && shelf.searchEdit.text.length === 0
                 && catFilter.currentIndex === 0
    }

    // ---- C8：全文搜索结果辅助 ----
    // L6（P0#7）：改走 Books.bookByIdModel 全库查——目标书被分类过滤/搜索词
    // 挤出 booksModel 时跳转仍能取到书；书不存在时后端返回空 map → 归一为 null
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
        if (fmt === "PDF") return  // PDF 无段落模型，不建全文索引，也不会命中
        // 打开书 → 定位章节 → 滚动到命中段（ReaderPage 的 initialChapter/initialParagraph）
        shelf.StackView.view.push("ReaderPage.qml", {
            book: book,
            initialChapter: hit.chapterIndex,
            initialParagraph: hit.paragraphIndex
        })
    }
}
