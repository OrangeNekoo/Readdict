# 任务3 复审修复收敛报告（2026-08-11）

## 结论

全量 QML 263/0（连续 6 次运行全部通过，含最终门禁一次）、ctest 20/20。
提交 `a8580e4`：任务3复审修复：页宽变化重定位 contentX 到逻辑页、停动画不误触发自动续章、null 段落 globalIndex 对齐与朗读防御。

## 生产修复（全部保留，4 处）

1. `ReaderContent.qml rebuildPageModel`：钳制 currentPage 后重定位
   `contentX = currentPage × 新页宽`（此前只钳 maxX，页宽变化后 contentX 停在
   旧几何值，与逻辑当前页错位）。
2. `ReaderContent.qml stopPageAnimations`：stop 前保存并清空 checkNextOnStop——
   `pageAnim.stop()` 同步触发 onStopped，修复前把"外部中断"误判为"自然到达章末"，
   误触发 requestNextChapter 自动续章。
3. `ReaderContent.qml paraComp.globalIndex`：scroll 模式 null 段落 globalIndex 取
   Repeater 自身 index（旧 `(modelData ?? 0)` 错映射为 0，句/划线索引错位）。
4. `ReaderPage.qml`：拍平段落句子时 null 按空段跳过（`(p ?? {}).sentences ?? []`），
   意外异常兜底置 loadError 可读占位。

## 回归测试（新增/修改，全部保留）

- `test_animationStopDoesNotChangeChapter` → 锁定修复 2
- `test_resizeRebuildStopsPageAnimation`（改断言）→ 锁定修复 1（中断不丢翻页意图）
- `test_resizeRepositionsContentXToCurrentPage`（新增）→ 锁定修复 1（resize 重定位不变量）
- `test_scrollNullParagraphKeepsGlobalIndex`（新增）→ 锁定修复 3/4

## 全量失败复现与根因排查

主控报告的 `ControlsSummonSmoke::test_realTextSelectionStillWorks` 263/1 失败
**未复现**：本次会话共运行全量 QML 6 次（含最终门禁），全部 263/0。

排查结论：

- 新测试均作用在销毁的页实例上；typography/root.width 均显式恢复；Settings/
  Books 由 tst_e4_keys 既有 initTestCase/cleanupTestCase 管理（pageMode 复位
  scroll、longbook/multibook 导入后删除）。未发现新测试的持久跨文件污染。
- 最可疑的时序竞态（[INFERENCE]，未确定性复现）：`test_realTextSelectionStillWorks`
  在 openPage 后约 50–200ms 执行拖选，而打开的书（findTxtBook 取 booksModel 最新
  TXT，实际为 tst_main 导入且不清理的 multibook）带有已保存滚动偏移，
  ReaderPage 滚动恢复定时器（200ms 收敛）可能在拖选中途跳变 contentY 破坏选区。
  该机制为既有竞态（tst_main 行为本次未改），与本次 diff 无直接因果；因无法
  稳定复现，按约束不修改旧断言、不删回归测试。
- 保留判断：263/1 为偶发时序抖动；新测试使 tst_e4_keys 运行时长增加约 10s，
  可能改变了竞态窗口的命中概率，但 6 次全量验证均为 0 fail。

## 验证证据

- `./build/Qt_6_11_1_for_macOS_Debug/tests/tst_qml -input tests/qml`
  → 263 passed, 0 failed, 4 skipped（6/6 次）
- `ctest`（build/Qt_6_11_1_for_macOS_Debug）→ 20/20 passed
- 提交前确认 tst_qml 二进制（03:01:17）新于 ReaderContent.qml/ReaderPage.qml
  （02:59:49），qrc 内嵌 QML 为最新代码；tst_e4_keys.qml 从磁盘加载（运行时）。
