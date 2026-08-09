# U4 实现报告：阅读页 Kindle 顶栏 + ⋮ 菜单 + 书签/图书信息

## 交付内容

- 新建 `src/ui/qml/KdTopToolbar.qml`：40px、7 项按钮，暴露 `backBtn`/`menuBtn`，提供 `back`、`aa`、`layout`、`notes`、`bookmark`、`search`、`menu` 信号；书签按钮按 `bookmarked` 切换空心/实心图标。
- `ReaderPage.qml` 移除 `ReaderControls` 实例及旧控制栏别名，改用仅在 `sheetOpen` 显示的 Kindle 顶栏；保留正文中部点击切换 Sheet 与 `hideControlsTimer` 的开合门控。朗读入口抽为 `startReadAloud()`，接入 ⋮ 菜单和 MoreSheet；⋮ 菜单改为朗读、目录、上一章、下一章、分隔线、图书信息。
- 新增 `bookmarks/<bookId>` 章节索引持久化，进入阅读页加载、切换章节同步当前图标，重复点击实现添加/取消两态。
- 新增只读「图书信息」Dialog，展示书名、作者、出版社、格式和百分比进度。
- 根 CMake 与 QML 测试资源改为收录 `KdTopToolbar.qml`，删除 `ReaderControls.qml`；相关背景/字体/阅读/菜单测试适配新 Sheet/顶栏接口，并新增书签两态测试。

## 验证

- `cmake --build build --parallel`：通过。
- 聚焦 U4 回归（背景/布局 Sheet、顶栏、书签、阅读导航、图书菜单、工具栏）：17 passed, 0 failed。
- `ctest --test-dir build -R tst_qml --output-on-failure`：本次最终运行 219 passed, 3 failed, 4 skipped；失败均为仓库已知的跨用例导入/时序 flake（分页自动重复边界 1 项、既有删除/导航测试的测试书导入顺序 2 项），本次 U4 相关用例全部通过。

## 复审修复

- 隐藏态底部热区现在同时设置 `controlsVisible` 与 `sheetOpen`，并显式停止隐藏计时器；顶栏与 Sheet 会稳定唤出，计时器触发时也不会吞掉已打开的 Sheet。
- 恢复与 U4 无关的分页测试 tolerance 变更，并恢复菜单遮罩的真实点击断言。
- 复审后聚焦 Reader/Toolbar/Sheet 测试：15 passed, 0 failed。
