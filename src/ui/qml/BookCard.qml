import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Readdict.Backend

Item {
    id: card
    property var book: ({})
    signal clicked()
    width: 180
    height: 280

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: Material.background
        border.color: Material.dividerColor

        Image {
            id: coverImg
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: 120
            height: 160
            source: card.book.cover ? "file://" + card.book.cover : ""
            fillMode: Image.PreserveAspectCrop
        }

        Text {
            anchors.top: coverImg.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 6
            text: card.book.title ?? ""
            elide: Text.ElideRight
            font.bold: true
        }

        ProgressBar {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 8
            value: card.book.progress ?? 0
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton)
                    cardMenu.popup()
                else
                    card.clicked()
            }
        }
    }

    Menu {
        id: cardMenu
        MenuItem {
            text: qsTr("设置分类")
            onTriggered: categoryDialog.open()
        }
    }

    Dialog {
        id: categoryDialog
        title: qsTr("设置分类") + (card.book.title ? " — " + card.book.title : "")
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        width: 320
        contentItem: ColumnLayout {
            spacing: 12
            Label {
                text: qsTr("选择已有分类")
            }
            ListView {
                id: catList
                Layout.fillWidth: true
                Layout.preferredHeight: 140
                clip: true
                model: Books.categoriesModel
                delegate: ItemDelegate {
                    width: ListView.view.width
                    text: modelData
                    highlighted: ListView.isCurrentItem
                    onClicked: catList.currentIndex = index
                }
                ScrollBar.vertical: ScrollBar {}
            }
            Label {
                text: qsTr("或新建分类")
            }
            TextField {
                id: newCatField
                Layout.fillWidth: true
                placeholderText: qsTr("输入新分类名称…")
            }
        }
        onOpened: {
            newCatField.text = ""
            // 预选当前书籍已有分类（若无则无选中，可新建）
            let idx = Books.categoriesModel.indexOf(card.book.category)
            catList.currentIndex = idx
        }
        onAccepted: {
            let name = newCatField.text.trim()
            if (name.length === 0 && catList.currentIndex >= 0)
                name = Books.categoriesModel[catList.currentIndex] ?? ""
            if (name.length > 0)
                Books.setCategory(card.book.id, name)
        }
    }
}
