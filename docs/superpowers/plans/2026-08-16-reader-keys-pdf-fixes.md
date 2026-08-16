# 阅读键位分流与 PDF 阅读交互修复实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 `superpowers:subagent-driven-development`。所有任务以 TDD 方式完成；实现子智能体使用 `impl-flash`（`opencode-go/deepseek-v4-flash`）。

**目标：** 竖向文本阅读仅由 W/S 在键盘翻动路径中前后滚动，横向文本阅读仅由 A/D 前后翻页；修复 PDF 页面默认缩放、翻页、菜单和失败反馈，使本地 PDF 可阅读和导航。

**架构：** 保持文本阅读的 `ReaderContent.handleKey()` 为唯一键位分流点。扩展 `PdfReaderPage.qml`，围绕 Qt 6.11 `PdfScrollablePageView` 的公共 `goToPage()`、`currentPage`、`scaleToWidth()`、`scaleToPage()` 接口增加显式控制层；不复制 Qt PDF 组件、不引入第三方库。

**技术栈：** Qt 6.11.1、Qt Quick、Qt Quick Controls、Qt Quick PDF、现有 QML QtTest。

---

## 根因与约束

- `ReaderContent.handleKey()` 的 scroll 分支当前将 A/D 映射为显式上一/下一章；paged 分支当前将 W/S/A/D 全部映射为翻页。该映射与用户要求相冲突。
- `PdfReaderPage.qml` 仅有返回按钮和双击缩放；没有页码、前后页控件、菜单入口、键盘处理或 `PdfDocument.Error` 可见反馈。`PdfScrollablePageView` 默认 `renderScale=1`，未在文档就绪后调用 `scaleToWidth()`，因此窄 PDF 页只占左侧并留下大块空白。
- 继续使用本地文件 URL；不使用 WebEngine、不修改解析器或数据库 schema、不新增依赖；Windows 10/11 x64、Linux x64、macOS ARM 只使用 Qt 公共 API。

## 文件职责

- 修改 `src/ui/qml/ReaderContent.qml`：按阅读模式收紧 W/S/A/D 映射。
- 修改 `src/ui/qml/PdfReaderPage.qml`：PDF 初始宽度适配、前后页操作、键盘路由、页码状态、更多菜单、加载错误反馈。
- 修改 `tests/qml/tst_e4_keys.qml`：锁定文本 scroll/paged 的 W/S/A/D 允许与拒绝语义。
- 修改 `tests/qml/tst_main.qml`：锁定 PDF 控制层、菜单、页码状态和真实 PDF（`READDICT_REAL_PDF`）加载/缩放/翻页行为。

---

### 任务 1：收紧文本阅读模式的 W/S/A/D 键位

**文件：**
- 修改：`src/ui/qml/ReaderContent.qml:829-862`
- 修改：`tests/qml/tst_e4_keys.qml`

- [ ] **步骤 1：写失败测试**

在现有 `ArrowKeyPagingSmoke` 与 `PagedModeSmoke` 中增加两个独立断言组：

```qml
// scroll：W/S 改变 contentY；A/D 返回 false，且不改变 Books.currentChapter。
verify(cv.handleKey(Qt.Key_W, Qt.NoModifier))
verify(!cv.handleKey(Qt.Key_A, Qt.NoModifier))
verify(!cv.handleKey(Qt.Key_D, Qt.NoModifier))

// paged：A/D 改变 currentPage；W/S 返回 false，且不改变 currentPage。
verify(cv.handleKey(Qt.Key_D, Qt.NoModifier))
verify(!cv.handleKey(Qt.Key_W, Qt.NoModifier))
verify(!cv.handleKey(Qt.Key_S, Qt.NoModifier))
```

方向键、PageUp/PageDown 的既有语义不在本任务改变；测试应继续断言它们的现有路径。

- [ ] **步骤 2：运行并确认红灯**

```bash
cmake --build build-nav --target tst_qml -j2
./build-nav/tests/tst_qml -platform offscreen \
  'ArrowKeyPagingSmoke::test_modeSpecificWasdKeys' \
  'PagedModeSmoke::test_modeSpecificWasdKeys'
```

预期：旧实现会接受 scroll 的 A/D 和 paged 的 W/S，新增拒绝断言失败。

- [ ] **步骤 3：最小实现**

将 `handleKey()` 收敛为：

```qml
if (flick.pageMode === "paged") {
    switch (key) {
    case Qt.Key_Left: case Qt.Key_PageUp: case Qt.Key_A:
        flick.pagePrev(isAutoRepeat); return true
    case Qt.Key_Right: case Qt.Key_PageDown: case Qt.Key_D:
        flick.pageNext(isAutoRepeat); return true
    }
    return false
}
switch (key) {
case Qt.Key_Up: case Qt.Key_PageUp: case Qt.Key_W:
    flick.scrollPage(-1, isAutoRepeat); return true
case Qt.Key_Down: case Qt.Key_PageDown: case Qt.Key_S:
    flick.scrollPage(1, isAutoRepeat); return true
}
return false
```

不得让 scroll 的 A/D 触发章节跳转；不得让 paged 的 W/S 翻页。

- [ ] **步骤 4：运行绿灯与相关回归**

```bash
cmake --build build-nav --target tst_qml -j2
./build-nav/tests/tst_qml -platform offscreen \
  'ArrowKeyPagingSmoke::test_modeSpecificWasdKeys' \
  'PagedModeSmoke::test_modeSpecificWasdKeys' \
  'ArrowKeyPagingSmoke::test_activeFocusAndProductionKeys'
```

- [ ] **步骤 5：提交**

```bash
git add src/ui/qml/ReaderContent.qml tests/qml/tst_e4_keys.qml
git commit -m "fix(阅读器): 按阅读模式分流WASD键位"
```

---

### 任务 2：实现可用的 PDF 阅读控制层

**文件：**
- 修改：`src/ui/qml/PdfReaderPage.qml`
- 修改：`tests/qml/tst_main.qml`

- [ ] **步骤 1：写失败测试**

扩展 `PdfReaderSmoke`，要求 PdfReaderPage 暴露稳定的测试句柄：`previousPageButton`、`nextPageButton`、`menuButton`、`pageLabel`、`pdfMenu`、`retryButton`。测试应覆盖：

```qml
verify(page.menuButton !== undefined)
verify(page.pdfMenu !== undefined)
verify(page.pageLabel.text.length > 0)
page.menuButton.clicked()
tryVerify(function () { return page.pdfMenu.visible }, 3000)
```

若 `READDICT_REAL_PDF` 已设置：等待 `PdfDocument.Ready` 后断言 `renderScale` 经 `scaleToWidth()` 改变、页码显示 `第 1 / N 页`、`nextPageButton` 调用后 `currentPage` 前进、`previousPageButton` 回退。真实 PDF 不存在时，只运行无需文件的控制层和错误状态测试，不伪造 Qt PDF 文档。

- [ ] **步骤 2：运行并确认红灯**

```bash
cmake --build build-nav --target tst_qml -j2
./build-nav/tests/tst_qml -platform offscreen \
  'PdfReaderSmoke::test_pdfReaderControlsExposeNavigationAndMenu'
```

预期：旧 PdfReaderPage 缺少菜单、页码和分页句柄，测试失败。

- [ ] **步骤 3：最小实现**

1. 在 `PdfDocument.Ready` 分支先调用 `pdfView.scaleToWidth(pdfView.width, pdfView.height)`，再恢复保存页；保留 `fitPage` 双击切换。
2. 新增 `previousPage()` / `nextPage()`：仅在 `Ready`、页数有效且边界内调用公共 `goToPage(currentPage ± 1)`。
3. 顶栏加入上一页、页码、下一页、更多按钮；按钮在未 Ready 或边界时禁用。
4. 添加 `menuOpen` 和复用 `KdDropdownMenu` 的缩放菜单：宽度适配、整页适配、重置缩放；菜单不覆盖返回键。
5. 添加 Page 的 `Keys.priority: Keys.BeforeItem`：Left/PageUp/A 调 `previousPage()`，Right/PageDown/D 调 `nextPage()`；只在处理后 `event.accepted = true`。
6. `PdfDocument.Error` 时显示错误信息、原始 `pdfDoc.error` 与重试按钮；重试通过重新设置同一 `source` 触发加载。Loading 期间显示可见状态，避免白屏无反馈。
7. 保留现有关闭渲染竞态防护和进度节流。

- [ ] **步骤 4：运行 PDF 控制层与真实 PDF 回归**

```bash
cmake --build build-nav --target tst_qml Readdict -j2
./build-nav/tests/tst_qml -platform offscreen 'PdfReaderSmoke::test_pdfReaderControlsExposeNavigationAndMenu'
ctest --test-dir build-nav -R tst_qml --output-on-failure
```

若环境提供 `READDICT_REAL_PDF`，额外执行现有 `test_pdfLoadsRealSource`、`test_pdfRestoresPage`、`test_pdfCloseWaitsRender`；若未提供，报告这些用例是环境跳过，不能声称真实文件加载已验证。

- [ ] **步骤 5：提交**

```bash
git add src/ui/qml/PdfReaderPage.qml tests/qml/tst_main.qml
git commit -m "fix(PDF): 增加阅读导航和菜单控制"
```

---

### 任务 3：最终构建与平台边界检查

**文件：** 仅前述修改文件。

- [ ] **步骤 1：重建应用与 QML 测试**

```bash
cmake --build build-nav --target Readdict tst_qml -j2
```

- [ ] **步骤 2：运行最终测试**

```bash
ctest --test-dir build-nav -R 'tst_qml|tst_settings|tst_bookmanager' --output-on-failure
```

- [ ] **步骤 3：检查跨平台边界**

确认 `ReaderContent.qml` 和 `PdfReaderPage.qml` 只使用 Qt Quick/Qt Quick PDF 公共类型，diff 中不存在 `WIN32`、`Q_OS_*`、macOS、Windows 或 Linux 专有分支；不新增库。

- [ ] **步骤 4：提交必要回归修复**

如最终测试发现只由本计划引入的回归，最小修复后以中文 `fix(阅读器): ...` 提交；否则保持前两项提交。
