import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.Backend
import Readdict.UI 1.0

Item {
    id: card
    property var book: ({})
    property bool compact: false
    // 测试/外部句柄（QML 冒烟经此驱动删除对话框交互，对齐 ShelfPage/SettingsPage 模式）
    property alias deleteDialog: deleteDialog
    property alias deleteFilesCheck: deleteFilesCheck
    property alias deleteWarning: deleteWarning
    // B2：封面兜底测试句柄——封面图/占位块/首字文本供冒烟断言互斥显示
    property alias coverImage: coverImage
    property alias progressBadge: progressBadge
    property alias newBadge: newBadge
    property alias progressBadgeLabel: pctLabel
    function isNew(addedAt) {
        return !!addedAt && (Date.now() - new Date(addedAt).getTime()) < 7 * 86400000
    }

    property alias coverPlaceholder: coverPlaceholder
    property alias coverLetterText: coverLetterText
    // U3：Kindle 化样式测试句柄——封面剪裁块（无圆角断言）、轻投影（shadowBook）、
    // 卡片底（无边框断言）、标题（fsListItem 字号断言）
    property alias coverClip: coverImg
    property alias coverShadow: coverShadow
    property alias cardChrome: cardChrome
    property alias cardTitle: titleText
    // B2：空封面或加载失败时显示品牌色占位。Image 无 source 时 status 是 Null
    // 而非 Error，故条件由「cover 非空」与「status 非 Error」双重构成：空 cover
    // 走第一支短路为 true；有 source 但文件缺失/解码失败（Error）走第二支。
    // Loading/Ready 期间占位隐藏，真实封面淡入。
    readonly property bool showPlaceholder: !card.book.cover || coverImage.status === Image.Error
    signal clicked()
    // U3：Kindle 封面网格——封面 3:4（宽 -12 = 168，高 224）、无圆角、轻投影
    //（UITheme.shadowBook rgba(0,0,0,0.08)）、无卡片边框；标题下置 15px（fsListItem）、
    // 作者小字灰（textSecondary）、进度细条。卡片 180×296（网格 cell 190×306，见 ShelfPage）。
    width: compact ? 96 : 180
    height: compact ? 168 : 296
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
        id: cardChrome
        anchors.fill: parent
        // U3：Kindle 化——无圆角、无边框（原 D7 radius 8 + border dividerColor +
        // layer/MultiEffect 重阴影 #3D000000 移除；轻投影改走 coverShadow 纯 Rectangle，
        // 网格多卡片场景免每卡一层 GPU layer，悬停缩放也不再触发整卡重渲染）
        radius: 0
        // U6：底色改 Token（原 Material.background——Main 已把它绑到 bgPrimary，
        // 直引 Token 去除框架依赖；卡片与书架同底，视觉由封面主导）
        color: UITheme.bgPrimary
        border.color: "transparent"

        // U3：轻投影——封面下方 2px 偏移的 shadowBook（rgba(0,0,0,0.08)）矩形；
        // 声明在封面之前故渲染于其下。Kindle 封面为直角矩形，硬边 8% 黑阴影
        // 视觉即足，无需 blur。
        Rectangle {
            id: coverShadow
            anchors.fill: coverImg
            anchors.topMargin: 2
            color: UITheme.shadowBook
        }

        // U3：封面无圆角（Kindle 封面直角，radius 0；clip 保留供图裁剪）
        Rectangle {
            id: coverImg
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: 8
            width: parent.width - 12
            height: compact ? 128 : 224 // 3:4；compact 适配主页横排封面
            radius: 0
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
            // 进度百分比角标（0<progress<1 时显示）
            Rectangle {
                id: progressBadge
                anchors.top: parent.top
                anchors.right: parent.right
                visible: card.book.progress > 0 && card.book.progress < 1
                color: UITheme.textPrimary
                width: pctLabel.width + 8
                height: 18
                Label {
                    id: pctLabel
                    anchors.centerIn: parent
                    text: Math.round(card.book.progress * 100) + "%"
                    font.pixelSize: 11
                    color: UITheme.bgPrimary
                }
            }
            // 新书角标：添加时间在七天内且尚未阅读
            Rectangle {
                id: newBadge
                anchors.top: parent.top
                visible: card.book.progress === 0 && !!card.isNew(card.book.addedAt)
                color: UITheme.textPrimary
                width: 22
                height: 18
                Label {
                    anchors.centerIn: parent
                    text: qsTr("新")
                    font.pixelSize: 11
                    color: UITheme.bgPrimary
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
            // U3：Kindle 列表项字号（fsListItem 15px），颜色走 textPrimary Token
            font.pixelSize: UITheme.fsListItem
            color: UITheme.textPrimary
        }

        // C5：作者行（Kindle 主页封面下 标题 + 作者 双行）——小字灰色，仅书有作者时显示；
        // U3：字号 12px（fsCaption 区间）、颜色走 textSecondary Token
        Text {
            id: authorLabel
            anchors.top: titleText.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: 2
            text: card.book.author ?? ""
            visible: !card.compact && (card.book.author ?? "").length > 0
            elide: Text.ElideRight
            font.pixelSize: 12
            color: UITheme.textSecondary
        }

        // B5：进度细条（Kindle 主页风格）——细 3px 圆角线替代 ProgressBar；
        // U1：填充色改 Kindle 选中 Token（light #1A1A1A / dark #E8E8E3）；
        // U3：轨道色改 divider Token（原硬编码 #33FFFFFF/#22000000 移除）
        Rectangle {
            visible: !card.compact
            id: progressLine
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.bottomMargin: 10
            height: 3
            radius: 1.5
            color: UITheme.divider
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
                // 仅当该书已设分类时可清除；清除后 categoriesModel（按书籍分类派生）自动移除该分类
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
