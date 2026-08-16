# 阅读器三项缺陷修复设计规格

- 日期：2026-08-16
- 状态：已获用户批准，进入实现计划阶段
- 技术边界：Qt 6.11.1、Qt Quick/QML 公共 API、C++17；Windows 10/11 x64、Linux x64、macOS ARM 共用实现
- 相关现有规格：`docs/superpowers/specs/2026-08-12-reader-pagination-continuity-design.md`

## 1. 问题

1. 竖向连续阅读跨章节时，窗口数据异步重建与旧 `contentY` 坐标不一致，向下翻页可能重新落到窗口起点，表现为跳回第一页。
2. 横向分页的左右箭头目前永久显示；闲置后应隐藏，鼠标移动到左右边缘热区时重新显示。W/A/D 已可翻页，但左右方向键在部分平台/焦点路径被 Flickable 键盘导航消费。
3. “全书”进度测量复用隐藏 `ReaderContent`，切章后可能读取上一章尚未失效的 `pageCount/pageModel`；测量尚未完成时显示逻辑又回退到本章页码，导致全书页码实际仍是本章页码。

## 2. 目标与非目标

### 目标

- 竖向模式跨章向下、向上滚动均保持稳定段落和相对视口偏移；窗口重建、自动续章和显式章节切换不能把用户位置拉回首屏。
- 横向箭头默认在进入分页模式或鼠标边缘移动后短时间可见；无鼠标移动达到闲置时隐藏；左右边缘热区只影响箭头显隐，不拦截正文点击、拖动、文本选择或翻页。
- 横向 `Left/Right` 与 `A/D` 使用同一 `pagePrev/pageNext`，适用于 ReaderPage 生产焦点链路和 ReaderContent 直接焦点链路；不使用平台专有键码。
- 全书页数严格为所有章节的视觉页数总和；全书当前页为前序章节页数之和加当前章节页号；异步测量完成前不得把本章页数标成全书页数。
- 保留现有设置键、数据库 schema、解析器、PDF 阅读器和 Qt 公共 API 边界。

### 非目标

- 不改阅读器整体布局、不增加第三方依赖、不迁移阅读模型到 C++。
- 不改变滚轮、W/A/D、PageUp/PageDown 的既有语义。
- 不隐藏滚动条或用固定延迟掩盖分页/窗口状态问题。

## 3. 设计

### 3.1 竖向窗口锚点事务

`ReaderContent` 将运行中的窗口重建锚点与首次打开的持久化恢复分开：

1. 任何 `scrollChapters`、活动章节或窗口模型变化前，捕获当前顶部可见段落的稳定键 `{chapterIndex, paragraphIndex}` 与 `offsetY`。
2. 根据锚点优先选择窗口切片起点，确保锚点段落仍在新 `scrollModel`；若锚点已不在书籍窗口，回退到活动章节焦点。
3. 新委托完成布局后，通过零延迟/单次定时器查找同一稳定键并恢复 `contentY`；只做钳制，不写入 `0`。
4. `showScrollChapter()`、`onChapterChanged`、`onScrollChaptersChanged` 使用同一事务入口，不再互相清除运行中的待恢复锚点。显式 `restoreAnchor/restoreScrollY` 仅用于页面初次打开或搜索跳转。
5. 章节激活仍由视口中线触发，ReaderPage 继续更新 `Books.currentChapter`、TTS 与书签，但窗口更新不销毁相邻章节的可见内容。

### 3.2 横向箭头与键盘

- 在 ReaderContent 增加不拦截输入的 HoverHandler/等价 Qt Quick 鼠标移动处理，记录视口坐标和左右边缘热区（约 15%，并设置最小宽度）。
- `edgeHintsVisible` 由分页模式、闲置 Timer 和最近边缘移动共同决定：进入 paged 显示；鼠标移动到左右热区显示并重启 Timer；Timer 到期隐藏。点击/拖动仍由现有 TapHandler/Flickable 处理。
- 左右箭头继续是纯视觉项，通过绑定 `edgeHintsVisible` 控制，不添加 MouseArea，避免遮挡翻页和文本操作。
- 在 ReaderContent 和 ReaderPage 的高优先级 Keys 路径补充显式左右方向键处理；处理函数统一调用现有 `handleKey`，设置 `event.accepted`，避免重复处理。修饰键仍交给系统/文本选择。

### 3.3 全书视觉页测量

- ReaderPage 的隐藏测量视图每章开始时清空上一章 `pageModel/pageCount`，并记录测量代次/目标章节。
- 只有测量视图确认目标章节完成实际布局且 `pageRepeater.count/pageCount` 稳定后，才将页数写入 `measuredChapterPages`；任何旧页模型不得被采纳。
- 全部章节测量完成后一次性设置 `bookPageTotal`，再根据 `Books.currentChapter` 与当前章节的实际页号计算 `bookPageNumber`。
- 在 `bookPageTotal` 尚未完成时，保持显式的全书安全值（1/1 或 0/0 的既有 UI 约定），不得调用本章页码作为全书页码来源。测量完成、章节激活、横向翻页、竖向滚动都触发统一更新。
- 排版参数或窗口尺寸改变时重新测量，旧全书缓存立即失效，避免不同布局参数混用。

## 4. 错误处理与兼容性

- 空书、空章、空段落、章节加载失败、窗口尺寸为 0 时使用安全锚点/1 页，不抛 QML 异常。
- 测量某章失败时该章按 1 页占位并继续扫描后续章节；全书总页数仍可完成。
- 只使用 `QtQuick`、`QtQuick.Controls` 现有类型和项目已有 C++ ReaderTextHelper；不增加 OS 分支。

## 5. 验收与测试

- `tst_e4_keys.qml`：跨章向下滚动后 `contentY` 不回到 0/首屏；向上回滚能看到上一章；生产 `keyClick(Qt.Key_Left/Right)` 在 paged 模式翻页。
- `tst_e4_keys.qml`：paged 箭头初始可见，闲置后不可见，边缘鼠标移动后可见；边缘点击仍翻页。
- `tst_readerpage.qml`：全书页数等待测量完成后大于单章页数，多章切换时全书当前页包含前序章节页数；排版变化重新测量。
- 现有 `tst_qml` 全套继续通过；构建使用现有 Qt 6.11.1，不安装任何库。
