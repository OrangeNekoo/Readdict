import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.UI 1.0

// U4：Kindle 底部 Sheet 工具栏容器（分析报告 §4：底部弹出 45-50% 屏高、
// 遮罩 rgba(0,0,0,0.3)、顶部标签栏 + 内容区 + 底部操作按钮）。
// 机制：
//   · 遮罩（UITheme.overlay）淡入淡出，点击面板外关闭（maskClicked）；
//   · 面板本体从底部滑出/收回（y 平移动画 260ms OutCubic），无圆角（Kindle
//     面板为直角矩形，§4 组件样式"矩形边框"）；
//   · 顶部标签栏复用 KdTabBar（文字标签 + 3px 下划线跟动，与 U2 顶部导航同源）；
//   · 内容区按 currentId 切换 pages 中的对应组件（Loader 实例化，组件创建上下文
//     为注入方——ReaderPage 内联 Component，故面板可直接访问 page/Settings）；
//   · 底部操作按钮区：actionText 非空时显示全宽描边按钮（§4"保存当前设置"），
//     点击发 actionClicked。
// 接口：open（开合）、tabs/pages（[{id,...}]）、currentId、sheetRatio（屏高占比，
// 默认 0.48）、actionText；信号 tabClicked/actionClicked/maskClicked。
// 测试/外部句柄：mask、body、tabBar、contentLoader（当前面板实例）、actionBar。
// 本组件无业务状态——开合与标签选中由宿主（ReaderPage）驱动，面板内容由宿主注入。
Item {
    id: sheet

    property bool open: false
    property var tabs: []        // [{id, text}] —— 顶部标签数据
    property var pages: []       // [{id, source: Component}] —— 各标签内容组件
    property string currentId: ""
    property real sheetRatio: 0.48   // §4：面板约占屏高 45-50%
    property string actionText: ""   // 底部操作按钮文字（空串隐藏按钮区）

    signal tabClicked(string id)
    signal actionClicked()
    signal maskClicked()             // 点击面板外（遮罩）——宿主置 open=false

    property alias mask: mask
    property alias body: body
    property alias contentLoader: panelLoader
    property alias panelScroller: panelScroller
    property alias tabBar: tabBar
    property alias actionBar: actionHost
    // 遮罩：Kindle 半透明暗色（rgba(0,0,0,0.3) → UITheme.overlay）。opacity 动画
    // 淡入淡出；关闭时禁用鼠标（enabled 门控）——透明层不拦截正文点击。
    Rectangle {
        id: mask
        anchors.fill: parent
        color: UITheme.overlay
        opacity: sheet.open ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
        }
        MouseArea {
            anchors.fill: parent
            enabled: sheet.open
            onClicked: sheet.maskClicked()
        }
    }

    // 面板本体：底部 sheetRatio 屏高，y 平移滑出/收回（收回目标 = 屏高，移出视口）
    Rectangle {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.max(200, parent.height * sheet.sheetRatio)
        y: sheet.open ? parent.height - height : parent.height
        Behavior on y {
            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
        }
        color: UITheme.bgPrimary

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // §4：标签栏上方分割线（细线）
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: UITheme.divider
            }

            // 顶部标签栏：复用 KdTabBar（文字 + 下划线跟动），高度 44 固定
            KdTabBar {
                id: tabBar
                Layout.fillWidth: true
                tabs: sheet.tabs
                currentId: sheet.currentId
                onTabClicked: (id) => sheet.tabClicked(id)
            }

            Flickable {
                id: panelScroller
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                interactive: panelLoader.item && panelScroller.contentHeight > panelScroller.height + 1
                contentWidth: width
                contentHeight: Math.max(height,
                    panelLoader.item ? panelLoader.item.implicitHeight : height)
                flickableDirection: Flickable.VerticalFlick
                ScrollBar.vertical: ScrollBar {
                    policy: panelScroller.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                }
                Loader {
                    id: panelLoader
                    width: panelScroller.width
                    height: Math.max(panelScroller.height,
                                     item ? item.implicitHeight : panelScroller.height)
                    sourceComponent: {
                        for (const p of sheet.pages)
                            if (p.id === sheet.currentId) return p.source
                        return null
                    }
                }
            }

            // 底部操作按钮区（§4：全宽描边按钮，左右 margin 24、上下 margin 16）
            Item {
                id: actionHost
                Layout.fillWidth: true
                Layout.preferredHeight: sheet.actionText.length > 0 ? 60 : 0
                visible: sheet.actionText.length > 0
                clip: true
                Button {
                    anchors.centerIn: parent
                    width: parent.width - 48
                    height: 40
                    text: sheet.actionText
                    font.pixelSize: 15
                    background: Rectangle {
                        color: "transparent"
                        radius: 6
                        border.color: UITheme.borderActive
                        border.width: 1
                    }
                    contentItem: Text {
                        text: parent.text
                        color: UITheme.textPrimary
                        font.pixelSize: 15
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: sheet.actionClicked()
                }
            }
        }
    }
}
