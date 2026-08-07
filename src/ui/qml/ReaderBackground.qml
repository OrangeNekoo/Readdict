import QtQuick
import QtQuick.Effects

// 阅读背景层：浅色 #FAFAFA / 深色 #121212 / 米白 #F5EFE0 / 自定义图片（MultiEffect 模糊+亮度）。
// blur 0..1 与 MultiEffect.blur 同范围；brightness 0.5..1.5 映射 MultiEffect.brightness -0.5..0.5
// （MultiEffect 亮度范围 -1..1，故换算 brightness - 1.0）。
// 图片模式：Image（PreserveAspectCrop）作 MultiEffect 源，mode 非 image 时两者隐藏（底色 Rectangle 可见）。
Item {
    id: bg
    property string mode: "light"      // light | dark | paper | image
    property string imagePath: ""
    property real blur: 0.0            // 0..1
    property real brightness: 1.0      // 0.5..1.5

    Rectangle {
        anchors.fill: parent
        color: mode === "dark" ? "#121212" : (mode === "paper" ? "#F5EFE0" : "#FAFAFA")
    }

    Image {
        id: img
        anchors.fill: parent
        visible: mode === "image"
        // imagePath 是本地绝对路径；为空串时 source 置空（"file://"+"" 会被当作根目录打开报错）；
        // 防御重复 file:// 前缀。图片被删除时加载失败：MultiEffect 输出透明，底色 Rectangle 兜底
        source: bg.imagePath ? (bg.imagePath.indexOf("file://") === 0 ? bg.imagePath : "file://" + bg.imagePath) : ""
        fillMode: Image.PreserveAspectCrop
        smooth: true
    }

    MultiEffect {
        anchors.fill: parent
        // 图片就绪才显示效果层：imagePath 缺失/被删除时（Image.Error 或 Loading）隐藏
        // MultiEffect——错误源经效果层的输出不保证透明（可能黑块），直接露出底色 Rectangle 兜底
        visible: mode === "image" && img.status === Image.Ready
        source: img
        blurEnabled: true
        blur: bg.blur
        brightness: bg.brightness - 1.0   // MultiEffect 亮度范围 -1..1
    }
}
