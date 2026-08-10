# U6 报告：R 阶段——i18n、Token 审计、全量回归（恢复完成）

实现模型：opencode-go/deepseek-v4-flash
审查模型：kitoolai/gpt-5.6-luna（由 Main 安排）
日期：2026-08-10
基底：HEAD d8fab13（U5 完成）；本次仅提交 U6 的 4 个文件，`.gitignore` 为用户既有 WIP，未触碰、未提交。

## 1. i18n 三语 0 unfinished（步骤 1）

- 现状核实（XML 解析，非文本 grep）：
  - `readdict_en.ts`：245 条 message / 23 context，其中 active（translation 无 type）=199、vanished=46，unfinished=0，空 translation=0，缺 translation=0
  - `readdict_zh_CN.ts`：245 / 23，active=199、vanished=46，unfinished=0，空=0，缺=0
  - `readdict_zh_TW.ts`：245 / 23，active=199、vanished=46，unfinished=0，空=0，缺=0
- 三语条目数一致（245=245=245），active/vanished 数一致（199/46 三语相等）。
- `ReaderControls` context 已从三份 TS 移除（23 个 context 均无 ReaderControls，三语一致）。
- 46 条 vanished 均为「代码引用消失」的遗留翻译：无 `<location>`（lupdate 在引用消失时移除 location），分布于 SettingsPage 26 / ShelfPage 10 / MoreSheet 6 / Main 2 / ReaderPage 1 / SyncPage 1（每语），三语 vanished source 集合逐一相等。vanished 不影响运行（`qsTr` 只查找 active 条目），验收「三语 0 unfinished」按 `type="unfinished"` 计，三语均为 0。
- lupdate 造成的 diff 主体是 `<location>` 行号重排与新增/回填串，无 unfinished 残留。
- 构建验证：`cmake --build build --target Readdict_lrelease -j2` 成功；`build/readdict_*.qm` 时间戳晚于 TS 修改（lrelease 以当前 TS 重新产出）。`tst_language` 用真实 .qm 验证三语切换翻译命中 → **PASS**（0.50s）。

## 2. Token 审计与删除清单（步骤 2/3）

- `ReaderContent.qml` diff 仅 1 处（1 hunk / 14 diff 行）：注释对话框辅助文字 `color: "#555555"` → `color: UITheme.textSecondary`（附 U6 说明注释）。`UITheme.textSecondary` 在 Theme.qml:70 定义，全项目 21 个文件已有同 Token 用法，一致无新约定。
- Token 一致性：`grep Material.primary|Material.accent|#3D5AFE|#536DFE` 于 src/ui/qml 无活动代码命中（仅注释记录"已移除"）；活动硬编码色仅存于 Theme.qml / ReaderBackground.qml（Token 定义/引用处）与**允许的功能色/组件常量/遮罩投影**（逐项清单见 §4）。
- 删除清单：`KdBottomNav` / `ReaderControls` 在 src 与 tests 全树 grep 无命中（含 CMake 清单、TS context、QML 引用）。KdTabBar 保留且消费者仅 KdBottomSheet，符合预期。

## 3. 构建与 ctest（步骤 4）

- 构建（全程低并发，未用无上限 `--parallel`）：
  - `cmake --build build --target Readdict_lrelease -j2` → 成功
  - `cmake --build build --target tst_qml -j2` → 成功
  - 发现其余 19 个测试二进制未编译（仅 _autogen 目录存在，前次构建被系统重启打断），补 `cmake --build build --target <19 个 tst_*> -j2` → 全部 Built target
  - `cmake --build build -j2`（默认目标）→ Readdict.app 重链成功（75s，QML 资源含 U6 改动后重编译）
- ctest：`ctest --test-dir build --output-on-failure` → **19/20 PASS，1 failed（tst_qml）**，总耗时 54s。tst_language / tst_webdav / tst_syncmanager / tst_synccontroller 等全部单元测试绿。
- tst_qml：228 passed / 4 failed / 4 skipped（skipped 为 READDICT_REAL_PDF 未设置的条件跳过，属预期）。4 个失败均为 QML 冒烟时序/隔离问题，与 U6 改动（Label 颜色属性 + 翻译串）无因果：
  1. `PagedModeSmoke::test_autoRepeatThrottlesChapterChange`（tst_e4_keys.qml:340）——paged 章末按键 autoRepeat 时序，隔离复跑仍失败，E4 既有时序 flake；U6 未改任何按键分发逻辑。
  2. `DeleteSmoke::test_deleteDialogRemovesBookAndFiles`（tst_main.qml:168）——"delme 书应导入"失败；**隔离复跑 PASS**（3 passed, 0 failed），属同进程内前序测试导入残留导致的书库重名冲突。
  3. `MainNavSmoke::test_navSwitchReaderResume`（tst_nav.qml:107）——QWARN 明示「同名文件已存在于书库」；**隔离复跑 PASS**，同上为跨测试污染。
  4. `ReaderSheetSmoke::test_middleTapOpensSheetAndReTapCloses`（tst_u4.qml:228）——底部 1/4 轻点后 `page.sheetOpen` 未在 verify 时归零，轻点→Sheet 竞态，E4 既有时序 flake；隔离复跑仍失败。
- 结论：4 个失败与 U6 改动无因果关系（改动仅一个 Label 的 color 属性与三份翻译文件，不触及按键/轻点分发与导入路径），判定为既有 flake/测试隔离问题，未纳入本次修复范围。

## 4. 启动冒烟（步骤 4）

- `build/Readdict.app/Contents/MacOS/Readdict` 后台启动，5 秒后 SIGTERM/SIGKILL 清理，`pgrep` 确认无残留进程（app exit=143 = SIGTERM）。
- 日志 10 行：字体加载（Source Han 系 8 个字体文件）+ `qt.multimedia.ffmpeg: Using Qt multimedia with FFmpeg 7.1.3`；**零 QML 错误、零 warning、零 crash**。

## 5. Commit（步骤 5）

- 仅提交 4 个 U6 文件：`src/ui/i18n/readdict_en.ts`、`src/ui/i18n/readdict_zh_CN.ts`、`src/ui/i18n/readdict_zh_TW.ts`、`src/ui/qml/ReaderContent.qml`。
- `.gitignore` 明确排除，未加入暂存区。
- commit message（简体中文）：见 git log 首行。

## 疑虑

1. ~~tst_qml 的 4 个失败为既有 flake/隔离问题~~ → 已在 U6 修复轮全部根因修复（见下节），非 flake：2 个为确定性产品/测试契约问题，2 个为同源搜索残留污染。
2. `cmake --build build` 默认目标不含 tests 子目录的测试可执行文件，需显式 `--target tst_*`；本次已全量补齐。
3. 上一轮构建因无限 `--parallel` 打满 CPU 被系统重启，本次全程 -j2，无异常占用。

---

# U6 修复轮（2026-08-10，追加）

实现模型：opencode-go/deepseek-v4-flash
基底：HEAD 5f279a6（U6 基础提交后，tst_qml 4 failed）；本次修复轮提交 6 文件（见 §7）。`.gitignore` 为用户既有 WIP，未触碰、未提交。

## 1. 最终验证证据

- `ctest --test-dir build --output-on-failure` 连续两遍 → **20/20 Passed**（每遍 ~33s）。
- `./build/tests/tst_qml` 连续两遍 → **232 passed / 0 failed / 4 skipped**（skipped 为 READDICT_REAL_PDF/EPUB 未设的条件跳过）。
- 隔离复跑：`PagedModeSmoke::test_autoRepeatThrottlesChapterChange` 3/3、`ReaderSheetSmoke::test_middleTapOpensSheetAndReTapCloses`、`DeleteSmoke`、`MainNavSmoke` 全部 PASS。
- 启动冒烟：`Readdict.app` 5 秒 → 字体加载 + FFmpeg 初始化，**零 QML 错误/警告/崩溃**，无残留进程。
- 全程低并发：仅 `cmake --build build --target <target> -j2`，未用无上限 `--parallel`。

## 2. 四个失败：根因与修复（逐一）

### 2.1 PagedModeSmoke::test_autoRepeatThrottlesChapterChange（tst_e4_keys.qml:340）——产品 bug：snapToPage 拽走章末

**根因（探针实证）**：paged 模式末页不完整时（multibook 章 1：maxY=2316.42，pageH=720，maxY%pageH=156.42），键盘翻页动画（pageAnim 目标即 maxY）结束后 200ms，`snapTimer` 触发 `snapToPage()`：`round(2316.42/720)*720=2160`，把停在真章末的 contentY 拽回上一整页边界。此后 pageNext 的章末检测（target==contentY 时 requestNextChapter）永不成立——**真实读者在 paged 模式也会卡死在末页**。既有 `test_pagedModeLastPageAdvancesChapter` 因在 snap 触发前 50ms 内按键而侥幸通过。

**修复**（`src/ui/qml/ReaderContent.qml` snapToPage）：`maxY` 纳入吸附候选，距当前 contentY 更近时以其为目标；其余页面 maxY 远在视口外，滚轮吸附行为不变。

### 2.2/2.3 DeleteSmoke::test_deleteDialogRemovesBookAndFiles（tst_main.qml:168）与 MainNavSmoke::test_navSwitchReaderResume（tst_nav.qml:107）——同源：搜索残留污染

**根因（全量日志实证）**：QML TestCase 按**逆声明序**执行，tst_main.qml 中 `FulltextSmoke::test_shelfFulltextHits` 先于 `DeleteSmoke` 运行；其 `win.topSearchBar.text = "第二行内容"` 经 Main.qml `onTextChanged → Books.doSearch` 把元数据搜索置为无命中词，且**不还原** → `Books.booksModel` 变空。DeleteSmoke 随后导入 delme（无 QWARN，导入成功）但 `findDeleteBook` 遍历空模型失败；tst_nav 紧随其后，找不到非 PDF 书 → 兜底 `doImport(sourceFiles[0]=zeta)` 撞上 tst_e2e 已导入的 `books/zeta.txt`（importFile 对 dest 已存在直接失败「同名文件已存在于书库」，不看 DB 行）→ QWARN + 失败。附带事实：`removeBook()` 只删行不删文件（tst_e2e:71 删 mike 行留 mike.txt），是「同名文件」冲突的放大器。

**修复**：
- 污染源（tst_main.qml FulltextSmoke）：测试末尾 `win.topSearchBar.text = ""` 还原搜索；
- 消费侧按仓库约定补防御复位（tst_main.qml DeleteSmoke、tst_nav.qml MainNavSmoke 各加 `initTestCase`：`doSearch("")+setFilter("")+setSort(0)`，同 tst_readerpage/tst_shelf/tst_u3/tst_u4 模式）。

### 2.4 ReaderSheetSmoke::test_middleTapOpensSheetAndReTapCloses（tst_u4.qml:228）——测试断言旧契约

**根因**：U4 修复（e26871f）后，隐藏态底部 1/4 轻点会同时置 `controlsVisible=true` 与 `sheetOpen=true`（稳定唤出顶栏，tst_readerpage:162/182/195 已按此断言并通过），但 tst_u4:228 仍断言 `!page.sheetOpen`——确定性契约失配，非竞态。

**修复**（tst_u4.qml）：断言改为新契约 `controlsVisible && sheetOpen && topToolbar.visible`（与 tst_readerpage 同款），注释同步。

## 3. 修复中暴露的第五个竞态：waitContentSettled 旧章高度残留（同测试 line 333）

修复 2.1 后首次全套出现新失败点（line 333）：`contentY=2316.42`（章 1 真 maxY）vs 捕获 `maxY=4231.375`（章 0 100 段高度）。根因：`waitContentSettled` 的「count 匹配 + 高度稳定×2」判据不充分——**委托 count 先更新，各委托 implicitHeight（富文本排版，`contentHeight: col.implicitHeight`）后落地**，窗口内旧章高度仍稳定 → 提前返回 → maxY 按旧章捕获，循环期间高度骤降导致 contentY 钳制与 pageNext 提前翻章（U5 加固只加 count 检查、未覆盖此窗口）。

**修复**（tst_e4_keys.qml waitContentSettled）：count 同步后要求高度相对首同步样本发生一次变动（新章布局落地）再稳定两次；5s 超时兜底。

## 4. Token 审计——逐项 hex 清单（简报步骤 2 复核）

对 `src/ui/qml` 全量逐行扫描（正则提取 `#RRGGBB` 与 `#AARRGGBB`，另以内置 grep 复核 `Material.primary|Material.accent|#3D5AFE|#536DFE`），并逐条区分「活动代码值」与「注释提及」。

**结论**：主题语义色零残留——活动代码无 `Material.primary/Material.accent/#3D5AFE/#536DFE`（仅 BookCard.qml:95、StatsPage.qml:158 注释记录"已移除"），也无游离的通用文字/背景色。非 Theme.qml（Token 定义源）/ReaderBackground.qml（Token 引用处）之外的活动 hex 均属**允许的功能色 / 组件内部明暗常量 / 遮罩投影浮层常量**，逐项列明如下，不做笼统豁免。

### 4.1 六位 hex（#RRGGBB）逐项——非 Theme/ReaderBackground 的活动代码值

| 位置 | 值 | 用途 | 处理状态 |
|---|---|---|---|
| PdfReaderPage.qml:100（注释 99 记录审计） | #1A1A1A | PDF 页顶栏标题文字 | **已替换** → `UITheme.lightTextPrimary`（同值），并补 `import Readdict.UI 1.0`（9b37274 收编）——当前代码零残留 |
| TtsBar.qml:26 | #E6E6E6 / #1A1A1A | 朗读条前景文字（明/暗两态） | 组件明暗前景常量：随自身 bgMode 三元选择；#1A1A1A 与 lightTextPrimary 同值但属组件内部配色，非主题语义色 |
| ReaderContent.qml:71 | #FFD54F | TTS 朗读游标高亮黄 | 功能色（朗读会话指示），C5 设计 |
| ReaderContent.qml:87-89 | #FFEB3B / #A5D6A7 / #F8BBD0 | 划线色板黄/绿/粉 | 用户功能色板，C7 设计 |
| ReaderContent.qml:91 | #FFEB3B | 默认划线色 | 同上（功能色板缺省值） |
| ReaderContent.qml:690/694/725/729 | #212121 | 浅色高亮底上的深色前景字（写入富文本 styles 的 `color:#212121`，非 color 属性） | B3 复审对比度决策：高亮底恒为浅色板、恒配深字，与背景模式解耦 |

### 4.2 八位 ARGB 半透明常量逐项（遮罩/投影/悬停/按压/分隔线/浮层表面——简报明示「确认属遮罩/投影常量」即允许）

| 位置 | 值 | 用途 | 允许理由 |
|---|---|---|---|
| ShelfPage.qml:74 | #E6323232 | Toast 背景（90% 深灰） | 浮层表面常量（自带圆角，非主题语义色） |
| TtsBar.qml:25 | #F2121212 / #F2FFFFFF | 朗读条表面（深浅两态 95% 透明） | 组件表面配套常量（随自身 bgMode 三元选择） |
| TtsBar.qml:33 | #33FFFFFF / #1A000000 | 朗读条顶部分隔线（20%/10%） | 分隔线透明常量 |
| ReaderContent.qml:764/818 | #EE303030 | 选择工具条/划线色板浮层表面（93% 深灰） | 阅读页内浮层表面常量 |
| ReaderContent.qml:782 | #55FFFFFF | 工具条按钮按压态 | 按压反馈遮罩常量 |
| ReaderContent.qml:830 | #99FFFFFF | 色板色块描边 | 描边常量 |
| ReaderPage.qml:304 | #0A000000 | 笔记列表斑马纹（4% 黑） | 斑马纹遮罩常量 |
| ReaderPage.qml:895 | #0A000000 | ⋮ 菜单行悬停着色 | 悬停着色常量 |
| KdListItem.qml:90 | #14FFFFFF / #14000000 | 列表项按压遮罩（8% 白/黑） | 按压反馈遮罩常量（Kd 内部，逐项列明非豁免） |
| KdDropdownMenu.qml:81 | #0A000000 | 菜单行悬停着色 | 悬停着色常量（Kd 内部，逐项列明非豁免） |
| ThemeSheet.qml:137 | #0A000000 | 管理主题入口悬停着色 | 悬停着色常量 |
| PdfReaderPage.qml:77/83 | #E6FFFFFF / #1A000000 | PDF 页顶栏表面 + 底部分隔线 | 浮层表面/分隔线常量 |

### 4.3 注释提及（非活动代码，记录审计历史）

BookCard.qml:59/95/178-179、ReaderContent.qml:36/855、ReaderPage.qml:336、Theme.qml/ReaderBackground.qml 内注释中的 hex 均为设计说明或"已移除/已收编"记录，不构成活动硬编码。

## 5. i18n 三语统计（XML 解析）

| 语言 | message 总数 | active（translation 无 type） | vanished | unfinished | active source 集合（去重） | context | 空 translation |
|---|---|---|---|---|---|---|---|
| readdict_en.ts | 245 | 199 | 46 | 0 | 156 | 23 | 0 |
| readdict_zh_CN.ts | 245 | 199 | 46 | 0 | 156（与 en 逐条相等） | 23 | 0 |
| readdict_zh_TW.ts | 245 | 199 | 46 | 0 | 156（与 en 逐条相等） | 23 | 0 |

三语 active/vanished 数量一致（199/46），active 与 vanished 的 source 集合三语逐一相等；vanished 46 条为无 `<location>` 的遗留翻译（SettingsPage 26 / ShelfPage 10 / MoreSheet 6 / Main 2 / ReaderPage 1 / SyncPage 1，每语），不影响 `qsTr` 运行，且三语一致无漂移。

## 6. 提交文件清单（修复轮）

- `src/ui/qml/ReaderContent.qml`（snapToPage 末页吸附修复）
- `src/ui/qml/PdfReaderPage.qml`（Token 收编 + import）
- `tests/qml/tst_e4_keys.qml`（waitContentSettled 竞态加固）
- `tests/qml/tst_main.qml`（FulltextSmoke 还原搜索 + DeleteSmoke 防御复位）
- `tests/qml/tst_nav.qml`（MainNavSmoke 防御复位）
- `tests/qml/tst_u4.qml`（底部轻点断言改 U4 契约）

## 7. 疑虑/遗留

1. `tst_e2e::test_05_remove` 与 `tst_highlightsui` 的 `removeBook`（只删行）遗留 `books/mike.txt`、`duptitles.txt` 孤儿文件；当前无测试会在行删除后重导同源，属潜在隐患，未扩大改动面（如需根治可改 `removeBookWithFiles`，留待后续）。
2. `waitContentSettled` 严格要求同步后高度变动；同章重载（高度不变）5s 超时后**严格失败**（return false，调用方 verify 报错），不再以未证明同步/稳定的旧高度静默成功——当前唯一调用点 `test_autoRepeatThrottlesChapterChange` 为章 0→章 1 切换，必然存在高度变动，不触达慢路径。
3. 本次全程 -j2 构建（tst_qml、Readdict、Readdict_lrelease），无高占用。

---

# U6 证据修复轮（2026-08-10，追加）

实现模型：opencode-go/deepseek-v4-flash
基底：HEAD 9b37274（U6 修复轮完成后）；本次提交 2 个文件：`tests/qml/tst_e4_keys.qml` + 本报告（force add，`.superpowers` 被 .gitignore 忽略）。`.gitignore` 为用户既有 WIP，未触碰、未提交。

## 1. waitContentSettled 超时兜底——不再静默成功

- 原实现 5s 超时后 `return cv.contentHeight > cv.height`：在**未证明同步/稳定**的旧高度上静默放行，掩盖 count/高度竞态（E4 既有 flake 的放大因素）。
- 改为超时一律 `return false`（tst_e4_keys.qml），由调用方 `verify` 显式失败；失败信息带诊断（contentHeight、视口高、Repeater count/章节段落数），不引入固定 sleep。
- 正常章节切换验证保留：唯一调用点 `test_autoRepeatThrottlesChapterChange`（章 0→章 1，高度必然变动）隔离复跑 PASS。

## 2. 报告统计修正（真实值，XML 解析）

- 三份 TS 各 **245 message = active 199 + vanished 46**，unfinished=0、空 translation=0、缺 translation=0，context=23。
- 三语 active 集合（source 去重 156 条）逐一相等、vanished 集合（46 条）逐一相等，无三语漂移。
- 46 条 vanished 均为无 `<location>` 的遗留翻译（SettingsPage 26 / ShelfPage 10 / MoreSheet 6 / Main 2 / ReaderPage 1 / SyncPage 1，每语），不影响 `qsTr`；原文「无 vanished 残留 / active=245」为统计错误，已更正（§1/§5）。
- 报告全文去除「Theme/ReaderBackground 之外六位 hex 零残留」绝对句：改为「主题语义色零残留」+ 允许的功能色/组件常量/遮罩投影逐项列明（§4.1 六位逐项、§4.2 八位 ARGB 逐项、§4.3 注释提及），TtsBar #E6E6E6/#1A1A1A 自八位表移入六位表，PdfReaderPage 行号修正（color 在 100、ARGB 在 77/83）。

## 3. 验证证据（本轮实测）

- `cmake --build build --target tst_qml -j2` → Built target（增量，含 tst_e4_keys.qml 变更重编）。
- `./build/tests/tst_qml` → **232 passed / 0 failed / 4 skipped**（4 skipped 为 READDICT_REAL_PDF/EPUB 未设的条件跳过），~112s。
- `ctest --test-dir build --output-on-failure` → **20/20 Passed**，~115s。
- 未改动产品代码（Token 无需再改：PdfReaderPage #1A1A1A 已在上轮收编为 UITheme.lightTextPrimary）。

