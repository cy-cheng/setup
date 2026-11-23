import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Bluetooth
import qs.services

// Bluetooth panel: drops down under the status island. Connected devices first,
// then paired, then new ones found while scanning (scans only while open).
// Click: connect / pair. Hover a connected or paired device: disconnect / forget.
PanelWindow {
    id: panel
    required property var modelData
    screen: modelData

    readonly property bool onFocusedScreen: Quickshell.screens.length < 2
        || modelData.name === (Hyprland.focusedMonitor?.name ?? "")
    visible: Panels.open === "bluetooth" && onFocusedScreen

    anchors { top: true; right: true }
    margins { top: Theme.panelTop; right: Theme.panelSide }
    implicitWidth: 360
    implicitHeight: content.implicitHeight + 28
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.namespace: "nixie-centre"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    HyprlandFocusGrab { windows: [panel]; active: panel.visible; onCleared: Panels.close() }

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool on: adapter?.enabled ?? false
    // Stable order: sorted once when the panel opens (connected, paired, then by name);
    // devices found later are appended at the bottom, so rows never jump under the cursor.
    property var order: []
    readonly property var known: {
        if (!adapter) return [];
        return adapter.devices.values
            // Nearby devices that only broadcast an address (name like 1A-87-FD-…) are noise.
            .filter(d => d.connected || d.paired || (d.name && !/^([0-9A-F]{2}[-:]){5}[0-9A-F]{2}$/i.test(d.name)));
    }
    function resort() {
        const rank = d => d.connected ? 0 : d.paired ? 1 : 2;
        order = known.slice().sort((a, b) => (rank(a) - rank(b)) || a.name.localeCompare(b.name)).map(d => d.address);
    }
    onVisibleChanged: if (visible) resort()
    readonly property var devices: {
        const byAddr = {};
        for (const d of known) byAddr[d.address] = d;
        const out = order.filter(a => byAddr[a]).map(a => byAddr[a]);
        for (const d of known) if (!order.includes(d.address)) out.push(d);   // new: at the end
        return out;
    }

    // Discover new devices only while the panel is open.
    Binding { target: panel.adapter; property: "discovering"; value: panel.visible && panel.on; when: panel.adapter !== null }

    function iconFor(d) {
        const i = d.icon || "";
        return i.includes("headset") || i.includes("headphone") ? "headphones"
             : i.includes("audio") ? "speaker"
             : i.includes("mouse") ? "mouse"
             : i.includes("keyboard") ? "keyboard"
             : i.includes("phone") ? "smartphone"
             : i.includes("computer") ? "computer"
             : i.includes("game") ? "sports_esports"
             : "bluetooth";
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius + 4
        color: Theme.glass
        border.color: Theme.line
        focus: true
        Keys.onEscapePressed: Panels.close()

        ColumnLayout {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 10

            RowLayout { // header: title + scanning hint + switch
                Layout.fillWidth: true
                spacing: 8
                Label { text: "Bluetooth"; font.pixelSize: Theme.textLg; font.weight: Font.DemiBold }
                Label { visible: panel.adapter?.discovering ?? false; text: "scanning…"; color: Theme.faint; font.pixelSize: Theme.textSm }
                Item { Layout.fillWidth: true }
                Rectangle { // switch
                    implicitWidth: 40; implicitHeight: 22; radius: 11
                    color: panel.on ? Theme.amber : Theme.raised
                    border.color: panel.on ? "transparent" : Theme.line
                    Rectangle {
                        width: 16; height: 16; radius: 8
                        anchors.verticalCenter: parent.verticalCenter
                        x: panel.on ? parent.width - width - 3 : 3
                        color: panel.on ? Theme.base : Theme.muted
                        Behavior on x { NumberAnimation { duration: 120 } }
                    }
                    MouseArea { anchors.fill: parent; onClicked: if (panel.adapter) panel.adapter.enabled = !panel.on }
                }
            }

            Label {
                visible: !panel.on || panel.devices.length === 0
                text: !panel.adapter ? "No Bluetooth adapter" : !panel.on ? "Bluetooth is off" : "Looking for devices…"
                color: Theme.muted
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: panel.on
                Repeater {
                    model: panel.devices.slice(0, 10)
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        readonly property var d: modelData
                        readonly property bool busy: d.pairing || d.state === BluetoothDeviceState.Connecting
                                                    || d.state === BluetoothDeviceState.Disconnecting
                        readonly property bool hovered: rowMouse.containsMouse || forgetMouse.containsMouse
                        Layout.fillWidth: true
                        implicitHeight: 44                      // fixed: nothing moves on hover
                        radius: 10
                        color: hovered ? Theme.raised : "transparent"

                        // Whole row: connect / disconnect / pair.
                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (row.busy) return;
                                if (row.d.connected) row.d.disconnect();
                                else if (row.d.paired) row.d.connect();
                                else { row.d.trusted = true; row.d.pair(); }
                            }
                        }

                        RowLayout {
                            anchors { fill: parent; leftMargin: 10; rightMargin: 6 }
                            spacing: 10
                            Icon { text: panel.iconFor(row.d); color: row.d.connected ? Theme.amber : Theme.fg }
                            Label {
                                Layout.fillWidth: true
                                text: row.d.name
                                elide: Text.ElideRight
                                font.weight: row.d.connected ? Font.DemiBold : Font.Normal
                            }
                            Label { // battery
                                visible: row.d.batteryAvailable
                                text: Math.round(row.d.battery * (row.d.battery > 1 ? 1 : 100)) + "%"
                                color: Theme.muted; font.pixelSize: Theme.textSm
                            }
                            Label { // what a click does (or what's happening)
                                text: row.busy ? "…"
                                    : row.d.connected ? (row.hovered ? "Disconnect" : "Connected")
                                    : row.d.paired ? "Connect" : "Pair"
                                color: row.d.connected && !row.hovered ? Theme.amber : row.hovered ? Theme.fg : Theme.faint
                                font.pixelSize: Theme.textSm
                            }
                            Item { // forget (known devices): fades in on hover, never changes the layout
                                Layout.preferredWidth: 28; Layout.preferredHeight: 28
                                visible: row.d.paired || row.d.connected
                                opacity: row.hovered ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 100 } }
                                Rectangle {
                                    anchors.fill: parent; radius: 14
                                    color: forgetMouse.containsMouse ? Qt.rgba(1, 0.36, 0.34, 0.18) : "transparent"
                                }
                                Icon {
                                    anchors.centerIn: parent; size: 16; text: "delete"
                                    color: forgetMouse.containsMouse ? Theme.red : Theme.muted
                                }
                                MouseArea {
                                    id: forgetMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: parent.visible
                                    onClicked: row.d.forget()
                                }
                                Tip { text: "Forget this device"; inPanel: true }
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.line }
            Label {
                text: "Bluetooth settings…"
                color: setMouse.containsMouse ? Theme.fg : Theme.muted
                font.pixelSize: Theme.textSm
                MouseArea { id: setMouse; anchors.fill: parent; hoverEnabled: true
                            onClicked: { Panels.close(); Quickshell.execDetached(["blueberry"]); } }
            }
        }
    }
}
