import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// 阅读页底部浮动控制栏：章节导航 / 目录 / 字号 / 背景四态 / 对齐 / 页宽。
// B5：Kindle 式图标工具栏——unicode 符号 + 短文字（非 emoji），悬停 ToolTip 显全名。
// 全部以信号上报 ReaderPage 处理（状态读写集中在页面，本组件无状态）。
// 注意：按钮 children 顺序不可变（ControlsSmoke 依赖 children[3]=A−、children[5]=A+），
// 新按钮只追加行尾（C7 笔记 / C8 搜索 即行尾追加，B5 未动）。
Rectangle {
    id: controls
    property int fontSize: 18
    property string bgMode: "light"   // 随阅读背景切换前景/底色，保证深色下可读
    // C5：阅读进度（0..1，章节粒度，ReaderPage 注入）——驱动底部 Kindle 式进度细条
    property real chapterProgress: 0
    signal prevChapter()
    signal nextChapter()
    signal changeFontSize(int size)
    signal toggleBackground()
    signal toggleAlign()
    signal togglePageWidth()
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
    // D4：字体弹层开合状态——ReaderPage 暂停控制栏 5s 自动隐藏（弹层是独立窗口，
    // 其内点击不会重置页面计时器，不暂停会弹层开着控制栏就淡出）
    property bool fontMenuOpen: fontPopup.opened
    // D4：测试句柄（QML 冒烟经此打开弹层/驱动选择）
    property alias fontPopup: fontPopup
    property alias fontList: fontPopupList

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
        CtlBtn { iconChar: "◐"; lbl: qsTr("背景"); tip: qsTr("切换阅读背景"); onClicked: controls.toggleBackground() }
        CtlBtn { iconChar: "☷"; lbl: qsTr("对齐"); tip: qsTr("切换对齐方式"); onClicked: controls.toggleAlign() }
        CtlBtn { iconChar: "↔"; lbl: qsTr("页宽"); tip: qsTr("切换页宽"); onClicked: controls.togglePageWidth() }
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
            color: "#E8993D"   // Kindle 琥珀橙进度色（深浅背景均可见）
        }
    }
}
