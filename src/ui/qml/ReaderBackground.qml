import QtQuick
import QtQuick.Effects
import Readdict.UI 1.0

// 阅读背景层：浅色（Kindle 暖白 Token）/ 深色（Kindle 深色系）/ 米白纸色 / 自定义图片。
// U1：底色全部引用 UITheme Token——light → lightBgPrimary(#F5F5F0)、dark →
// darkBgPrimary(#1E1E1E)、paper → lightBgPaper(#F5EFE0 米白，Kindle 主题预设)。
// 阅读背景模式与全局主题（isDark）独立：模式是用户逐页选择的阅读预设（Kindle 语义），
// 故直接引用浅/深具体 Token，而非 isDark 解析别名。
// blur 0..1 与 MultiEffect.blur 同范围；brightness 0.5..1.5 映射 MultiEffect.brightness -0.5..0.5
// （MultiEffect 亮度范围 -1..1，故换算 brightness - 1.0）。
// 图片模式：Image（PreserveAspectCrop）作 MultiEffect 源，mode 非 image 时两者隐藏（底色 Rectangle 可见）。
// 子项布局约定（tst_background 依赖）：children[0]=底色 Rectangle，[1]=Image，[2]=MultiEffect。
Item {
    id: bg
    property string mode: "light"      // light | dark | paper | image
    property string imagePath: ""
    property real blur: 0.0            // 0..1
    property real brightness: 1.0      // 0.5..1.5

    Rectangle {
        anchors.fill: parent
        color: mode === "dark" ? UITheme.darkBgPrimary
             : (mode === "paper" ? UITheme.lightBgPaper : UITheme.lightBgPrimary)
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
