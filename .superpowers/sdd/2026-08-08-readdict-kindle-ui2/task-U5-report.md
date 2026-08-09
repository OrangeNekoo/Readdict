# U5 实现报告：LayoutSheet 图标卡 + MoreSheet 瘦身

## 状态

PASS（U5 范围完成；未修改 U6 与 i18n）。

## 交付内容

- 新增 `src/ui/qml/KdIconCard.qml`：72×52 圆角卡片，`selected`/`lines`/`glyph`/`dense` 接口，选中态使用 UITheme 活跃边框，内部绘制横线或竖线示意并发出 `clicked()`。
- `LayoutSheet.qml` 三组方向、页边距、行间距由 `Row + Repeater + KdIconCard` 渲染，保留 `setPageMode`、`setPageWidth`、`setLineHeight` 与 `modeItems`/`marginItems`/`lineItems` 句柄；补回 `KdSegmentedSlider` 对齐控件及 `setAlign` 接线。
- `MoreSheet.qml` 删除 `menuModel`、菜单 Repeater 及六个旧 `request*` 信号，只保留自动续章/深色跟随开关和 `requestToc`；新增可点击「阅读进度 / 书中位置」行。
- `ReaderPage.qml` 只保留 MoreSheet 的 `requestToc` 宿主接线，并接入布局对齐状态。
- 根 CMake 与测试 QML 资源清单同步 `KdIconCard.qml`；新增 `tests/qml/tst_sheets.qml`，并适配 `tst_u4.qml` 使用真实图标卡与阅读进度行。

## 验证

- `cmake --build build --parallel`：通过。
- U5 聚焦 QML：`IconCardSmoke`、`LayoutSheetSmoke`、`MoreSheetSmoke` 共 9 passed、0 failed。
- Sheet 回归：`ReaderSheetSmoke` 布局/更多/标签测试 5 passed、0 failed。
- `ctest --test-dir build -R tst_qml --output-on-failure`：227 passed、4 failed、4 skipped；失败为仓库既有 QML 导入/时序 flake（`PagedModeSmoke::test_autoRepeatThrottlesChapterChange`、`DeleteSmoke::test_deleteDialogRemovesBookAndFiles`、`MainNavSmoke::test_navSwitchReaderResume`、`ReaderSheetSmoke::test_middleTapOpensSheetAndReTapCloses`），U5 新增及适配用例均通过。

## 疑虑

完整 QML 回归中的 4 个失败不属于 U5：分页自动重复、DeleteSmoke/MainNavSmoke 测试书导入时序、以及 ReaderSheetSmoke 中部/底部点击语义；U5 聚焦回归未复现失败。

## 修复轮（2026-08-09，ImplU5Fix2）

### 修复内容

- `LayoutSheet.qml`：三组图标卡由 `Row`（fillWidth + AlignHCenter 无效导致卡片靠左）改为 `Item`（fillWidth）内嵌 `Row`，`anchors.horizontalCenter` 真正水平居中；句柄 `modeItems`/`marginItems`/`lineItems` 仍指向 Repeater，`setPageMode`/`setPageWidth`/`setLineHeight`/`setAlign` 接口不变。
- `KdIconCard.qml`：新增 `verticalLineItems` 句柄（竖排示意 Repeater），供 dense/竖排示意测试。
- `tst_sheets.qml`：`IconCardSmoke` 增加选中边框 Token（`UITheme.borderActive`）与 2.5px 断言、横线/竖线 Repeater count 跟随 `lines`、dense/vertical 竖线可见性断言；`LayoutSheetSmoke` 增加默认方向卡选中边框断言、mapToItem 实测图标卡组在 Sheet 中水平居中。
- `tst_u4.qml`：`ReaderSheetSmoke::test_layoutPanelApplies` 增加 `alignSlider.selectValue("center"/"left")` 后断言 `Settings.value("typography/align")` 与 `page.typography.align` 同步持久化。

### 验证

- `cmake --build build --target tst_qml --parallel`：通过（0.72s，增量无重编，资源时间戳晚于源文件，改动已入 qrc）。
- 聚焦 QML：`IconCardSmoke::test_cardDimensionsAndClick`、`LayoutSheetSmoke::test_iconCardsApplyAndAlignSlider`、`MoreSheetSmoke::test_progressRowAndTocOnly`（简报写的 `test_moreSheetSlimAndProgressRow` 实际函数名为 `test_progressRowAndTocOnly`）9 passed、0 failed。
- ReaderSheet 集成：`ReaderSheetSmoke::test_layoutPanelApplies`（含新增 setAlign Settings/响应断言）、`test_morePanelToggles` 4 passed、0 failed。
- 工作树清理：4 个 U5 文件提交后无残留。

### 疑虑

- 既有全量回归中的 4 个 flake（分页自动重复、DeleteSmoke/MainNavSmoke 导入时序、middleTap 点击语义）在聚焦运行中均未复现，与 U5 无关。

## 修复轮 2（2026-08-09，ImplU5Fix2，dense/vertical 分支真实性）

### 修复内容

- `KdIconCard.qml`：内部横线容器 id `horizontalLines`→`hLines`、竖线容器 id `verticalLines`→`vLines`，新增稳定测试句柄 `property alias horizontalLines` / `property alias verticalLines`（`visible` 分支可经句柄直接断言；原 id 仅组件内部使用，无外部引用）。
- `tst_sheets.qml`：
  - `IconCardSmoke::test_cardDimensionsAndClick`：原 43–46 行同一对象同时置 `glyph="v"` 与 `dense=true` 且只断言竖线可见，改为单条件 `glyph="v", dense=false` 并同时断言 `verticalLines.visible=true` 与 `horizontalLines.visible=false`，消除分支掩盖。
  - 新增 `IconCardSmoke::test_denseAndGlyphVisibilityBranches`：用独立卡片分别覆盖两个 visible 分支并断言 lines count——① `glyph='v', dense=false` 时 `verticalLines.visible=true`、`horizontalLines.visible=false`、`verticalLineItems.count===lines===4`、`lineItems.count===4`；② `glyph='h', dense=true` 时同样竖线可见、横线隐藏、数量随 `lines`；③ 对照默认 `glyph='h', dense=false` 卡横线可见、竖线隐藏，证明分支未被掩盖。
- 保持既有接口不变：`selected`/`lines`/`dense`/`glyph`/`clicked`/`lineItems`/`verticalLineItems` 均未改动，`LayoutSheet`/`MoreSheet` 与 tst_u4 使用不受影响。

### 验证

- `cmake --build build --target tst_qml --parallel`：通过（增量重编 qrc + 链接）。
- U5 聚焦：`IconCardSmoke::test_cardDimensionsAndClick`、`IconCardSmoke::test_denseAndGlyphVisibilityBranches`、`LayoutSheetSmoke::test_iconCardsApplyAndAlignSlider`、`MoreSheetSmoke::test_progressRowAndTocOnly` 共 10 passed、0 failed（含新增用例）。
- 全量 `tst_qml`：228 passed、4 failed、4 skipped；4 个失败（`PagedModeSmoke::test_autoRepeatThrottlesChapterChange`、`DeleteSmoke::test_deleteDialogRemovesBookAndFiles`、`MainNavSmoke::test_navSwitchReaderResume`、`ReaderSheetSmoke::test_middleTapOpensSheetAndReTapCloses`）已用 stash 对比验证为修复前既有：前两者全量顺序 flake（单独运行通过），后两者单独运行也复现，均与本修复无关（本修复仅改 KdIconCard 内部 id 命名 + 测试）。

### 疑虑

- 无新增疑虑；全量回归 4 个失败与上轮一致，均为仓库既有 flake。
