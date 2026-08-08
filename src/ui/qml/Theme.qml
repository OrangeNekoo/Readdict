import QtQuick
pragma Singleton

// Kindle 设计 Token 单例（任务 U1，后续 U2-U6 所有 Kindle 化 UI 的基础）。
// 值来源：.superpowers/sdd/kindel-ui-analysis.md §7（mimo 视觉分析，Token 唯一来源）；
// 深色映射见任务 U1 描述（bg #1E1E1E、bgSec #262626、text #E8E8E3、textSec #9A9A9A、
// border #3A3A3A、active #E8E8E3、divider #333333，Kindle 深色系）。
// U6 会审计 Token 命名/值一致性——修改前先对照 §7 与 U1 报告。
//
// 机制：QML 文件单例，经 qmlRegisterSingletonType(QUrl) 注册为 Readdict.UI/UITheme
//（main.cpp 与 tst_qmlmain.cpp 各注册一次，与 Books/Settings 等同机制）。
// pragma Singleton 为 QUrl 单例注册所必需（否则引擎报 "qmldir defines type as
// singleton, but no pragma Singleton found"）。页面统一 `import Readdict.UI 1.0`
// 引用 UITheme（不 import Readdict 模块引用模块侧 Theme，避免双实例）。
QtObject {
    id: theme

    // ---- 深浅开关：唯一可变属性（Main.applyTheme / Component.onCompleted 写入）；
    // 只读 Token 经此解析到浅/深两套。----
    property bool isDark: false

    // ================= 浅色 Token（Kindle 暖白系，§7）=================
    readonly property color lightBgPrimary: "#F5F5F0"      // 暖白主背景
    readonly property color lightBgSecondary: "#EDECEB"    // 设置页背景（略深）
    readonly property color lightBgSearch: "#E8E8E3"       // 搜索框背景
    readonly property color lightTextPrimary: "#1A1A1A"    // 主文字（近黑）
    readonly property color lightTextSecondary: "#888888"  // 辅助文字（中灰）
    readonly property color lightTextDisabled: "#BBBBBB"   // 不可用文字（浅灰）
    readonly property color lightBorderDefault: "#CCCCCC"  // 默认边框（浅灰）
    readonly property color lightBorderActive: "#1A1A1A"   // 选中/激活边框（黑）
    readonly property color lightDivider: "#E0E0E0"        // 分隔线（浅灰）
    // 阅读米白纸色（ReaderBackground paper 模式）：沿袭既有实现 #F5EFE0，对应 Kindle
    // 主题预设「米白」。§7 主集仅含一个暖白（bg-primary），故作为派生 Token 记录于此
    //（U1 决策：保留 paper 与 light 的区分，而非把 paper 并入 bgPrimary）。
    readonly property color lightBgPaper: "#F5EFE0"

    // ================= 深色 Token（Kindle 深色系，任务映射）=================
    readonly property color darkBgPrimary: "#1E1E1E"
    readonly property color darkBgSecondary: "#262626"
    // 深色搜索框背景：任务映射未给出，取 bgSecondary 与 border 之间的中性灰（派生值）
    readonly property color darkBgSearch: "#333333"
    readonly property color darkTextPrimary: "#E8E8E3"
    readonly property color darkTextSecondary: "#9A9A9A"
    // 深色不可用文字：弱于 textSec 的灰（派生值）
    readonly property color darkTextDisabled: "#666666"
    readonly property color darkBorderDefault: "#3A3A3A"
    readonly property color darkBorderActive: "#E8E8E3"
    readonly property color darkDivider: "#333333"
    // 深色米白纸：暖调近黑，与 bgPrimary 区分（paper 模式深色兜底，派生值）
    readonly property color darkBgPaper: "#2A2A26"

    // ================= 遮罩/投影（两模式共用，§7）=================
    readonly property color overlay: "#4D000000"     // rgba(0,0,0,0.3) → #4D000000
    readonly property color shadowBook: "#14000000"  // rgba(0,0,0,0.08) → #14000000

    // ================= 解析到当前深浅的 Token（页面引用这些）=================
    readonly property color bgPrimary: isDark ? darkBgPrimary : lightBgPrimary
    readonly property color bgSecondary: isDark ? darkBgSecondary : lightBgSecondary
    readonly property color bgSearch: isDark ? darkBgSearch : lightBgSearch
    readonly property color bgPaper: isDark ? darkBgPaper : lightBgPaper
    readonly property color textPrimary: isDark ? darkTextPrimary : lightTextPrimary
    readonly property color textSecondary: isDark ? darkTextSecondary : lightTextSecondary
    readonly property color textDisabled: isDark ? darkTextDisabled : lightTextDisabled
    readonly property color borderDefault: isDark ? darkBorderDefault : lightBorderDefault
    readonly property color borderActive: isDark ? darkBorderActive : lightBorderActive
    readonly property color divider: isDark ? darkDivider : lightDivider

    // ================= 字体层级（§7 Typography；px，Bold = 700）=================
    readonly property int fsPageTitle: 24     // 22-24 Bold（页面大标题）
    readonly property int fsSectionTitle: 20  // 20-22 Bold（分区标题）
    readonly property int fsTabNav: 17        // 16-18（选中 Bold / 未选中 Regular）
    readonly property int fsBody: 19          // 18-20 Regular（阅读正文基准，阅读页按排版设置可调）
    readonly property int fsListItem: 15      // 15-16 Regular（列表项/菜单项）
    readonly property int fsCaption: 13       // 12-14 Regular（辅助文字/作者行/当前值）

    // ================= 间距（§7 Spacing；px）=================
    readonly property int pageMargin: 22      // 20-24 阅读页左右边距
    readonly property int sectionGap: 16      // 分区间距
    readonly property int itemGap: 12         // 12-16 条目间距
    readonly property real lineHeight: 1.7    // 1.6-1.8 阅读行高（倍）
}
