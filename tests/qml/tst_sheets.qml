import QtQuick
import QtQuick.Controls
import QtTest
import Readdict.UI 1.0

// U5：阅读页布局/更多 Sheet 的真实组件冒烟。组件经 Loader + qrc 加载，
// 驱动 KdIconCard、Sheet Repeater 与 requestToc 信号，避免仅检查源码结构。
Item {
    id: root
    width: 500; height: 500

    Component {
        id: cardComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/KdIconCard.qml" }
    }
    Component {
        id: layoutComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/LayoutSheet.qml" }
    }
    Component {
        id: moreComp
        Loader { source: "qrc:/qt/qml/Readdict/ui/qml/MoreSheet.qml" }
    }

    TestCase {
        name: "IconCardSmoke"

        function test_cardDimensionsAndClick() {
            var loader = cardComp.createObject(root)
            var card = loader.item
            verify(card !== null, "KdIconCard 应能加载")
            compare(card.width, 72, "图标卡宽度应为 72px")
            compare(card.height, 52, "图标卡高度应为 52px")
            card.lines = 5
            card.glyph = "wide"
            card.selected = true
            compare(card.lines, 5, "图标卡应保留 lines")
            compare(card.glyph, "wide", "图标卡应保留 glyph")
            compare(card.lineItems.count, 5, "横线 Repeater 数量应跟随 lines")
            compare(String(card.border.color), String(UITheme.borderActive),
                    "选中卡片应使用活跃边框 Token")
            compare(card.border.width, 2.5, "选中卡片边框应加粗")
            card.glyph = "v"
            card.dense = false
            compare(card.verticalLineItems.count, 5, "竖线 Repeater 数量应跟随 lines")
            verify(card.verticalLines.visible, "glyph=v 且非 dense 时 verticalLines 应可见")
            verify(!card.horizontalLines.visible, "glyph=v 且非 dense 时 horizontalLines 应隐藏")
            var clicked = false
            card.clicked.connect(function () { clicked = true })
            mouseClick(card, card.width / 2, card.height / 2)
            verify(clicked, "点击图标卡应发 clicked")
            loader.destroy()
        }

        function test_denseAndGlyphVisibilityBranches() {
            // 分支一：glyph='v' + dense=false → verticalLines 可见、horizontalLines 隐藏。
            var vLoader = cardComp.createObject(root)
            var vCard = vLoader.item
            verify(vCard !== null, "竖排卡应能加载")
            vCard.glyph = "v"
            vCard.dense = false
            compare(vCard.lines, 4, "竖排卡默认 lines 应为 4")
            verify(vCard.verticalLines.visible, "glyph=v 且 dense=false 时 verticalLines 应可见")
            verify(!vCard.horizontalLines.visible, "glyph=v 且 dense=false 时 horizontalLines 应隐藏")
            compare(vCard.verticalLineItems.count, 4, "竖排卡竖线数量应跟随 lines")
            compare(vCard.lineItems.count, 4, "竖排卡横线 Repeater 数量应保留")

            // 分支二：glyph='h' + dense=true → verticalLines 可见、horizontalLines 隐藏。
            var hLoader = cardComp.createObject(root)
            var hCard = hLoader.item
            verify(hCard !== null, "密排卡应能加载")
            hCard.glyph = "h"
            hCard.dense = true
            compare(hCard.lines, 4, "密排卡默认 lines 应为 4")
            verify(hCard.verticalLines.visible, "glyph=h 且 dense=true 时 verticalLines 应可见")
            verify(!hCard.horizontalLines.visible, "glyph=h 且 dense=true 时 horizontalLines 应隐藏")
            compare(hCard.verticalLineItems.count, 4, "密排卡竖线数量应跟随 lines")
            compare(hCard.lineItems.count, 4, "密排卡横线 Repeater 数量应保留")

            // 对照：默认 h + 非 dense → horizontalLines 可见、verticalLines 隐藏，证明分支未被掩盖。
            var dLoader = cardComp.createObject(root)
            var dCard = dLoader.item
            verify(dCard.horizontalLines.visible, "默认卡 horizontalLines 应可见")
            verify(!dCard.verticalLines.visible, "默认卡 verticalLines 应隐藏")

            vLoader.destroy()
            hLoader.destroy()
            dLoader.destroy()
        }
    }

    TestCase {
        name: "LayoutSheetSmoke"

        function test_iconCardsApplyAndAlignSlider() {
            var loader = layoutComp.createObject(root)
            loader.width = 400
            loader.height = 400
            var sheet = loader.item
            verify(sheet !== null, "LayoutSheet 应能加载")
            tryVerify(function () {
                return sheet.modeItems.count === 2 && sheet.marginItems.count === 3
                       && sheet.lineItems.count === 3
            }, 3000, "三组图标卡应完成实例化")
            var selectedCard = sheet.modeItems.itemAt(0)
            compare(String(selectedCard.border.color), String(UITheme.borderActive),
                    "默认方向卡应使用活跃边框 Token")
            compare(selectedCard.border.width, 2.5, "选中方向卡边框应为 2.5px")
            var first = sheet.modeItems.itemAt(0)
            var last = sheet.modeItems.itemAt(1)
            var left = first.mapToItem(sheet, 0, 0).x
            var right = last.mapToItem(sheet, last.width, 0).x
            verify(Math.abs((left + right) / 2 - sheet.width / 2) < 1,
                   "方向图标卡组应在 Sheet 中水平居中")
            compare(sheet.modeItems.itemAt(0).glyph, "v", "连续滚动应使用竖排 glyph")
            compare(sheet.modeItems.itemAt(1).glyph, "h", "整页翻动应使用横排 glyph")
            compare(sheet.marginItems.itemAt(0).glyph, "narrow", "窄页边距 glyph")
            compare(sheet.marginItems.itemAt(2).glyph, "wide", "宽页边距 glyph")
            compare(sheet.lineItems.itemAt(0).glyph, "tight", "紧凑行距 glyph")
            compare(sheet.lineItems.itemAt(2).glyph, "loose", "宽松行距 glyph")

            var mode = ""
            sheet.setPageMode.connect(function (value) { mode = value })
            mouseClick(sheet.modeItems.itemAt(1), 36, 26)
            compare(mode, "paged", "点击方向卡应发 setPageMode")

            verify(sheet.alignSlider !== undefined, "应保留对齐 KdSegmentedSlider")
            var align = ""
            sheet.setAlign.connect(function (value) { align = value })
            sheet.alignSlider.selectValue("center")
            compare(align, "center", "对齐滑块应发 setAlign")
            loader.destroy()
        }
    }

    TestCase {
        name: "MoreSheetSmoke"

        function test_progressRowAndTocOnly() {
            var loader = moreComp.createObject(root)
            loader.width = 400
            loader.height = 300
            var sheet = loader.item
            verify(sheet !== null, "MoreSheet 应能加载")
            verify(sheet.menuModel === undefined, "MoreSheet 不应再暴露旧 menuModel")
            verify(sheet.menuItems === undefined, "MoreSheet 不应再暴露旧 menuItems")
            verify(sheet.progressRow !== undefined, "MoreSheet 应暴露阅读进度行")
            verify(sheet.requestNotes === undefined, "MoreSheet 不应再暴露笔记信号")
            verify(sheet.requestSearch === undefined, "MoreSheet 不应再暴露搜索信号")
            verify(sheet.requestReadAloud === undefined, "MoreSheet 不应再暴露朗读信号")
            verify(sheet.requestPrevChapter === undefined, "MoreSheet 不应再暴露上一章信号")
            verify(sheet.requestNextChapter === undefined, "MoreSheet 不应暴露下一章信号")
            var tocRequested = false
            sheet.requestToc.connect(function () { tocRequested = true })
            mouseClick(sheet.progressRow, sheet.progressRow.width / 2, sheet.progressRow.height / 2)
            verify(tocRequested, "点击阅读进度行应保留 requestToc")
            loader.destroy()
        }
    }
}
