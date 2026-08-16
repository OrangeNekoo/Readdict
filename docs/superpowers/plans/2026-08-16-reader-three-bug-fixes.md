# 阅读器三项缺陷修复实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 `superpowers:subagent-driven-development`；步骤使用复选框（`- [ ]`）跟踪进度。实现子智能体必须使用项目配置的 `impl-flash`，模型为 `opencode-go/deepseek-v4-flash`。

**目标：** 修复竖向跨章回跳、横向箭头闲置显隐与左右方向键、全书视觉进度计算错误。

**架构：** 保留 `ReaderPage.qml` 与 `ReaderContent.qml` 边界。运行中的竖向窗口使用稳定段落锚点事务；横向箭头使用 Qt Quick 鼠标悬停处理与独立闲置计时器，键盘统一进入 `pagePrev/pageNext`；全书页数复用现有实际布局测量视图，但用测量代次和稳定条件拒绝旧页模型。

**技术栈：** Qt 6.11.1、Qt Quick、Qt Quick Controls 2、QML QtTest、现有 `ReaderTextHelper`。

---

## 文件职责

- 修改 `src/ui/qml/ReaderContent.qml`：统一竖向窗口锚点事务；横向箭头闲置显隐；左右方向键显式处理；暴露测试所需状态。
- 修改 `src/ui/qml/ReaderPage.qml`：跨章窗口调用保持锚点；全书测量代次、稳定采纳、全书页码更新；页面级左右键兜底。
- 修改 `tests/qml/tst_e4_keys.qml`：补充跨章上下滚动、箭头闲置显隐、生产左右方向键回归。
- 修改 `tests/qml/tst_readerpage.qml`：补充全书页数总和、前序章节页码偏移、测量完成前不冒充本章页码的回归。
- 新建 `docs/superpowers/specs/2026-08-16-reader-three-bug-fixes-design.md`：记录批准的设计和验收。

---

### 任务 1：竖向窗口锚点事务

**文件：**
- 修改：`src/ui/qml/ReaderContent.qml` 的 `captureWindowAnchor`、`rebuildScrollModel`、`showScrollChapter`、`onChapterChanged`、`onScrollChaptersChanged`、窗口恢复 Timer。
- 修改：`src/ui/qml/ReaderPage.qml` 的 `loadChapter`、`activateChapter`、`makeScrollChapters` 调用关系。
- 测试：`tests/qml/tst_e4_keys.qml`。

- [ ] **步骤 1：编写失败回归测试**

在现有 scroll 测试组新增多章稳定性用例：打开 `multibook`，加载第 0 章，记录底部前一屏的稳定段落键和相对偏移；滚到真实底部触发下一章加载；等待窗口稳定后断言 `contentY > 0`、上一章末段仍在窗口或视口上方邻近位置、向上滚动能再次看到上一章。重复从第 1 章向上滚动，断言不回到第 1 章首屏。

- [ ] **步骤 2：运行测试确认当前缺陷未被锁定**

运行：`cmake --build build-nav --target tst_qml -j2 && ctest --test-dir build-nav -R tst_qml --output-on-failure`
预期：现有测试可能通过，但新增用例应在旧窗口重建路径中暴露 `contentY` 回到 0 或稳定锚点丢失。

- [ ] **步骤 3：实现最小锚点事务**

在 `ReaderContent.qml` 中：

- 重建前保留运行锚点，不在 `onScrollChaptersChanged` 和 `showScrollChapter` 中无条件清空它。
- `rebuildScrollModel` 先按运行锚点查找焦点，找不到才按活动章节计算 `scrollWindowStart`。
- 模型切换后通过单次 Timer 查找 `{chapterIndex, paragraphIndex}`，按 `item.y + offsetY` 恢复并钳制 `contentY`。
- 将页面初次 `restoreAnchor/restoreScrollY` 的恢复标志与运行窗口锚点分开；窗口更新不得触发初次恢复逻辑。
- `ReaderPage.loadChapter/activateChapter` 保持相邻章节数据并在更新前后走同一锚点事务，不额外写入 `contentY=0`。

- [ ] **步骤 4：运行专项回归测试**

运行：`cmake --build build-nav --target tst_qml -j2 && ctest --test-dir build-nav -R 'tst_qml' --output-on-failure`
预期：跨章向下、向上测试通过，既有自动续章、滚动恢复和动画停止测试不回归。

- [ ] **步骤 5：Commit**

```bash
git add src/ui/qml/ReaderContent.qml src/ui/qml/ReaderPage.qml tests/qml/tst_e4_keys.qml
git commit -m "fix(阅读器): 保持竖向跨章滚动锚点"
```

---

### 任务 2：横向箭头显隐与左右方向键

**文件：**
- 修改：`src/ui/qml/ReaderContent.qml` 的箭头提示、Keys 处理和鼠标悬停逻辑。
- 修改：`src/ui/qml/ReaderPage.qml` 的页面级 Keys 兜底。
- 测试：`tests/qml/tst_e4_keys.qml`。

- [ ] **步骤 1：编写失败回归测试**

扩展 `test_pagedEdgeClickPagesAndHints`：进入 paged 后断言箭头初始可见；把闲置延迟注入为短值，等待 Timer 到期后断言两箭头隐藏；将鼠标移动到左、右边缘热区后分别断言对应动作使箭头重新可见；边缘点击仍改变 `currentPage`。

扩展生产焦点测试：使用 `keyClick(Qt.Key_Right)` 和 `keyClick(Qt.Key_Left)`，不直接调用 `handleKey`，断言 paged 模式 `currentPage` 分别推进/回退；同时保留 W/A/D 断言。

- [ ] **步骤 2：运行测试确认当前缺陷未被锁定**

运行：`cmake --build build-nav --target tst_qml -j2 && ctest --test-dir build-nav -R tst_qml --output-on-failure`
预期：箭头闲置隐藏断言在当前永久可见实现中失败；左右键回归在不同焦点路径至少有一条失败或无法证明生产路径。

- [ ] **步骤 3：实现显隐与显式按键处理**

在 `ReaderContent.qml` 中增加 paged 专用 `edgeHintsVisible`、闲置 Timer、边缘热区检测和 Qt Quick HoverHandler/不拦截鼠标移动处理。分页模式进入时显示并启动 Timer；边缘移动/点击时显示并重启 Timer；Timer 到期隐藏。`prevEdgeHint/nextEdgeHint.visible` 同时受分页模式和该状态控制。

在 `ReaderContent.qml` 与 `ReaderPage.qml` 的高优先级 Keys 路径增加显式 Left/Right 处理，均调用现有 `handleKey`，只在处理成功时接受事件；不改修饰键和 A/D 语义。

- [ ] **步骤 4：运行专项回归测试**

运行：`cmake --build build-nav --target tst_qml -j2 && ctest --test-dir build-nav -R tst_qml --output-on-failure`
预期：箭头按闲置/边缘移动显隐；鼠标边缘点击、文本选择、拖动和生产左右方向键均通过。

- [ ] **步骤 5：Commit**

```bash
git add src/ui/qml/ReaderContent.qml src/ui/qml/ReaderPage.qml tests/qml/tst_e4_keys.qml
git commit -m "fix(阅读器): 优化横向箭头和方向键"
```

---

### 任务 3：修复全书视觉进度测量

**文件：**
- 修改：`src/ui/qml/ReaderPage.qml` 的 `measureBookPages`、`measureBookStep`、`updateBookPageNumber`、进度派生属性。
- 测试：`tests/qml/tst_readerpage.qml`。

- [ ] **步骤 1：编写失败回归测试**

新增多章全书进度用例：切到 `progressScope=book`，等待 `bookPageTotal > 0` 且 `measuredChapterPages.length === Books.chapterCount(book.id)`；断言 `bookPageTotal` 等于章节页数数组之和；切到后续章节后断言 `bookPageNumber` 大于该章本章页码，且 `progressText` 的页数使用全书前缀。切换字号/窗口宽度后等待重新测量，断言旧总页数不继续使用。

- [ ] **步骤 2：运行测试确认当前缺陷未被锁定**

运行：`cmake --build build-nav --target tst_qml -j2 && ctest --test-dir build-nav -R tst_qml --output-on-failure`
预期：当前异步复用旧 `pageCount/pageModel` 或测量未完成回退路径会被新增断言暴露。

- [ ] **步骤 3：实现带代次的稳定测量**

在 ReaderPage 中：

- 每次开始全书测量时递增代次，清空页数组、总页数和当前全书页码。
- 对每个章节设置隐藏视图的目标章节 token，清空旧 `pageModel/pageCount`，等待目标章节完成布局并确认 `pageRepeater.count === pageCount` 连续稳定后采纳页数。
- 失败章节按 1 页占位并继续；旧代次 Timer 触发时直接丢弃。
- 只有所有章节完成才设置 `bookPageTotal`；全书范围派生值在此之前使用明确安全值，不调用当前章页数冒充全书。
- 排版、窗口或页面模式变化时使测量失效并重新开始；`updateBookPageNumber` 按前序章节累计值加当前章视觉页号。

- [ ] **步骤 4：运行专项回归测试**

运行：`cmake --build build-nav --target tst_qml -j2 && ctest --test-dir build-nav -R 'tst_qml' --output-on-failure`
预期：全书总页数是所有章节实际页数之和，后续章节页码带前序章节偏移，排版变化重新测量。

- [ ] **步骤 5：Commit**

```bash
git add src/ui/qml/ReaderPage.qml tests/qml/tst_readerpage.qml
git commit -m "fix(阅读器): 修正全书视觉进度"
```

---

### 任务 4：最终构建、回归与跨平台静态检查

**文件：**
- 修改：必要时仅修复前述任务引入的回归；不新增无关重构。

- [ ] **步骤 1：构建应用和 QML 测试**

运行：`cmake --build build-nav --target tst_qml Readdict -j2`
预期：Qt 6.11.1 macOS ARM 构建退出码为 0；不新增库或平台专有源文件。

- [ ] **步骤 2：运行完整相关测试**

运行：`ctest --test-dir build-nav -R 'tst_qml|tst_bookmanager|tst_settings' --output-on-failure`
预期：所有匹配测试通过且失败数为 0。

- [ ] **步骤 3：检查跨平台 API 边界**

检查 `ReaderPage.qml`、`ReaderContent.qml` 和测试 diff：键盘只使用 Qt `Keys`/`Qt.Key_*`，鼠标只使用 Qt Quick 类型；不出现 macOS、Windows、Linux 专有分支，不添加依赖安装或环境修改。

- [ ] **步骤 4：Commit**

若最终审查没有需要修复的项，保留前述任务提交；若有必要的回归修复，使用一个中文 `fix(阅读器): ...` 提交并记录专项测试命令与输出。
