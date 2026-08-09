import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.Backend
import Readdict.UI 1.0

// 图书馆筛选与排序底部面板。所有选择按值维护，选择后立即更新 Books 并持久化。
// 对外接口：currentCategory/currentSort/currentScope、open()/close()、scopeChanged；
// catList/sortList/scopeList 为测试与宿主句柄。
Item {
    id: sheet
    anchors.fill: parent
    visible: false

    property string currentCategory: ""
    property int currentSort: 0
    property int currentScope: 0
    signal scopeChanged(int scope)
    property alias catList: catList
    property alias sortList: sortList
    property alias scopeList: scopeList
    property bool ready: false

    function open() { sheet.visible = true }
    function close() { sheet.visible = false }

    function settingString(value, fallback) {
        if (value === undefined || value === null) return fallback
        if (typeof value === "string") return value
        if (value && typeof value.toString === "function") {
            const text = value.toString()
            return text.length > 0 ? text : fallback
        }
        return String(value)
    }
    function syncIndexes() {
        catList.currentIndex = sheet.currentCategory === "" ? 0 : Math.max(0, catList.model.indexOf(sheet.currentCategory))
        sortList.currentIndex = sheet.currentSort
        scopeList.currentIndex = sheet.currentScope
    }

    function chooseCategory(index) {
        sheet.currentCategory = index === 0 ? "" : catList.model[index]
        if (catList.currentIndex !== index) catList.currentIndex = index
        Books.setFilter(sheet.currentCategory)
        Settings.setValue("shelf/category", sheet.currentCategory)
    }
    function chooseSort(index) {
        sheet.currentSort = index
        if (sortList.currentIndex !== index) sortList.currentIndex = index
        Books.setSort(index)
        Settings.setValue("shelf/sort", index)
    }
    function chooseScope(index) {
        sheet.currentScope = index
        if (scopeList.currentIndex !== index) scopeList.currentIndex = index
        Settings.setValue("shelf/scope", index)
        sheet.scopeChanged(index)
    }
    Connections {
        target: Books
        function onBooksChanged() {
            if (!sheet.ready) return
            const categories = Books.categoriesModel
            if (sheet.currentCategory !== "" && categories.indexOf(sheet.currentCategory) < 0) {
                sheet.currentCategory = ""
                Settings.setValue("shelf/category", "")
                Books.setFilter("")
            }
            sheet.syncIndexes()
        }
    }



    Rectangle {
        anchors.fill: parent
        color: UITheme.overlay
        visible: sheet.visible
        MouseArea {
            anchors.fill: parent
            onClicked: sheet.close()
        }
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
            clip: true
            ColumnLayout {
                width: parent.width
                spacing: 8

                Label {
                    text: qsTr("分类")
                    font.bold: true
                    color: UITheme.textPrimary
                }
                ListView {
                    id: catList
                    Layout.fillWidth: true
                    Layout.preferredHeight: count * 48
                    interactive: false
                    cacheBuffer: 1000
                    model: [qsTr("全部")].concat(Books.categoriesModel)
                    delegate: RadioButton {
                        width: catList.width
                        height: 48
                        text: modelData
                        checked: sheet.currentCategory === (index === 0 ? "" : modelData)
                        onClicked: sheet.chooseCategory(index)
                    }
                    onCurrentIndexChanged: {
                        const selected = sheet.currentCategory === "" ? 0
                            : Books.categoriesModel.indexOf(sheet.currentCategory) + 1
                        if (sheet.ready && currentIndex >= 0 && currentIndex !== selected)
                            sheet.chooseCategory(currentIndex)
                    }
                }

                Label {
                    text: qsTr("排序")
                    font.bold: true
                    color: UITheme.textPrimary
                }
                ListView {
                    id: sortList
                    Layout.preferredHeight: count * 48
                    interactive: false
                    cacheBuffer: 1000
                    model: [qsTr("最近添加"), qsTr("作者"), qsTr("出版社"), qsTr("类型"), qsTr("最近阅读")]
                    delegate: RadioButton {
                        width: sortList.width
                        text: modelData
                        checked: index === sheet.currentSort
                        height: 48
                        onClicked: sheet.chooseSort(index)
                    }
                    onCurrentIndexChanged: {
                        if (sheet.ready && currentIndex >= 0 && currentIndex !== sheet.currentSort)
                            sheet.chooseSort(currentIndex)
                    }
                }

                Label {
                    text: qsTr("搜索范围")
                    font.bold: true
                    color: UITheme.textPrimary
                }
                ListView {
                    id: scopeList
                    Layout.preferredHeight: count * 48
                    interactive: false
                    cacheBuffer: 1000
                    model: [qsTr("元数据"), qsTr("全文")]
                    delegate: RadioButton {
                        width: scopeList.width
                        text: modelData
                        checked: index === sheet.currentScope
                        height: 48
                        onClicked: sheet.chooseScope(index)
                    }
                    onCurrentIndexChanged: {
                        if (sheet.ready && currentIndex >= 0 && currentIndex !== sheet.currentScope)
                            sheet.chooseScope(currentIndex)
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        sheet.currentCategory = sheet.settingString(Settings.value("shelf/category"), "")
        sheet.currentSort = Number(Settings.value("shelf/sort")) || 0
        sheet.currentScope = Number(Settings.value("shelf/scope")) || 0
        sheet.syncIndexes()
        sheet.ready = true
        Books.setFilter(sheet.currentCategory)
        Books.setSort(sheet.currentSort)
    }
}
