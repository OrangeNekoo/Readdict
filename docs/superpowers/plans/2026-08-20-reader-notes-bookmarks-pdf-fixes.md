# 阅读器笔记、收藏与 PDF 交互 BUG 修复计划

> **面向 AI 代理的工作者：** 必需子技能：使用 `superpowers:subagent-driven-development` 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法跟踪进度。
>
> **用户决策：** PDF 笔记采用“选中文字笔记”方案；笔记跳转至少精确回到保存页，文本阅读继续精确到句子。

**目标：** 修复文本阅读器笔记跳转错位、分页收藏状态不随页面变化、PDF 选中文字笔记/收藏/目录入口不可用三个用户可见问题。

**架构：** 保留现有 `ReaderShell` 统一顶栏和 `Highlights` SQLite 数据流。文本阅读器增加“显式跳转事务”与页级收藏键；PDF 复用 Qt 6.11 `PdfMultiPageView`/`PdfScrollablePageView` 的原生 `selectedText`，用现有 `Highlights` 表保存“PDF 页 + 选中文本”，新增 PDF 笔记列表/编辑/跳页逻辑。所有跨格式操作继续由各自 adapter 实现，`ReaderShell` 只负责 capability 与输入分发。

**技术栈：** Qt 6.11.1、Qt Quick/QML、QtQuick.Pdf、Qt Quick Controls、现有 `HighlightManager`/`SettingsStore`；不新增依赖、不修改第三方库、不增加平台分支。

---

## 调查结论与根因

1. **文本笔记跳转：** `ReaderPage.jumpToHighlight()` 仅以章节标题查找索引，`loadChapter()` 在连续滚动模式重建前后章节窗口时保留旧 `contentY`。重建后的中线激活会把 `Books.currentChapter` 从目标章重新激活为旧章；随后 `jumpTimer` 调用 `followSentence(sentenceIndex)`，句索引在错误章节内解释，最终滚到错误段落。数据库已有 1 起的 `chapterIndex`，但跳转路径没有使用它，也没有在跳转后锁定目标句所在段落。
2. **文本分页收藏：** `ReaderPage.toggleBookmark()`/`syncCurrentBookmark()` 只使用 `Books.currentChapter`。分页模式同一章节内多个逻辑页共享同一个收藏键，所以任一页收藏后整个章节页都显示实心书签；持久化数据也没有页索引，无法判断具体页。
3. **PDF 笔记/收藏/目录：** `PdfReaderPage` adapter 将 `supportsNotes` 固定为 `false`，因此 PDF 顶栏笔记按钮没有动作；PDF 页面只实现了页书签和页码目录的内部函数，没有笔记数据与管理 UI。PDF 收藏恢复在 `restoreDone` 放行前可能错过首个页码变化，且收藏切换使用代理页码而非当前视图原始页码，存在状态滞后风险。菜单动作关闭 `menuOpen` 但保留 `sheetOpen`，对需要独立模态 Dialog 的 PDF 目录/笔记入口会留下底部 Sheet 输入层竞争。

**官方 API 依据：** Qt `PdfSelection` 支持 `document/from/to/hold/page/renderScale/text`；`PdfScrollablePageView` 和 `PdfMultiPageView` 均提供只读 `selectedText`、`selectAll()`、`goToPage()`。实现使用 Qt 官方现有选择/跳页能力，不重写 PDF 文本解析或坐标引擎。

---

## 文件边界

**修改：**
- `src/ui/qml/ReaderContent.qml`：显式滚动跳转事务、句子到段落映射、目标章锁定。
- `src/ui/qml/ReaderPage.qml`：使用 1 起 `chapterIndex` 跳转；文本分页收藏键与状态同步；保持旧章节收藏数据可读。
- `src/ui/qml/PdfReaderPage.qml`：PDF 原生选中文本读取、笔记编辑/管理/跳页、页书签恢复与状态同步、目录/笔记 Dialog 打开前关闭 Sheet。
- `tests/qml/tst_highlightsui.qml`：多章节笔记跳转回归。
- `tests/qml/tst_e4_keys.qml` 或 `tests/qml/tst_readerpage.qml`：文本分页收藏逐页状态回归。
- `tests/qml/tst_main.qml`：PDF 选中文字笔记、页书签逐页状态、真实顶栏/菜单目录点击回归。

**不修改：** `DatabaseManager` schema、同步协议、PDF 第三方组件、Qt 安装、跨平台构建配置。PDF 笔记沿用 `highlights` 行：`chapter = "pdf-page:<zero-based-page>"`、`chapterIndex = page + 1`、`text = selectedText`、`sentenceIndex = 0`；PDF 页面通过前缀过滤，不影响文本阅读器章节标题查找。

---

### 任务 1：修复文本显式笔记跳转事务

**文件：**
- 修改：`src/ui/qml/ReaderContent.qml`（窗口锚点状态、`focusScrollParagraph` 附近、`paragraphForIndex`/跳转函数）
- 修改：`src/ui/qml/ReaderPage.qml`（`jumpToHighlight`、目录/搜索共用显式跳转入口）
- 测试：`tests/qml/tst_highlightsui.qml`

- [ ] **步骤 1：编写失败的回归测试**

在 `test_notesListJump()` 后增加多章节场景：导入 `TestEnv.multiSource`，从第 2 章保存句索引 10 的高亮，先把阅读页切回第 1 章，再调用 `jumpToHighlight()`。断言：

```qml
page.jumpToHighlight(highlight)
tryVerify(function () { return Books.currentChapter === 1 }, 3000)
tryVerify(function () {
    var item = page.contentView.itemForChapterParagraph(1, 10)
    return item && Math.abs((item.y - page.contentView.contentY)
                            - page.contentView.height / 3) < page.contentView.height / 2
}, 3000)
```

测试必须断言目标章和目标段，不只断言 Dialog 关闭。

- [ ] **步骤 2：运行测试确认红灯**

运行：

```bash
QT_QPA_PLATFORM=offscreen ./build-nav/tests/tst_qml \
  -input tests/qml/tst_highlightsui.qml \
  HighlightInteraction::test_notesListJump
```

预期：失败，观测到 `Books.currentChapter` 回到旧章或目标段落不在视口附近；失败原因必须是显式跳转与连续窗口激活竞争，而非测试语法错误。

- [ ] **步骤 3：实现最小显式跳转修复**

1. 在 `ReaderContent` 增加显式导航准备状态；调用时清理 `pendingWindowAnchor`/`windowAnchorTimer`，并让接下来一次 `onChapterChanged`/`onScrollChaptersChanged` 不捕获旧视口锚点。
2. 增加“当前章节内句索引 → 段落索引”的函数，按每个段落 `sentences.length` 累加，不能把句索引直接当段落索引。
3. 增加 `focusScrollSentence(chapterIndex, sentenceIndex)`：把 `activeScrollChapter`/`scrollFocusChapter` 锁定到目标章，重建窗口并把目标段设为 `pendingScrollTarget`；`scrollTargetTimer` 等委托存在后将其滚到视口约 1/3 处。
4. `ReaderPage.jumpToHighlight()` 以高亮保存的 1 起 `chapterIndex` 为主（转换为 0 起目标章），只有旧数据无有效 `chapterIndex` 时才回退到标题查找；调用显式导航准备、`loadChapter`、`focusScrollSentence`，再执行闪烁提示。目录/全文搜索的显式跳转也走同一保护路径，避免修复只覆盖笔记入口。
5. 不改变自动续章/用户自然滚动的运行锚点语义；不要通过固定延时或强制写 `contentY = 0` 掩盖状态竞争。

- [ ] **步骤 4：运行回归测试确认绿灯**

运行同一测试命令，预期新增多章节断言与现有高亮 UI 全部通过。

- [ ] **步骤 5：提交任务变更**

提交信息：`fix(阅读器): 保证笔记显式跳转目标稳定`

---

### 任务 2：让文本分页收藏按逻辑页保存和显示

**文件：**
- 修改：`src/ui/qml/ReaderPage.qml`（书签属性、同步、切换、初始化、Connections）
- 修改：`src/ui/qml/ReaderContent.qml`（仅在需要时暴露已有 `currentPage/pageMode` 信号，不复制分页状态）
- 测试：`tests/qml/tst_e4_keys.qml` 或 `tests/qml/tst_readerpage.qml`

- [ ] **步骤 1：编写失败的回归测试**

在文本书的 paged 场景中：打开多页书，清空该书书签，确认第 0 页未收藏；切换到第 1 页并点击顶栏收藏；断言第 1 页点亮、第 0 页不点亮；返回第 0 页后图标熄灭，再回第 1 页后点亮。断言 Settings 保存值含页级键。

```qml
page.toggleBookmark()
verify(page.currentBookmarked)
page.contentView.goToPage(0)
tryVerify(function () { return !page.currentBookmarked }, 3000)
page.contentView.goToPage(1)
tryVerify(function () { return page.currentBookmarked }, 3000)
```

- [ ] **步骤 2：运行测试确认红灯**

运行目标 QML 测试函数，预期当前实现因只按章节索引保存而失败：第 0 页仍显示收藏，或保存数组没有页级区分。

- [ ] **步骤 3：实现最小页级收藏修复**

1. 定义 `bookmarkKey()`：scroll 模式返回 `chapter:<chapterIndex>` 的兼容章节键，paged 模式返回 `page:<chapterIndex>:<currentPage>`。
2. `syncCurrentBookmark()` 按当前模式和当前逻辑页精确匹配，不再只 `indexOf(Books.currentChapter)`。
3. `toggleBookmark()` 只增删当前模式的精确键；scroll 模式继续接受并保留旧整数章节数据，paged 模式写字符串页键，避免破坏已有用户收藏。
4. 在 `Books.currentChapterChanged`、`content.currentPageChanged`、`pageModeChanged` 与首次章节加载完成后统一调用同步函数；章节切换、分页动画完成和方向切换都必须刷新按钮状态。
5. 旧 Settings 数组整数按章节键解释；非法/重复键去重，不修改其它设置。

- [ ] **步骤 4：运行文本阅读器回归集**

运行收藏新增测试以及已有 `tst_readerpage.qml`、`tst_e4_keys.qml` 中相关函数，预期旧章节收藏断言仍通过、分页收藏按页切换正确。

- [ ] **步骤 5：提交任务变更**

提交信息：`fix(阅读器): 让分页收藏绑定当前逻辑页`

---

### 任务 3：恢复 PDF 选中文字笔记、页收藏和目录交互

**文件：**
- 修改：`src/ui/qml/PdfReaderPage.qml`
- 修改：`tests/qml/tst_main.qml`

- [ ] **步骤 1：编写失败的回归测试**

加入确定性 `TestEnv.textPdfSource` 场景：

1. `activePdfView.selectAll()` 后读取 `selectedText`，点击真实顶栏笔记按钮；断言选中文字笔记编辑 Dialog 打开，确认后 `Highlights.highlightsForBook(book.id)` 产生 `chapter` 前缀为 `pdf-page:` 的行并保存页码/文本。
2. 打开 PDF 笔记管理 Dialog，点击该行跳转；断言 `pdfView.currentPage` 为保存页。
3. 预置第 0 页书签，Ready 恢复后图标点亮；真实点击下一页后图标熄灭，返回第 0 页后重新点亮；点击顶栏按钮只增删当前页。
4. 真实打开顶栏更多菜单并点击“目录”行，而不是只直接调用 adapter；断言目录 Dialog 可见，点击第 2 页条目后 Dialog 关闭且页码变为 1。

初始测试在当前实现上应看到：`supportsNotes === false` 导致笔记按钮无动作/没有编辑 Dialog；PDF 笔记列表不存在；目录实际菜单路径无法保证释放 Sheet 后仍可交互。

- [ ] **步骤 2：运行测试确认红灯**

运行：

```bash
QT_QPA_PLATFORM=offscreen ./build-nav/tests/tst_qml \
  -input tests/qml/tst_main.qml PdfReaderSmoke::test_pdfNotesBookmarksAndContents
```

预期失败必须对应上述缺失行为。

- [ ] **步骤 3：实现 PDF 选中文字笔记**

1. 通过活动 `PdfMultiPageView`/`PdfScrollablePageView` 的 `selectedText` 读取 Qt 原生选择文本；在页码变化或方向切换时清理过期选择状态。选中文本为空时，笔记入口打开笔记列表；有选中文本时打开编辑 Dialog。
2. 新增 PDF 笔记编辑 Dialog：展示当前页码和选中文本，接受时新增/更新 `Highlights` 行；取消不写库。用 `pdf-page:<zero-based-page>` 作为稳定章节标识，`chapterIndex = page + 1`，使用 `text` 匹配同页同选区的已有行以复用编辑。
3. 新增 PDF 笔记列表 Dialog：过滤当前书 `chapter` 以 `pdf-page:` 开头的行，显示页码/选中文本/笔记，提供编辑、删除、跳转；跳转解析页索引后调用 `goToPdfPage()`，关闭模态层并恢复页面焦点。
4. adapter 将 `supportsNotes` 改为 `true`，`openNotes()` 关闭 `readerShell.sheetOpen` 后按“有选区→编辑、无选区→列表”分发。

- [ ] **步骤 4：实现 PDF 页书签状态修复**

1. `togglePdfBookmark()` 与 `syncPdfBookmarkState()` 直接读取 `activePdfView.currentPage`，不依赖可能尚未重求值的 `pdfViewProxy.currentPage`。
2. 在 Ready 恢复页完成后再次同步书签，避免恢复期首个 `currentPageChanged` 被 `restoreDone` 门控后遗失图标状态。
3. 页码变化只更新活动视图的进度、文本和收藏状态；隐藏视图的页码变化不得污染当前按钮。

- [ ] **步骤 5：实现 PDF 目录可点击路径**

`openContents()` 在打开 `tocDialog` 前关闭 `readerShell.menuOpen` 与 `sheetOpen`；`goToPdfPage()` 先关闭目录、停止 PDF TTS、调用活动视图 `goToPage()`。保持原有页标签和目录 `pageLabel()` 文案。

- [ ] **步骤 6：运行 PDF 回归测试确认绿灯**

运行新增函数及已有 PDF 测试：

```bash
QT_QPA_PLATFORM=offscreen ./build-nav/tests/tst_qml \
  -input tests/qml/tst_main.qml PdfReaderSmoke
```

确认新增选区/笔记/书签/目录测试与已有加载、翻页、朗读、关闭竞态测试全部通过；不设置 `READDICT_REAL_PDF` 时不依赖外部文件。

- [ ] **步骤 7：提交任务变更**

提交信息：`fix(PDF): 恢复选区笔记收藏与目录交互`

---

## 全局验证与交付检查

- [ ] 运行 `HighlightInteraction`、文本分页收藏、`PdfReaderSmoke` 针对性 QML 测试。
- [ ] 运行 `ctest --test-dir build-nav --output-on-failure`，确认 C++ 数据库/解析器回归未受 QML 数据复用影响。
- [ ] 使用 `QT_QPA_PLATFORM=offscreen` 完成自动化 smoke；不安装任何软件或库。
- [ ] 检查 QML 警告、未定义对象、Dialog 关闭后焦点恢复与动画竞态；不把 PDF 选区映射扩展成 OCR/全文索引。
- [ ] 复核 Windows 10/11 x64、Linux x64、macOS ARM 仅依赖 Qt 官方跨平台 API，路径和剪贴板不写平台分支。
- [ ] 最终报告列出修改文件、根因、测试命令与真实输出；没有通过的测试不得宣称完成。
