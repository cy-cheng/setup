import QtQuick
import Quickshell
import qs.services

// Hover tooltip for any item: put `Tip { text: "…" }` inside it.
// A real popup window, so the frame or other windows never cover it.
//
// Hover state comes from enter/leave events, and those stop arriving while a drop-down
// holds the pointer grab (the bar never hears that the cursor left). So bar tips hide
// while any panel is open, and afterwards only return once the pointer actually moves
// over the item again. Tips inside a panel set `inPanel: true`.
Item {
    id: tip
    property string text
    property bool inPanel: false
    anchors.fill: parent

    readonly property bool blocked: !inPanel && (Panels.open !== "" || Notifs.centreOpen)
    property bool fresh: false          // pointer really moved here since the last block
    onBlockedChanged: if (blocked) fresh = false

    MouseArea {                         // hover only: takes no buttons, so clicks pass through
        id: hover
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        onEntered: tip.fresh = true
        onPositionChanged: tip.fresh = true
        onExited: tip.fresh = false
    }
    readonly property bool hovered: hover.containsMouse && fresh && !blocked

    Timer { // short delay so tips don't flash while moving across the bar
        id: delay
        interval: 350
        running: tip.hovered
        onTriggered: tip.shown = true
    }
    property bool shown: false
    onHoveredChanged: if (!hovered) shown = false

    PopupWindow {
        visible: tip.shown && tip.hovered && tip.text !== ""
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
