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
// 同阅读页参数）。任务5：bgThumb 固定为小长方形卡片（220×120，始终可见），覆盖
// 测试文本实时预览当前模式；仅 image 模式显示字体颜色预设（≥3 个安全色，白名单
// 见 UITheme.imageTextColorPresets）→ 即时写 background/textColor，供 ReaderPage
// 恢复注入正文。E4：翻页方式（竖滚连续 scroll / 整页翻动 paged）持久化
// reading/pageMode。U5：单选改为 KdRadioGrid（○/● 网格，分析报告 §4）。
// 返回：固定顶部"← 返回"（B4 模式）。
// 测试/外部句柄：backButton、goBack()、bgGrid（背景四态 KdRadioGrid）、
// bgBlurSlider/bgBrightnessSlider、bgThumb/bgThumbImg/bgThumbFx/bgThumbText
// （缩略图预览 + 测试文本）、textColorSection/textColorGrid（字体颜色预设，
// 仅 image 模式显示）、pageModeGrid（翻页方式）、bgImageHint、
// setBgMode/setBgBlur/setBgBrightness/setTextColor/importBackgroundImage/restoreBackground。
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
    property alias bgThumbText: bgThumbText
    // 审查修复：暴露滚动容器句柄（窄窗口水平可达性断言）
    property alias bgScroll: bgScroll
    property alias textColorSection: textColorSection
    property alias textColorGrid: textColorGrid
    property alias bgImageHint: bgImageHint
    // BUG8：FileDialog 句柄（空 selectedFiles 防御路径冒烟断言用）
    property alias bgFileDialog: bgFileDialog
    // 当前背景分区状态（onCompleted 从 Settings 恢复；导入后更新）
    property string bgImagePath: ""
    property real bgBlur: 0.0
    property real bgBrightness: 1.0
    // 任务5：当前字体颜色（background/textColor 恢复值，白名单校验后的规范串；
    // 非法/缺失为 ""）。thumbTextColor 为预览测试文本色——image 模式用所选色，
    // 其它模式沿用各自默认文字色（不被自定义色污染，与 ReaderPage 注入语义一致）。
    property string bgTextColor: ""
    property color thumbTextColor: bgGrid.currentValue === "dark" ? UITheme.darkTextPrimary
        : (bgGrid.currentValue === "image" ? UITheme.imageTextColorValue(page.bgTextColor)
                                           : UITheme.lightTextPrimary)

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
        // 审查修复：窄窗口水平可达策略——内容超出视口时出现横向滚动条，
        // 固定尺寸卡片不因裁剪而不可达（ScrollView 对 Layout 子项按隐式尺寸
        // 计算 contentWidth，故列宽下限取 implicitWidth 保证可达）。
        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
        ColumnLayout {
            width: Math.max(0, bgScroll.width
                                - bgScroll.leftPadding - bgScroll.rightPadding,
                            implicitWidth)
            spacing: 14
            // 使用实际视口宽度，避免 availableWidth 初始为 0 导致内容坍缩；
            // 下限 implicitWidth 使窄窗口内容保持隐式宽度（≥ 固定卡片 220），
            // 由横向滚动条水平可达。

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
                Layout.fillWidth: true
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
                // BUG8：防御性接受——取消/个别平台路径可能以空 selectedFiles 发
                // accepted，空选择不触发导入；非空才走复制导入（selectedFiles[0]
                // 为 file:// URL，copyToBackgrounds 可处理）
                onAccepted: page.handleBgFileAccepted()
            }
            // 任务5：自定义图片预览固定为小长方形卡片（220×120，始终可见）——
            // 未选图时显示当前背景模式底色；image 模式叠加图片与 MultiEffect
            // （blur 直通、brightness 换算 -1..1，与 ReaderBackground 同参数）。
            // 卡片中央覆盖测试文本，颜色随当前模式文字色（image 模式 = 所选
            // 字体颜色，非法/缺失回退浅色默认），实时预览阅读观感。
            // 图片加载失败时效果层隐藏露出底色（不显示黑块，同阅读页兜底）。
            Rectangle {
                id: bgThumb
                Layout.alignment: Qt.AlignHCenter
                // 审查修复：min/max 同值 = 硬固定 220×120，窄窗口不被压缩；
                // 同时恒定贡献给 ColumnLayout 隐式宽度 → ScrollView
                // contentWidth ≥ 220，卡片始终水平可达（不裁剪）。
                Layout.minimumWidth: 220
                Layout.maximumWidth: 220
                Layout.minimumHeight: 120
                Layout.maximumHeight: 120
                radius: 6
                color: bgGrid.currentValue === "dark" ? UITheme.darkBgPrimary
                     : (bgGrid.currentValue === "paper" ? UITheme.lightBgPaper
                                                        : UITheme.lightBgPrimary)
                clip: true
                Image {
                    id: bgThumbImg
                    anchors.fill: parent
                    visible: bgGrid.currentValue === "image"
                    // 与 ReaderBackground 同源构造：FileUrl 统一转 file URL（已是 scheme 的保留）
                    source: page.bgImagePath ? FileUrl.fromPath(page.bgImagePath) : ""
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                }
                MultiEffect {
                    id: bgThumbFx
                    anchors.fill: parent
                    visible: bgGrid.currentValue === "image"
                             && bgThumbImg.status === Image.Ready
                    source: bgThumbImg
                    blurEnabled: true
                    blur: page.bgBlur
                    brightness: page.bgBrightness - 1.0   // MultiEffect 亮度范围 -1..1
                }
                Label {
                    id: bgThumbText
                    anchors.centerIn: parent
                    text: qsTr("阅读测试文本 Aa 背景预览")
                    color: page.thumbTextColor
                    font.pixelSize: 16
                }
            }
            // 任务5：字体颜色预设——仅 image 模式显示（≥3 个安全色，白名单
            // UITheme.imageTextColorPresets）；选择即写 background/textColor 并
            // 同步响应层（预览文本色随 thumbTextColor 实时联动）。
            ColumnLayout {
                id: textColorSection
                visible: bgGrid.currentValue === "image"
                spacing: 6
                Label {
                    text: qsTr("字体颜色")
                    font.pixelSize: UITheme.fsCaption
                    color: UITheme.textSecondary
                }
                KdRadioGrid {
                    id: textColorGrid
                    Layout.fillWidth: true
                    columns: 4
                    options: UITheme.imageTextColorPresets.map(p => ({ text: p.name, value: p.color }))
                    // 恢复路径赋值 currentValue（不触发 selected → 不回写 Settings，
                    // 同 bgGrid 恢复语义）；非法/缺失经 imageTextColorValue 归一为默认近黑
                    currentValue: page.bgTextColor
                                 ? page.bgTextColor : UITheme.imageTextColorValue("")
                    onSelected: (v) => page.setTextColor(v)
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
                Layout.fillWidth: true
            }
            RowLayout {
                Layout.fillWidth: true
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
            // E4：翻页方式——竖向连续滚动（scroll，默认）/ 横向分页（paged，任务3：
            // 页面沿 x 轴排列，左右/上下键按页宽整页翻动）。
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
                    { text: qsTr("竖向连续滚动"), value: "scroll" },
                    { text: qsTr("横向分页"), value: "paged" }
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

    // B4/BUG2：返回上一页（设置页）——只 pop 当前层（绝不经 Main.goBack
    // 弹回主页；无 StackView 上下文如测试直载时安全空操作）。抽函数暴露供
    // QML 冒烟测试驱动
    function goBack() {
        const stack = page.StackView.view
        if (stack && stack.depth > 1) stack.pop()
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
    // BUG8：FileDialog accepted 防御——取消/空 selectedFiles（个别平台以空列表
    // 发 accepted）不触发导入；非空才转交 importBackgroundImage（函数供冒烟驱动）
    function handleBgFileAccepted() {
        if (bgFileDialog.selectedFiles.length === 0) return
        page.importBackgroundImage(bgFileDialog.selectedFiles[0])
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
    // 任务5：字体颜色选择——白名单校验后即时持久化 background/textColor（仅
    // image 模式可见的预设发出，双保险防手改属性绕过）并同步响应层（预览文本色联动）
    function setTextColor(v) {
        if (!UITheme.isSafeImageTextColor(v)) return
        page.bgTextColor = UITheme.imageTextColorValue(v)
        Settings.setValue("background/textColor", page.bgTextColor)
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
        // 任务5：字体颜色恢复——白名单校验（非法/缺失置空 → 预设选中默认近黑、
        // 预览文本色回退浅色默认；不回写存储值，非法值仅显示回退）
        const tc = Settings.value("background/textColor")
        page.bgTextColor = UITheme.isSafeImageTextColor(tc) ? UITheme.imageTextColorValue(tc) : ""
        textColorGrid.currentValue = page.bgTextColor
                                     ? page.bgTextColor : UITheme.imageTextColorValue("")
        // E4：翻页方式——reading/pageMode 白名单归一后选中对应单选
        //（程序化 currentValue 赋值不触发 selected，不会回写 Settings，同背景模式恢复）
        pageModeGrid.currentValue = Settings.value("reading/pageMode") === "paged" ? "paged" : "scroll"
    }
    Component.onCompleted: page.restoreBackground()
}
