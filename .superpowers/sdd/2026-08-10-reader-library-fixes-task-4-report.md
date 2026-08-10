# 任务 4 报告：书籍元数据导入与展示

- 日期：2026-08-10
- 实现者：impl-flash（opencode-go/deepseek-v4-flash）
- 计划：`docs/superpowers/plans/2026-08-10-reader-library-fixes.md` 任务 4
- 提交：见文末（简体中文 commit）

## 目标回顾

1. `DocumentModel` 增加 publisher；各成熟格式解析器读取已有格式元数据：EPUB OPF `dc:creator`/`dc:publisher`，FB2 `title-info/author` 与 `publisher`，MOBI/AZW3 的 `mobi_meta_get_author`/`mobi_meta_get_publisher`。
2. `BookImporter::registerBook()` 将解析结果写入 `Book.author/publisher`，标题仍以元数据优先、文件名兜底；解析失败不阻断入库。
3. 避免重复解析造成明显开销（按格式实现最小 helper）。
4. 书架卡片/图书信息显示作者、出版社；空字段隐藏对应行。
5. 测试覆盖元数据存在、缺失、解析失败和数据库持久化；不添加网络查询或新依赖。

## TDD 顺序（红→绿）

- **红**：先改 fixture（sample.epub OPF 加 `<dc:publisher>出版社甲</dc:publisher>`、sample.fb2 加 `<publisher>测试出版社</publisher>`）并写失败测试（tst_epubparser/tst_fb2parser 断言 publisher、tst_mobiparser 新增 EXTH 构造器与 `parsesExthMetadata`、tst_bookimporter 新增 `epubImportWritesAuthorAndPublisher`/`metadataMissingKeepsFieldsEmpty` 并扩展 `epubParseFailureKeepsPlaceholder`、tst_main.qml 新增 `CoverSmoke::test_publisherLine`）。构建即 FAIL：`no member named 'publisher' in 'DocumentModel'`（DocumentModel 尚无该字段），实证测试先行。
- **绿**：实现后全部转绿（见验证节）。

## 改动

### `src/parsers/DocumentModel.h`
- `struct DocumentModel` 增加 `QString publisher`（Book 结构本就含 publisher 列，无需改动）。

### `src/parsers/EpubParser.{h,cpp}`
- `parseOpf`：新增 `dc:publisher` 读取（与 title/creator 同模式，标签名去前缀匹配兼容命名空间写法），`OpfInfo` 增 `publisher` 字段；`parse()` 填充 `m.publisher`。
- 新增轻量 `DocumentModel readMetadata(const QString &epubPath)`：只走 container.xml → OPF 扫描（复用 `readZipEntry`/`containerRootfile`/`parseOpf`），不解压/解析任何章节；OPF 缺失/损坏返回空模型不设错误（调用方按"元数据缺失"处理）。

### `src/parsers/Fb2Parser.{h,cpp}`
- `readMetadata`（title-info 内）：新增 `<publisher>` 读取（book-title/author 同模式）。
- 新增轻量 `DocumentModel readMetadataOnly(const QString &fb2Path)`：只做第一遍的 `<description>` 扫描（读到即 break，不含 binary 收集与正文分章）；XML 损坏返回空模型并设错误。

### `src/parsers/MobiParser.{h,cpp}`
- `parse()`：补 `mobi_meta_get_publisher(m)`（libmobi 0.8.x 已导出，third_party/libmobi/src/meta.c:274）→ `model.publisher`。
- 新增轻量 `DocumentModel readMetadataOnly(const QString &mobiPath)`：只 `mobi_init`/`mobi_load_filename` + EXTH 读取，不跑 rawml 重建与正文分章；错误分支与 parse() 一致（DRM/非 MOBI/加载失败返回空模型）。

### `src/parsers/ParserFactory.{h,cpp}`
- 新增 `static DocumentModel readMetadata(filePath, format)`：EPUB→`EpubParser::readMetadata`、FB2→`Fb2Parser::readMetadataOnly`、MOBI/AZW3→`MobiParser::readMetadataOnly`；TXT/MD/PDF/未知格式无元数据来源返回空模型（PDF 按计划裁定保留空字段、不伪造，当前 Qt API 无稳定作者/出版社读取）。

### `src/core/BookImporter.cpp`
- `registerBook()`：注册前调 `ParserFactory::readMetadata(destPath, format)` 一次——标题元数据优先、文件名兜底；`Book.author/publisher` 写入解析结果；解析失败不阻断入库（标题回退文件名、作者/出版社留空）。EPUB 封面提取的整书解析仅发生在"无 OPF 封面声明"的回退分支，与元数据最小读取不叠加。

### `src/ui/qml/BookCard.qml`
- 新增出版社行（`publisherLabel`）：紧跟作者行（作者为空时 `anchors.top` 回退到标题底部，不悬空），空值隐藏；暴露 `property alias publisherLabel` 测试句柄。作者行行为不变。

### `src/ui/qml/ReaderPage.qml`
- `infoDialog` 内容改为按字段动态拼接：书名/作者/出版社/格式空值隐藏对应行（进度恒显示）。注：本文件仅含本次 infoDialog 改动（任务 5 的 bgTextColor 改动由 ImplementBackgroundColor 另管，互不覆盖）。

### fixtures / 测试
- `tests/fixtures/sample.epub`：OPF 增 `dc:publisher`；`tests/fixtures/sample.fb2`：title-info 增 `<publisher>`。
- `tests/tst_epubparser.cpp`：`parsesStructure` 增 `QCOMPARE(m.publisher, "出版社甲")`。
- `tests/tst_fb2parser.cpp`：`parsesStructure` 增 `QCOMPARE(m.publisher, "测试出版社")`。
- `tests/tst_mobiparser.cpp`：`buildMobiPdb` 支持 EXTH 记录（tag→bytes，按 libmobi `mobi_parse_extheader` 布局）；`parsesMinimalMobi` 断言无 EXTH 时 author/publisher 为空；新增 `parsesExthMetadata`（EXTH 作者 100/出版社 101 → `mobi_meta_get_*` 链路读取）。
- `tests/tst_bookimporter.cpp`：`makeCoverEpub` OPF 增 `dc:publisher`；新增 `epubImportWritesAuthorAndPublisher`（元数据优先于文件名 + 独立 BookManager 连接回读持久化）、`metadataMissingKeepsFieldsEmpty`（TXT 全空 + 仅 dc:title 的 EPUB author/publisher 空）；`epubParseFailureKeepsPlaceholder` 增断言（标题回退文件名 "bad"、author/publisher 空）。
- `tests/qml/tst_main.qml`：`CoverSmoke` 新增 `test_publisherLine`（有出版社显示/无隐藏、句柄存在）；`RefreshCoversSmoke::findCoverBook` 改按 OPF 元数据标题 "封面刷新书" 查找（原按文件名 coverepub，属任务 4 标题语义变更的必要适配）。
- `tests/qml/tst_qmlmain.cpp`：仅注释同步（标题取 OPF 元数据，不再回退文件名）。

## 验证

- 构建：`cmake --build build/Qt_6_11_1_for_macOS_Debug --target tst_epubparser tst_fb2parser tst_mobiparser tst_bookimporter tst_qml -j8` 成功，无编译警告新增。
- 定向 C++ 套件（ctest 工作目录 build/tests 内直接运行）：
  - `tst_epubparser`：9 passed, 0 failed（含新 publisher 断言）。
  - `tst_fb2parser`：9 passed, 0 failed。
  - `tst_mobiparser`：7 passed, 0 failed（含 `parsesExthMetadata`）。
  - `tst_bookimporter`：17 passed, 0 failed, 3 skipped（3 skipped 为 READDICT_REAL_* 环境变量门控的真实书用例，未设置属预期）。
- 相关套件回归：`tst_parserfactory` 12 passed、`tst_bookmanager` 30 passed, 1 skipped（skipped 亦为真实书门控）。
- QML 定向（tst_qml，150 函数全量）：**252 passed, 0 failed, 4 skipped**（34s）。其中 `CoverSmoke`（含新 test_publisherLine）、`RefreshCoversSmoke`、`ReaderRestore::test_chapterRestore`、`ReaderToolbarSmoke`（含图书信息 Dialog 用例）均绿。
- 测试过程中修复的两个测试自身缺陷（非实现缺陷）：books() 按 added_at DESC 排序导致按索引取 EPUB 取到 TXT（改按格式定位）；`for (const Book &b : imp.books())` 临时向量悬垂指针（改先绑定局部向量）。

## 语义确认

- 元数据优先：EPUB OPF dc:title 覆盖文件名；解析失败（坏 EPUB）仍入库，标题回退文件名、作者/出版社为空（不伪造）。
- 缺失字段：TXT/MD/PDF 无元数据来源 → 作者/出版社空；无 publisher 声明的 EPUB/FB2/MOBI → 空。
- 展示：BookCard 出版社行与作者行同规则（空值隐藏）；ReaderPage 图书信息 Dialog 空字段行隐藏、进度恒显示。
- 数据库持久化：books 表 publisher 列随 addBook 写入，独立连接 bookById 回读一致（books_fts 的 publisher 列同步写入，排序/搜索不受影响）。

## 提交

- 20 个文件一次提交（ReaderPage.qml 仅含本任务 infoDialog hunk，任务 5 改动未混入）。
- commit message（简体中文）：「任务4：EPUB/FB2/MOBI 元数据（作者/出版社）导入与展示」

---

## 复审修复轮：malformed EPUB/FB2 元数据回退语义（追加）

### 审查发现（元数据审查）

1. `EpubParser::readMetadata` 忽略 `parseOpf` 的 bool 返回值与 `QXmlStreamReader` error——有效容器 + OPF 有元数据但**缺 spine**、或 OPF **XML 良构错误**时仍返回元数据，与完整 `parse()`（缺 spine 即失败）语义不一致。
2. `Fb2Parser::readMetadataOnly` 读到 `<description>` 后立即 `break`，**不校验 description 之后的尾部 XML**——畸形 FB2 仍返回元数据，与 `parse()` 的整文档良构校验不一致。

### TDD 顺序（红→绿）

- **红**：新增 5 个失败测试并确认全部按当前错误行为失败：
  - `tst_epubparser::readMetadataMissingSpineReturnsEmpty`（缺 spine 的 OPF 带出 dc:title，红）、`readMetadataMalformedOpfReturnsEmpty`（OPF XML 错误带出元数据，红）。
  - `tst_fb2parser::readMetadataOnlyRejectsTrailingXmlError`（description 后正文错配仍返回标题，红）。
  - `tst_parserfactory::readMetadataFb2TrailingXmlReturnsEmpty`（工厂路由 FB2 同红）。
  - `tst_bookimporter::malformedEpubImportsWithFallbackTitle` / `malformedFb2ImportsWithFallbackTitle`（当前标题取 OPF/FB2 元数据而非文件名回退，红）。
- **绿**：实现后全部转绿（见验证节）。

### 改动

#### `src/parsers/EpubParser.cpp`
- `parseOpf`：循环条件加 `&& !r.hasError()`，返回值改为 `!r.hasError() && !out->spineIds.isEmpty()`——XML 良构错误与缺 spine 都判无效，与 `parse()` 的失败语义一致。
- `readMetadata`：检查 `parseOpf` 返回值，失败（缺 spine / XML 错误）直接返回空模型不设错误（标题回退由调用方 BookImporter 处理）；成功路径行为不变（标题空时回退文件名）。

#### `src/parsers/Fb2Parser.cpp`
- `readMetadataOnly`：删除 `<description>` 后的 `break`，完整扫描整份文档并检查 `QXmlStreamReader` error——尾部 XML 错配同样判失败返回空模型（不收集 binary、不分章的开销不变）。

#### 注释同步（无行为变化）
- `EpubParser.h` / `Fb2Parser.h` / `BookImporter.cpp` 的 readMetadata 语义注释更新（"只扫 description"→"完整扫描校验良构"）。

#### BookImporter
- 无需代码改动：`registerBook` 本就按 `meta.title.isEmpty()` 回退文件名、author/publisher 取空——修复后元数据失败自动落入该路径。

### 测试（新增 5 个用例）

- `tst_epubparser`：`readMetadataMissingSpineReturnsEmpty`（minizip 写端构造有效容器 + 缺 spine OPF；断言 title/author/publisher 全空，且 `parse()` 同失败）、`readMetadataMalformedOpfReturnsEmpty`（OPF 元数据后 `<itemref>` 未闭合遇 `</spine>` 的 XML 错误；断言 readMetadata 空、`parse()` 空——锁定 parseOpf hasError 修复）。
- `tst_fb2parser`：`readMetadataOnlyRejectsTrailingXmlError`（description 良构、body 错配；断言元数据全空、`parse()` 同失败）。
- `tst_parserfactory`：`readMetadataFb2TrailingXmlReturnsEmpty`（经 ParserFactory::readMetadata 路由断言同语义）。
- `tst_bookimporter`：`malformedEpubImportsWithFallbackTitle`（缺 spine 与 XML 错误 EPUB 均入库，标题=文件名、author/publisher 空）、`malformedFb2ImportsWithFallbackTitle`（尾部 XML 错误 FB2 入库，标题=文件名、author/publisher 空）。

### 验证（定向 + 回归）

- 构建：`cmake --build build/Qt_6_11_1_for_macOS_Debug --target tst_epubparser tst_fb2parser tst_bookimporter tst_parserfactory -j8` 成功，无新增编译警告。
- 定向套件（ctest 工作目录 build/tests 内直接运行）：
  - `tst_epubparser`：11 passed, 0 failed（红阶段 2 failed → 绿）。
  - `tst_fb2parser`：10 passed, 0 failed（红阶段 1 failed → 绿）。
  - `tst_parserfactory`：13 passed, 0 failed（红阶段 1 failed → 绿）。
  - `tst_bookimporter`：19 passed, 0 failed, 3 skipped（红阶段 2 failed → 绿；3 skipped 为 READDICT_REAL_* 环境变量门控的真实书用例）。
- 相关回归：`tst_bookmanager` 30 passed, 1 skipped；`tst_mobiparser` 7 passed；`tst_textparser` 6 passed；`tst_qml` 252 passed, 0 failed, 4 skipped（与基线一致，parseOpf 改动未破坏正常 EPUB 解析与导入路径）。
- 未改动任务 5 ReaderPage 背景 hunk（本修复不触碰任何 QML 文件）。

## 提交

- 9 个文件一次提交（5 个测试文件 + 4 个实现/注释文件）。
- commit message（简体中文）：「修复任务4：畸形 EPUB/FB2 元数据失败回退文件名与空字段」
