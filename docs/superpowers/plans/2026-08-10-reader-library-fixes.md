# Readdict 阅读与书架问题修复计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development 逐任务实现此计划。每个任务完成后必须进行定向审查；全部任务完成后进行一次整体审查。

**目标：** 修复同步页信息不可滚动、阅读方向键与横向分页、阅读控件唤出、书架排序筛选四项问题，并完善自定义背景预览/字体颜色与可用格式的书籍作者/出版社元数据导入。

**架构：** 保留现有 Qt Quick Controls、`ReaderContent` 正文渲染和 `BookManager` 数据库边界。滚动修复使用页面级 `ScrollView`；阅读模式分为现有竖向连续滚动与独立的横向页状态/分页视图，不继续把“横向翻页”伪装成纵向 `contentY` 吸附。点击与键盘事件统一在阅读内容宿主建立可验证的输入桥接。元数据沿现有 Parser → BookImporter → BookManager 数据流传递，不引入新的第三方依赖。

**技术栈：** C++17、Qt 6.11 Qt Quick/QML、Qt Quick Controls、Qt SQL、现有 libmobi/minizip、QtTest。

---

## 根因与范围裁定

1. **整页滚动：** `Main.qml` 已将 `StackView` 锚定在底部导航上方；问题在 `SyncPage.qml` 仅把最后的日志 `ListView` 设为可滚动，表单本身没有 page-level scroll。修复整页滚动并保留日志独立可滚动区域，避免底部导航遮挡表单。
2. **阅读：** `pageMode="paged"` 当前仅按视口高度改变 `contentY`，不满足横向分页；新增真实横向页模型/视图，`scroll` 模式保持现有内容流。方向键必须通过真实 `activeFocus`/`Keys` 链路验证，不能只测试 `handleKey()`。
3. **控件唤出：** 生产路径必须让正文宿主与页面边缘点击都能到达统一状态机；测试覆盖真实 QML 鼠标点击或等价的宿主事件入口，并验证顶部/底部点击。
4. **筛选排序：** 优先修复筛选面板布局宽度和点击回写；用真实 `booksModel` 顺序和分类结果验证，而不是只验证 Settings 持久化。
5. **背景：** 使用固定长方形 preview card 展示当前背景、测试文本、模糊/亮度效果；字体颜色仅在自定义图片背景模式显示并持久化。
6. **元数据：** 不安装新依赖。复用 EPUB OPF、FB2 XML、libmobi EXTH；PDF 使用 Qt 可读的文档元数据（若当前 Qt API 可用），TXT/MD 使用文件名兜底，缺失字段保持空，不伪造作者/出版社。

---

## 任务 1：同步页与筛选面板的滚动/宽度修复

**文件：**
- 修改：`src/ui/qml/SyncPage.qml`
- 修改：`src/ui/qml/KdFilterSheet.qml`
- 修改：`tests/qml/tst_sync.qml`、`tests/qml/tst_u3.qml` 或对应现有 QML 测试

**交付：**
- 同步页整个配置表单放入 page-level `ScrollView`，内容列宽基于实际 viewport 宽度与 padding 计算。
- 日志区域保留明确高度和内部垂直滚动，页面滚动条在内容超出时可见；不让底部导航覆盖可访问内容。
- 筛选面板的分类、排序、搜索范围三个列表全部 `Layout.fillWidth`，delegate 宽度跟随列表；面板内容列使用实际 viewport 宽度，禁止 0 宽度初始化。
- 测试断言：小窗口下表单内容高度大于视口且 page scrollbar/可滚动范围有效；排序和范围选项文字可见宽度大于 0。

**验证：** 先运行新增失败测试确认当前实现失败，再运行定向 QML 测试确认通过。

---

## 任务 2：阅读控件点击唤出与方向键焦点链路

**文件：**
- 修改：`src/ui/qml/ReaderPage.qml`
- 修改：`src/ui/qml/ReaderContent.qml`
- 修改：`src/ui/qml/PdfReaderPage.qml`（仅当共享点击桥接需要）
- 修改：`tests/qml/tst_readerpage.qml`、`tests/qml/tst_e4_keys.qml`

**交付：**
- 正文宿主显式暴露单击入口；顶部正文区域、底部控制栏原位置和隐藏态正文底部点击均进入同一 `handleContentTap` 状态机。
- 不破坏文本选择、Flickable 拖动、Sheet 遮罩和按钮点击；拖动超过阈值不误触发唤出。
- ReaderPage 激活时确保正文获得 active focus；方向键由生产 `Keys.onPressed` 路径处理。测试至少覆盖 `activeFocus`、真实按键事件入口或等价的焦点事件转发、上下滚动和左右翻页/翻章。
- 不把“调用函数”作为唯一的交互测试证据。

**验证：** 新增一个会在现状失败的点击/焦点测试；定向运行 `ReaderToolbarSmoke`、`ControlsSummonSmoke`、`ArrowKeyPagingSmoke`。

---

## 任务 3：真正的横向分页模式

**文件：**
- 修改：`src/ui/qml/ReaderContent.qml`
- 修改：`src/ui/qml/ReaderPage.qml`
- 修改：`src/ui/qml/LayoutSheet.qml` 或 `SettingsBackgroundPage.qml`（仅同步文案/选项语义）
- 修改：`tests/qml/tst_e4_keys.qml` 及必要的 ReaderContent QML 测试

**交付：**
- `scroll`：保持单列竖向连续滚动。
- `paged`：按可见 viewport 生成横向页序列，页面沿 x 轴排列，左右键/点击翻页改变 `contentX`/当前页；上下键在该模式下使用同一页步进语义；章首/章末继续走上一章/下一章边界逻辑。
- 页宽、字体、行高、窗口尺寸或章节变化时重新计算页数并钳制当前页；图片段落和富文本段落必须保留现有渲染语义，无法分页的异常内容显示可读错误而不是空白。
- 设置仍持久化 `reading/pageMode`，但 UI 文案明确为“竖向连续滚动/横向分页”。

**验证：** 新增测试断言 paged 模式 `contentWidth > width`、`contentX` 变化而 `contentY` 不承担分页职责，并覆盖首末页边界和换章。

---

## 任务 4：书籍元数据导入与展示

**文件：**
- 修改：`src/parsers/DocumentModel.h`
- 修改：`src/parsers/EpubParser.cpp/.h`
- 修改：`src/parsers/Fb2Parser.cpp/.h`
- 修改：`src/parsers/MobiParser.cpp/.h`（使用现有 libmobi publisher API）
- 修改：`src/core/BookImporter.cpp/.h`
- 修改：`src/ui/qml/BookCard.qml`、图书信息 Dialog 所在 QML
- 修改：`tests/tst_epubparser.cpp`、`tests/tst_fb2parser.cpp`、`tests/tst_mobiparser.cpp`、`tests/tst_bookimporter.cpp`

**交付：**
- `DocumentModel` 增加 publisher；各成熟格式解析器读取已有格式元数据：EPUB OPF `dc:creator`/`dc:publisher`，FB2 `title-info/author` 与 `publisher`，MOBI/AZW3 的 `mobi_meta_get_author`/`mobi_meta_get_publisher`。
- `BookImporter::registerBook()` 将解析结果写入 `Book.author/publisher`，标题仍以元数据优先、文件名兜底；解析失败不阻断入库。
- PDF 仅在当前 Qt API 能稳定读取时接入，否则保留空字段并明确不伪造。
- 书架卡片/图书信息显示作者、出版社；空字段隐藏对应行。
- 测试覆盖元数据存在、缺失、解析失败和数据库持久化；不添加网络查询或新依赖。

---

## 任务 5：自定义背景测试预览与字体颜色

**文件：**
- 修改：`src/ui/qml/SettingsBackgroundPage.qml`
- 修改：`src/ui/qml/ReaderPage.qml`
- 修改：`src/ui/qml/ReaderBackground.qml` 或 `src/ui/qml/ReaderContent.qml`
- 修改：`src/ui/qml/Theme.qml`（仅新增所需 token/颜色校验）
- 修改：`tests/qml/tst_background.qml`、`tests/qml/tst_readerpage.qml`

**交付：**
- 自定义图片预览固定为小长方形卡片，显示测试文本；实时反映图片、模糊度和亮度。
- 图片背景模式下显示字体颜色选择控件，至少支持颜色选择/预设色，持久化到 `background/textColor`；浅色/深色/米白模式继续使用各自默认文字颜色。
- ReaderPage 读取并传递该颜色，正文富文本/纯文本一致使用；非法或缺失值回退到背景模式默认色。
- 测试覆盖预览可见尺寸、测试文本、颜色持久化、阅读页实际 textColor 注入和模式切换回退。

---

## 最终验证与审查

1. 每个任务先写失败测试并确认失败，再实现最小修复。
2. 每个任务由 `impl-flash` 实现并提交；随后由 `review-max`（`kitoolai/gpt-5.6-luna`）定向审查，不使用 Qwen。
3. 所有任务完成后运行低并发完整构建、全量 CTest、相关 QML 定向测试。
4. 运行最终整分支代码审查，检查未解决的交互、布局、数据流和测试覆盖问题。
5. 不修改系统环境变量，不安装软件包或开发包；所有 Git 提交使用简体中文提交信息。
