# 任务 3 报告：真正的横向分页模式

- 日期：2026-08-10
- 实现者：impl-flash（opencode-go/deepseek-v4-flash）
- 计划：`docs/superpowers/plans/2026-08-10-reader-library-fixes.md` 任务 3
- 提交：见文末（简体中文 commit）

## 目标回顾

1. `scroll`：保持单列竖向连续滚动（ReaderContent 既有路径与旧测试语义不变）。
2. `paged`：按可见 viewport 生成横向页序列，页面沿 x 轴排列；左右键/点击翻页改变 `contentX`/当前页；上下键同页步进语义；章首/章末继续走上一章/下一章边界逻辑。
3. 页宽/字体/行高/窗口尺寸/章节变化时重算页数并钳制当前页；图片段与富文本段保留现有渲染语义；异常内容不空白。
4. 设置仍持久化 `reading/pageMode`，UI 文案明确为「竖向连续滚动/横向分页」。

## 核心设计：稳定单向分页模型（无振荡）

此前两次方案因「动态测量高度回填分页」振荡回滚。本任务采用**最小稳定方案**：

- **分页只依赖稳定输入**：段落字符串长度/段落边界、viewport 几何（width/height）、typography 字号/行高/页宽档。`rebuildPageModel()` 一次同步算出 `pageModel`（每页 = 段落全局索引数组）与 `pageCount`，**绝不读取 delegate 异步 implicitHeight 作分页反馈**——无反馈回路，pageCount 一经生成即收敛，无振荡。
- **无隐藏测量列、无双重 Repeater**：段落渲染抽为共享 `paraComp` Component（scroll 主 Repeater 与 paged 页内 Repeater 共用同一渲染代码，text/html/image 语义完全一致）；同一段落只挂在一个 Repeater 上（另一侧 model 置空），不存在重复渲染。
- **页面布局**：`pageRow`（Row）沿 x 轴排列 `pageComp`（每页 = 页宽 = 视口宽、页高 = 视口高的独立 Item，页内 Column 复用 scroll 相同正文列宽公式）。`contentWidth = pageCount × width`（> 视口宽）、`contentHeight = height` + `flickableDirection = HorizontalOnly`（纵向锁死）→ `contentY` 恒 0，分页职责完全由 `contentX` 承担。
- **估算偏保守**：全角字符宽按 0.8 字号估算、h1-h6 与 `<br>` 行高加权、图片段独占一页、超长段不拆段（单页内自然换行）——避免页内容溢出视口被裁剪；非空章至少一页，无空白页。
- **重算时机**：`onChapterChanged` / `onPageModeChanged` / `onTypographyChanged` / `onWidthChanged` / `onHeightChanged` → `rebuildPageModel()` 并钳制 `contentX ≤ (页数-1)×页宽`。

## 改动

### `src/ui/qml/ReaderContent.qml`
- 新增 `pageModel`/`pageCount` 属性、`pageRepeater`/`pageAnimationX` 句柄、`rebuildPageModel`/`pageWidth`/`pageForParagraph`/`paragraphItemAt`/`goToPage`。
- `contentWidth`/`contentHeight`/`flickableDirection` 按模式分流（paged：页数×页宽 / 视口高 / 锁纵向）。枚举用数值（本 Qt 6.11 实测 `Flickable.HorizontalOnly` 类型名枚举不可解析，返回 undefined；0=Auto/1=HorizontalOnly 为 Qt 稳定 ABI）。
- 段落渲染抽为 `paraComp` Component（`modelData` 段落对象 vs 页内索引数字两态判别收敛到 `paraData`/`globalIndex`）；`col` 在 paged 时 model 置空并隐藏；新增 `pageRow`/`pageComp`（页内 `pageParaRep`）。
- `pagePrev`/`pageNext`/`snapToPage` 全部改写为 contentX 页边界语义（首页 ← 翻上一章、末页 → 翻下一章、拖拽/滚轮收敛吸附）；新增 `pageAnimX`（contentX 动画，与 followAnim 互斥）；`followSentence`/`scrollToParagraph` paged 分支翻到所在页；`clearSelection`/`simulateSelection` 改经 `paragraphItemAt`（paged 下按页内 Repeater 定位）。
- `contentTapped` 信号增加 x 参数；`applyRestore` paged 分支直接消费 pending（不置 restoreApplied，避免永久关闭 snapToPage 门控）。

### `src/ui/qml/ReaderPage.qml`
- `onContentTapped: (x, y) => page.handleContentTap(content.y + y, x)`；`handleContentTap(y, x)` 新增 paged 分支：右半屏 `pageNext`、左半屏 `pagePrev`（首末页边界换章由 pageNext/pagePrev → autoNext/autoPrevChapter 处理）；x 缺省（旧测试直调路径）保持唤出语义。scroll 模式行为不变。

### `src/ui/qml/LayoutSheet.qml` / `SettingsBackgroundPage.qml`
- 模式文案：`连续滚动`→`竖向连续滚动`、`整页翻动`→`横向分页`（value token 不变，持久化键不变）；同步更新注释。`src/core/SettingsStore.cpp` 注释对齐。

### `tests/qml/tst_e4_keys.qml`
- PagedModeSmoke 全部改写为横向语义：新增 `waitPagesSettled`（pageCount 稳定两采样 + 页面委托数同步）；`test_pagedContentIsHorizontal`（contentWidth > width、contentHeight ≤ 视口高、→/↓/←/↑ 按页宽改 contentX、contentY 恒 0、pageCount 连续采样不振荡、首页 ←/↑ 兜底不换章）；`test_pagedLastPageAdvancesChapter`/`test_pagedPrevChapterAtChapterStart`/`test_autoRepeatThrottlesChapterChange`/`test_pagedWheelSnapToPageBoundary`/`test_pageAnimStopsFollowAnim` 相应改写。scroll 模式用例（ArrowKeyPagingSmoke）一行未动。

## TDD 证据

- 红：新断言（contentWidth > width、contentX 翻页、contentY 不变等）在旧实现（contentWidth == width、contentY 假分页）上 6 个 paged 用例全部 FAIL。
- 绿：实现后 tst_e4_keys 16/16 通过；修复过程中定位两处问题并解决：
  1. `Flickable.HorizontalOnly` 类型名枚举在本 Qt 6.11 不可解析（探针实证 `Flickable.Auto`/`.HorizontalOnly` 均为 undefined）→ 改稳定数值枚举（0/1）。
  2. 章 1（60 段短段）字符估算下恰为 1 页，原 autoRepeat 测试逐页循环第一按即误触发翻章 → 改用章 0（100 段 ≈ 3 页）测末页停留。
  3. 委托销毁瞬间 `paraData` 瞬时 undefined 导致 TypeErrors → `?? {}` 兜底，零警告。

## 验证

- 构建：`cmake --build build/Qt_6_11_1_for_macOS_Debug --target tst_qml Readdict -j8` 成功（0 error）。
- 定向（项目实际方式 `tst_qml -input <abs path>`）：
  - `tst_e4_keys.qml`：**16 passed, 0 failed**（含 6 个改写后的 paged 横向用例）。
  - `tst_readerpage.qml`：**20 passed, 0 failed**（点击唤出/选择/拖动回归，scroll 语义不变）。
  - `tst_background.qml`：**13 passed, 0 failed**。
  - `tst_u4.qml`：**18 passed, 0 failed**。
- 回归（段落渲染共享组件触及套件）：tst_sheets 10、tst_highlightsui 24、tst_c4_scroll 8、tst_textcolor 8、tst_ttsbar 9 全绿。
- `tst_main` 的 `FulltextSmoke::test_shelfFulltextHits`（书架全文搜索命中数）在**本改动前后均失败**（git stash 至干净树复现同款 FAIL，4 skipped 亦为原状）——既有环境性失败，与本任务无关，未修（范围外）。
- 无 pageCount 振荡：`test_pagedContentIsHorizontal` 断言 pageCount 连续采样不变；`waitPagesSettled` 要求两采样稳定；实现为纯同步估算，无 delegate 高度反馈回路。
- 探针（tst_flickenum_probe.qml）已删除，工作区无残留探针。

## 交互语义确认（测试实测）

- paged：`contentWidth = pageCount × width > width`；`→`/`↓`/`PageDown`/`PageUp`/`←`/`↑` 均按页宽步进 `contentX`；`contentY` 恒 0（contentHeight = 视口高 + HorizontalOnly 双保险）；首页 `←`/`↑` 回上一章（autoPrevChapter 首章兜底）、末页 `→` 进下一章（autoNextChapter 末章兜底）；拖拽/滚轮非页边界位置 200ms 收敛吸附。
- 点击：paged 模式右半屏翻下一页、左半屏翻上一页（contentTapped 传 x）；scroll 模式点击唤出状态机与选择/拖动/Sheet 遮罩行为完全不变（tst_readerpage 真实点击用例回归）。
- TTS 跟随/搜索跳转在 paged 下翻到目标段所在页；选择工具条定位公式本就兼容 contentX（视口固定）。
- 文案：布局 Sheet 与设置页「竖向连续滚动 / 横向分页」，存储键 `reading/pageMode` 不变。

## 提交

- commit：简体中文 message（见文末）

---

# 任务3 审查修复（横向分页关键问题）

## 评审问题与修复

1. **页内容超页高被裁剪（P0）**：paged 段落按估算整体归页，实际 TextEdit 高度可能超过页高（估算偏乐观：全角字符宽按 0.8 字号计 → 每行字符数高估；图片段按宽等比缩放，竖图必然超高），而 contentY 恒 0 → 超页高内容被视口裁掉且不可达。**修复**：`pageComp` 内为 `pageCol` 提供稳定内部垂直 Flickable（`pageScroll`，VerticalOnly、clip、contentHeight 绑定 Column 隐式高度）——超页高内容页内可滚动到底，不丢失；页 Item 仍 = 视口高，外层 contentHeight 锁视口高、contentY 恒 0、分页/吸附/动画全部不受影响；contentHeight 不参与 rebuildPageModel 反馈回路，无 pageCount 振荡。句柄 `pageScroller`/`pageColumn` 供断言。
2. **换章/尺寸重算动画竞态（P0）**：`onChapterChanged`/`rebuildPageModel` 原来不停动画——在途 pageAnimX/followAnim/pageAnim 目标基于旧章旧几何，重算后继续运行把 contentX/contentY 拽回旧目标（旧动画写新章）。旧实现仅在换章时因 `contentX=0` 外部写入隐式停动画（resize 路径实测仍会继续运行，`test_resizeRebuildStopsPageAnimation` 红）。**修复**：新增 `stopPageAnimations()`，`onChapterChanged` 顶部与 `rebuildPageModel` 顶部显式停三动画，不依赖隐式行为。
3. **快速反向输入提前换章/丢页（P0）**：pagePrev/pageNext 按 `Math.round(contentX/页宽)` 反推当前页——动画刚起步（contentX≈0）时 ← 被误判为首页 → 提前 `requestPrevChapter`；两连 → 第二按按中间值四舍五入只到第 1 页丢一页。**修复**：新增 `currentPage` 逻辑当前页（goToPage 写动画目标；无动画时 onContentXChanged 按吸附页同步），pagePrev/pageNext 按逻辑页计算；goToPage 目标与当前位置一致但仍有在途动画时先停动画（反向取消场景）。
4. **null 段落安全**：`rebuildPageModel`/`computeSentenceStarts` 直接解引用段落——QML 引擎对 null 属性访问宽容（返回 undefined）故未崩，但依赖隐式语义；改为显式 `p ?? {}` / `(paras[i] ?? {}).sentences ?? []` 空段落安全值，段落全局索引对齐不破坏。
5. **w<48 负宽**：`flick.width - 48` 在 w<48 时产出负列宽（估算公式、页内列、scroll 列三处同公式）。**修复**：三处统一 `Math.max(1, w - 48)` 兜底。

## 改动文件

- `src/ui/qml/ReaderContent.qml`：currentPage 属性与同步（goToPage/onContentXChanged/onChapterChanged/onPageModeChanged/rebuildPageModel 钳制）；stopPageAnimations + 两处调用；pagePrev/pageNext 改逻辑页；pageComp 内嵌 pageScroll（句柄 pageScroller/pageColumn）；三处列宽公式 Math.max(1, w-48)；rebuildPageModel/computeSentenceStarts null 兜底。scroll 路径与既有接口（pageRepeater/pageAnimationX 等句柄、handleKey、contentTapped 信号）全部保留。
- `tests/qml/tst_e4_keys.qml`：PagedModeSmoke 新增 6 用例——`test_pageContentOverflowIsReachable`、`test_chapterChangeStopsPageAnimation`、`test_resizeRebuildStopsPageAnimation`、`test_fastReverseInputUsesLogicalTargetPage`、`test_nullParagraphSafeFallback`、`test_narrowWidthNoNegativeColumn`。

## TDD 证据

- 红：旧实现上 4 用例失败——overflow（页内无 pageScroller 句柄）、resize（尺寸重算后 pageAnimX 仍 running）、fastReverse（currentPage 不存在 + 动画中途 ← 提前翻章）、narrowWidth（pageColumn 负宽 -18）；chapterChange/null 两用例在旧实现上因「contentX=0 写入隐式停动画」「QML null 属性访问宽容」自愈通过，保留为回归守卫，修复使其行为显式化。
- 绿：实现后 tst_e4_keys **22/22**（含 6 新用例）。

## 验证

- 构建：`cmake --build build/Qt_6_11_1_for_macOS_Debug --target tst_qml Readdict -j8` 成功（0 error）。
- 必需套件：tst_e4_keys **22**、tst_readerpage **20**、tst_highlightsui **24**、tst_background **13**、tst_u4 **18** 全绿（0 failed）。
- 补充套件（段落渲染/滚动跟随触点）：tst_c4_scroll 8、tst_sheets 10、tst_textcolor 8、tst_ttsbar 9 全绿。
- 内嵌 Flickable 未破坏选择/TTS/点击：tst_readerpage 真实点击/拖动用例、tst_highlightsui 选择工具条用例、tst_c4_scroll TTS 跟随用例全部通过。

---

# 任务3 审查修复回归（ReaderRestore 恢复/搜索跳转测试）

## 症状与复现

全量 QML 258 pass/2 fail（提交 33ee3fc 修复后 260/0）：
- `tst_main.qml ReaderRestore::test_scrollRestore`：首断言「长文本书内容高度应远大于视口」（`contentView.contentHeight > 2000`）失败。
- `tst_main.qml ReaderRestore::test_searchJumpScrolls`：跳转后 `contentView.contentY=0`（期望 > 500）。

定向复现：`tst_qml -input <abs>/tst_main.qml` 单独跑即复现同款 2 失败——**排除跨文件 settings 污染**（全量跑与单文件跑同样失败；且诊断实测 `reading/pageMode=scroll`，`page.pageMode=scroll`，`contentView.pageMode=scroll`）。

## 根因（A/B 实证）

1. `contentWidth`/`contentHeight`/`flickableDirection` 三绑定在 e8f0c74 前后**逐字相同**（`contentHeight = pageMode==="paged" ? height : col.implicitHeight`）——scroll contentHeight 未被页面组件覆盖；pageComp/内嵌 Flickable 仅 paged 渲染，scroll 路径不参与。
2. 真根因是 **e8f0c74 第 5 项修复（w<48 防负宽 `Math.max(1, w-48)`）改变了 0 尺寸视口行为**：tst_main 的 `openReader` 用 Loader **无尺寸**创建 ReaderPage（无头环境 Page 锚定布局不可靠 → 0×0，同文件 test_scrollAutoNextSignal 注释早已记载该约定），ReaderContent 宽 0 → scroll 列宽公式：
   - 旧（e8f0c74^）：`Math.min(0*0.9, 0-48, cap) = -48` → 负宽怪癖使 TextEdit 隐式高巨大 → `contentHeight > 2000` **假通过**；
   - 新（e8f0c74）：`Math.min(0*0.9, max(1,-48), cap) = 0` → 列宽 0 → `col.implicitHeight` 塌陷为 0 → contentHeight=0 → 首断言失败；scrollToParagraph 的 `rep.itemAt(250)` 无布局 → contentY 恒 0。
3. A/B 锁定：单独把 scroll 列宽公式还原为 `flick.width - 48` 重建后两测试即 PASS（50 pass/1 fail，余 1 为既有 FulltextSmoke 环境性失败，见任务3报告「验证」节）。

结论：e8f0c74 的防负宽修复本身**正确**（负宽是真实缺陷，tst_e4_keys 的窄宽用例锁定），不回退；回归源是测试环境 0×0 视口，此前靠负宽怪癖意外假通过。

## 修复（最小、不放宽断言）

- `tests/qml/tst_main.qml` `openReader`：显式 `loader.width = 800; loader.height = 600` 真实视口（同文件 ContentSmoke/test_scrollAutoNextSignal 的既有约定——锚定布局在无头测试环境不可靠，显式设宽高），恢复/搜索跳转在真实内容高度下验证。
- `test_scrollRestore` 追加真实视口健全断言（`contentView.width > 100`）——防止未来再次静默 0×0。
- 产品代码（ReaderContent/ReaderPage）**未动**；横向分页不回退；无断言放宽。

## 验证

- 构建：`cmake --build build/Qt_6_11_1_for_macOS_Debug --target tst_qml -j10` 成功（0 error）。
- 定向：tst_main.qml **50 passed, 1 failed**（唯一失败 FulltextSmoke::test_shelfFulltextHits 为既有环境性失败——搜索词只在 zeta/alpha/mike 书，由其他文件导入，本文件单独跑无命中；任务3报告已记载，全量套件通过）、tst_e4_keys.qml **22 passed, 0 failed**、tst_readerpage.qml **20 passed, 0 failed**。
- 全量 QML：**260 passed, 0 failed, 4 skipped**（此前 258/2 fail，两失败均修复，无新增破坏）。

## 提交

- `33ee3fc 修复任务3审查回归：ReaderRestore 恢复/搜索跳转测试显式视口尺寸`
