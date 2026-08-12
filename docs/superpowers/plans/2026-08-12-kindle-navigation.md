# Kindle 风格导航优化实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 将 Readdict 的主导航收敛为 Kindle 风格的“主页/图书馆”双导航，统一辅助页面和阅读层的进入、返回与状态同步。

**架构：** 保留现有 QML `StackView`，由 `Main.qml` 成为唯一导航协调者。主页和图书馆是主导航上下文，统计、同步、设置等是辅助层，EPUB/PDF 阅读器是独立阅读层。底部导航只显示主页、图书馆和当前阅读入口，不新增侧边栏；书籍卡片采用 Kindle 视觉层级并按窗口宽度自适应排列。

**技术栈：** Qt 6.11.1、QML、Qt Quick Controls 2、C++ 后端状态接口、现有 Qt Test/QML 测试基础设施。

---

## 文件职责

- 修改：`src/ui/qml/Main.qml`，集中实现主导航上下文、辅助层/阅读层边界、统一返回和重复压栈保护。
- 修改：`src/ui/qml/KdBottomTabs.qml`，将主导航项目收敛为主页和图书馆，并保留当前阅读入口的独立操作语义。
- 修改：`src/ui/qml/HomePage.qml`，按 Kindle 层级组织最近阅读区域，所有书籍打开动作走 Main.qml 统一阅读入口。
- 修改：`src/ui/qml/ShelfPage.qml`，按 Kindle 风格提供搜索、筛选/排序和响应式书籍网格，页面状态可在主导航往返中保留。
- 修改：`src/ui/qml/BookCard.qml`，固定卡片边界，避免标题、进度和状态标识改变网格尺寸。
- 修改：`src/ui/qml/ReaderPage.qml`，接入统一阅读层返回和工具栏显隐语义。
- 修改：`src/ui/qml/PdfReaderPage.qml`，与普通阅读器使用相同的阅读层边界和返回语义。
- 修改：`src/ui/qml/KdTopToolbar.qml`，提供阅读层返回入口，并保持工具栏默认隐藏、点击阅读区域唤出。
- 修改：`src/ui/qml/KdTopSearchBar.qml`，使主页输入搜索时通过统一导航切换到图书馆，并传递搜索文本。
- 修改：`tests/CMakeLists.txt`，仅在已有测试组织方式下登记新增导航行为测试。
- 创建：`tests/tst_navigation.cpp`，验证导航状态机的可观察行为；不复制 QML 视觉实现。

## 任务 1：建立可测试的导航状态契约

**文件：**
- 创建：`tests/tst_navigation.cpp`
- 修改：`tests/CMakeLists.txt`
- 参考：`src/ui/qml/Main.qml:47-84`

- [ ] **步骤 1：编写失败测试，覆盖导航状态转换**

测试使用现有 Qt Test 约定，构造一个最小的导航状态对象或可测试的 QML 状态接口，覆盖以下转换：

```cpp
void NavigationTest::mainTabsDoNotDuplicatePages();
void NavigationTest::auxiliaryPageReturnsToOriginTab();
void NavigationTest::readerReturnsToOriginTab();
void NavigationTest::unsupportedBookDoesNotChangeNavigation();
void NavigationTest::searchFromHomeTargetsShelf();
```

断言必须检查：目标主页面重复点击不增加页面实例；辅助页和阅读页返回原主导航上下文；不支持格式保持原页面；主页搜索切换到图书馆并传递文本。

- [ ] **步骤 2：运行单测确认失败**

运行：

```bash
cmake --build build --target tst_navigation
ctest --test-dir build -R tst_navigation --output-on-failure
```

预期：测试目标尚未存在或新契约失败；不得用跳过测试掩盖失败。

- [ ] **步骤 3：定义最小导航状态接口**

在 `Main.qml` 内将导航逻辑收敛为以下可观察函数/属性，名称在后续任务中保持一致：

```qml
property string currentNavId: "home"
property string returnNavId: "home"
property bool navVisible: true

function navigateTo(navId)
function openAuxiliary(pageUrl)
function openBook(book)
function goBack()
function syncNav()
```

`navigateTo()` 只处理 `home`/`shelf`；`openAuxiliary()` 记录当前主导航后打开辅助页；`openBook()` 校验格式后记录当前主导航并打开 EPUB 类或 PDF 阅读器；`goBack()` 关闭当前层并恢复主导航状态。

- [ ] **步骤 4：运行测试确认基础契约通过**

运行同一组 `tst_navigation` 命令。预期：状态转换测试通过；尚未覆盖的 QML 页面交互测试保留为后续任务。

- [ ] **步骤 5：Commit**

```bash
git add tests/tst_navigation.cpp tests/CMakeLists.txt src/ui/qml/Main.qml
git commit -m "test: define navigation state contract"
```

## 任务 2：实现主页/图书馆双导航和辅助页面路由

**文件：**
- 修改：`src/ui/qml/Main.qml`
- 修改：`src/ui/qml/KdBottomTabs.qml`
- 修改：`src/ui/qml/KdTopSearchBar.qml`
- 修改：`src/ui/qml/HomePage.qml`
- 修改：`src/ui/qml/ShelfPage.qml`

- [ ] **步骤 1：清点所有直接压栈入口**

在上述 QML 文件中逐一替换直接操作 `StackView.view.push()`、直接修改导航选中状态、重复打开辅助页面的入口。每个入口明确归类为 `navigateTo()`、`openAuxiliary()`、`openBook()` 或弹窗操作。

- [ ] **步骤 2：实现主导航切换规则**

`navigateTo(navId)` 必须：

```qml
if (navId !== "home" && navId !== "shelf") return
if (stack.currentItem && stack.currentItem.navId === navId) return
while (stack.depth > 1) stack.pop(null, StackView.Immediate)
stack.replace(root.navPages[navId], StackView.Immediate)
root.syncNav()
```

实际实现必须保留现有 QML 页面加载方式，并确保目标页面只存在一个实例。底部导航只发出 `tabClicked(id)`，不自行维护主导航业务状态。

- [ ] **步骤 3：统一辅助页面入口**

右上角菜单的统计、同步和设置都调用 `openAuxiliary()`；菜单关闭后不再重复压栈。辅助页面返回调用 `goBack()`，回到记录的 `returnNavId`。

- [ ] **步骤 4：统一搜索切换**

主页搜索输入非空时调用 `navigateTo("shelf")`，再把文本传给图书馆的搜索状态。图书馆搜索输入只刷新图书馆结果，不重复创建页面。清空搜索时保留图书馆上下文。

- [ ] **步骤 5：运行导航单测和应用烟测**

运行：

```bash
cmake --build build --target Readdict tst_navigation
ctest --test-dir build -R tst_navigation --output-on-failure
```

启动 `Readdict`，手动验证主页/图书馆重复切换、菜单进入统计/设置/同步后返回、主页搜索切换图书馆。预期页面不重复压栈，底部选中项始终对应栈顶主页面。

- [ ] **步骤 6：Commit**

```bash
git add src/ui/qml/Main.qml src/ui/qml/KdBottomTabs.qml src/ui/qml/KdTopSearchBar.qml src/ui/qml/HomePage.qml src/ui/qml/ShelfPage.qml
git commit -m "fix: unify home and library navigation"
```

## 任务 3：实现 Kindle 风格主页和自适应图书馆卡片

**文件：**
- 修改：`src/ui/qml/HomePage.qml`
- 修改：`src/ui/qml/ShelfPage.qml`
- 修改：`src/ui/qml/BookCard.qml`

- [ ] **步骤 1：锁定卡片尺寸和文本边界**

`BookCard.qml` 使用稳定的 `implicitWidth`/`implicitHeight` 或显式宽高约束；标题、作者和进度信息使用省略或固定行数，不允许文本内容撑大卡片。进度标识和操作入口固定在卡片内部边界。

- [ ] **步骤 2：实现主页 Kindle 层级**

主页按顶部搜索、最近阅读标题、横向书籍卡片、继续阅读入口和底部导航的层级排列。最近阅读卡片点击统一调用 `root.openBook(book)`，不直接操作 `StackView`。

- [ ] **步骤 3：实现图书馆自适应网格**

图书馆使用现有 Qt Quick 布局组件计算可用宽度和列数。卡片采用 Kindle 风格边框和状态表达；窗口变宽时增加网格列数或调整列宽，但不创建侧边栏，不让卡片超出内容区域。

- [ ] **步骤 4：验证窗口边界**

在最小窗口、默认窗口和宽窗口下运行应用，检查卡片不重叠、不溢出、标题和进度标识不跳动；检查搜索、筛选和排序状态切换后卡片布局仍稳定。

- [ ] **步骤 5：Commit**

```bash
git add src/ui/qml/HomePage.qml src/ui/qml/ShelfPage.qml src/ui/qml/BookCard.qml
git commit -m "feat: apply Kindle library layout"
```

## 任务 4：统一普通阅读器和 PDF 阅读器边界

**文件：**
- 修改：`src/ui/qml/Main.qml`
- 修改：`src/ui/qml/ReaderPage.qml`
- 修改：`src/ui/qml/PdfReaderPage.qml`
- 修改：`src/ui/qml/KdTopToolbar.qml`

- [ ] **步骤 1：实现统一阅读入口**

`openBook(book)` 只接受已有书籍对象；格式为空或不支持时保持当前页面并调用现有错误反馈。PDF 使用 `PdfReaderPage.qml`，其他已支持格式使用 `ReaderPage.qml`。入口记录 `returnNavId`，不创建重复主页面。

- [ ] **步骤 2：实现阅读层显隐规则**

进入普通阅读器或 PDF 阅读器时设置 `navVisible = false`；离开阅读层后由 `syncNav()` 恢复。阅读工具栏默认隐藏，点击阅读区域只切换工具栏显隐，不影响 StackView。

- [ ] **步骤 3：统一返回路径**

顶部返回按钮、键盘 Escape/Back 和窗口关闭阅读层的 QML 入口都调用 `goBack()`。`goBack()` 优先关闭阅读层；若当前是辅助页则关闭辅助页；主页面不再继续 pop 到空栈。

- [ ] **步骤 4：运行阅读路径验证**

启动应用，从主页打开 EPUB 和 PDF，再从图书馆打开 EPUB 和 PDF。分别验证底部导航隐藏、工具栏显隐、返回后回到原主页面、搜索/筛选上下文未被清空。

- [ ] **步骤 5：Commit**

```bash
git add src/ui/qml/Main.qml src/ui/qml/ReaderPage.qml src/ui/qml/PdfReaderPage.qml src/ui/qml/KdTopToolbar.qml
git commit -m "fix: isolate reader navigation layer"
```

## 任务 5：跨平台构建与完整验收

**文件：**
- 修改：仅在构建失败明确属于导航改动时修改 `CMakeLists.txt` 或 `tests/CMakeLists.txt`
- 测试：`tests/tst_navigation.cpp` 及现有受影响测试

- [ ] **步骤 1：运行导航专项测试**

```bash
cmake --build build --target tst_navigation Readdict
ctest --test-dir build -R 'tst_navigation|tst_bookmanager|tst_database' --output-on-failure
```

预期：导航契约和受影响的书籍状态测试通过。

- [ ] **步骤 2：执行 macOS ARM 烟测**

使用已配置的 Qt 6.11.1 构建并运行应用，完成主页/图书馆切换、菜单辅助页往返、搜索切换、EPUB/PDF 阅读往返和窗口宽度检查。若 Qt 组件缺失，停止并报告缺失组件，不安装任何库。

- [ ] **步骤 3：执行 Windows/Linux 配置检查**

使用项目现有 CMake 配置确认导航代码不依赖平台专有 API；不在当前 macOS 环境模拟不存在的系统组件。保留跨平台 Qt 类型、键盘事件和 QML 路径。

- [ ] **步骤 4：检查规格覆盖和改动范围**

确认设计规格中的每项契约都有对应实现或测试：双主导航、无侧边栏、Kindle 层级、自适应卡片、辅助页面菜单、独立阅读层、统一返回、重复点击保护、搜索传递、跨平台边界和非目标范围。

- [ ] **步骤 5：Commit**

```bash
git add tests src/ui/qml
 git commit -m "test: verify Kindle navigation flows"
```
