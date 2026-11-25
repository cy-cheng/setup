import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// Popup stack: top-right, next to the rail. Only "needs" / "fyi" / "system"
// show here (quiet ones go straight to history); in focus mode only "needs".
PanelWindow {
    id: popups
    required property var modelData
    screen: modelData

    readonly property bool onFocusedScreen: Quickshell.screens.length < 2
        || modelData.name === (Hyprland.focusedMonitor?.name ?? "")

    visible: Notifs.popups.length > 0 && onFocusedScreen && !Notifs.centreOpen
    anchors { top: true; right: true }
    margins { top: Theme.panelTop; right: Theme.panelSide }
    implicitWidth: 380
    implicitHeight: stack.implicitHeight
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.namespace: "nixie-popups"
    WlrLayershell.layer: WlrLayer.Overlay

    Column {
        id: stack
        width: parent.width
        spacing: Theme.gap
        Repeater {
            model: { Notifs.rev; return Notifs.popups; }
            delegate: NotifCard {
                required property var modelData
                rec: modelData
            }
        }
    }
}
