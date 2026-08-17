# 统一阅读器壳层与 PDF 文本朗读实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 `superpowers:subagent-driven-development` 逐任务实现；每项任务先写失败测试、确认红灯、最小实现、确认绿灯并提交。

**目标：** 让所有书籍格式复用 EPUB 的阅读框架与操作逻辑，并让有文本层的 PDF 支持基于现有 TTS 的逐页朗读；图片型 PDF 禁用朗读且明确说明原因。

**架构：** 新建 `ReaderShell.qml` 作为唯一的格式无关交互层，接收带 capability 与动作方法的 `reader` 适配器对象。`ReaderPage.qml` 保留文本章节、搜索、划线和章节朗读；`PdfReaderPage.qml` 保留 Qt PDF 渲染、缩放、页级进度与安全关闭，新增 PDF 页文本适配。通过 `ReaderTextHelper.splitSentences()` 将既有 C++ `SentenceSplitter` 暴露给 QML，避免在 QML 重写语言规则。

**技术栈：** Qt 6.11.1、Qt Quick / Controls / PDF、Qt TextToSpeech、现有 `SentenceSplitter`、QML QtTest 和 QtTest C++。

---

## 文件职责

- 创建：`src/ui/qml/ReaderShell.qml` — 所有格式共享的顶栏、菜单、面板、TTS 条、中央点击与焦点状态机。
- 修改：`src/ui/qml/ReaderPage.qml` — 将已有文本格式状态与动作绑定到 `ReaderShell`，删除已迁出的壳层重复实现，保留文本专属内容与 Dialog。
- 修改：`src/ui/qml/PdfReaderPage.qml` — 绑定 `ReaderShell`，实现 PDF 页适配器、页码目录、书签和文本 TTS。
- 修改：`src/ui/ReaderTextHelper.h`、`src/ui/ReaderTextHelper.cpp` — 向 QML 暴露现有 `SentenceSplitter` 的句子切分。
- 修改：`CMakeLists.txt` — 将 `ReaderShell.qml` 加入 QML 模块。
- 修改：`tests/CMakeLists.txt` — 添加 `tst_readertexthelper`。
- 创建：`tests/tst_readertexthelper.cpp` — 验证 QML 桥接结果保持 `SentenceSplitter` 的句子边界。
- 修改：`tests/qml/tst_qmlmain.cpp` — 在临时目录生成一个有文本页和一个仅图片页的 PDF fixture，并经 `TestEnv` 暴露 `textPdfSource`、`imagePdfSource`。
- 修改：`tests/qml/tst_main.qml` — 覆盖共享壳层、文本阅读回归、真实 PDF 朗读/续读和图片 PDF 禁用朗读。

## 统一适配器契约

`ReaderShell` 只读取/调用以下稳定成员；不得读取 `ReaderContent`、`PdfScrollablePageView`、`Books.currentChapter` 或自行写进度：

```qml
property var reader
// reader 提供：
// progressText, canGoPrevious, canGoNext,
// canReadAloud, readAloudUnavailableReason,
// supportsContents, supportsSearch, supportsNotes, supportsBookmarks,
// previous(), next(), startReadAloud(), stopReadAloud(),
// openContents(), openSearch(), openNotes(), toggleBookmark()
```

`previousLabel`/`nextLabel` 分别由适配器提供：文本是“上一章/下一章”，PDF 是“上一页/下一页”。Shell 只按照 capability 显示或禁用项：禁用的 PDF 朗读项须显示 `readAloudUnavailableReason`，但不可触发 `Tts.play()`。

---

### 任务 1：把已有句子分割器安全暴露给 QML

**文件：**
- 创建：`tests/tst_readertexthelper.cpp`
- 修改：`tests/CMakeLists.txt`
- 修改：`src/ui/ReaderTextHelper.h`
- 修改：`src/ui/ReaderTextHelper.cpp`

- [ ] **步骤 1：写失败的桥接测试**

创建最小 `ReaderTextHelperTest`，直接调用未来的公开槽。测试中同时验证中文、英文缩写和空白输入：

```cpp
void splitSentencesMatchesParserContract() {
    ReaderTextHelper helper;
    QCOMPARE(helper.splitSentences(u"第一句。第二句！"),
             QStringList({u"第一句。", u"第二句！"}));
    QCOMPARE(helper.splitSentences(u"Dr. Smith reads. Next."),
             QStringList({u"Dr. Smith reads. ", u"Next."}));
    QVERIFY(helper.splitSentences(u" \n\t ").isEmpty());
}
```

在 `tests/CMakeLists.txt` 新增 `tst_readertexthelper`，编译 `ReaderTextHelper.cpp` 与 `SentenceSplitter.cpp`，链接 `Qt6::Test Qt6::Quick Qt6::Gui`，并注册 `add_test`。

- [ ] **步骤 2：确认红灯**

```bash
cmake --build build-nav --target tst_readertexthelper -j2
./build-nav/tests/tst_readertexthelper
```

预期：编译失败，因为 `ReaderTextHelper::splitSentences()` 不存在。

- [ ] **步骤 3：最小实现**

在头文件声明 QML 可调用接口：

```cpp
Q_INVOKABLE QStringList splitSentences(const QString &text) const;
```

在实现文件包含 `parsers/SentenceSplitter.h`，仅转换 `QVector<QString>`：

```cpp
QStringList ReaderTextHelper::splitSentences(const QString &text) const {
    const QVector<QString> sentences = SentenceSplitter::split(text);
    QStringList result;
    result.reserve(sentences.size());
    for (const QString &sentence : sentences)
        if (!sentence.trimmed().isEmpty()) result.append(sentence);
    return result;
}
```

不得复制/改写 `SentenceSplitter` 的缩写、标点或空白规则。

- [ ] **步骤 4：确认绿灯**

```bash
cmake --build build-nav --target tst_readertexthelper -j2
./build-nav/tests/tst_readertexthelper
./build-nav/tests/tst_sentencesplitter
```

预期：两个测试均为 0 failures。

- [ ] **步骤 5：提交**

```bash
git add src/ui/ReaderTextHelper.h src/ui/ReaderTextHelper.cpp \
        tests/tst_readertexthelper.cpp tests/CMakeLists.txt
git commit -m "feat(阅读器): 向QML暴露统一句子分割"
```

---

### 任务 2：实现独立的共享阅读交互壳层

**文件：**
- 创建：`src/ui/qml/ReaderShell.qml`
- 修改：`CMakeLists.txt`
- 修改：`tests/qml/tst_main.qml`

- [ ] **步骤 1：写失败的 QML 壳层契约测试**

在 `tst_main.qml` 新建 `ReaderShellSmoke` 和内联假适配器对象。断言壳层暴露 `topToolbar`、`ttsBar`、`menuOpen`、`sheetOpen`；以假适配器验证：

```qml
adapter.canReadAloud = false
adapter.readAloudUnavailableReason = "当前 PDF 无可朗读文本"
shell.openMenu()
verify(shell.menuItem("read").enabled === false)
compare(shell.menuItem("read").disabledReason, adapter.readAloudUnavailableReason)
verify(Tts.state === 0)
verify(!shell.ttsBar.visible)

adapter.canReadAloud = true
shell.triggerMenuAction("read")
compare(adapter.readCalls, 1)
```

同时断言 `previousLabel`/`nextLabel` 来自适配器，而不是固定章节文案。

- [ ] **步骤 2：确认红灯**

```bash
cmake --build build-nav --target tst_qml -j2
./build-nav/tests/tst_qml -platform offscreen 'ReaderShellSmoke::test_readerShellAdapterContract'
```

预期：组件无法加载，因为 `ReaderShell.qml` 不存在。

- [ ] **步骤 3：最小实现 ReaderShell**

实现 `ReaderShell.qml`，仅包含以下可复用逻辑：

1. `property var reader` 和所有可测试的 `property alias`。
2. 从当前 `ReaderPage` 迁入 `KdTopToolbar`、菜单遮罩、中央点击/hover、自动隐藏计时器、`TtsBar` 和 `Connections { target: Tts }`。
3. 菜单模型从 `reader` 的 capability 和标签构造；`canReadAloud=false` 时“朗读”条目为 disabled，呈现原因，且 `triggerMenuAction("read")` 不调用 `reader.startReadAloud()`。
4. 使用 `focus: true`、`Component.onCompleted` 与 `StackView.onActivated` 恢复可传入的 `contentItem.forceActiveFocus()`；Shell 不抢走 Dialog/输入框焦点。
5. TTS 条只由 `Tts.state !== 0` 显示；其控制按钮仅调用现有 `Tts.play/pause/stop/previous/next`。

不得把主题、字体、正文渲染、PDF 缩放、进度写入或关闭安全逻辑移入 Shell。

- [ ] **步骤 4：注册并确认绿灯**

在 `qt_add_qml_module(... QML_FILES ...)` 中紧邻 `ReaderPage.qml` 添加 `ReaderShell.qml`。运行：

```bash
cmake --build build-nav --target tst_qml Readdict -j2
./build-nav/tests/tst_qml -platform offscreen 'ReaderShellSmoke::test_readerShellAdapterContract'
```

预期：所有 ReaderShellSmoke 用例通过。

- [ ] **步骤 5：提交**

```bash
git add CMakeLists.txt src/ui/qml/ReaderShell.qml tests/qml/tst_main.qml
git commit -m "feat(阅读器): 添加统一阅读交互壳层"
```

---

### 任务 3：将文本阅读页迁移到共享壳层

**文件：**
- 修改：`src/ui/qml/ReaderPage.qml`
- 修改：`tests/qml/tst_main.qml`
- 修改：`tests/qml/tst_e4_keys.qml`

- [ ] **步骤 1：写迁移回归测试**

在 ReaderPage 现有 smoke 用例旁新增：

```qml
verify(page.readerShell !== undefined)
verify(page.readerShell.topToolbar === page.topToolbar)
page.readerShell.triggerMenuAction("read")
tryVerify(function () { return Tts.state === 1 }, 3000)
page.readerShell.triggerMenuAction("next")
tryVerify(function () { return Books.currentChapter === 1 }, 3000)
```

在 `tst_e4_keys.qml` 保持并运行 `test_activeFocusAndProductionKeys`，确保迁移后 QML 生产 `keyClick` 路径仍到达 `ReaderContent.handleKey()`。

- [ ] **步骤 2：确认红灯**

```bash
cmake --build build-nav --target tst_qml -j2
./build-nav/tests/tst_qml -platform offscreen \
  'ReaderPageSmoke::test_readerUsesSharedShell' \
  'ArrowKeyPagingSmoke::test_activeFocusAndProductionKeys'
```

预期：第一用例失败，因为 ReaderPage 尚未提供 `readerShell`。

- [ ] **步骤 3：最小迁移实现**

1. 在 ReaderPage 定义单个文本适配器对象，提供统一契约。它映射 `previous()/next()` 到已有 `loadChapter()` + 视口定位，映射 `startReadAloud()` 到既有 `startReadAloud()`，映射目录、搜索、笔记和书签到原有 Dialog/函数。
2. 将现有顶栏、菜单、`TtsBar`、hover/点击控制状态机与 `KdBottomSheet` 壳层移动到 `ReaderShell` 的内容槽/属性；保留 ThemeSheet、FontSheet、LayoutSheet、MoreSheet 及全部文本 Dialog 在 ReaderPage，由 Shell 的 slots 承载。
3. ReaderContent 保留全文正文、连续滚动、分页、划线和 TTS 句子跟随；其点击信号传给 Shell 的统一动作。
4. 保留公开 alias（`topToolbar`、`backButton`、`ttsBar`、`notesDialog`、`searchDialog`、`tocDlg`、`contentView`）以迁移所有现有测试和调用者；不得留双份顶栏/菜单/朗读条。

- [ ] **步骤 4：确认文本回归绿灯**

```bash
cmake --build build-nav --target tst_qml -j2
./build-nav/tests/tst_qml -platform offscreen \
  'ReaderPageSmoke::test_readerUsesSharedShell' \
  'ArrowKeyPagingSmoke::test_activeFocusAndProductionKeys' \
  'ArrowKeyPagingSmoke::test_modeSpecificWasdKeys' \
  'PagedModeSmoke::test_modeSpecificWasdKeys'
```

预期：文本阅读页、生产键盘焦点、滚动/分页 WASD、跨章和 TTS 相关用例全部通过。

- [ ] **步骤 5：提交**

```bash
git add src/ui/qml/ReaderPage.qml tests/qml/tst_main.qml tests/qml/tst_e4_keys.qml
git commit -m "refactor(阅读器): 文本阅读页接入统一壳层"
```

---

### 任务 4：将 PDF 迁移到共享壳层并实现文本朗读

**文件：**
- 修改：`src/ui/qml/PdfReaderPage.qml`
- 修改：`tests/qml/tst_qmlmain.cpp`
- 修改：`tests/qml/tst_main.qml`

- [ ] **步骤 1：生成确定性 PDF 测试夹具并写失败测试**

在 `TestEnv` 构造中用 `QPdfWriter` + `QPainter` 创建：

- 两页 `text_pdf_fixture.pdf`：每页绘制不同可提取文本，至少包含两个句子。
- 一页 `image_pdf_fixture.pdf`：仅绘制 `QImage`，不调用 `drawText()`。

通过 `Q_PROPERTY(QString textPdfSource ...)` 和 `imagePdfSource` 暴露本地路径。新增 QML 测试：

```qml
page.book = { id: 999101, title: "文本PDF", path: TestEnv.textPdfSource }
tryVerify(function () { return page.pdfDocument.status === PdfDocument.Ready }, 15000)
tryVerify(function () { return page.readerAdapter.canReadAloud }, 3000)
page.readerShell.triggerMenuAction("read")
tryVerify(function () { return Tts.state === 1 }, 3000)

page.book = { id: 999102, title: "图片PDF", path: TestEnv.imagePdfSource }
tryVerify(function () { return page.pdfDocument.status === PdfDocument.Ready }, 15000)
verify(!page.readerAdapter.canReadAloud)
compare(page.readerAdapter.readAloudUnavailableReason, "当前 PDF 无可朗读文本")
verify(!page.readerShell.menuItem("read").enabled)
compare(Tts.state, 0)
verify(!page.readerShell.ttsBar.visible)
```

为文本 PDF 加入生产 `keyClick(D)` 前进、TTS 读完一页后的页级自动推进、手动翻页停止 TTS、以及 `renderSettled` 关闭安全回归。为 PDF 断言共享 Shell 的顶栏和菜单对象存在。

- [ ] **步骤 2：确认红灯**

```bash
cmake --build build-nav --target tst_qml -j2
./build-nav/tests/tst_qml -platform offscreen \
  'PdfReaderSmoke::test_textPdfCanReadAloud' \
  'PdfReaderSmoke::test_imagePdfDisablesReadAloud'
```

预期：当前实现没有 `ReaderShell`、`readerAdapter`、`getAllText()` 和测试夹具属性，新增用例失败。

- [ ] **步骤 3：最小 PDF 适配器实现**

1. `PdfReaderPage` 创建 `readerAdapter`，实现统一契约：
   - 上一/下一项为 `previousPage()`/`nextPage()`，标签为“上一页/下一页”。
   - `progressText` 复用当前页/总页数；目录显示 `pdfDoc.pageLabel(i)`，跳转使用 `goToPage(i)`。
   - 书签保存 `bookmarks/pdf_<bookId>` 的页索引；只开放已经有真实操作语义的能力。
2. 在 `PdfDocument.Ready` 和 `pdfView.currentPageChanged` 后调用 `pdfDoc.getAllText(currentPage)`；只在 Ready 时读取，使用 `ReaderText.splitSentences(text)` 填充页句子并更新 `canReadAloud`/不可用原因。
3. `startReadAloud()` 先验证文本可用，再 `Tts.setSentences(pdfSentences)`、`Tts.setChapter(currentPage)`、`Tts.setCurrentIndex(0)`、`Tts.play()`。不得在空文本时触碰 TTS。
4. PDF 专用 `Connections { target: Tts }` 只在该 PDF 页拥有活动会话时处理 `chapterCompleted`：寻找下一含文本页，跳转、重提取、重新设置句子并续播；没有后续文本时 `Tts.stop()` 并通过 Shell 显示“后续 PDF 页面无可朗读文本”。
5. 任何手动 `previousPage()`/`nextPage()`、目录跳转、返回或 Error 都必须停止 PDF 活动会话，防止旧页继续发声。
6. 迁出自定义 PDF 顶栏、`KdDropdownMenu` 和独立 TTS 逻辑；PDF 缩放操作进入共享菜单的 PDF 专属 action 槽。保留 `scaleToWidth()`、`scaleToPage()`、`resetScale()`、Ready 后恢复页和 `requestClose()` 的渲染安全等待。

- [ ] **步骤 4：确认 PDF 绿灯与实际应用构建**

```bash
cmake --build build-nav --target Readdict tst_qml -j2
./build-nav/tests/tst_qml -platform offscreen \
  'PdfReaderSmoke::test_textPdfCanReadAloud' \
  'PdfReaderSmoke::test_imagePdfDisablesReadAloud' \
  'PdfReaderSmoke::test_pdfKeyNavChangesPageWithActiveFocus' \
  'PdfReaderSmoke::test_pdfCloseWaitsRender'
```

预期：文本 PDF 朗读及跨页续读通过；图片 PDF 朗读明确禁用；加载、缩放、页码、键盘、进度恢复、重试和关闭竞态用例无失败。

- [ ] **步骤 5：提交**

```bash
git add src/ui/qml/PdfReaderPage.qml tests/qml/tst_qmlmain.cpp tests/qml/tst_main.qml
git commit -m "feat(PDF): 接入统一阅读器与文本朗读"
```

---

### 任务 5：端到端回归与跨平台边界检查

**文件：** 仅修复由前四项引入的回归；无新功能文件。

- [ ] **步骤 1：完整构建**

```bash
cmake --build build-nav --target Readdict tst_qml tst_readertexthelper -j2
```

- [ ] **步骤 2：运行针对性测试集**

```bash
./build-nav/tests/tst_readertexthelper
./build-nav/tests/tst_sentencesplitter
./build-nav/tests/tst_qml -platform offscreen \
  'ReaderShellSmoke::test_readerShellAdapterContract' \
  'ReaderPageSmoke::test_readerUsesSharedShell' \
  'PdfReaderSmoke::test_textPdfCanReadAloud' \
  'PdfReaderSmoke::test_imagePdfDisablesReadAloud' \
  'PdfReaderSmoke::test_pdfKeyNavChangesPageWithActiveFocus' \
  'PdfReaderSmoke::test_pdfCloseWaitsRender' \
  'ArrowKeyPagingSmoke::test_activeFocusAndProductionKeys' \
  'ArrowKeyPagingSmoke::test_modeSpecificWasdKeys' \
  'PagedModeSmoke::test_modeSpecificWasdKeys'
```

- [ ] **步骤 3：检查不支持能力未被伪装开放**

确认图片 fixture 满足以下可观察结果：朗读项 disabled、原因精确为“当前 PDF 无可朗读文本”、`Tts.state` 仍为 0、`TtsBar.visible` 为 false。确认 PDF 未新增 OCR、平台条件分支、私有 Qt API 或第三方依赖。

- [ ] **步骤 4：提交只由回归修复产生的差异**

```bash
git add <仅本计划修改的文件>
git commit -m "fix(阅读器): 修复统一壳层回归"
```

若无回归差异，不创建空提交。
