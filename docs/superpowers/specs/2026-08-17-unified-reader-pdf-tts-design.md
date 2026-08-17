# 统一阅读器壳层与 PDF 文本朗读设计

**日期：** 2026-08-17  
**状态：** 已获设计批准，待用户审查书面规格  
**范围：** 统一 EPUB、MOBI、AZW3、FB2、TXT、MD 与 PDF 的阅读页壳层和基础操作；为含文本层 PDF 接入现有 TTS；图片型 PDF 明确禁用朗读。

## 背景与问题

`ReaderPage.qml` 承载所有文本格式，具备 Kindle 风格的顶部工具栏、中央点击唤出/隐藏、更多菜单、底部控制面板、进度、焦点恢复、朗读条和文本阅读能力。`PdfReaderPage.qml` 独立实现，近期补上缩放、页码和翻页，但顶栏、菜单、点击状态机与 EPUB 不同，导致用户在格式之间切换时需要重新学习操作。

PDF 朗读目前没有文本输入：页面虽然通过 `PdfScrollablePageView` 渲染，但从未调用 `QPdfDocument.getAllText()` 给 `Tts.setSentences()`。因此点击朗读没有可靠的语义。Qt 6.11.1 的 `QPdfDocument.getAllText(int page)` 是可从 QML 调用的公共 API，能返回带边界的 `QPdfSelection`；图片型 PDF 的选择文本为空，不能朗读。

## 目标

1. 所有受支持格式使用相同的阅读页框架、控件位置、菜单入口、显隐逻辑、朗读条和键盘焦点行为。
2. 保留文本阅读器现有章节、连续滚动、划线、笔记、全文搜索和句级 TTS 行为。
3. PDF 保留原生逐页渲染、缩放、页码、渲染关闭竞态防护和页级进度。
4. 有文本层的 PDF 能从当前页开始朗读，并在页尾自动转到下一可朗读页。
5. 图片型或无文本的当前 PDF 页不启动 TTS；菜单中的朗读项禁用，并显示“当前 PDF 无可朗读文本”。

## 非目标

- 不新增 OCR、网络服务、模型、语言包或第三方 PDF/TTS 库。
- 不将 PDF 重排为 EPUB 文本，不伪造章节、划线、笔记或全文索引。
- 不修改书籍数据库 schema、导入格式、同步协议或现有 TTS 引擎。
- 不改变既有文本格式的按键、滚动和分页语义。

## 架构

### ReaderShell：唯一的阅读交互壳层

新增 `ReaderShell.qml`，仅负责格式无关的展示与输入状态机：

- `KdTopToolbar`、返回、书签、笔记、搜索与更多入口。
- 右上菜单遮罩、中央点击唤出、5 秒自动隐藏、底部 `KdBottomSheet`。
- `TtsBar`、TTS 状态/错误绑定、阅读进度标签、StackView 激活后的焦点恢复。
- 向内容适配器转发上一项、下一项、朗读、目录、搜索和书签操作。

Shell 不引用 `Books.currentChapter`、`ReaderContent`、`PdfScrollablePageView` 或 PDF 具体类型；内容和格式状态留在适配器。

### 文本与 PDF 适配器

`ReaderPage.qml` 继续拥有文本章节装载、`ReaderContent`、高亮/笔记/搜索和章节级 TTS。它通过适配器接口为 Shell 提供动作和状态。

`PdfReaderPage.qml` 继续拥有 `PdfDocument`、`PdfScrollablePageView`、`renderSettled()`、关闭轮询、页级进度和缩放。它通过适配器接口为 Shell 提供页级动作和状态。

共享壳层与适配器使用以下 QML 契约：

```qml
property string progressText
property bool canGoPrevious
property bool canGoNext
property bool canReadAloud
property string readAloudUnavailableReason
property bool supportsContents
property bool supportsSearch
property bool supportsNotes
property bool supportsBookmarks

function previous()
function next()
function startReadAloud()
function stopReadAloud()
function openContents()
function openSearch()
function openNotes()
function toggleBookmark()
```

Shell 按 capability 控制菜单项可见性或可用性；它不调用不支持的操作。PDF 的上一项/下一项显示为“上一页/下一页”；文本格式保持“上一章/下一章”。

## 统一交互规则

| 操作 | 文本格式 | PDF |
| --- | --- | --- |
| 中央点击 | 唤出统一菜单/底部面板 | 同文本格式 |
| 返回、菜单、焦点恢复 | 共享 Shell | 共享 Shell |
| W/S、A/D、方向键 | 保持现有模式语义 | 页级 A/D、方向键与 PageUp/PageDown |
| 上一项/下一项 | 上一章/下一章 | 上一页/下一页 |
| 进度 | 章节或全书 | 页码或全书，沿用统一显示设置 |
| 主题 | 正文背景、字体、布局 | Shell 和页外背景；不变更 PDF 页面内容 |
| 目录 | 章节目录 | 页码列表，使用 `QPdfDocument.pageLabel()` 显示自定义页码 |
| 书签 | 当前章节 | 当前页码 |
| 朗读 | 当前视口句子 | 当前页可提取文本 |
| 搜索、划线、笔记 | 保持现有 | 不开放，直到有真实 PDF 文本映射与定位支持 |

## PDF 文本朗读

### 文本发现

在 `PdfDocument.Ready` 及每次页码变化后，适配器调用：

```qml
const selection = pdfDoc.getAllText(pdfView.currentPage)
const text = selection ? String(selection.text || "").trim() : ""
```

仅当文本非空时，使用现有 `SentenceSplitter` 切句并设置 `canReadAloud = true`。提取失败、文本为空、或切句结果为空时，设为 false，原因固定为“当前 PDF 无可朗读文本”。

### 开始与续读

1. 用户点朗读时，若 `canReadAloud` 为 false，菜单项已禁用；不调用 TTS，朗读条保持隐藏。
2. 含文本时，将当前页句子传入 `Tts.setSentences()`，索引置为 0 并调用 `Tts.play()`。
3. `Tts` 读完当前页时，适配器进入下一页，提取该页文本。
4. 连续的无文本页被跳过；若后续没有可读文本，调用 `Tts.stop()` 并通过既有错误/状态通道显示“后续 PDF 页面无可朗读文本”。
5. 用户手动翻页时停止当前会话；新页文本可用性立即重新计算，避免旧页句子在新页继续播放。

PDF 不做句子高亮或自动滚动跟随，因为 PDF 文本坐标映射、缩放和跨页渲染尚未实现；朗读条仍完整提供播放、暂停、停止、前后句、语速和音色。

## 错误与边界

- PDF 加载失败保留现有 Loading/Error/Retry 覆盖层。
- 文本提取只能在 `PdfDocument.Ready` 后执行；其它状态一律视为不可朗读。
- 加密、损坏、仅图片或选择文本为空的 PDF 不能误显示可朗读。
- 用户从 PDF 返回时，继续保持 `renderSettled()` 轮询，绝不提前销毁在途渲染文档。
- Shell 菜单本身必须避免和 Loading/Error 覆盖层抢输入；不可用项不进入操作路径。

## 测试策略

### 共享壳层

- 文本与 PDF 页面均使用同一顶栏、菜单模型、中央点击状态机和 TtsBar。
- StackView 首次 push 与 pop 返回后都拥有 activeFocus；生产 `keyClick` 覆盖 A/D 和方向键。

### 文本回归

- 保持现有 scroll/paged WASD、方向键、跨章连续滚动、章节朗读、笔记、搜索测试。

### PDF 回归

- 真实含文本 PDF：Ready、宽度适配、页码、书签/目录、键盘、菜单、从当前页朗读和页尾续读。
- 真实图片 PDF：朗读菜单项不可用、不可用说明可见、`Tts.state === 0`、`TtsBar.visible === false`。
- 翻页/返回：手动翻页停止旧页朗读；渲染尚未稳定时关闭页仍保持存活。
- 使用仓库内 PDF fixture 或测试运行时显式传入的路径；不新增外部测试依赖。

## 跨平台与依赖

实现仅使用 Qt 6.11.1 的 Qt Quick、Qt Quick Controls、Qt Quick PDF 与项目现有 C++/QML 类型。不得加入平台分支或额外库，行为在 Windows 10/11 x64、Linux x64、macOS ARM 一致。
