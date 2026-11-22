import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// Slide-in dock on the right edge.
//   Rest the pointer on the very right edge for ~0.7 s → the dock slides in;
//   move away → it slides out. Super+D (qs ipc call dock toggle) opens it and keeps it
//   open until Super+D is pressed again.
//   While hidden, a short amber line on the edge means something is unread / needs you.
Scope {
    id: root
    required property var modelData

    property bool revealed: false
    property bool sticky: false                  // opened with Super+D: stays until toggled again
    readonly property int revealDelay: 700       // ms the pointer must rest on the edge
    readonly property bool attention: { Notifs.rev; return Notifs.history.some(r => !r.seen && r.tier !== "quiet"); }
    readonly property bool urgent: { Notifs.rev; return Notifs.history.some(r => !r.seen && r.tier === "needs"); }

    // ── Where is the cursor? ──
    // Polled from Hyprland while it matters: after the pointer touched the edge, and
    // while the dock is open (unless pinned with Super+D). Resting still counts.
    property bool watching: false
    property real edgeSince: 0
    property real awaySince: 0
    readonly property int hideDelay: 500
    Timer {
        interval: 100; repeat: true; triggeredOnStart: true
        running: root.watching || (root.revealed && !root.sticky)
        onTriggered: if (!cursorPos.running) cursorPos.running = true
    }
    Process {
        id: cursorPos
        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector { onStreamFinished: root.onCursor(text) }
    }
    function onCursor(t) {
        let p;
        try { p = JSON.parse(t); } catch (e) { return; }
        const s = root.modelData, now = Date.now();
        const right = s.x + s.width;
        const inY = p.y >= s.y && p.y < s.y + s.height;
        const onEdge = inY && p.x >= right - 2 && p.x < right;
        const top = s.y + Theme.barH + Theme.gap;
        const inDock = root.revealed && inY
            && p.x >= right - Theme.gap - panel.implicitWidth - 4
            && p.y >= top - 4 && p.y <= top + panel.implicitHeight + 4;

        if (!root.revealed) {
            root.awaySince = 0;
            if (!onEdge) { root.edgeSince = 0; root.watching = false; return; }
            if (!root.edgeSince) root.edgeSince = now;
            if (now - root.edgeSince >= root.revealDelay) {
                root.revealed = true; root.sticky = false; root.edgeSince = 0;
            }
        } else if (!root.sticky) {
            if (onEdge || inDock) { root.awaySince = 0; return; }
            if (!root.awaySince) root.awaySince = now;
            if (now - root.awaySince >= root.hideDelay) {
                root.revealed = false; root.awaySince = 0; root.watching = false;
            }
        }
    }

    IpcHandler {
        target: "dock"
        function toggle(): void {
            root.revealed = !(root.revealed && root.sticky);
            root.sticky = root.revealed;
        }
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

        // Any pointer event on the strip starts the position check below; the
        // decision itself is made from the real cursor position, not from events.
        HoverHandler { onHoveredChanged: if (hovered) root.watching = true }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: root.watching = true
            onPositionChanged: root.watching = true
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
        visible: root.revealed || card.x < panel.implicitWidth
        anchors { top: true; right: true }
        margins { top: Theme.barH + Theme.gap; right: Theme.gap }
        implicitWidth: content.implicitWidth + 8
        implicitHeight: content.implicitHeight + 8
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "nixie-popups"
        WlrLayershell.layer: WlrLayer.Overlay


        Rectangle {
            id: card
            width: parent.width; height: parent.height
            x: root.revealed ? 0 : panel.implicitWidth + Theme.gap * 2
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            radius: Theme.radius + 4
            color: Theme.glass
            border.color: Theme.line
            DockContent {
                id: content
                anchors.centerIn: parent
                width: implicitWidth; height: implicitHeight
            }
        }
    }
}
