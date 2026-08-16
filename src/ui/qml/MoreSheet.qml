import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Readdict.UI 1.0

// Sheet「更多」只保留阅读行为与进度显示格式。目录入口只在顶栏 ⋮ 菜单。
Item {
    id: moreSheet
    objectName: "moreSheetPanel"
    implicitHeight: moreColumn.implicitHeight
    property bool autoContinue: true
    property bool darkFollow: false
    property string progressDisplay: "pages"
    property string progressScope: "chapter"
    property string progressPreview: ""
    property var progressItems: [
        { label: qsTr("页数"), value: "pages" },
        { label: qsTr("百分比"), value: "percent" }
    ]
    property var progressScopeItems: [
        { label: qsTr("本章"), value: "chapter" },
        { label: qsTr("全书"), value: "book" }
    ]
    signal setAutoContinue(bool on)
    signal setDarkFollow(bool on)
    signal setProgressDisplay(string display)
    signal setProgressScope(string scope)

    property alias continueToggle: continueToggle
    property alias followToggle: followToggle
    property alias progressRow: progressRow
    property alias progressSelector: progressSelector
    property alias scopeSelector: scopeSelector
    property alias progressPreviewLabel: progressPreviewLabel

    function selectProgressDisplay(display) {
        if (display !== "pages" && display !== "percent") return
        if (moreSheet.progressDisplay === display) return
        moreSheet.progressDisplay = display
        moreSheet.setProgressDisplay(display)
    }
    function selectProgressScope(scope) {
        if (scope !== "chapter" && scope !== "book") return
        if (moreSheet.progressScope === scope) return
        moreSheet.progressScope = scope
        moreSheet.setProgressScope(scope)
    }

    ColumnLayout {
        id: moreColumn
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        // Toggle 开关行（Kindle 开关语义：右侧开关）。
        RowLayout {
            Layout.fillWidth: true
            Label {
                text: qsTr("自动续章")
                Layout.fillWidth: true
                font.pixelSize: 15
                color: UITheme.textPrimary
            }
            Switch {
                id: continueToggle
                checked: moreSheet.autoContinue
                onToggled: moreSheet.setAutoContinue(checked)
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Label {
                text: qsTr("深色跟随")
                Layout.fillWidth: true
                font.pixelSize: 15
                color: UITheme.textPrimary
            }
            Switch {
                id: followToggle
                checked: moreSheet.darkFollow
                onToggled: moreSheet.setDarkFollow(checked)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: UITheme.divider
            Layout.topMargin: 4
            Layout.bottomMargin: 4
        }

        RowLayout {
            id: progressRow
            Layout.fillWidth: true
            spacing: 10
            Label {
                text: qsTr("阅读进度")
                font.pixelSize: 15
                color: UITheme.textPrimary
            }
            Item { Layout.fillWidth: true }
            Label {
                id: progressPreviewLabel
                text: moreSheet.progressPreview
                font.pixelSize: UITheme.fsCaption
                color: UITheme.textSecondary
            }
        }
        KdSegmentedSlider {
            id: scopeSelector
            Layout.fillWidth: true
            segments: moreSheet.progressScopeItems
            currentValue: moreSheet.progressScope
            onSelected: (value) => moreSheet.selectProgressScope(value)
        }
        KdSegmentedSlider {
            id: progressSelector
            Layout.fillWidth: true
            segments: moreSheet.progressItems
            currentValue: moreSheet.progressDisplay
            onSelected: (value) => moreSheet.selectProgressDisplay(value)
        }
    }
}
