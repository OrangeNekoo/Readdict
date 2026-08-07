import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Effects
import QtQuick.Layouts
import Readdict.Backend

Item {
    id: card
    property var book: ({})
    // 测试/外部句柄（QML 冒烟经此驱动删除对话框交互，对齐 ShelfPage/SettingsPage 模式）
    property alias deleteDialog: deleteDialog
    property alias deleteFilesCheck: deleteFilesCheck
    property alias deleteWarning: deleteWarning
    signal clicked()
    width: 180
    height: 280

    // D7：悬停上浮——scale 1.03 + Behavior 缓动（Material 卡片悬停反馈）
    scale: cardMouse.hovered ? 1.03 : 1.0
    Behavior on scale {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
    }

    // B1：删除入口——右键菜单触发（亦供 QML 冒烟测试/复用直接调用）
    function requestDelete() { deleteDialog.open() }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: Material.background
        border.color: Material.dividerColor
        // D7：轻阴影（Material elevation）——layer 化后按圆角形状投影，随悬停缩放联动
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 0.4
            shadowColor: "#3D000000"
            shadowVerticalOffset: 2
        }

        // D7：封面圆角——Rectangle 圆角 + clip 裁剪（Image 无 radius 属性）
        Rectangle {
            id: coverImg
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: 120
            height: 160
            radius: 6
            clip: true
            Image {
                anchors.fill: parent
                source: card.book.cover ? "file://" + card.book.cover : ""
                fillMode: Image.PreserveAspectCrop
            }
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
            id: cardMouse
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
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
        MenuItem {
            text: qsTr("删除")
            onTriggered: card.requestDelete()
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
            Button {
                text: qsTr("清除分类")
                // 仅当该书已设分类时可清除；清除后侧栏 categoriesModel（按书籍分类派生）自动移除该分类
                enabled: (card.book.category ?? "").length > 0
                onClicked: {
                    Books.setCategory(card.book.id, "")
                    categoryDialog.close()
                }
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

    // B1：删除确认对话框——破坏性操作必须有确认；默认不勾选删文件（防误触）
    Dialog {
        id: deleteDialog
        title: qsTr("删除书籍") + (card.book.title ? " — " + card.book.title : "")
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        width: 360
        contentItem: ColumnLayout {
            spacing: 12
            Label {
                id: deleteWarning
                text: qsTr("删除后无法恢复，确定要删除这本书吗？")
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            CheckBox {
                id: deleteFilesCheck
                text: qsTr("同时删除书库中的文件")
            }
        }
        // 每次打开复位为不删文件，避免上次勾选状态误伤
        onOpened: deleteFilesCheck.checked = false
        onAccepted: Books.removeBookWithFiles(card.book.id, deleteFilesCheck.checked)
    }
}
