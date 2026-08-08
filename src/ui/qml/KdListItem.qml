import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.UI 1.0

// U5：Kindle 全屏列表项（分析报告 §4 组件库/§7 规范：线性图标 24-28px + 文字 +
// 右箭头 chevron，无背景色，点击态短暂遮罩）。
// - icon：KdIcons 图标名（留空不绘制）；text：主文案（fsListItem 15px）；
//   subtext：副文案/当前值（fsCaption 13px 灰）；showChevron：右箭头是否显示；
//   iconColor：图标描边色（默认主文字）。
// - content：默认属性——尾部内嵌控件（如 KdToggle、提示 Label），置于行尾。
// - 点击：整行 MouseArea（z 最底）→ clicked() 信号；按压态为 8% 黑/白遮罩
//   （深浅主题自适应，遮罩在 z 顶、仅视觉不拦截输入——尾部控件点击优先）。
// 测试/外部句柄：textLabel（主文案 Label）、chevronIcon、clickItem()（等价点击路径）。
Item {
    id: item

    property string icon: ""
    property string text: ""
    property string subtext: ""
    property bool showChevron: true
    property color iconColor: UITheme.textPrimary
    signal clicked()
    default property alias content: trailingSlot.data

    implicitHeight: 60
    height: 60

    // 点击热区（z 最底）：整行可点；尾部内嵌控件（z 高于热区）优先接收自己的点击
    MouseArea {
        id: clickArea
        anchors.fill: parent
        onClicked: item.clicked()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 14

        KdIcons {
            name: item.icon
            size: 26
            color: item.iconColor
            visible: item.icon !== ""
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 2
            Label {
                id: textLabel
                text: item.text
                font.pixelSize: UITheme.fsListItem
                color: UITheme.textPrimary
                elide: Text.ElideRight
                Layout.fillWidth: true
                verticalAlignment: Text.AlignVCenter
            }
            Label {
                text: item.subtext
                font.pixelSize: UITheme.fsCaption
                color: UITheme.textSecondary
                elide: Text.ElideRight
                visible: item.subtext !== ""
                Layout.fillWidth: true
                verticalAlignment: Text.AlignVCenter
            }
        }
        // 尾部内嵌控件槽（KdToggle 等）：按内容隐式尺寸占位
        Item {
            id: trailingSlot
            Layout.preferredWidth: trailingSlot.childrenRect.width
            Layout.preferredHeight: trailingSlot.childrenRect.height
            Layout.alignment: Qt.AlignVCenter
        }
        KdIcons {
            id: chevronIcon
            name: "chevron"
            size: 22
            color: UITheme.textSecondary
            visible: item.showChevron
        }
    }

    // 按压态遮罩（z 顶，纯视觉：8% 黑 / 深色 8% 白，Kindle 按压反馈）
    Rectangle {
        anchors.fill: parent
        color: UITheme.isDark ? "#14FFFFFF" : "#14000000"
        opacity: clickArea.pressed ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 100 } }
    }

    // 测试/外部句柄：textLabel（主文案 Label）、chevronIcon（右箭头）、
    // clickItem()（等价点击路径）
    property alias textLabel: textLabel
    property alias chevronIcon: chevronIcon

    // 测试/外部驱动：与真实点击同路径（MouseArea.onClicked → item.clicked）
    function clickItem() { item.clicked() }
}
