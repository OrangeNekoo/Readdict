# PDF 双方向、整页居中与顶栏悬停背景修复计划

> **面向 AI 代理的工作者：** 必需子技能：使用 `superpowers:subagent-driven-development`；实现和测试使用 `impl-flash` 配置的 `opencode-go/deepseek-v4-flash`，最高可用思考深度。

**目标：** 让 PDF 与 EPUB 一样支持竖向连续阅读和横向分页，修复 PDF 整页适配居中，并将顶栏悬停背景限制在实际控件边界内。

**架构：** PDF 适配器根据 `Settings.value("reading/pageMode")` 在 Qt 6.11.1 的 `PdfMultiPageView`（竖向）和 `PdfScrollablePageView`（横向）之间切换；共享 PDF 适配器继续负责页码、进度、书签、文本朗读和安全关闭。整页模式通过 Flickable 的对称左右边距居中。`KdTopToolbar` 为每个 ToolButton 使用按钮本地背景，移除 Material 默认扩散阴影。

**范围：** `PdfReaderPage.qml`、`KdTopToolbar.qml`、现有 QML PDF/阅读器测试及必要的 Qt PDF 测试夹具。Qt 官方公共 API，不新增库、不加入 OCR、不修改 EPUB 内容渲染。

---

## 根因证据

- 当前 `PdfReaderPage.qml` 只有 `PdfScrollablePageView`，因此没有多页竖向视图；PDF 方向没有接入 `reading/pageMode`。
- Qt 6.11.1 官方 `PdfMultiPageView` 是用于“scrolling through multiple pages”的多页视图，提供 `document`、`currentPage`、`goToPage()`、`scaleToPage()`、`scaleToWidth()` 等公共 API；`PdfScrollablePageView` 继续作为单页横向分页视图。
- `scaleToPage()` 只计算 `renderScale`；视图继承 Flickable，窄页面在 `contentWidth < width` 时默认从 `contentX=0` 开始，造成整页模式靠左。对称 `leftMargin/rightMargin` 可让内容中心对齐视口。
- `KdTopToolbar.qml` 的 ToolButton 没有自定义 `background`，继承 Qt Quick Controls Material 默认悬停背景/阴影，绘制范围大于本地按钮内容。

## 任务 1：PDF 双方向视图切换

**文件：**
- 修改：`src/ui/qml/PdfReaderPage.qml`
- 修改：`tests/qml/tst_main.qml`
- 如现有 fixture/test helper 需要：修改 `tests/qml/tst_qmlmain.cpp`

- [ ] **步骤 1：写失败测试**

新增真实 PDF 测试属性和用例，覆盖：

```qml
page.setPageMode("scroll")
tryVerify(function () { return page.pdfViewKind === "multi" }, 3000)
compare(page.pdfView.currentPage, 0)

page.setPageMode("paged")
tryVerify(function () { return page.pdfViewKind === "single" }, 3000)
page.nextPage()
tryVerify(function () { return page.pdfView.currentPage === 1 }, 3000)
```

测试还必须验证切换方向后当前页索引保留，并且 `Settings.value("reading/pageMode")` 与页面状态一致。无真实 PDF 时用已有确定性 PDF fixture，不跳过这条新增契约。

- [ ] **步骤 2：运行确认红灯**

```bash
cmake --build build-nav --target tst_qml -j2
./build-nav/tests/tst_qml -platform offscreen \
  'PdfReaderSmoke::test_pdfSupportsVerticalAndHorizontalModes'
```

预期：现有页面没有 `pdfViewKind`/方向切换接口，测试失败。

- [ ] **步骤 3：实现视图适配**

1. 从 Settings 初始化 `pageMode`，只接受 `scroll`/`paged`，默认沿用 `reading/pageMode` 当前值。
2. 使用两个 Loader 或两个显式视图：
   - `PdfMultiPageView`：`visible: pageMode === "scroll"`，`document: pdfDoc`，用于竖向连续阅读。
   - `PdfScrollablePageView`：`visible: pageMode === "paged"`，`document: pdfDoc`，用于横向单页分页。
3. 提供统一只读 `pdfView` 代理及 `pdfViewKind`：当前活动视图的 `currentPage`、`goToPage()`、`renderScale`、`contentWidth`、`width`、边距和 `status` 必须由适配器统一访问；TTS/进度/书签不得绑定具体视图 id。
4. `setPageMode(mode)` 先保存当前页，再写 `Settings.setValue("reading/pageMode", mode)`，切换活动视图，待文档/视图 Ready 后调用 `goToPage(savedPage)`；不重置 PDF 朗读、页码或书签状态，手动切换时按已有契约停止当前页 TTS。
5. 两种模式共享现有 `scaleToWidth`、`scaleToPage`、`resetScale`、`refreshPageText`、`requestClose` 和 `renderSettled` 语义；视图销毁/重建不能销毁 `PdfDocument` 或绕过关闭竞态。
6. 方向菜单使用 EPUB 现有“布局/阅读方向”入口，不能另建一套 PDF 专用设置控件。

- [ ] **步骤 4：运行绿灯与键盘回归**

```bash
cmake --build build-nav --target Readdict tst_qml -j2
./build-nav/tests/tst_qml -platform offscreen \
  'PdfReaderSmoke::test_pdfSupportsVerticalAndHorizontalModes' \
  'PdfReaderSmoke::test_pdfReadAloudSkipsImagePage' \
  'PdfReaderSmoke::test_pdfKeyNavChangesPageWithActiveFocus' \
  'ArrowKeyPagingSmoke::test_modeSpecificWasdKeys' \
  'PagedModeSmoke::test_modeSpecificWasdKeys'
```

- [ ] **步骤 5：提交**

```bash
git add src/ui/qml/PdfReaderPage.qml tests/qml/tst_main.qml tests/qml/tst_qmlmain.cpp
git commit -m "feat(PDF): 支持竖向连续与横向分页阅读"
```

## 任务 2：修复 PDF 整页适配居中

**文件：**
- 修改：`src/ui/qml/PdfReaderPage.qml`
- 修改：`tests/qml/tst_main.qml`

- [ ] **步骤 1：写失败测试**

在真实 PDF fixture 下进入整页模式，等待布局稳定后断言：

```qml
page.setFitPage(true)
tryVerify(function () { return page.pdfHorizontalMargin >= 0 }, 3000)
compare(page.pdfLeftMargin, page.pdfRightMargin)
verify(Math.abs(page.pdfContentCenter - page.pdfViewportCenter) < 1.0)
```

同时验证宽度适配不强制居中，且窗口尺寸改变后仍重新计算。

- [ ] **步骤 2：运行确认红灯**

```bash
./build-nav/tests/tst_qml -platform offscreen \
  'PdfReaderSmoke::test_fitPageCentersNarrowPdf'
```

预期：当前实现没有统一边距/中心状态，断言失败或页面内容中心不等于视口中心。

- [ ] **步骤 3：最小实现**

实现 `updatePdfAlignment()`，只在 `fitPage` 且当前视图为 Flickable 时执行：

```qml
function updatePdfAlignment() {
    const view = page.activePdfView
    if (!view) return
    const margin = page.fitPage
        ? Math.max(0, (view.width - view.contentWidth) / 2) : 0
    view.leftMargin = margin
    view.rightMargin = margin
    page.pdfLeftMargin = view.leftMargin
    page.pdfRightMargin = view.rightMargin
}
```

在 `scaleToPage()`、视图 `widthChanged`、`contentWidthChanged`、方向切换和文档 Ready 后调用；宽度适配与重置缩放清除居中边距。中心计算必须基于实际活动视图，不使用固定窗口尺寸。

- [ ] **步骤 4：运行绿灯**

```bash
./build-nav/tests/tst_qml -platform offscreen \
  'PdfReaderSmoke::test_fitPageCentersNarrowPdf' \
  'PdfReaderSmoke::test_pdfSupportsVerticalAndHorizontalModes'
```

- [ ] **步骤 5：提交**

```bash
git add src/ui/qml/PdfReaderPage.qml tests/qml/tst_main.qml
git commit -m "fix(PDF): 让整页适配内容居中"
```

## 任务 3：限制顶栏悬停背景到控件边界

**文件：**
- 修改：`src/ui/qml/KdTopToolbar.qml`
- 修改：`tests/qml/tst_main.qml` 或现有顶栏测试文件

- [ ] **步骤 1：写失败测试**

为五个顶栏 `ToolButton` 增加可观察句柄，测试悬停前后几何不变，且按钮背景的 `x/y/width/height` 与按钮本身一致：

```qml
for (const button of page.topToolbarButtons) {
    verify(button.background !== null)
    compare(button.background.x, 0)
    compare(button.background.y, 0)
    compare(button.background.width, button.width)
    compare(button.background.height, button.height)
}
```

- [ ] **步骤 2：运行确认红灯**

```bash
./build-nav/tests/tst_qml -platform offscreen \
  'ReaderToolbarSmoke::test_hoverBackgroundMatchesButtonBounds'
```

预期：当前 Material 默认背景不是项目显式的按钮级背景，测试无法满足边界契约。

- [ ] **步骤 3：最小实现**

给五个 `ToolButton` 使用统一本地背景：

```qml
background: Rectangle {
    anchors.fill: parent
    radius: 0
    color: parent.hovered ? UITheme.hover : "transparent"
}
```

不要添加 DropShadow、阴影扩散或超出按钮矩形的装饰；图标、间距、按钮点击信号保持不变。若项目现有 hover token 名称不同，复用已有 UITheme token，不创建第二套颜色。

- [ ] **步骤 4：运行绿灯与实际界面验证**

```bash
cmake --build build-nav --target Readdict tst_qml -j2
./build-nav/tests/tst_qml -platform offscreen \
  'ReaderToolbarSmoke::test_hoverBackgroundMatchesButtonBounds' \
  'ReaderToolbarSmoke::test_toolbarSignalsAndBookmarkTwoStates'
```

启动实际 `Readdict.app`，分别验证 PDF 竖向、PDF 横向、整页居中和鼠标悬停五个顶栏按钮；截图确认悬停背景不超出按钮边界。

- [ ] **步骤 5：提交**

```bash
git add src/ui/qml/KdTopToolbar.qml tests/qml/tst_main.qml
 git commit -m "fix(阅读器): 限制顶栏按钮悬停背景范围"
```

## 最终任务：专项回归与审查

- [ ] 构建 `Readdict`、`tst_qml`。
- [ ] 运行 PDF 双方向、整页居中、TTS、图片 PDF、ReaderShell、ReaderPage、顶栏和键位回归。
- [ ] 运行最终子智能体只读审查，检查 Qt 公共 API、无重复壳层、无平台专属分支。
- [ ] 使用实际 macOS 应用完成 UI 验证；若 Orca 无法枚举直接启动的 app，记录该限制并以 QML 行为测试作为补充证据。
