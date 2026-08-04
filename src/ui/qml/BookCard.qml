import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

Item {
    id: card
    property var book: ({})
    signal clicked()
    width: 180
    height: 280

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: Material.background
        border.color: Material.dividerColor

        Image {
            id: coverImg
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: 120
            height: 160
            source: card.book.cover ? "file://" + card.book.cover : ""
            fillMode: Image.PreserveAspectCrop
        }

        Text {
            anchors.top: coverImg.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 6
            text: card.book.title
            elide: Text.ElideRight
            font.bold: true
        }

        ProgressBar {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 8
            value: card.book.progress ?? 0
        }

        MouseArea {
            anchors.fill: parent
            onClicked: card.clicked()
        }
    }
}
