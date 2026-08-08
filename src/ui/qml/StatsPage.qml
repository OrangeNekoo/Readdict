import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Readdict.Backend
import Readdict.UI 1.0

// D4：阅读统计页。数据来自 Books.stats()（BookManager 聚合查询：COUNT/SUM/AVG +
// 分类 GROUP BY）。卡片网格：总藏书、累计阅读时长（秒 → "X 小时 Y 分"）、平均进度
// 进度条、分类分布（横向柱条宽度按占比）。进入页面时读取一次（StackView push 每次
// 新建实例，Component.onCompleted 保证数据新鲜；B10 计时在离开阅读页时已结算）。
// 测试/外部句柄：refresh() 重新读取、statsData 持有最近结果、formatDuration 秒格式化
//（SettingsPage/SyncPage 同模式）。
Page {
    id: page
    title: qsTr("阅读统计")
    // 最近一次 Books.stats() 结果（QVariantMap；QML 冒烟经此断言数字正确性）
    property var statsData: ({})

    // 卡片样式：Material 表面色 + 数值大号展示，children 落入 ColumnLayout 排版
    //（内联组件须声明在对象作用域内——qmllint/qmlcachegen 对文件顶层内联组件报语法错）
    component StatCard: Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 116
        radius: 8
        color: Material.theme === Material.Dark ? "#263238" : "#F5F5F5"
        border.color: Material.theme === Material.Dark ? "#37474F" : "#E0E0E0"
        border.width: 1
        default property alias content: cardContent.data
        ColumnLayout {
            id: cardContent
            anchors.fill: parent
            anchors.margins: 16
            spacing: 4
        }
    }

    function refresh() { page.statsData = Books.stats() }
    // 秒 → "X 小时 Y 分"（负值/缺失兜底 0，空库显示 "0 小时 0 分"）
    function formatDuration(seconds) {
        const s = Math.max(0, Math.floor(Number(seconds) || 0))
        return qsTr("%1 小时 %2 分").arg(Math.floor(s / 3600)).arg(Math.floor((s % 3600) / 60))
    }
    function totalBookCount() { return Number(page.statsData.totalBooks || 0) }
    // 分类占比：该分类数量 / 总藏书（柱条宽度按占比）
    function categoryRatio(c) {
        const t = page.totalBookCount()
        return t > 0 ? Number(c.count || 0) / t : 0
    }

    Component.onCompleted: page.refresh()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        RowLayout {
            Button {
                text: qsTr("返回")
                onClicked: page.StackView.view.pop()
            }
            Label {
                text: qsTr("阅读统计")
                font.bold: true
                font.pixelSize: 18
            }
        }

        // 卡片网格：两列等高卡片
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 16
            rowSpacing: 16

            StatCard {
                Label { text: qsTr("总藏书"); color: Material.secondaryTextColor }
                Label {
                    text: page.totalBookCount()
                    font.pixelSize: 30
                    font.bold: true
                }
            }
            StatCard {
                Label { text: qsTr("累计阅读时长"); color: Material.secondaryTextColor }
                Label {
                    text: page.formatDuration(page.statsData.totalReadSeconds)
                    font.pixelSize: 24
                    font.bold: true
                }
            }
            StatCard {
                Label { text: qsTr("平均进度"); color: Material.secondaryTextColor }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    ProgressBar {
                        Layout.fillWidth: true
                        from: 0; to: 1
                        value: Number(page.statsData.totalProgress || 0)
                    }
                    Label {
                        text: Math.round(Number(page.statsData.totalProgress || 0) * 100) + "%"
                        font.pixelSize: 18
                        font.bold: true
                    }
                }
            }

            // 分类分布：横向柱条，宽度按占比（空库时显示占位提示）
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 116
                radius: 8
                color: Material.theme === Material.Dark ? "#263238" : "#F5F5F5"
                border.color: Material.theme === Material.Dark ? "#37474F" : "#E0E0E0"
                border.width: 1
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 8
                    Label { text: qsTr("分类分布"); font.bold: true }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 10
                        Repeater {
                            model: page.statsData.byCategory || []
                            delegate: ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Label {
                                        text: modelData.name.length > 0 ? modelData.name : qsTr("未分类")
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        color: Material.primaryTextColor
                                    }
                                    Label {
                                        text: modelData.count
                                        color: Material.secondaryTextColor
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 8
                                    radius: 4
                                    color: Material.theme === Material.Dark ? "#37474F" : "#E0E0E0"
                                    Rectangle {
                                        width: parent.width * page.categoryRatio(modelData)
                                        height: parent.height
                                        radius: 4
                                        // U1：填充色改 Kindle 选中 Token（原 Material.accent 靛蓝）
                                        color: UITheme.borderActive
                                    }
                                }
                            }
                        }
                        Label {
                            visible: (page.statsData.byCategory || []).length === 0
                            text: qsTr("暂无分类数据")
                            color: Material.secondaryTextColor
                        }
                        Item { Layout.fillHeight: true } // 分类少时撑满卡片高度，与左侧卡片等高
                    }
                }
            }
        }
    }
}
