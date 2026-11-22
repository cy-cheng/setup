import QtQuick
import Quickshell
import qs.services

// Hover tooltip for any item: put `Tip { text: "…" }` inside it.
// Uses a HoverHandler (doesn't steal clicks) and a real popup window,
// so the frame or windows never cover it.
Item {
    id: tip
    property string text
    anchors.fill: parent

    HoverHandler { id: hover }

    Timer { // short delay so tips don't flash while moving across the bar
        id: delay
        interval: 350
        running: hover.hovered
    }

    PopupWindow {
        visible: hover.hovered && !delay.running && tip.text !== ""
        anchor.item: tip
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 12
        implicitWidth: label.implicitWidth + 20
        implicitHeight: 26
        color: "transparent"
        Rectangle {
            anchors.fill: parent
            radius: 13
            color: Theme.glass
            border.color: Theme.line
            Label {
                id: label
                anchors.centerIn: parent
                text: tip.text
                font.pixelSize: Theme.textSm
            }
        }
    }
}
