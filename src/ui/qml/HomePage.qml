import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.Backend
import Readdict.UI 1.0

// Kindle 主页：最近阅读横排 + 阅读统计摘要行（点击进 StatsPage）。
Page {
    id: home
    property string navId: "home"
    property var recentBooksModel: []
    property int statsRevision: 0
    background: Rectangle { color: UITheme.bgPrimary }

    Component.onCompleted: home.refreshData()

    Connections {
        target: Books
        function onBooksChanged() { home.refreshData() }
        function onReadingActivityChanged() { home.refreshData() }
    }
    ScrollView {
        anchors.fill: parent
        contentWidth: parent.width
        ColumnLayout {
            width: parent.width
            spacing: UITheme.sectionGap

            Label {
                text: qsTr("最近阅读")
                font.pixelSize: UITheme.fsSectionTitle
                font.bold: true
                color: UITheme.textPrimary
                Layout.margins: UITheme.pageMargin
                Layout.bottomMargin: 0
            }
            Row {
                spacing: 12
                leftPadding: UITheme.pageMargin
                Repeater {
                    model: home.recentBooksModel
                    delegate: Column {
                        spacing: 4
                        width: 96
                        BookCard {
                            book: modelData
                            compact: true
                            width: 96
                            onClicked: home.openBook(modelData)
                        }
                    }
                }
            }
            Label {
                text: qsTr("阅读统计")
                font.pixelSize: UITheme.fsSectionTitle
                font.bold: true
                color: UITheme.textPrimary
                Layout.margins: UITheme.pageMargin
                Layout.bottomMargin: 0
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: UITheme.pageMargin
                Layout.rightMargin: UITheme.pageMargin
                height: 56
                color: "transparent"
                MouseArea {
                    anchors.fill: parent
                    onClicked: home.StackView.view.push("StatsPage.qml")
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
                    Label {
                        id: statsSummary
                        text: home.statsText()
                        font.pixelSize: UITheme.fsListItem
                        color: UITheme.textSecondary
                        Layout.fillWidth: true
                    }
                    Label { text: "›"; color: UITheme.textSecondary }
                }
            }
        }
    }

    function refreshData() {
        home.recentBooksModel = Books.recentBooks(6) || []
        ++home.statsRevision
    }

    function statsText() {
        const revision = home.statsRevision
        const s = Books.stats() || {}
        const secs = s.totalReadSeconds || 0
        const hours = Math.floor(secs / 3600)
        const mins = Math.floor((secs % 3600) / 60)
        return qsTr("累计 %1 小时 %2 分 · 共 %3 本书")
            .arg(hours).arg(mins).arg(s.totalBooks || 0)
    }

    function openBook(b) {
        if (!b) return
        const fmt = (b.format ?? "").toUpperCase()
        home.StackView.view.push(fmt === "PDF" ? "PdfReaderPage.qml" : "ReaderPage.qml", { book: b })
    }
}
