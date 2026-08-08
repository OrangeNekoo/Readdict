# Readdict 第二轮 Kindle 化对齐与逻辑优化 — 设计规格

- 日期：2026-08-08
- 状态：待用户审查
- 技术栈：C/C++ + Qt 6.11.1，纯 QML（QuickControls2）UI
- 前序文档：`2026-08-04-readdict-design.md`（基线）、`.superpowers/sdd/kindel-ui-analysis.md`（第一轮分析，部分与参考图不符，以本规格为准）

## 1. 概述

第一轮 Kindle 化（U1–U6）已落地 Token 基座、Kd 组件库、设置列表化与底部 Aa Sheet，但其依据的视觉分析报告与真实 Kindle 参考图（`~/Desktop/kindel界面参考/` 10 张）存在结构性偏差。本轮目标：

1. **UI 全面对齐参考图**：重做导航体系（顶搜索栏 + 底部 2 文字标签 + 悬浮迷你封面）、阅读页顶栏、书库细节、布局设置图标卡、新增主页。
2. **修复功能代码错误逻辑与不直觉交互**：P0×7、P1×11、高价值 P2×15（清单见 §5）。

架构不变：纯 QML UI + C++ 后端单例（`qmlRegisterSingletonInstance`），SQLite + settings.json。不引入新依赖、不改分层。

## 2. 需求基线（头脑风暴确认结论）

| # | 决策 | 结论 |
|---|------|------|
| 1 | 对齐策略 | 全面对齐参考图；保留第一轮可复用基座（Token、Kd 组件库、设置列表、Aa Sheet） |
| 2 | 全局导航 | 严格映射：顶全宽搜索栏 + ⋮；底「主页 \| 图书馆」文字标签 + 中间悬浮当前阅读书迷你封面 |
| 3 | 主页内容 | 最近阅读横排 + 阅读统计摘要行（点击进统计详情页） |
| 4 | 阅读页工具栏 | 顶栏照搬参考图 7 项；朗读入口进顶栏 ⋮ 下拉；朗读中底部浮现 TtsBar |
| 5 | 导入入口 | 书库页 ⋮ 菜单首项「导入书籍」，保留拖拽导入 |
| 6 | 筛选滑块 | 搜索栏下滑块图标 → 筛选+排序面板（分类 + 排序方式） |
| 7 | 统计/同步入口 | 均进书库页 ⋮ 菜单；主页仅承载统计摘要 |
| 8 | 逻辑修复范围 | P0 + P1 + 高价值 P2；纯重构型 P2（流式上传、导入后台化等）推迟 |
| 9 | 实施顺序 | 后端契约先行（L 阶段）→ UI 对齐（U 阶段）→ 回归（R 阶段） |

## 3. 总体架构与阶段划分

分层与数据流沿用基线规格 §4。本轮组件账本：

- **新建**：`HomePage.qml`、`KdTopSearchBar.qml`、`KdBottomTabs.qml`（2 文字标签 + 悬浮封面）、`KdTopToolbar.qml`（阅读顶栏）、`KdDropdownMenu.qml`（⋮ 下拉，顶栏与搜索栏共用）、`KdFilterSheet.qml`（筛选+排序）、`KdIconCard.qml`（布局图标卡）、`ThemeManagePage.qml`（自定义预设删除列表）
- **重做**：`Main.qml` 导航体系、`ShelfPage.qml`（图书馆页）、`ReaderPage.qml` 顶栏部分、`LayoutSheet.qml`（分段滑块 → 图标卡）
- **复用**：`Theme.qml` Token、Kd 组件库（ListItem/Toggle/RadioGrid/SegmentedSlider/BottomSheet/Icons）、`SettingsPage` 及子页、Aa Sheet 容器与 Theme/Font/MoreSheet、`TtsBar`、`BookCard`、`StatsPage`、`SyncPage`
- **删除**：`KdTabBar.qml`、`KdBottomNav.qml`（被新导航替代）、`ReaderControls.qml` 快捷条（被顶栏替代，其选项列表并入 Aa 面板单一数据源）

三阶段：

- **L 阶段（逻辑）**：§5 全部后端修复；每修一组跑对应 ctest；UI 不动。
- **U 阶段（UI）**：按 §6 对齐参考图；tst_qml 适配新导航句柄。
- **R 阶段（回归）**：Token 一致性审计（全仓无 Material 靛蓝/硬编码色残留）、三语 i18n 0 unfinished、构建 0 error/warning、ctest 与 tst_qml 全绿、启动零 QML 错误。

## 4. 导航体系（U 阶段核心）

### 4.1 顶部区域（主页/图书馆页可见）

- 全宽搜索栏：全圆角（~20px）浅灰底（`bgSearch`），内嵌放大镜图标 + 占位「搜索 Readdict」；输入实时过滤图书馆网格（主页输入时切到图书馆标签）。右侧 ⋮ 按钮。
- 图书馆页搜索栏下左对齐滑块筛选图标（KdIcons 新增 `filter`），点击弹 `KdFilterSheet`：分类单选列表（全部 + 各分类）+ 排序方式单选（最近阅读/作者/出版社/类型/添加时间），**按值维护**（修 P1#17），选择即生效即持久化。

### 4.2 底部区域

- 2 等宽文字标签「主页」「图书馆」：选中加粗 + 3px 黑下划线（`borderActive`），未选中 `textSecondary`。
- 中间悬浮迷你封面：3:4 约 40×54px，上凸越过分隔线，1px 边框 + 轻投影；显示**正在阅读的书**（`last_read_at` 最新且 progress>0）封面；点击 push 阅读页恢复进度；无记录时隐藏（占位保持两标签等宽）。

### 4.3 页面映射与栈

- 主页 `HomePage`：分区标题「最近阅读」+ 横排书籍行（封面 + 书名 + 作者，复用 BookCard 缩略形态）；分区「阅读统计」摘要行（本周时长/连续天数，数据源 StatsPage 既有统计逻辑）点击 push `StatsPage`。
- 图书馆 `ShelfPage`：封面网格（既有 Kindle 样式）+ 进度 % 角标（黑底白字小旗，右上）+「新」角标（added_at 7 天内且未读，斜向丝带）+ 筛选图标。
- 书库页 ⋮ 下拉菜单（`KdDropdownMenu`：实色背景、遮罩 rgba(0,0,0,0.3)、线性图标 + 文字、分割线分组）：导入书籍 / 阅读统计 / 同步 / 设置 / ─ / 关于（关于 = 简单对话框：版本/技术栈/开源许可，不建独立页）。
- 沉浸页（reader/pdf）与推入页（stats/sync/settings 及子页）隐藏顶搜索栏与底部标签（沿用 `navVisible` 机制）。

### 4.4 阅读页顶栏（点屏幕中部唤出，与 Aa 面板同显同隐）

`← 书库 | Aa | 布局 | 笔记 | 书签 | 搜索 | ⋮`

- ← 书库：pop 回图书馆。
- Aa：打开底部 Aa 面板（默认主题标签）。布局：打开面板布局标签。**顶栏为快捷入口，面板为唯一实现**（修 P2#19 双份选项）。
- 笔记：push 笔记列表页（既有）。
- 书签：切换当前位置书签；图标描边/填充两态。
- 搜索：书内搜索（既有）。
- ⋮：下拉菜单（朗读 / 目录 / 上章 / 下章 / 图书信息；跳转进度由「更多」标签「阅读进度」行承担）。朗读启动后顶栏可隐，底部 TtsBar 浮现（既有形态）。

### 4.5 底部 Aa 面板（复用 KdBottomSheet，四标签）

- 主题：2×2 预设卡（○/● 勾选标记）+「保存当前设置」描边按钮（**实现**：存为自定义预设持久化，修 P1#10）+ 管理主题行（push `ThemeManagePage`：自定义预设列表 + 删除）。
- 字体：4 字体族 radio 网格（宋/黑/楷/圆）+ 粗体分段滑块 + 大小分段滑块（既有，与参考图一致）。
- 布局：**图标卡**（KdIconCard，圆角矩形描边、选中加粗边）——方向 2 卡（竖滚/横翻）、页边距 3 卡、行间距 3 卡；对齐保留分段滑块（参考图「对齐不可用」，Readdict 可用故保留既有控件）。
- 更多：Toggle 列表（阅读时显示时钟 等）+「阅读进度：书中位置 >」行（修 P1 语义）。

## 5. 后端逻辑修复清单（L 阶段）

### P0（7，全修）

1. **Clipboard 未注册**（ReaderContent.qml:779）：注册基于 `QGuiApplication::clipboard()` 的 QML 单例 `Clipboard`（main.cpp 与 tst_qmlmain.cpp 同机制），复制生效。
2. **同步设置绕过单例**（SyncManager.cpp:248）：`SettingsStore` 增 `reloadFromDisk()`；`applySettingsJson` 写盘后经单例重载（或合并后由单例写盘），杜绝内存快照覆盖同步结果。
3. **书体同步孤儿文件**（SyncManager.cpp:575）：远端命名改内容哈希（SHA1 前 256KB + 扩展名）；上传前查远端同名跳过；下载后经 `BookImporter` 注册入库（去重：哈希命中已有书仅关联）。
4. **settings.json 非原子写 + 静默重置**（SettingsStore.cpp）：save 用临时文件 + rename；构造解析失败时备份原文件（`.corrupt-<ts>`）+ qWarning，不静默覆盖。
5. **解析失败空白章**（ReaderPage.qml:573）：`loadChapter` 返回错误码/错误串；QML 显示错误占位页（含重试按钮），导入时对持久解析失败书标记（联动 P2#31）。
6. **笔记跨章排序错**（HighlightManager.cpp:115）：highlights 表增 `chapter_index` 列（DB 迁移），写入时填值，列表按 (chapter_index, sentence_index, id) 排序；旧数据迁移按 chapter 标题序回填。
7. **过滤态搜索点击无响应**（ShelfPage.qml:238）：`BookManager::bookById` 标 Q_INVOKABLE 查全库（不受 booksModel 过滤影响）。

### P1（11，全修）

8. 深色三态恢复：设置页 radio 三选（跟随系统/浅色/深色），修 auto 单向丢失。
9. TtsBar 语速范围统一 0.25–4.0（与 TtsController/设置页一致）。
10. 「保存当前设置」实现（见 §4.5）。
11. 同步勾选即写：SyncPage 勾选项 onChange 即持久化（与设置页即时生效语义一致），「立即同步」按钮只触发同步。
12. `SyncResult` 结构化返回（success/errorCode/message），删 C++/QML 两份字符串判败。
13. 进度语义解耦：`progress` 取 max（最远进度），当前位置独立存（修回退早章进度倒退）。
14. chapterProgress C++ 侧缓存（载书时算好），删 QML 绑定内 O(n) 重算与跨书残留。
15. tts 音色键按引擎拆分：`tts/systemVoice` / `tts/openaiVoice`（旧 `tts/voice` 迁移）。
16. savePosition 仅值变化时写盘。
17. catFilter 按值维护（修索引漂移）。
18. applyHighlights 跳过本地不存在的书 + emit `highlightsChanged`。

### 高价值 P2（15，修）

19. 快捷条与 Sheet 选项列表合一（U 阶段删 ReaderControls 后单一数据源：面板）。
20. ⋯ 菜单与 MoreSheet 功能菜单合一（U 阶段顶栏 ⋮ 为唯一功能菜单源：朗读/目录/上章/下章/图书信息；「更多」标签只留 Toggle 与阅读进度行）。
21. 删 categories 死 API（表保留、删无消费者方法，测试适配）。
22. 删 SearchEngine::indexBook 游标路径。
23. 删 TtsController 死接口（currentSentence/atEnd/seekTo）。
24. 删 BookImporter::moveIntoLibrary 死参。
25. 删 TextParser inPre 空转。
26. progress 写路径合一（currentChapter 持久化与 savePosition 合并）。
27. removeBook 级联清理 highlights + settings 的 progress/scroll_/pdf_ 键。
30. SyncController 只读解析 settings（不触发 save 重写）。
31. backfill 对持久失败书标记跳过（联动 P0#5）。
32. DatabaseManager 迁移失败致命化（与 open 失败同等 qFatal）。
33. 背景模式归一化抽公共函数。
34. PdfReaderPage 翻页持久化节流合并。
37. TtsController::reconfigure 先 stop 旧引擎。
40. applyProgress/applyHighlights 批处理 + 事务。

### 推迟（记录在案，不在本轮）

#28 书体流式 PUT、#29 MKCOL 去重、#36 syncOne 拆分、#38 导入后台化、#39 insertPath 告警。

## 6. 数据流与错误处理

- settings.json 写入者收敛为**唯一**：SettingsStore 单例。SyncManager 合并后经单例写盘 + reload；SyncController 只读。
- 同步书体：哈希命名 → 上传去重 → 下载经导入管线注册（复用解析/封面/FTS），失败书单本跳过不中断。
- 解析失败：导入期标记 + 阅读期错误页，双保险。
- 其余错误处理沿用基线规格 §12。实施计划按阶段拆为两份：L 阶段计划、U+R 阶段计划（writing-plans 产出）。

## 7. 测试策略

- L 阶段：每修一组补/改对应 ctest 用例（SettingsStore 原子写与 reload、SyncManager 哈希命名与注册、HighlightManager 排序、BookManager bookById/进度语义、TtsController 键拆分）。
- U 阶段：tst_qml 导航句柄适配（navStack/tabBar/bottomNav → 新组件别名）、新组件冒烟（KdBottomTabs 悬浮封面显隐、KdTopToolbar 7 项分发、KdFilterSheet 按值筛选、KdIconCard 选中态）。
- R 阶段：全量 ctest + tst_qml + i18n 0 unfinished + Token 审计 grep。

## 8. 非目标（YAGNI）

- 不做推荐算法/商店页（参考图「主页/商店」语义仅借结构，不借内容）。
- 不做网页浏览器、法务页等 Kindle 设备专属项。
- 不做 §5 推迟清单。
- 不改 PDF 渲染管线、不引入 WebEngine。
