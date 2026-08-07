import QtQuick
import QtQuick.Effects

// 阅读背景层：浅色 #FAFAFA / 深色 #121212 / 米白 #F5EFE0 / 彩色墨水屏 #F2E8D5 / 自定义图片。
// eink（B5）：浅彩纸色底 + 预置小纹理 PNG 平铺（噪点/纸纤维，GPU 平铺零逐帧成本），
// 文字墨色走 ReaderPage→ReaderContent 的 textColor 链路，图片类纸化走 ReaderContent 的
// MultiEffect（本组件不含图片处理）。
// blur 0..1 与 MultiEffect.blur 同范围；brightness 0.5..1.5 映射 MultiEffect.brightness -0.5..0.5
// （MultiEffect 亮度范围 -1..1，故换算 brightness - 1.0）。
// 图片模式：Image（PreserveAspectCrop）作 MultiEffect 源，mode 非 image 时两者隐藏（底色 Rectangle 可见）。
// 子项布局约定（tst_background 依赖）：children[0]=底色 Rectangle，[1]=Image，[2]=MultiEffect，
// [3]=eink 纸纹层（仅 eink 态可见，追加在尾部不动既有索引）。
Item {
    id: bg
    property string mode: "light"      // light | dark | paper | eink | image
    property string imagePath: ""
    property real blur: 0.0            // 0..1
    property real brightness: 1.0      // 0.5..1.5

    Rectangle {
        anchors.fill: parent
        color: mode === "dark" ? "#121212"
             : (mode === "paper" ? "#F5EFE0"
             : (mode === "eink" ? "#F2E8D5" : "#FAFAFA"))
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

    // B5：eink 纸纹层——预置 256px 噪点/纤维纹理平铺（资源内嵌，GPU 平铺无逐帧 shader
    // 成本；纹理半透明叠加在浅彩纸色上模拟纸张质感）。ShaderEffect 运行时烘焙在本 Qt
    // 安装不可用（无 QtShaderTools QML 模块），按简报许可选用"预置小纹理平铺"方案。
    Image {
        id: einkTexture
        anchors.fill: parent
        visible: mode === "eink"
        source: "qrc:/qt/qml/Readdict/ui/qml/paper/paper_texture.png"
        fillMode: Image.Tile
        opacity: 0.5
    }
}
