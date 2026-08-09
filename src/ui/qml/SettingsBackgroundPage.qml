import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs
import QtQuick.Effects
import QtQuick.Layouts
import Readdict.Backend
import Readdict.UI 1.0

// U5：阅读背景设置子页（Kindle 全屏列表化——设置页"阅读背景"行进入）。
// D5 功能原样迁移：四模式单选（浅/深/米白/自定义图片）持久化 background/mode；
// 自定义图片经 FileDialog 选图 → Settings.copyToBackgrounds 复制到
// AppData/backgrounds/ → background/imagePath + mode=image；模糊/亮度滑条即改即存
// background/blur、background/brightness。E2：缩略图实时预览（bgThumb，MultiEffect
// 同阅读页参数）。E4：翻页方式（竖滚连续 scroll / 整页翻动 paged）持久化
// reading/pageMode。U5：单选改为 KdRadioGrid（○/● 网格，分析报告 §4）。
// 返回：固定顶部"← 返回"（B4 模式）。
// 测试/外部句柄：backButton、goBack()、bgGrid（背景四态 KdRadioGrid）、
// bgBlurSlider/bgBrightnessSlider、bgThumb/bgThumbImg/bgThumbFx（缩略图预览）、
// pageModeGrid（翻页方式）、bgImageHint、setBgMode/setBgBlur/setBgBrightness/
// importBackgroundImage/restoreBackground。
Page {
    id: page
    title: qsTr("阅读背景")
    property string navId: "settings"
    property alias backButton: backButton
    property alias bgGrid: bgGrid
    property alias pageModeGrid: pageModeGrid
    property alias bgBlurSlider: bgBlurSlider
    property alias bgBrightnessSlider: bgBrightnessSlider
    property alias bgThumb: bgThumb
    property alias bgThumbImg: bgThumbImg
    property alias bgThumbFx: bgThumbFx
    property alias bgImageHint: bgImageHint
    // 当前背景分区状态（onCompleted 从 Settings 恢复；导入后更新）
    property string bgImagePath: ""
    property real bgBlur: 0.0
    property real bgBrightness: 1.0

    // 固定顶部：返回 + 页面标题（B4 返回导航位，同 SyncPage/StatsPage 模式）
    RowLayout {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        anchors.topMargin: 16
        ToolButton {
            id: backButton
            text: "← " + qsTr("返回")
            onClicked: page.goBack()
        }
        Label {
            text: page.title
            font.pixelSize: UITheme.fsPageTitle
            font.bold: true
            color: UITheme.textPrimary
            Layout.leftMargin: 8
        }
    }

    ScrollView {
        id: bgScroll
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.top: header.bottom
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        anchors.bottomMargin: 24
        anchors.topMargin: 12
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        ColumnLayout {
            width: bgScroll.availableWidth
            spacing: 14

            // 背景四态单选（浅/深/米白/自定义图片）——KdRadioGrid ○/● 网格
            Label {
                text: qsTr("背景模式")
                font.pixelSize: UITheme.fsCaption
                color: UITheme.textSecondary
            }
            KdRadioGrid {
                id: bgGrid
                Layout.fillWidth: true
                columns: 4
                options: [
                    { text: qsTr("浅色"), value: "light" },
                    { text: qsTr("深色"), value: "dark" },
                    { text: qsTr("米白"), value: "paper" },
                    { text: qsTr("自定义图片"), value: "image" }
                ]
                onSelected: (v) => page.setBgMode(v)
            }

            RowLayout {
                Label { text: qsTr("背景图片") }
                Button {
                    text: qsTr("选择图片…")
                    onClicked: bgFileDialog.open()
                }
                Label {
                    id: bgImageHint
                    text: page.bgImagePath ? page.bgImagePath : qsTr("未选择")
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                    color: UITheme.textSecondary
                }
            }
            FileDialog {
                id: bgFileDialog
                title: qsTr("选择背景图片")
                fileMode: FileDialog.OpenFile
                nameFilters: ["图片 (*.png *.jpg *.jpeg *.webp *.bmp *.gif)"]
                onAccepted: page.importBackgroundImage(bgFileDialog.selectedFiles[0])
            }
            // E2：缩略图预览——选图后实时预览模糊/亮度效果，与 ReaderBackground 同
            // MultiEffect 参数（blur 直通、brightness 换算 -1..1）。滑条移动经
            // setBgBlur/setBgBrightness 同步 page.bgBlur/bgBrightness 作绑定源（实时联动）。
            // 未选图整行隐藏；图片加载失败时效果层隐藏露出底色（不显示黑块，同阅读页兜底）。
            Rectangle {
                id: bgThumb
                visible: page.bgImagePath !== ""
                Layout.fillWidth: true
                Layout.preferredHeight: 135
                radius: 6
                color: UITheme.bgSecondary
                clip: true
                Image {
                    id: bgThumbImg
                    anchors.fill: parent
                    // 与 ReaderBackground 同源构造：本地绝对路径补 file://，防御重复前缀
                    source: page.bgImagePath
                            ? (page.bgImagePath.indexOf("file://") === 0
                               ? page.bgImagePath : "file://" + page.bgImagePath)
                            : ""
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                }
                MultiEffect {
                    id: bgThumbFx
                    anchors.fill: parent
                    visible: page.bgImagePath !== "" && bgThumbImg.status === Image.Ready
                    source: bgThumbImg
                    blurEnabled: true
                    blur: page.bgBlur
                    brightness: page.bgBrightness - 1.0   // MultiEffect 亮度范围 -1..1
                }
            }
            RowLayout {
                Label { text: qsTr("模糊度") }
                Slider {
                    id: bgBlurSlider
                    Layout.fillWidth: true
                    from: 0.0
                    to: 1.0
                    stepSize: 0.05
                    // ready 门闩：onCompleted 恢复初值不写盘；此后任意变更即持久化
                    property bool ready: false
                    Component.onCompleted: { value = page.bgBlur; ready = true }
                    onValueChanged: if (ready) page.setBgBlur(value)
                }
                Label {
                    text: bgBlurSlider.value.toFixed(2)
                    Layout.preferredWidth: 40
                    horizontalAlignment: Text.AlignRight
                }
            }
            RowLayout {
                Label { text: qsTr("亮度") }
                Slider {
                    id: bgBrightnessSlider
                    Layout.fillWidth: true
                    from: 0.5
                    to: 1.5
                    stepSize: 0.05
                    property bool ready: false
                    Component.onCompleted: { value = page.bgBrightness; ready = true }
                    onValueChanged: if (ready) page.setBgBrightness(value)
                }
                Label {
                    text: bgBrightnessSlider.value.toFixed(2)
                    Layout.preferredWidth: 40
                    horizontalAlignment: Text.AlignRight
                }
            }
            // E4：翻页方式——竖滚连续（scroll，默认）/ 整页翻动（paged，按视口高度切页）。
            // 持久化 reading/pageMode；ReaderPage 打开时读取。
            Label {
                text: qsTr("翻页方式")
                font.pixelSize: UITheme.fsCaption
                color: UITheme.textSecondary
            }
            KdRadioGrid {
                id: pageModeGrid
                Layout.fillWidth: true
                columns: 2
                options: [
                    { text: qsTr("连续滚动"), value: "scroll" },
                    { text: qsTr("整页翻动"), value: "paged" }
                ]
                onSelected: (v) => Settings.setValue("reading/pageMode", v)
            }
            Label {
                id: bgErrorText
                text: ""
                color: UITheme.danger
                visible: false
            }
            Timer {
                id: bgErrorTimer
                interval: 3000
                onTriggered: bgErrorText.visible = false
            }
            Item { Layout.fillHeight: true }
        }
    }

    // B4：返回上一页（设置页）。抽函数暴露供 QML 冒烟测试驱动
    function goBack() {
        page.StackView.view.pop()
    }

    // ---- D5：阅读背景分区（background/mode、imagePath、blur、brightness）----
    function setBgMode(mode) {
        Settings.setValue("background/mode", mode)
    }
    function setBgBlur(v) {
        // E2：页面属性作响应层（ReaderPage 同模式）——滑条移动即同步，缩略图 MultiEffect
        // 绑定 page.bgBlur 实时预览；同时持久化 background/blur（含钳制）
        page.bgBlur = Math.max(0, Math.min(1, v))
        Settings.setValue("background/blur", page.bgBlur)
    }
    function setBgBrightness(v) {
        page.bgBrightness = Math.max(0.5, Math.min(1.5, v))
        Settings.setValue("background/brightness", page.bgBrightness)
    }
    // 选图导入：复制到 AppData/backgrounds/ 成功后写 imagePath + mode=image，并同步单选/提示。
    // 注：程序化 currentValue 赋值不触发 KdRadioGrid.selected（Qt 6.11 实测语义），
    // mode 必须显式写。
    function importBackgroundImage(url) {
        const dest = Settings.copyToBackgrounds(url)
        if (!dest) {
            bgErrorText.text = qsTr("图片导入失败，请换一张重试")
            bgErrorText.visible = true
            bgErrorTimer.restart()
            return
        }
        page.bgImagePath = dest
        bgImageHint.text = dest
        bgGrid.currentValue = "image"
        Settings.setValue("background/mode", "image")
        Settings.setValue("background/imagePath", dest)
    }
    // 启动恢复：从 Settings 读 background/ 分区应用到单选/滑条/路径（含钳制）
    function restoreBackground() {
        // L9（P2#33）：四态白名单归一抽至 BackgroundNorm（与 ReaderPage 共用）；
        // 旧版 eink 等非法值归一为 light，且回写 settings.json 使存储值同步归一
        const rawMode = Settings.value("background/mode")
        const mode = BackgroundNorm.norm(rawMode)
        if (mode !== rawMode)
            Settings.setValue("background/mode", mode)
        bgGrid.currentValue = mode
        page.bgImagePath = Settings.value("background/imagePath") || ""
        bgImageHint.text = page.bgImagePath || qsTr("未选择")
        const blur = Number(Settings.value("background/blur")) || 0.0
        page.bgBlur = Math.max(0, Math.min(1, blur))
        const bright = Number(Settings.value("background/brightness")) || 1.0
        page.bgBrightness = Math.max(0.5, Math.min(1.5, bright))
        // E4：翻页方式——reading/pageMode 白名单归一后选中对应单选
        //（程序化 currentValue 赋值不触发 selected，不会回写 Settings，同背景模式恢复）
        pageModeGrid.currentValue = Settings.value("reading/pageMode") === "paged" ? "paged" : "scroll"
    }
    Component.onCompleted: page.restoreBackground()
}
