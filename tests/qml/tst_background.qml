import QtQuick
import QtTest
import Readdict.Backend
import Readdict.Test 1.0

// D5：阅读背景冒烟——真实图片导入路径（copyToBackgrounds → backgrounds/）、
// ReaderBackground 四态（浅/深/米白/自定义图片 + MultiEffect 模糊/亮度）、
// ReaderPage 从 Settings background/ 分区恢复、控制栏四态循环（E1：不含 eink；
// 旧值 eink 归一 light 并回写）、设置页单选/滑条持久化。
// E2：设置页缩略图预览（未选图隐藏；选图后可见、MultiEffect 模糊/亮度随滑条实时联动）。
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
    // U5：设置页背景配置迁入子页 SettingsBackgroundPage（KdRadioGrid 四态单选）
    Component { id: bgSettingsComp; Loader { source: "qrc:/qt/qml/Readdict/ui/qml/SettingsBackgroundPage.qml" } }

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
            // 四态模式切换：底色随 mode 变化，image 态显示 Image 与 MultiEffect。
            // E1：组件无纸纹层（children 仅 3 项：Rectangle/Image/MultiEffect）；
            // 旧值 eink 在组件层无分支，按默认浅色回退（归一在 ReaderPage/SettingsPage）
            var loader = bgComp.createObject(root)
            verify(loader.item !== null, "ReaderBackground 应能加载（含 QtQuick.Effects import 编译检查）")
            var b = loader.item
            b.width = 200; b.height = 300
            b.mode = "light"
            compare(String(b.children[0].color), "#f5f5f0", "light 底色随 Token（暖白 #F5F5F0）")
            b.mode = "dark"
            compare(String(b.children[0].color), "#1e1e1e", "dark 底色随 Token（Kindle 深色 #1E1E1E）")
            b.mode = "paper"
            compare(String(b.children[0].color), "#f5efe0", "paper 底色随 Token（米白 #F5EFE0）")
            b.mode = "eink"
            compare(String(b.children[0].color), "#f5f5f0", "eink 旧值应回退浅色（组件无 eink 分支）")
            verify(b.children.length === 3, "ReaderBackground 应只含 Rectangle/Image/MultiEffect（无纸纹层），实际 "
                   + b.children.length)
            b.mode = "image"
            // 无图（imagePath 空）时：Image 层显示但 MultiEffect 依赖图片就绪态，
            // 未就绪 → 效果层隐藏，露出底色 Rectangle（D5 复审兜底行为）
            verify(b.children[1].visible, "image 态应显示 Image 层")
            verify(!b.children[2].visible, "无图时 MultiEffect 应隐藏（等待 Image.Ready）")
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

        function test_05_sheetSelectsBackground() {
            var dest = Settings.copyToBackgrounds(TestEnv.backgroundImage)
            Settings.setValue("background/imagePath", dest)
            Settings.setValue("background/mode", "light")
            var loader = readerComp.createObject(root)
            loader.setSource("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: {} })
            var page = loader.item
            verify(page !== null, "ReaderPage 应能加载")
            page.sheetTab = "theme"
            page.sheetOpen = true
            var panel = page.bottomSheet.contentLoader.item
            tryVerify(function () { return panel && panel.objectName === "themeSheetPanel" }, 3000,
                      "主题面板应加载")
            compare(panel.builtinModel.length, 4, "主题背景应为四态")
            panel.setBackgroundMode("paper")
            compare(page.bgMode, "paper", "选中米白应同步页面模式")
            compare(String(Settings.value("background/mode")), "paper", "选中应写 background/mode")
            panel.setBackgroundMode("image")
            compare(page.bgMode, "image", "有图时选择自定义图片应生效")
            loader.destroy()

            Settings.setValue("background/imagePath", "")
            Settings.setValue("background/mode", "light")
            loader = readerComp.createObject(root)
            loader.setSource("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: {} })
            page = loader.item
            page.sheetTab = "theme"
            page.sheetOpen = true
            panel = page.bottomSheet.contentLoader.item
            tryVerify(function () { return panel && panel.themeItems.itemAt(3) !== null }, 3000,
                      "自定义图片主题项应就绪")
            panel.setBackgroundMode("image")
            compare(page.bgMode, "light", "无图时选择 image 应保持浅色")
            Settings.setValue("background/mode", "eink")
            loader.destroy()
            loader = readerComp.createObject(root)
            loader.setSource("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: {} })
            page = loader.item
            compare(page.bgMode, "light", "旧 eink 值应归一为 light")
            compare(String(Settings.value("background/mode")), "light", "归一应回写 background/mode")
            loader.destroy()
        }

        // E3：对齐/页宽上拉框——三态选择 + 当前值高亮 + 应用即关闭
        function test_06_alignAndWidthSheets() {
            Settings.setValue("typography/pageWidth", "normal")
            Settings.setValue("reading/pageMode", "scroll")
            var loader = readerComp.createObject(root)
            loader.setSource("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: {} })
            var page = loader.item
            verify(page !== null, "ReaderPage 应能加载")
            page.sheetTab = "layout"
            page.sheetOpen = true
            var panel = page.bottomSheet.contentLoader.item
            tryVerify(function () { return panel && panel.objectName === "layoutSheetPanel" }, 3000,
                      "布局面板应加载")
            compare(panel.marginModel.length, 3, "页宽应为三态")
            panel.setPageWidth("wide")
            compare(String(Settings.value("typography/pageWidth")), "wide", "选宽应写 typography/pageWidth")
            compare(page.typography.pageWidth, "wide", "阅读页 pageWidth 应更新")
            panel.setPageWidth("normal")
            compare(page.typography.pageWidth, "normal", "切回正常页宽")
            panel.setPageMode("paged")
            compare(String(Settings.value("reading/pageMode")), "paged", "整页翻动应持久化")
            compare(page.pageMode, "paged", "整页翻动应即时生效")
            loader.destroy()
            Settings.setValue("typography/pageWidth", "normal")
            Settings.setValue("reading/pageMode", "scroll")
        }

        // E3：Sheet 打开暂停 hideControlsTimer，关闭后恢复。
        function test_07_sheetPausesAutoHide() {
            var loader = readerComp.createObject(root)
            loader.setSource("qrc:/qt/qml/Readdict/ui/qml/ReaderPage.qml", { book: {} })
            var page = loader.item
            verify(page !== null, "ReaderPage 应能加载")
            page.controlsHideDelay = 300
            page.controlsVisible = true
            page.sheetOpen = true
            tryVerify(function () { return !page.hideTimer.running }, 2000,
                      "Sheet 打开应暂停自动隐藏")
            wait(400)
            verify(page.controlsVisible, "Sheet 打开期间状态不应自动隐藏")
            page.sheetOpen = false
            tryVerify(function () { return page.hideTimer.running }, 2000,
                      "Sheet 关闭后应恢复自动隐藏")
            tryVerify(function () { return !page.controlsVisible }, 3000,
                      "关闭后计时到期应隐藏")
            loader.destroy()
        }

        function test_06_settingsPage() {
            Settings.setValue("background/mode", "image")
            Settings.setValue("background/imagePath", "")
            Settings.setValue("background/blur", 0.6)
            Settings.setValue("background/brightness", 0.9)
            var loader = bgSettingsComp.createObject(root)
            loader.width = 1100; loader.height = 720
            var page = loader.item
            verify(page !== null, "SettingsBackgroundPage 应能加载")
            verify(page.bgGrid !== undefined, "应暴露背景四态 KdRadioGrid 句柄")
            compare(page.bgGrid.currentValue, "image", "恢复后应选中 image")
            verify(page.bgEinkRadio === undefined, "背景子页不应再有 bgEinkRadio 句柄")
            compare(page.bgBlurSlider.value, 0.6, "模糊滑条应恢复 0.6")
            compare(page.bgBrightnessSlider.value, 0.9, "亮度滑条应恢复 0.9")
            page.bgGrid.selectValue("light")
            compare(Settings.value("background/mode"), "light", "选浅色应写 background/mode")
            Settings.setValue("background/mode", "eink")
            loader.destroy()
            loader = bgSettingsComp.createObject(root)
            loader.width = 1100; loader.height = 720
            page = loader.item
            compare(page.bgGrid.currentValue, "light", "旧 eink 值应归一为 light")
            compare(Settings.value("background/mode"), "light", "归一应回写 background/mode")
            page.bgGrid.selectValue("image")
            compare(Settings.value("background/mode"), "image")
            page.bgBlurSlider.value = 0.8
            compare(Settings.value("background/blur"), 0.8, "模糊滑条应写 background/blur")
            page.bgBrightnessSlider.value = 1.4
            compare(Settings.value("background/brightness"), 1.4, "亮度滑条应写 background/brightness")
            page.bgBlurSlider.value = 5.0
            compare(page.bgBlurSlider.value, 1.0, "滑条应在 0..1 内钳制")
            page.setBgBlur(5)
            compare(Settings.value("background/blur"), 1.0, "setBgBlur 越界应钳到 1.0")
            page.setBgBrightness(0.1)
            compare(Settings.value("background/brightness"), 0.5, "setBgBrightness 越界应钳到 0.5")
            page.importBackgroundImage("file:///nonexistent/x.png")
            compare(Settings.value("background/mode"), "image", "导入失败不应改当前模式")
            page.importBackgroundImage(TestEnv.backgroundImage)
            var dest = Settings.value("background/imagePath")
            verify(dest.length > 0, "导入成功应写 imagePath")
            verify(dest.indexOf("backgrounds") >= 0, "imagePath 应位于 backgrounds/：" + dest)
            compare(Settings.value("background/mode"), "image", "导入成功应写 mode=image")
            compare(page.bgGrid.currentValue, "image", "导入成功应选中自定义图片")
            loader.destroy()
        }

        function test_07_settingsThumbnail() {
            // E2：缩略图预览——未选图隐藏；选图后可见、图片就绪后效果层显示，
            // MultiEffect 模糊/亮度随滑条与页面属性实时联动（与 ReaderBackground 同换算）
            Settings.setValue("background/mode", "light")
            Settings.setValue("background/imagePath", "")
            var loader = bgSettingsComp.createObject(root)
            loader.width = 1100; loader.height = 720
            var page = loader.item
            verify(page !== null, "SettingsBackgroundPage 应能加载")
            verify(page.bgThumb !== undefined, "缩略图容器句柄应存在")
            verify(!page.bgThumb.visible, "未选图时缩略图应隐藏")
            // 选图（真实图片）→ 缩略图可见、图片就绪后效果层显示
            page.importBackgroundImage(TestEnv.backgroundImage)
            verify(Settings.value("background/imagePath").length > 0, "导入成功应写 imagePath")
            tryVerify(function () { return page.bgThumb.visible }, 5000, "选图后缩略图应可见")
            tryVerify(function () { return page.bgThumbImg.status === Image.Ready }, 5000,
                      "缩略图应加载为 Ready，实际 " + page.bgThumbImg.status)
            verify(page.bgThumbFx.visible, "图片就绪后效果层应显示")
            // 滑条移动 → page 属性（响应层）+ MultiEffect 实时联动（blur 直通、亮度换算 -1..1）
            page.bgBlurSlider.value = 0.5
            compare(page.bgBlur, 0.5, "滑条应同步 page.bgBlur（缩略图绑定源）")
            compare(page.bgThumbFx.blur, 0.5, "缩略图 blur 应随滑条实时更新")
            page.bgBrightnessSlider.value = 1.4
            compare(page.bgBrightness, 1.4, "滑条应同步 page.bgBrightness")
            compare(page.bgThumbFx.brightness, 0.4, "brightness 1.4 应换算为 MultiEffect 0.4")
            // 页面属性直改（导入/恢复路径同源）同样实时反映到效果层
            page.bgBlur = 0.8
            compare(page.bgThumbFx.blur, 0.8, "属性直改应实时反映到缩略图")
            page.bgBrightness = 0.5
            compare(page.bgThumbFx.brightness, -0.5, "brightness 0.5 应换算为 -0.5")
            wait(50)   // 渲染若干帧（模糊效果在帧上执行），不崩即通过
            // 清空路径后重启（启动恢复路径）→ 缩略图隐藏
            Settings.setValue("background/imagePath", "")
            loader.destroy()
            loader = bgSettingsComp.createObject(root)
            loader.width = 1100; loader.height = 720
            page = loader.item
            verify(!page.bgThumb.visible, "无图路径恢复后缩略图应隐藏")
            loader.destroy()
        }
    }
}
