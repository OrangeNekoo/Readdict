import QtQuick
import QtTest
import Readdict.Backend
import Readdict.Test 1.0

// D5：阅读背景冒烟——真实图片导入路径（copyToBackgrounds → backgrounds/）、
// ReaderBackground 五态（浅/深/米白/彩色墨水屏 eink/自定义图片 + MultiEffect 模糊/亮度 +
// eink 纸纹层）、ReaderPage 从 Settings background/ 分区恢复、控制栏五态循环、
// 设置页单选/滑条持久化。
// 不打开原生 FileDialog（测试环境无窗口系统交互），导入路径直接调 Settings.copyToBackgrounds。
// 结构约定（与 tst_main/tst_ttsbar 一致）：根为带尺寸的 Item，TestCase 是其子项，
// 组件经 createObject(root) 挂到该 Item 下——挂在 TestCase 下时其 visible=false，
// 子树内 visible 绑定不会被求值（探针实证），背景层可见性断言将失效。
// QML TestCase 按函数名字母序执行，故用数字前缀；每个用例开头显式复位背景分区避免相互污染。
Item {
    id: root
    width: 1100; height: 720

    Component { id: bgComp; Loader { source: "qrc:/qt/qml/Readdict/ui/qml/ReaderBackground.qml" } }
    Component { id: readerComp; Loader { source: "qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml" } }
    Component { id: settingsComp; Loader { source: "qrc:/qt/qml/Readdict/ui/qml/SettingsPage.qml" } }

    TestCase {
        id: testCase
        name: "BackgroundSmoke"

        // ReaderBackground 子项布局：children[0]=底色 Rectangle，[1]=Image，[2]=MultiEffect
        function test_01_copyImage() {
            // 真实图片文件导入路径：复制到 AppData/backgrounds/ 成功、返回路径可加载、同名覆盖
            var src = TestEnv.backgroundImage
            verify(src.length > 0, "TestEnv 应提供真实背景图")
            var dest = Settings.copyToBackgrounds(src)
            verify(dest.length > 0, "copyToBackgrounds 应返回目标路径，实际 " + dest)
            verify(dest.indexOf("backgrounds") >= 0, "目标应位于 backgrounds/ 目录：" + dest)
            // 复制出的文件能被 QML Image 解码加载（真实导入路径验证）
            var probe = Qt.createQmlObject('import QtQuick; Image { source: "" }', root, "probe")
            probe.source = "file://" + dest
            tryVerify(function () { return probe.status === Image.Ready }, 5000,
                      "复制出的图片应能加载为 Ready，实际 " + probe.status)
            probe.destroy()
            // 同名文件覆盖为同一目标路径（不残留旧副本引用）
            var dest2 = Settings.copyToBackgrounds(src)
            compare(dest2, dest, "重复导入同名文件应覆盖同一目标")
            // 不存在的源 → 空串
            compare(Settings.copyToBackgrounds("file:///nonexistent/x.png"), "", "无效源应返回空串")
        }

        function test_02_backgroundModes() {
            // 五态模式切换：底色随 mode 变化，image 态显示 Image 与 MultiEffect，
            // eink 态显示纸纹层（children[3]，B5 追加在尾部不动既有 0..2 索引）
            var loader = bgComp.createObject(root)
            verify(loader.item !== null, "ReaderBackground 应能加载（含 QtQuick.Effects import 编译检查）")
            var b = loader.item
            b.width = 200; b.height = 300
            b.mode = "light"
            compare(String(b.children[0].color), "#fafafa")
            b.mode = "dark"
            compare(String(b.children[0].color), "#121212")
            b.mode = "paper"
            compare(String(b.children[0].color), "#f5efe0")
            b.mode = "eink"
            compare(String(b.children[0].color), "#f2e8d5", "eink 底色应为浅彩纸色 #F2E8D5")
            verify(b.children[3].visible, "eink 态应显示纸纹层（children[3]）")
            tryVerify(function () { return b.children[3].status === Image.Ready }, 3000,
                      "纸纹纹理资源应能加载为 Ready（qrc 路径），实际 status="
                      + b.children[3].status)
            verify(!b.children[1].visible && !b.children[2].visible,
                   "eink 态不应显示 Image/MultiEffect（仅纸纹层）")
            b.mode = "image"
            // 无图（imagePath 空）时：Image 层显示但 MultiEffect 依赖图片就绪态，
            // 未就绪 → 效果层隐藏，露出底色 Rectangle（D5 复审兜底行为）
            verify(b.children[1].visible, "image 态应显示 Image 层")
            verify(!b.children[2].visible, "无图时 MultiEffect 应隐藏（等待 Image.Ready）")
            verify(!b.children[3].visible, "非 eink 态纸纹层应隐藏")
            b.mode = "light"
            verify(!b.children[1].visible && !b.children[2].visible, "非 image 态应隐藏 Image 与 MultiEffect")
            loader.destroy()
        }

        function test_03_imageLoadAndEffects() {
            // 真实图片加载 + 模糊/亮度属性设置渲染不崩；亮度换算到 MultiEffect -1..1
            var dest = Settings.copyToBackgrounds(TestEnv.backgroundImage)
            verify(dest.length > 0)
            var loader = bgComp.createObject(root)
            var b = loader.item
            b.width = 200; b.height = 300
            b.mode = "image"
            b.imagePath = dest
            var img = b.children[1]
            tryVerify(function () { return img.status === Image.Ready }, 5000,
                      "背景图应加载为 Ready，实际 " + img.status)
            // 模糊/亮度属性设置 → MultiEffect 联动（渲染若干帧不崩即通过）
            b.blur = 0.4
            b.brightness = 1.3
            var fx = b.children[2]
            compare(fx.blur, 0.4, "blur 0.4 应直通 MultiEffect")
            compare(fx.brightness, 0.3, "brightness 1.3 应换算为 MultiEffect 0.3")
            b.brightness = 0.5
            compare(fx.brightness, -0.5, "brightness 0.5 应换算为 MultiEffect -0.5")
            wait(80)   // 渲染若干帧（模糊效果在帧上执行），不崩即通过
            // D5 复审：图片被删除/路径失效时（Image.Error）效果层必须隐藏，
            // 由底色 Rectangle 兜底——错误源经 MultiEffect 输出不保证透明，可能黑块
            b.imagePath = "/nonexistent/missing-bg.png"
            tryVerify(function () { return img.status === Image.Error }, 5000,
                      "无效路径应使图片加载为 Error，实际 " + img.status)
            verify(!fx.visible, "图片加载失败时 MultiEffect 应隐藏（不显示黑块）")
            verify(b.children[0].visible, "底色 Rectangle 应保持可见作兜底")
            loader.destroy()
        }

        function test_04_readerPageRestore() {
            // 持久化 + 启动恢复：写入 background 分区后打开 ReaderPage 应应用 image 模式全参数
            var dest = Settings.copyToBackgrounds(TestEnv.backgroundImage)
            verify(dest.length > 0)
            Settings.setValue("background/mode", "image")
            Settings.setValue("background/imagePath", dest)
            Settings.setValue("background/blur", 0.3)
            Settings.setValue("background/brightness", 1.2)
            var loader = readerComp.createObject(root)
            loader.setSource("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: {} })
            var page = loader.item
            verify(page !== null, "ReaderPage 应能加载")
            compare(page.bgMode, "image", "ReaderPage 应从 Settings 恢复 image 模式")
            compare(page.bgImagePath, dest, "应恢复 imagePath")
            compare(page.bgBlur, 0.3, "应恢复 blur")
            compare(page.bgBrightness, 1.2, "应恢复 brightness")
            loader.destroy()
            // 越界值钳制
            Settings.setValue("background/blur", 9)
            Settings.setValue("background/brightness", 0.05)
            loader = readerComp.createObject(root)
            loader.setSource("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: {} })
            page = loader.item
            compare(page.bgBlur, 1.0, "blur 越界应钳到 1.0")
            compare(page.bgBrightness, 0.5, "brightness 越界应钳到 0.5")
            loader.destroy()
        }

        function test_05_cycleBackground() {
            // 控制栏"背景"循环：有图五态 浅→米白→深→eink→图片→浅；无图四态跳过 image
            var dest = Settings.copyToBackgrounds(TestEnv.backgroundImage)
            Settings.setValue("background/imagePath", dest)
            Settings.setValue("background/mode", "light")
            var loader = readerComp.createObject(root)
            loader.setSource("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: {} })
            var page = loader.item
            page.cycleBackground()
            compare(page.bgMode, "paper")
            compare(Settings.value("background/mode"), "paper", "循环应同步写 background/mode")
            page.cycleBackground()
            compare(page.bgMode, "dark")
            page.cycleBackground()
            compare(page.bgMode, "eink", "dark 后应切到彩色墨水屏 eink")
            page.cycleBackground()
            compare(page.bgMode, "image")
            page.cycleBackground()
            compare(page.bgMode, "light", "有图时五态循环应回到 light")
            loader.destroy()
            // 无图：四态循环（eink 之后回到 light，跳过 image）
            Settings.setValue("background/imagePath", "")
            Settings.setValue("background/mode", "eink")
            loader = readerComp.createObject(root)
            loader.setSource("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: {} })
            page = loader.item
            compare(page.bgMode, "eink", "恢复 eink 模式")
            page.cycleBackground()
            compare(page.bgMode, "light", "无图时 eink 后应回 light（跳过 image）")
            loader.destroy()
        }

        function test_06_settingsPage() {
            // 设置页：单选/滑条恢复 + 交互写 Settings + 越界钳制（不打开原生 FileDialog）
            Settings.setValue("background/mode", "image")
            Settings.setValue("background/imagePath", "")
            Settings.setValue("background/blur", 0.6)
            Settings.setValue("background/brightness", 0.9)
            var loader = settingsComp.createObject(root)
            loader.width = 1100; loader.height = 720
            var page = loader.item
            verify(page !== null, "SettingsPage 应能加载")
            // D3：返回按钮固定顶部后滚动内容下移，阅读背景卡在 720 高窗口内
            // 需先滚入视口（mouseClick 要求目标落在窗口内；mapToItem 定位 +
            // contentY 滚动，滚动量稳定可复现）
            var fl = page.settingsScroll.contentItem
            fl.contentY = Math.max(0, page.bgImageRadio.mapToItem(fl, 0, 0).y - 80)
            wait(100)
            verify(page.bgImageRadio.checked && !page.bgLightRadio.checked
                   && !page.bgDarkRadio.checked && !page.bgPaperRadio.checked
                   && !page.bgEinkRadio.checked,
                   "恢复后应恰好选中 image（其余未选）")
            compare(page.bgBlurSlider.value, 0.6, "模糊滑条应恢复 0.6")
            compare(page.bgBrightnessSlider.value, 0.9, "亮度滑条应恢复 0.9")
            // 单选切换用 mouseClick 模拟真实点击（程序化 checked=true 不触发 onToggled，Qt 6.11 实测）→ background/mode
            mouseClick(page.bgLightRadio, page.bgLightRadio.width / 2, page.bgLightRadio.height / 2)
            compare(Settings.value("background/mode"), "light", "点浅色应写 background/mode")
            // B5：eink 单选——恢复 + 点击两路径都验证
            Settings.setValue("background/mode", "eink")
            loader.destroy()
            loader = settingsComp.createObject(root)
            loader.width = 1100; loader.height = 720
            page = loader.item
            fl = page.settingsScroll.contentItem
            fl.contentY = Math.max(0, page.bgEinkRadio.mapToItem(fl, 0, 0).y - 80)
            wait(100)
            verify(page.bgEinkRadio.checked && !page.bgImageRadio.checked,
                   "恢复 eink 后应恰好选中彩色墨水屏（其余未选）")
            mouseClick(page.bgEinkRadio, page.bgEinkRadio.width / 2, page.bgEinkRadio.height / 2)
            compare(Settings.value("background/mode"), "eink", "点彩色墨水屏应写 background/mode")
            mouseClick(page.bgImageRadio, page.bgImageRadio.width / 2, page.bgImageRadio.height / 2)
            compare(Settings.value("background/mode"), "image")
            // 滑条值变更（onValueChanged 经 setBgBlur/setBgBrightness）→ 持久化 + 钳制
            page.bgBlurSlider.value = 0.8
            compare(Settings.value("background/blur"), 0.8, "模糊滑条应写 background/blur")
            page.bgBrightnessSlider.value = 1.4
            compare(Settings.value("background/brightness"), 1.4, "亮度滑条应写 background/brightness")
            page.bgBlurSlider.value = 5.0   // 滑条自身钳到 to=1.0
            compare(page.bgBlurSlider.value, 1.0, "滑条应在 0..1 内钳制")
            page.setBgBlur(5)
            compare(Settings.value("background/blur"), 1.0, "setBgBlur 越界应钳到 1.0")
            page.setBgBrightness(0.1)
            compare(Settings.value("background/brightness"), 0.5, "setBgBrightness 越界应钳到 0.5")
            // 无效源导入：失败提示且不改当前模式
            page.importBackgroundImage("file:///nonexistent/x.png")
            compare(Settings.value("background/mode"), "image", "导入失败不应改当前模式")
            // 成功导入（真实图片）：复制 + 写 mode=image + imagePath，单选同步
            page.importBackgroundImage(TestEnv.backgroundImage)
            var dest = Settings.value("background/imagePath")
            verify(dest.length > 0, "导入成功应写 imagePath")
            verify(dest.indexOf("backgrounds") >= 0, "imagePath 应位于 backgrounds/：" + dest)
            compare(Settings.value("background/mode"), "image", "导入成功应写 mode=image")
            verify(page.bgImageRadio.checked, "导入成功应选中自定义图片")
            loader.destroy()
        }
    }
}
