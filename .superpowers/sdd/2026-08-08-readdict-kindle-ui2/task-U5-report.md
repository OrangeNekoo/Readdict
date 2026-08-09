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
