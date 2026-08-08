import QtQuick
import Readdict.UI 1.0

// U5：Kindle/iOS 风格胶囊开关（分析报告 §4：圆角轨道 40×24px，左灰=关/右深=开）。
// - checked：开/关；toggled(bool)：用户操作后发出（即时生效语义由调用方处理）。
// - 轨道色随深浅主题：关=borderDefault 灰；开=borderActive（浅色近黑/深色近白）。
// - 滑块 20px 圆、bgPrimary（浅色暖白/深色深底），x 平移动画。
// 测试/外部句柄：clickArea（MouseArea，clicked() 等价用户点击）、
// setChecked(v)（程序化设置并发出 toggled——与点击同路径，供恢复/测试）。
Item {
    id: toggle

    property bool checked: false
    signal toggled(bool checked)

    width: 40
    height: 24

    // 轨道
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: toggle.checked ? UITheme.borderActive : UITheme.borderDefault
        Behavior on color { ColorAnimation { duration: 120 } }
    }
    // 滑块
    Rectangle {
        width: 20
        height: 20
        radius: 10
        color: UITheme.bgPrimary
        x: toggle.checked ? parent.width - width - 2 : 2
        y: 2
        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    }
    MouseArea {
        id: clickArea
        anchors.fill: parent
        onClicked: toggle.setChecked(!toggle.checked)
    }

    // 程序化设置：与点击同路径（走 toggled 信号），供启动恢复与测试驱动
    function setChecked(v) {
        if (toggle.checked === v) return
        toggle.checked = v
        toggle.toggled(v)
    }
}
