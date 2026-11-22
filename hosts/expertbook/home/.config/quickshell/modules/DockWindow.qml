import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// Slide-in dock on the right edge.
//   Rest the pointer on the very right edge for ~2 s → the dock slides in;
//   move away → it slides out. Super+D (qs ipc call dock toggle) toggles it.
//   While hidden, a short amber line on the edge means something is unread / needs you.
Scope {
    id: root
    required property var modelData

    property bool revealed: false
    readonly property int revealDelay: 2000      // ms the pointer must rest on the edge
    readonly property bool attention: { Notifs.rev; return Notifs.history.some(r => !r.seen && r.tier !== "quiet"); }
    readonly property bool urgent: { Notifs.rev; return Notifs.history.some(r => !r.seen && r.tier === "needs"); }

    IpcHandler {
        target: "dock"
        function toggle(): void { root.revealed = !root.revealed; }
    }

    // ── Hot edge: 1 px strip on the right ──
    PanelWindow {
        screen: root.modelData
        anchors { top: true; bottom: true; right: true }
        implicitWidth: 1
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "nixie-dock-edge"
        WlrLayershell.layer: WlrLayer.Overlay

        HoverHandler { id: edgeHover }
        Timer {
            interval: root.revealDelay
            running: edgeHover.hovered && !root.revealed
            onTriggered: root.revealed = true
        }
    }

    // Attention line drawn just inside the edge (no input)
    PanelWindow {
        screen: root.modelData
        visible: !root.revealed && root.attention
        anchors { top: true; right: true }
        margins { top: Theme.barH + 24; right: 1 }
        implicitWidth: 3
        implicitHeight: 72
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Region {}
        WlrLayershell.namespace: "nixie-dock-hint"
        WlrLayershell.layer: WlrLayer.Overlay
        Rectangle {
            anchors.fill: parent
            radius: 1.5
            color: root.urgent ? Theme.amber : Theme.muted
            SequentialAnimation on opacity {
                running: root.urgent
                loops: Animation.Infinite
                NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
            }
        }
    }

    // ── The dock ──
    PanelWindow {
        id: panel
        screen: root.modelData
        visible: root.revealed || card.x < card.width
        anchors { top: true; right: true }
        margins { top: Theme.barH + Theme.gap; right: Theme.gap }
        implicitWidth: content.implicitWidth + 8
        implicitHeight: content.implicitHeight + 8
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "nixie-popups"
        WlrLayershell.layer: WlrLayer.Overlay

        HoverHandler { id: dockHover }
        Timer { // slide out shortly after the pointer leaves
            interval: 500
            running: root.revealed && !dockHover.hovered && !edgeHover.hovered
            onTriggered: root.revealed = false
        }

        Rectangle {
            id: card
            width: parent.width; height: parent.height
            x: root.revealed ? 0 : width + Theme.gap * 2
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            radius: Theme.radius + 4
            color: Theme.glass
            border.color: Theme.line
            RailContent {
                id: content
                anchors.centerIn: parent
                width: implicitWidth; height: implicitHeight
            }
        }
    }
}
