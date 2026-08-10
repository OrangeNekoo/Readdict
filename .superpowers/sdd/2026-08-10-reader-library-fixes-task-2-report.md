# 任务 2 报告：阅读控件点击唤出与方向键焦点链路

- 日期：2026-08-10
- 实现者：impl-flash（opencode-go/deepseek-v4-flash）
- 计划：`docs/superpowers/plans/2026-08-10-reader-library-fixes.md` 任务 2
- 提交：见文末（简体中文 commit）

## 目标回顾

1. 正文宿主显式暴露单击入口；顶部正文区域、底部控制栏原位置和隐藏态正文底部点击均进入同一 `handleContentTap` 状态机。
2. 不破坏文本选择、Flickable 拖动、Sheet 遮罩和按钮点击；拖动超过阈值不误触发唤出。
3. ReaderPage 激活时确保正文获得 active focus；方向键由生产 `Keys.onPressed` 路径处理。测试覆盖 `activeFocus`、真实按键事件入口、上下滚动和左右翻页/翻章。
4. 不把"调用函数"作为唯一的交互测试证据。

## 根因（实测确认）

- **点击唤出失效**：旧实现 `TapHandler` 挂在 `ReaderPage`（Page）层末尾，被正文 `ReaderContent`（Flickable）在 mousePressEvent 中的按压 grab 吞掉——Flickable 作为页面内顶层可接受按压的视觉项抢走独占 grab，Page 层 TapHandler 的 DragThreshold 轻点手势被取消，生产点击永远到不了 `handleContentTap`。新增真实点击测试（`mouseClick(contentView, 5, 50)` 与 `(5, 700)`）在修复前均 FAIL（sheetOpen 保持 false）证实。
- **方向键**：`ReaderContent` 的 `focus:true` + `Keys.onPressed → handleKey` 与 `ReaderPage.onCompleted → content.forceActiveFocus()` 已存在，生产 `keyClick`（走窗口 activeFocusItem → Keys）实测在 push 后即可用；缺口在 **pop 返回路径**（如从 ThemeManagePage 返回）——`onCompleted` 只在首次创建执行，`StackView.onActivated` 未补聚焦，返回后焦点留在弹层/上一页，方向键失效。修复：`StackView.onActivated` 补 `content.forceActiveFocus()`。

## 改动

### `src/ui/qml/ReaderContent.qml`
- 新增 `signal contentTapped(real y)`：正文宿主显式单击入口。
- 新增 `TapHandler`（child of Flickable，同 `PdfReaderPage` 双击检测模式）：
  - `acceptedButtons: Qt.LeftButton` + `gesturePolicy: TapHandler.DragThreshold`——位移超阈值手势取消，Flickable 拖动照常；观察模式不抢 grab，Sheet 遮罩/顶栏/TtsBar/选择工具条按钮点击不受影响。
  - `onTapped: flick.contentTapped(point.position.y)`，`point.position` 为视口坐标（handler 非视觉项，不随内容滚动）。
  - 实测确认：TapHandler 挂 Flickable 表面在 Qt 6.11 下真实轻点可触发（此前"被吞掉"的根因是挂在 Page 层，非 Flickable 内）。

### `src/ui/qml/ReaderPage.qml`
- `ReaderContent` 实例接 `onContentTapped: (y) => page.handleContentTap(content.y + y)`：视口坐标换算回页面坐标（隐藏态 content.y=0 为恒等；Sheet 打开时 content 下移 topToolbar 高仍需换算）。`content` 为本组件 id 词法解析，不可写 `page.content`（id 非父对象属性，写错会 TypeError）。
- 删除旧 Page 层 `TapHandler`（`contentTapHandler` id）与失效的 `property alias contentTapHandler`（无任何外部引用，清理干净）。
- `handleContentTap` 状态机本身不变（sheetOpen/menuOpen 关闭、底部 1/4 唤出、中部开 Sheet），注释更新为桥接新路径。
- `StackView.onActivated` 补 `content.forceActiveFocus()`：首次 push 与 pop 返回都确保正文持有 activeFocus，方向键即开即用。

### `tests/qml/tst_readerpage.qml`（ControlsSummonSmoke 新增 3 用例）
- `test_realClickTopContentSummons`：`mouseClick(contentView, 5, 50)`（正文列左侧留白，命中 Flickable 表面）→ sheetOpen + topToolbar 显示。**修复前 FAIL**。
- `test_realClickHiddenBarStripSummons`：`mouseClick(contentView, 5, 700)`（隐藏控制栏原位置/正文底部）→ 唤出。**修复前 FAIL**。
- `test_realTextSelectionStillWorks`：正文列内真实拖选（press+move+release）→ 选择工具条照常弹出且不误唤出 Sheet（点击桥接不吞选择）。修复前后均 PASS（回归守卫）。

### `tests/qml/tst_e4_keys.qml`（ArrowKeyPagingSmoke 新增 2 用例）
- `test_activeFocusAndProductionKeys`：push 后断言 `contentView.activeFocus === true`；`keyClick(Qt.Key_Down)` 生产 Keys 路径滚动一视口页、`keyClick(Qt.Key_Up)` 回退；multibook 上 `keyClick(Qt.Key_Right/Left)` 生产路径翻章/回章。不调 `handleKey` 注入。
- `test_realDragScrollDoesNotSummon`：`mouseDrag(contentView, 5, 250, 0, -160)`（位移远超 DragThreshold）→ contentY 滚动生效且 sheetOpen 保持 false（拖动不误触唤出、拖动未被桥接拦截）。修复前后均 PASS（回归守卫）。

## 验证

- TDD 顺序：先加真实点击测试并确认**修复前 FAIL**（`test_realClickTopContentSummons`/`test_realClickHiddenBarStripSummons` 报 "returned FALSE"，实证 TapHandler 被吞），再实现最小修复，确认转绿。
- 构建：`cmake --build build/Qt_6_11_1_for_macOS_Debug --target tst_qml -j2` 成功。
- 定向运行（项目实际方式 `tst_qml -input <abs path>`）：
  - `tst_readerpage.qml`：17 passed, 0 failed（连跑 2 次稳定）。
  - `tst_e4_keys.qml`：16 passed, 0 failed（连跑 2 次稳定；ArrowKeyPagingSmoke 首条 QWARN "同名文件已存在于书库" 为既有 fixture 重复导入告警，非本改动引入）。
- 回归（ReaderPage/ReaderContent 相关套件全绿）：tst_u4 18、tst_background 11、tst_highlightsui 24、tst_c4_scroll 8、tst_nav 9、tst_sheets 10、tst_textcolor 7、tst_ttsbar 9。
- 按计划要求跳过全量套件。

## 交互语义确认（测试实测）

- 真实点击顶部正文/隐藏底部热区 → `TapHandler(contentView) → contentTapped → handleContentTap` 统一状态机（顶部正文点中部开 Sheet、底部 1/4 唤出快捷控制栏语义由 handleContentTap 原逻辑保持，未改动）。
- 文本拖选照常弹出工具条（TextEdit selectByMouse 优先于点击桥接，选择语义保留）；正文拖动（mouseDrag）滚动生效且不误唤出。
- 方向键生产链路（keyClick → activeFocusItem=ReaderContent → Keys.onPressed → handleKey）滚动与翻章均可用；pop 返回路径经 onActivated 补聚焦。
- `pageMode` 算法未改动（任务 3 范围外的真正横向分页不实现）。

## 提交

- commit：简体中文 message（见文末）

---

## 复审修复（按钮点击回归）

### 审查发现

ReaderContent 根级 `TapHandler` 覆盖全视口（含 `selectionToolbar`/`colorToolbar` 子按钮）：若轻点命中可见工具条仍发 `contentTapped`，ReaderPage 会连带打开 Sheet，违反"按钮点击不受影响"。

### 实测结论（评审证据）

- 先用探针（真实 `mouseClick` 逐点驱动）验证泄漏是否可复现：划线按钮、色板色块、工具条非按钮内边距、复制按钮共 4 类点击，`contentTapped` 均未触发、sheetOpen 保持 false；仅正文宿主裸表面（左/下边缘留白）触发。Qt 6.11 下 Flickable 对内容区按压的 grab 仲裁会取消根级 TapHandler 的轻点手势——泄漏在当前环境不可复现，但屏蔽依赖该隐式仲裁（不同 Qt 版本/输入设备/未来重构下可能变化）。
- 复现过程中发现既有缺陷（**范围外，未修**）：复制按钮 `onClicked` 引用 `Clipboard`（`Clipboard.text = selText`），全仓库无任何注册（main.cpp/tst_qmlmain.cpp 均无），点击复制抛 QML ReferenceError 且中断后续 `clearSelection()`——选择工具条不收起。建议后续任务单独修复（注册 Clipboard 单例或改经 C++ 剪贴板助手）。

### 修复（`src/ui/qml/ReaderContent.qml`）

- `TapHandler.onTapped` 发送前做视口命中过滤：`toolbarHitTest(vx, vy)` 检查轻点坐标是否落在**可见** `selBar`/`colorBar` 矩形内（`visible` 门控 + `mapToItem` 换算回视口坐标系，与 `point.position` 同坐标系）；命中则不上报 `contentTapped`。工具条按钮自身行为（复制/划线/笔记/选色）完全不受影响。
- 屏蔽由"隐式 grab 仲裁"升级为"显式命中判定"：不依赖 Flickable 按压 grab 的行为细节，任何输入路径（鼠标/触控/未来 Qt 版本）下工具条点击都不可能连带开/关 Sheet。
- 注意点：工具条是 `contentItem` 子项（内容坐标），`mapToItem(flick,0,0)` 正确换算回视口；不可写 `flick.selBar`（id 非属性，会 TypeError 导致全部点击被吞——实现中已实测修正为组件作用域内直接按 id 引用）。

### 回归测试（`tests/qml/tst_readerpage.qml` ControlsSummonSmoke）

- 新增 `test_toolbarButtonClicksDoNotTouchSheet`：打开选择工具条后真实点击「划线」按钮 → 色板展开（按钮行为照常）且 sheetOpen 保持 false；再真实点击色板色块 → 落库一条划线（按钮行为照常）且 sheetOpen 保持 false；用例内清理本次划线（幂等：先清残留首句划线再断言 +1）。
- 保留既有真实正文点击唤出、拖选、拖动、方向键用例（未改）；Sheet 打开态下工具条被 Sheet 全页遮罩盖住（点面板外关闭是 Sheet 自身契约），故本用例只锁定关闭态的按钮点击解耦。

### 验证

- TDD 顺序：先加回归测试运行——当前 Qt 6.11 下按钮点击已受隐式 grab 屏蔽，测试修复前即绿（守卫性质）；修复后显式过滤生效，测试保持绿。修复过程中暴露的 `flick.selBar` 引用错误曾致全部点击被吞（summon 用例 FAIL），按 id 修正后全绿。
- 定向运行（`tst_qml -input <abs path>`）：
  - `tst_readerpage.qml`：18 passed, 0 failed（17 既有 + 1 新增）。
  - `tst_e4_keys.qml`：16 passed, 0 failed。
  - `tst_highlightsui.qml`（工具条/色板最相关套件）：24 passed, 0 failed。
- 构建：`cmake --build build/Qt_6_11_1_for_macOS_Debug --target tst_qml -j2` 成功。

### 提交

- commit：简体中文 message（见文末）

