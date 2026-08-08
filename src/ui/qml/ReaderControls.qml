import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.UI 1.0

// 阅读页底部浮动控制栏：章节导航 / 目录 / 字号 / 背景四态 / 对齐 / 页宽。
// B5：Kindle 式图标工具栏——unicode 符号 + 短文字（非 emoji），悬停 ToolTip 显全名。
// E3：背景/对齐/页宽从轮询切换改为底部上拉框直接选择（ModeSheet 弹层，
// 当前值高亮、选中即应用+关闭）；其余仍以信号上报 ReaderPage 处理（状态读写
// 集中在页面，本组件无状态）。
// 注意：按钮 children 顺序不可变（ControlsSmoke 依赖 children[3]=A−、children[5]=A+），
// 新按钮只追加行尾（C7 笔记 / C8 搜索 即行尾追加，B5 未动）；Popup 弹层是独立
// 窗口不占 children 索引。
Rectangle {
    id: controls
    property int fontSize: 18
    property string bgMode: "light"   // 随阅读背景切换前景/底色，保证深色下可读
    // C5：阅读进度（0..1，章节粒度，ReaderPage 注入）——驱动底部 Kindle 式进度细条
    property real chapterProgress: 0
    signal prevChapter()
    signal nextChapter()
    signal changeFontSize(int size)
    // E3：背景/对齐/页宽由轮询切换改为上拉框直接选择——三个 set 信号（值见
    // backgroundModel/alignModel/pageWidthModel），不再有 toggle* 信号
    signal setBackgroundMode(string mode)
    signal setAlign(string align)
    signal setPageWidth(string width)
    signal openToc()
    signal openNotes()
    // C8：书内搜索（ReaderPage 打开 Dialog → Search.searchModel(bookId) → 跳转）
    signal openSearch()
    // C2：朗读入口——TtsBar 门控后默认隐藏，朗读只能从控制栏启动；
    // ReaderPage 接住：无会话/暂停时 Tts.play()（TtsBar 随 state 门控显示）
    signal readAloud()
    // D4：正文字体选择——ReaderPage 接住写 typography/fontFamily 并刷新排版
    signal setFontFamily(string family)
    // C2：朗读按钮句柄（ReaderPage 冒烟测试经此点击；同一文档内 alias，供外部实例访问）
    property alias readAloudBtn: readBtn
    // D4：当前字族存储 token（ReaderPage 注入 Settings 值，驱动弹层高亮当前项）
    property string fontFamily: ""
    // E3：当前背景图片路径（ReaderPage 注入，驱动上拉框 image 项启用态与提示）
    property string bgImagePath: ""
    // E3：当前对齐/页宽（ReaderPage 注入 typography 值，驱动上拉框高亮当前项）
    property string align: "left"
    property string pageWidth: "normal"
    // D4：字体弹层开合状态——ReaderPage 暂停控制栏 5s 自动隐藏（弹层是独立窗口，
    // 其内点击不会重置页面计时器，不暂停会弹层开着控制栏就淡出）
    property bool fontMenuOpen: fontPopup.opened
    // E3：三个上拉框任一打开即暂停 5s 自动隐藏（同 fontMenuOpen 语义），关闭恢复
    property bool sheetOpen: bgPopup.opened || alignPopup.opened || widthPopup.opened
    // D4：测试句柄（QML 冒烟经此打开弹层/驱动选择）
    property alias fontPopup: fontPopup
    property alias fontList: fontPopupList
    // E3：测试句柄（冒烟经此打开上拉框/驱动选择/断言高亮与禁用态）
    property alias bgPopup: bgPopup
    property alias bgList: bgPopup.listView
    property alias alignPopup: alignPopup
    property alias alignList: alignPopup.listView
    property alias widthPopup: widthPopup
    property alias widthList: widthPopup.listView

    // E3：上拉框三组数据（text 可翻译、value 为存储 token——与 ReaderPage 的
    // bgMode/typography.align/pageWidth 语义一致；浅/深/米白/自定义图片沿用
    // SettingsPage 同一源串，lupdate 归并为同一条消息）。
    property var backgroundModel: [
        { text: qsTr("浅色"), value: "light" },
        { text: qsTr("深色"), value: "dark" },
        { text: qsTr("米白"), value: "paper" },
        { text: qsTr("自定义图片"), value: "image" }
    ]
    property var alignModel: [
        { text: qsTr("左对齐"), value: "left" },
        { text: qsTr("居中"), value: "center" },
        { text: qsTr("右对齐"), value: "right" }
    ]
    property var pageWidthModel: [
        { text: qsTr("窄"), value: "narrow" },
        { text: qsTr("正常"), value: "normal" },
        { text: qsTr("宽"), value: "wide" }
    ]

    // C5：46px 细条（与 TtsBar 同高、比旧 52px 更 Kindle）；ReaderPage 的
    // controlsHost 同高，tst_readerpage 几何断言同步（52→46）。
    height: 46
    color: controls.bgMode === "dark" ? "#F2121212" : "#F2FFFFFF"
    property color fgColor: controls.bgMode === "dark" ? "#E6E6E6" : "#1A1A1A"

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: controls.bgMode === "dark" ? "#33FFFFFF" : "#1A000000"
    }

    // B5：iconChar 图标字符 + lbl 短文字；tip 为 ToolTip 全名（不参与布局，
    // ToolTip 是附加属性内部对象，不影响 RowLayout children 索引）。
    component CtlBtn: ToolButton {
        required property string lbl
        property string iconChar: ""
        property string tip: ""
        text: iconChar.length > 0 ? iconChar + " " + lbl : lbl
        font.pixelSize: 12
        padding: 4
        ToolTip.visible: hovered && tip.length > 0
        ToolTip.text: tip
        ToolTip.delay: 600
        contentItem: Text {
            text: parent.text
            color: controls.fgColor
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 2
        CtlBtn { iconChar: "⇤"; lbl: qsTr("上章"); tip: qsTr("上一章"); onClicked: controls.prevChapter() }
        CtlBtn { iconChar: "☰"; lbl: qsTr("目录"); tip: qsTr("目录"); onClicked: controls.openToc() }
        Item { Layout.fillWidth: true }
        CtlBtn { lbl: "A−"; tip: qsTr("减小字号"); onClicked: controls.changeFontSize(controls.fontSize - 1) }
        Label {
            text: controls.fontSize
            color: controls.fgColor
            Layout.preferredWidth: 26
            horizontalAlignment: Text.AlignHCenter
        }
        CtlBtn { lbl: "A+"; tip: qsTr("增大字号"); onClicked: controls.changeFontSize(controls.fontSize + 1) }
        CtlBtn { id: bgBtn; iconChar: "◐"; lbl: qsTr("背景"); tip: qsTr("选择阅读背景"); onClicked: bgPopup.open() }
        CtlBtn { id: alignBtn; iconChar: "☷"; lbl: qsTr("对齐"); tip: qsTr("选择对齐方式"); onClicked: alignPopup.open() }
        CtlBtn { id: widthBtn; iconChar: "↔"; lbl: qsTr("页宽"); tip: qsTr("选择页宽"); onClicked: widthPopup.open() }
        CtlBtn { iconChar: "⇥"; lbl: qsTr("下章"); tip: qsTr("下一章"); onClicked: controls.nextChapter() }
        // C7：笔记列表（追加在行尾，保持既有按钮的 children 索引不变——ControlsSmoke 依赖）
        CtlBtn { iconChar: "≣"; lbl: qsTr("笔记"); tip: qsTr("笔记列表"); onClicked: controls.openNotes() }
        // C8：书内搜索（同样追加行尾，不动既有索引）
        CtlBtn { iconChar: "⌕"; lbl: qsTr("搜索"); tip: qsTr("书内搜索"); onClicked: controls.openSearch() }
        // C2：朗读入口（追加行尾保持既有 children 索引——ControlsSmoke 依赖 children[3]/[5]）
        CtlBtn {
            id: readBtn
            iconChar: "▶"; lbl: qsTr("朗读"); tip: qsTr("开始朗读")
            onClicked: controls.readAloud()
        }
        // D4：正文字体（行尾追加 children[13]，保持既有 0..12 索引不变——ControlsSmoke 依赖）
        CtlBtn {
            iconChar: "Aa"; lbl: qsTr("字体"); tip: qsTr("选择正文字体")
            onClicked: fontPopup.open()
        }
    }

    // E3：上拉框通用组件——贴控制栏上沿的底部弹层（Popup 独立窗口，与 fontPopup
    // 同机制：不占 controls.children 索引，ControlsSmoke 的 children[0..2] 不受影响）。
    // 圆角顶 + 拖拽把手 + 选项列表（当前值高亮 + ✓ 标记）；选中即发 picked(value) 并关闭。
    // anchorItem：按钮锚点（弹层横向对齐按钮）；disabledValue/disabledValueActive：
    // 逐项禁用（背景的 image 项无图时禁用）；hintText/showHint：底部提示（无图引导）。
    component ModeSheet: Popup {
        id: sheet
        property var items: []
        property string current: ""
        property Item anchorItem: null
        property string disabledValue: ""
        property bool disabledValueActive: false
        property string hintText: ""
        property bool showHint: false
        // 测试句柄：实例经 bgPopup.listView 访问选项列表（驱动选择/断言高亮）
        property alias listView: sheetList
        signal picked(string value)
        width: 230
        padding: 0
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
        // opened 翻转时才求值锚点坐标（行内按钮布局已稳定；mapToItem 调用不被
        // 依赖追踪，提前求值可能拿到未 polish 的 0 坐标）
        x: {
            if (!sheet.opened || !sheet.anchorItem) return 8
            const bx = sheet.anchorItem.mapToItem(controls, 0, 0).x
            return Math.max(4, Math.min(controls.width - sheet.width - 4,
                                        bx + sheet.anchorItem.width / 2 - sheet.width / 2))
        }
        y: -sheet.height - 12
        background: Rectangle {
            radius: 12
            color: controls.bgMode === "dark" ? "#F2262626" : "#FDFFFFFF"
            border.color: controls.bgMode === "dark" ? "#33FFFFFF" : "#1A000000"
        }
        contentItem: Column {
            width: sheet.availableWidth
            spacing: 4
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 36; height: 4; radius: 2
                color: controls.bgMode === "dark" ? "#44FFFFFF" : "#33000000"
            }
            ListView {
                id: sheetList
                width: parent.width
                implicitHeight: sheetList.count * 44 + 8
                clip: true
                model: sheet.items
                delegate: ItemDelegate {
                    width: ListView.view.width
                    height: 44
                    highlighted: modelData.value === sheet.current
                    // 绑定式启用判定（tracked）：disabledValueActive 变化即时重求值
                    enabled: !(modelData.value === sheet.disabledValue && sheet.disabledValueActive)
                    onClicked: {
                        sheet.picked(modelData.value)
                        sheet.close()
                    }
                    contentItem: RowLayout {
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        Label {
                            text: modelData.text
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                            color: controls.bgMode === "dark" ? "#E6E6E6" : "#1A1A1A"
                        }
                        Label {
                            visible: modelData.value === sheet.current
                            text: "✓"
                            color: UITheme.accentAmber
                            font.pixelSize: 14
                        }
                    }
                }
            }
            Label {
                visible: sheet.showHint
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: sheet.hintText
                font.pixelSize: 11
                color: controls.bgMode === "dark" ? "#AAAAAA" : "#888888"
                padding: 8
                wrapMode: Text.Wrap
            }
        }
    }

    // E3：背景上拉框——四态（浅/深/米白/自定义图片，与 ReaderPage bgMode 一致）；
    // 无图时 image 项禁用并显示提示（引导到设置页选图）。选中即发 setBackgroundMode。
    ModeSheet {
        id: bgPopup
        parent: controls
        anchorItem: bgBtn
        items: controls.backgroundModel
        current: controls.bgMode
        disabledValue: "image"
        disabledValueActive: controls.bgImagePath.length === 0
        hintText: qsTr("自定义图片背景需先在设置页选择图片")
        showHint: controls.bgImagePath.length === 0
        onPicked: (v) => controls.setBackgroundMode(v)
    }
    // E3：对齐上拉框——左/中/右，选中即发 setAlign
    ModeSheet {
        id: alignPopup
        parent: controls
        anchorItem: alignBtn
        items: controls.alignModel
        current: controls.align
        onPicked: (v) => controls.setAlign(v)
    }
    // E3：页宽上拉框——窄/正常/宽，选中即发 setPageWidth
    ModeSheet {
        id: widthPopup
        parent: controls
        anchorItem: widthBtn
        items: controls.pageWidthModel
        current: controls.pageWidth
        onPicked: (v) => controls.setPageWidth(v)
    }

    // D4：字体选择弹层——非模态 Popup 位于控制栏上方；数据源 fontListModel 的 value
    // 为存储 token（与 Books.resolveFontFamily 映射链一致，见 D4 扩展），text 为显示名
    //（可翻译；en/zh_TW 的译文不改变 token，避免破坏族名匹配——沿用旧设置页决策）。
    // E3 上拉框统一前先用简单弹层（本任务优先完成功能，样式整合留给 E3）。
    // Popup 不是 Item，不进入 controls.children（进度细条 children[2] 索引不受影响）。
    property var fontListModel: [
        { text: qsTr("思源宋体 VF"), value: "思源宋体 VF" },
        { text: qsTr("思源黑体 VF"), value: "思源黑体 VF" },
        { text: qsTr("思源黑体 HW VF"), value: "SourceHanSansHW-VF" },
        { text: qsTr("得意黑"), value: "得意黑" }
    ]
    Popup {
        id: fontPopup
        parent: controls
        x: Math.max(4, controls.width - fontPopup.width - 8)
        y: -fontPopup.height - 10
        width: 190
        padding: 4
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
        contentItem: ListView {
            id: fontPopupList
            width: fontPopup.availableWidth
            implicitHeight: fontPopupList.count * 40 + 8
            clip: true
            model: controls.fontListModel
            delegate: ItemDelegate {
                width: ListView.view.width
                height: 40
                text: modelData.text
                highlighted: modelData.value === controls.fontFamily
                onClicked: {
                    controls.setFontFamily(modelData.value)
                    fontPopup.close()
                }
            }
            ScrollBar.vertical: ScrollBar {}
        }
    }

    // C5：Kindle 式底部进度细条——2px 琥珀色进度线贴工具栏底边（Kindle 阅读页
    // 底部进度线同构）。声明在 RowLayout 之后（children[2]），children[0]=分隔线、
    // [1]=RowLayout 索引不变（ControlsSmoke 依赖）。宽 = chapterProgress × 全宽。
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 2
        color: controls.bgMode === "dark" ? "#33FFFFFF" : "#14000000"
        Rectangle {
            width: Math.max(0, Math.min(1, controls.chapterProgress)) * parent.width
            height: parent.height
            color: UITheme.accentAmber   // Kindle 琥珀橙进度色（深浅背景均可见）
        }
    }
}
