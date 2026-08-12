import QtQuick
import QtQuick.Controls
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

        // 审查修复：用例级 cleanup——测试失败路径也复位背景分区，避免污染
        // Settings（background/mode、imagePath、textColor 为任务5读写键），
        // 保证用例间/套件间隔离。
        function cleanup() {
            Settings.setValue("background/mode", "light")
            Settings.setValue("background/imagePath", "")
            Settings.setValue("background/textColor", "")
        }

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
            // 任务5：预览固定为小长方形卡片，始终可见（未选图时显示当前背景模式
            // 底色 + 测试文本）；选图后叠加图片/模糊/亮度效果；测试文本颜色随
            // 模式文字色（image 模式 = 所选字体颜色，非法回退浅色默认）。
            Settings.setValue("background/mode", "light")
            Settings.setValue("background/imagePath", "")
            Settings.setValue("background/textColor", "")
            var loader = bgSettingsComp.createObject(root)
            loader.width = 1100; loader.height = 720
            var page = loader.item
            verify(page !== null, "SettingsBackgroundPage 应能加载")
            verify(page.bgThumb !== undefined, "缩略图容器句柄应存在")
            verify(page.bgThumb.visible, "预览卡片应始终可见（含未选图）")
            verify(page.bgThumbText !== undefined, "预览应暴露测试文本句柄")
            verify(page.bgThumbText.visible && page.bgThumbText.text.length > 0,
                   "预览应显示测试文本")
            compare(page.bgThumb.width, 220, "预览应为固定小卡片宽 220，实际 " + page.bgThumb.width)
            compare(page.bgThumb.height, 120, "预览应为固定小卡片高 120，实际 " + page.bgThumb.height)
            compare(String(page.bgThumbText.color), "#1a1a1a", "light 模式测试文本应为默认深字")
            compare(String(page.thumbTextColor), "#1a1a1a", "light 模式 thumbTextColor 应为默认深字")
            // 选图（真实图片）→ 图片就绪后效果层显示；滑条与页面属性实时联动
            page.importBackgroundImage(TestEnv.backgroundImage)
            verify(Settings.value("background/imagePath").length > 0, "导入成功应写 imagePath")
            tryVerify(function () { return page.bgThumbImg.status === Image.Ready }, 5000,
                      "缩略图应加载为 Ready，实际 " + page.bgThumbImg.status)
            verify(page.bgThumbFx.visible, "图片就绪后效果层应显示")
            page.bgBlurSlider.value = 0.5
            compare(page.bgBlur, 0.5, "滑条应同步 page.bgBlur（缩略图绑定源）")
            compare(page.bgThumbFx.blur, 0.5, "缩略图 blur 应随滑条实时更新")
            page.bgBrightnessSlider.value = 1.4
            compare(page.bgBrightness, 1.4, "滑条应同步 page.bgBrightness")
            compare(page.bgThumbFx.brightness, 0.4, "brightness 1.4 应换算为 MultiEffect 0.4")
            page.bgBlur = 0.8
            compare(page.bgThumbFx.blur, 0.8, "属性直改应实时反映到缩略图")
            page.bgBrightness = 0.5
            compare(page.bgThumbFx.brightness, -0.5, "brightness 0.5 应换算为 -0.5")
            // 深色模式：卡片测试文本色随模式（自定义色不污染非 image 模式）
            page.bgGrid.selectValue("dark")
            compare(String(page.bgThumbText.color), "#e8e8e3", "dark 模式测试文本应为浅字")
            wait(50)   // 渲染若干帧（模糊效果在帧上执行），不崩即通过
            // 清空路径后重启 → 卡片仍可见（显示模式底色 + 测试文本）
            Settings.setValue("background/imagePath", "")
            loader.destroy()
            loader = bgSettingsComp.createObject(root)
            loader.width = 1100; loader.height = 720
            page = loader.item
            verify(page.bgThumb.visible, "无图路径恢复后预览卡片仍应可见")
            verify(page.bgThumbText.visible, "无图路径恢复后测试文本仍应可见")
            loader.destroy()
            Settings.setValue("background/mode", "light")
        }

        // 任务5：字体颜色预设——仅 image 模式显示（≥3 个安全色），选择即时写
        // background/textColor；恢复合法值选中对应预设，非法/缺失回退默认近黑。
        function test_08_textColorPresets() {
            Settings.setValue("background/mode", "light")
            Settings.setValue("background/imagePath", "")
            Settings.setValue("background/textColor", "")
            var loader = bgSettingsComp.createObject(root)
            loader.width = 1100; loader.height = 720
            var page = loader.item
            verify(page !== null, "SettingsBackgroundPage 应能加载")
            verify(page.textColorGrid !== undefined, "应暴露字体颜色预设句柄")
            verify(!page.textColorSection.visible, "非 image 模式应隐藏字体颜色选择")
            verify(page.textColorGrid.options.length >= 3,
                   "字体颜色预设应不少于 3 个，实际 " + page.textColorGrid.options.length)
            // 选图（进入 image 模式）→ 字体颜色选择显示
            page.importBackgroundImage(TestEnv.backgroundImage)
            tryVerify(function () { return page.textColorSection.visible }, 2000,
                      "image 模式应显示字体颜色选择")
            // 选择预设 → 即时持久化 + 页面状态同步 + 预览测试文本色联动
            page.textColorGrid.selectValue("#FFFFFF")
            compare(String(Settings.value("background/textColor")), "#FFFFFF",
                    "选择应即时写 background/textColor")
            compare(page.bgTextColor, "#FFFFFF", "页面 bgTextColor 应同步")
            compare(String(page.thumbTextColor), "#ffffff", "预览测试文本色应联动为所选色")
            compare(String(page.bgThumbText.color), "#ffffff", "预览文本应使用所选颜色")
            // 恢复合法值：重载页面 → bgTextColor 恢复、预设选中对应值
            loader.destroy()
            loader = bgSettingsComp.createObject(root)
            loader.width = 1100; loader.height = 720
            page = loader.item
            compare(page.bgTextColor, "#FFFFFF", "恢复后 bgTextColor 应为合法自定义色")
            compare(page.textColorGrid.currentValue, "#FFFFFF", "恢复后应选中对应预设")
            loader.destroy()
            // 非法值 → 回退默认近黑（bgTextColor 置空、预设选中默认）
            Settings.setValue("background/textColor", "#ZZZZZZ")
            loader = bgSettingsComp.createObject(root)
            loader.width = 1100; loader.height = 720
            page = loader.item
            compare(page.bgTextColor, "", "非法值应回退（bgTextColor 置空）")
            compare(page.textColorGrid.currentValue, "#1A1A1A", "非法值预设应回退默认近黑")
            compare(String(page.thumbTextColor), "#1a1a1a", "非法值预览测试文本色应回退默认")
            loader.destroy()
            // 缺失值 → 回退默认近黑
            Settings.setValue("background/textColor", "")
            loader = bgSettingsComp.createObject(root)
            loader.width = 1100; loader.height = 720
            page = loader.item
            compare(page.bgTextColor, "", "缺失值应回退（bgTextColor 置空）")
            compare(page.textColorGrid.currentValue, "#1A1A1A", "缺失值预设应回退默认近黑")
            loader.destroy()
            // 清理
            Settings.setValue("background/mode", "light")
            Settings.setValue("background/imagePath", "")
            Settings.setValue("background/textColor", "")
        }

        // 审查修复：窄窗口下预览卡片保持固定 220×120（min/max 硬约束不被
        // 压缩），且父 ScrollView 水平可达——contentWidth 覆盖卡片右缘、
        // 内容宽于视口、横向滚动条策略非 AlwaysOff（内容不裁剪）。
        function test_09_narrowWindowFixedThumb() {
            // 路径 A：宽窗口创建后缩到窄窗口（审查复现场景）
            var loader = bgSettingsComp.createObject(root)
            loader.width = 1100; loader.height = 720
            var page = loader.item
            verify(page !== null, "SettingsBackgroundPage 应能加载")
            wait(50)
            loader.width = 240
            wait(50)
            compare(page.bgThumb.width, 220, "窄窗口下预览宽应保持固定 220，实际 "
                   + page.bgThumb.width)
            compare(page.bgThumb.height, 120, "窄窗口下预览高应保持固定 120，实际 "
                   + page.bgThumb.height)
            verify(page.bgThumb.visible, "窄窗口下预览卡片仍应可见")
            verify(page.bgScroll.contentWidth >= page.bgThumb.x + page.bgThumb.width,
                   "横向内容宽度应覆盖卡片右缘（水平可达）：contentWidth="
                   + page.bgScroll.contentWidth + " 卡片右缘="
                   + (page.bgThumb.x + page.bgThumb.width))
            verify(page.bgScroll.contentWidth > page.bgScroll.width,
                   "窄窗口内容应宽于视口（可横向滚动）：contentWidth="
                   + page.bgScroll.contentWidth + " 视口=" + page.bgScroll.width)
            verify(page.bgScroll.ScrollBar.horizontal.policy !== ScrollBar.AlwaysOff,
                   "横向滚动条策略应允许滚动（非 AlwaysOff）")
            loader.destroy()
            // 路径 B：直接以窄窗口创建
            loader = bgSettingsComp.createObject(root)
            loader.width = 240; loader.height = 720
            page = loader.item
            wait(80)
            compare(page.bgThumb.width, 220, "直接窄窗口创建宽应仍为 220，实际 "
                   + page.bgThumb.width)
            compare(page.bgThumb.height, 120, "直接窄窗口创建高应仍为 120，实际 "
                   + page.bgThumb.height)
            loader.destroy()
        }

        // BUG8：FileDialog 防御——取消/空 selectedFiles 不触发导入（onAccepted
        // 只处理非空选择；个别平台/路径可能以空列表发 accepted，不得写模式/路径）
        function test_10_fileDialogEmptySelectionNoImport() {
            Settings.setValue("background/mode", "light")
            Settings.setValue("background/imagePath", "")
            var loader = bgSettingsComp.createObject(root)
            loader.width = 1100; loader.height = 720
            var page = loader.item
            verify(page !== null, "SettingsBackgroundPage 应能加载")
            verify(page.bgFileDialog !== undefined, "应暴露背景 FileDialog 句柄")
            // 未打开/取消后 selectedFiles 为空——防御路径不触发导入
            compare(page.bgFileDialog.selectedFiles.length, 0,
                    "未选择的 FileDialog selectedFiles 应为空")
            page.handleBgFileAccepted()
            compare(String(Settings.value("background/mode")), "light",
                    "空 selectedFiles 不应改背景模式")
            compare(String(Settings.value("background/imagePath")), "",
                    "空 selectedFiles 不应导入图片")
            // 非空选择仍正常导入（防御不破坏正常路径）
            page.importBackgroundImage(TestEnv.backgroundImage)
            verify(String(Settings.value("background/imagePath")).length > 0,
                   "有效选择仍应导入图片")
            loader.destroy()
            Settings.setValue("background/mode", "light")
            Settings.setValue("background/imagePath", "")
        }
    }
}
