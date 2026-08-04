import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

ApplicationWindow {
    id: root
    width: 1100; height: 720
    visible: true
    title: qsTr("Readdict")

    StackView {
        id: stack
        anchors.fill: parent
        initialItem: "ShelfPage.qml"
    }
}
