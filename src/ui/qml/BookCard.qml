import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Effects
import QtQuick.Layouts
import Readdict.Backend
import Readdict.UI 1.0

Item {
    id: card
    property var book: ({})
    // 测试/外部句柄（QML 冒烟经此驱动删除对话框交互，对齐 ShelfPage/SettingsPage 模式）
    property alias deleteDialog: deleteDialog
    property alias deleteFilesCheck: deleteFilesCheck
    property alias deleteWarning: deleteWarning
    // B2：封面兜底测试句柄——封面图/占位块/首字文本供冒烟断言互斥显示
    property alias coverImage: coverImage
    property alias coverPlaceholder: coverPlaceholder
    property alias coverLetterText: coverLetterText
    // B2：空封面或加载失败时显示品牌色占位。Image 无 source 时 status 是 Null
    // 而非 Error，故条件由「cover 非空」与「status 非 Error」双重构成：空 cover
    // 走第一支短路为 true；有 source 但文件缺失/解码失败（Error）走第二支。
    // Loading/Ready 期间占位隐藏，真实封面淡入。
    readonly property bool showPlaceholder: !card.book.cover || coverImage.status === Image.Error
    signal clicked()
    // B5：Kindle 主页风格——封面主导（近满宽）、标题下置（小号非加粗）、进度细条
    // C5：封面墙强化——封面占比更大（宽 -12、高 176、顶距 8）、新增作者行（小字灰，
    // 有作者才显示），卡片 180×280（网格 cell 190×294，见 ShelfPage）。
    width: 180
    height: 280
    // C5：作者行句柄（冒烟断言有作者显示/无作者隐藏）
    property alias authorLabel: authorLabel

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
            anchors.topMargin: 8
            width: parent.width - 12
            height: 176
            radius: 6
            clip: true
            Image {
                id: coverImage
                anchors.fill: parent
                source: card.book.cover ? "file://" + card.book.cover : ""
                fillMode: Image.PreserveAspectCrop
                visible: !card.showPlaceholder
            }
            // B2：Kindle 风格占位——近黑底（Kindle 选中/强调 Token）+ 白色首字；
            // U1：原品牌色靛蓝 #3D5AFE 移除，改固定近黑（lightBorderActive #1A1A1A，
            // 两模式对比度恒保证：白字在黑底上）；与封面图互斥显示
            Rectangle {
                id: coverPlaceholder
                anchors.fill: parent
                visible: card.showPlaceholder
                color: UITheme.lightBorderActive
                Text {
                    id: coverLetterText
                    anchors.centerIn: parent
                    text: (card.book.title ?? "") !== "" ? card.book.title[0] : "?"
                    color: "white"
                    font.pixelSize: 56
                    font.bold: true
                }
            }
        }

        Text {
            id: titleText
            anchors.top: coverImg.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: 8
            text: card.book.title ?? ""
            elide: Text.ElideRight
            font.pixelSize: 13
            color: Material.theme === Material.Dark ? "#CCCCCC" : "#333333"
        }

        // C5：作者行（Kindle 主页封面下 标题 + 作者 双行）——小字灰色，仅书有作者时显示
        Text {
            id: authorLabel
            anchors.top: titleText.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: 2
            text: card.book.author ?? ""
            visible: (card.book.author ?? "").length > 0
            elide: Text.ElideRight
            font.pixelSize: 11
            color: Material.theme === Material.Dark ? "#888888" : "#8A8A8A"
        }

        // B5：进度细条（Kindle 主页风格）——细 3px 圆角线替代 ProgressBar；
        // U1：填充色改 Kindle 选中 Token（light #1A1A1A / dark #E8E8E3，
        // 原 Material.accent 靛蓝移除——不覆盖 accent 后 Material 默认 accent 为
        // 粉色，必须显式改 Token）
        Rectangle {
            id: progressLine
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.bottomMargin: 10
            height: 3
            radius: 1.5
            color: Material.theme === Material.Dark ? "#33FFFFFF" : "#22000000"
            Rectangle {
                width: Math.max(0, Math.min(1, card.book.progress ?? 0)) * parent.width
                height: parent.height
                radius: parent.radius
                color: UITheme.borderActive
            }
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
