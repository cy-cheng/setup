import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// Notification centre (slides in from the right edge). Grouped by source, "needs" first.
// Super+N toggles it (qs ipc call notifs toggle); Esc or a click outside closes.
PanelWindow {
    id: centre
    required property var modelData
    screen: modelData

    readonly property bool onFocusedScreen: Quickshell.screens.length < 2
        || modelData.name === (Hyprland.focusedMonitor?.name ?? "")

    readonly property bool open: Notifs.centreOpen && onFocusedScreen
    visible: open || card.x < width        // stays mapped while it slides out
    anchors { top: true; bottom: true; right: true }
    margins { top: Theme.gap; bottom: Theme.gap; right: Theme.gap }
    implicitWidth: 400
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.namespace: "nixie-centre"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    readonly property var groups: { Notifs.rev; return Notifs.groups(); }
    property var collapsed: ({})       // key -> true when a group is folded

    HyprlandFocusGrab { // click outside closes the centre
        windows: [centre]
        active: centre.open
        onCleared: Notifs.centreOpen = false
    }

    // Slides in from the right edge (where the dock lives) and back out.
    Rectangle {
        id: card
        width: parent.width
        height: parent.height
        x: centre.open ? 0 : width + Theme.gap * 2
        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        radius: Theme.radius + 4
        color: Theme.centre         // lighter than the cards so they stand out on it
        border.color: Theme.line
        focus: true
        Keys.onEscapePressed: Notifs.centreOpen = false

        // ── Header ──
        Item {
            id: header
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            height: 26
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: "Notifications"
                color: Theme.fg
                font { family: Theme.font; pixelSize: 15; weight: Font.DemiBold }
            }
            component Toggle: Rectangle {
                property string label
                property bool on
                signal toggled
                width: tText.implicitWidth + 18; height: 24; radius: 12
                color: on ? Theme.amberDim : (tMouse.containsMouse ? Theme.raised : "transparent")
                border.color: on ? "transparent" : Theme.line
                Text { id: tText; anchors.centerIn: parent; text: parent.label
                       color: Theme.fg; font { family: Theme.font; pixelSize: 11 } }
                MouseArea { id: tMouse; anchors.fill: parent; hoverEnabled: true; onClicked: parent.toggled() }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 8
                Toggle { label: "☾ Focus"; on: Notifs.focusMode; onToggled: Notifs.focusMode = !Notifs.focusMode }
                Toggle { label: "Clear all"; on: false; onToggled: Notifs.clearAll() }
            }
        }

        // ── Groups ──
        Flickable {
            anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom
                      margins: 12; topMargin: 14 }
            contentHeight: list.implicitHeight
            clip: true
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Column {
                id: list
                width: parent.width
                spacing: 14

                Text {
                    visible: centre.groups.length === 0
                    text: "All clear."
                    color: Theme.faint
                    font { family: Theme.font; pixelSize: 13 }
                }

                Repeater {
                    model: centre.groups
                    delegate: Column {
                        id: group
                        required property var modelData
                        readonly property bool folded: centre.collapsed[modelData.key] ?? (modelData.tier === "quiet")
                        width: list.width
                        spacing: 6

                        Item { // group header: name · count · fold · dismiss all
                            width: parent.width
                            height: 18
                            Text {
                                id: gTitle
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                text: (group.folded ? "▸ " : "▾ ") + group.modelData.label
                                color: Theme.tierColor(group.modelData.tier)
                                font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        const c = Object.assign({}, centre.collapsed);
                                        c[group.modelData.key] = !group.folded;
                                        centre.collapsed = c;
                                    }
                                }
                            }
                            Text {
                                anchors { left: gTitle.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                text: group.modelData.items.length
                                color: Theme.faint
                                font { family: Theme.font; pixelSize: 11 }
                            }
                            Text {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                text: "dismiss"
                                color: dMouse.containsMouse ? Theme.fg : Theme.faint
                                font { family: Theme.font; pixelSize: 10 }
                                MouseArea { id: dMouse; anchors.fill: parent; hoverEnabled: true
                                            onClicked: Notifs.dismissGroup(group.modelData.key) }
                            }
                        }

                        Repeater {
                            model: group.folded ? [] : group.modelData.items.slice(0, 6)
                            delegate: NotifCard {
                                required property var modelData
                                rec: modelData
                                compact: true
                                width: group.width
                            }
                        }
                        Text {
                            visible: !group.folded && group.modelData.items.length > 6
                            text: "… " + (group.modelData.items.length - 6) + " more"
                            color: Theme.faint
                            font { family: Theme.font; pixelSize: 11 }
                        }
                    }
                }
            }
        }
    }
}
