# U2 实现报告：Main 导航体系与 HomePage

## 状态
已完成 U2 范围：主页、顶部搜索/菜单、底部主页/图书馆标签与悬浮最近阅读封面、沉浸式阅读导航，以及测试和 QML/CMake 资源同步。

## 实现内容
- 新建 `src/ui/qml/HomePage.qml`：使用 `Books.recentBooks(6)` 横排展示 compact 书卡；统计摘要点击进入 `StatsPage.qml`；书卡按 PDF/文本格式进入对应阅读页。
- `BookCard.qml` 增加 `compact` 属性。compact 卡片自适应小尺寸并隐藏作者行、进度条，普通书库卡片行为保持不变。
- 重做 `Main.qml`：保留主题三态、`effectiveDark`/`UITheme`、`navPages`、`navigateTo` 栈清理和 `navStack`；StackView 初始 `HomePage.qml`；接入 `KdTopSearchBar`、`KdDropdownMenu`、`KdBottomTabs`；菜单接入导入/统计/同步/设置/关于；阅读器和 PDF 页沉浸隐藏导航；底部封面可恢复最近阅读。
- 删除 `KdBottomNav.qml`，根模块及 `tst_qml` 资源清单移除旧组件并加入 `HomePage.qml`。
- `tests/qml/tst_nav.qml` 改用新底部标签句柄，覆盖 `currentId`、主页/图书馆真实点击、最近阅读悬浮封面点击恢复 ReaderPage。

## 验证
- `cmake --build build -j2`：通过。
- `ctest --test-dir build -R tst_qml --output-on-failure`：通过（1/1，完整 QML 套件）。

## 已知输出
QML 套件仍会打印既有 `ShelfPage.qml:254` 的 `TypeError` 警告及测试环境字体/文件提示，但本次完整测试通过，未新增失败。


## 修复轮（基于 c66fdf7）
- `KdBottomTabs` 将绝对封面路径转换为 `file://`，已有 `file:/`、`qrc:/`、HTTP(S) URL 原样保留；`tst_nav` 增加 file URL 断言，并选择确定的非 PDF 测试书。
- `HomePage` 增加 `recentBooksModel`/`refreshData()`，监听 `Books.booksChanged` 与 `readingActivityChanged`，刷新最近阅读和统计摘要。
- `BookManager::reportProgress` 在不回退进度的成功分支 emit `readingActivityChanged()`，不 emit `booksChanged()`；新增单元测试锁定该信号语义。Main 同步监听该信号。
- 清理 `KdIcons.qml` 中已删除旧底部导航组件名称。

## 修复轮验证
- `cmake --build build --target tst_qml --parallel`：通过。
- `ctest --test-dir build -R 'tst_bookmanager|tst_qml' --output-on-failure`：通过。