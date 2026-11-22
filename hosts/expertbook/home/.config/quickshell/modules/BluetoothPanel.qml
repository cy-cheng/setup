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
    margins { top: Theme.gap; right: Theme.gap }
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
    readonly property var devices: {
        if (!adapter) return [];
        const rank = d => d.connected ? 0 : d.paired ? 1 : 2;
        return adapter.devices.values
            // Nearby devices that only broadcast an address (name like 1A-87-FD-…) are noise.
            .filter(d => d.connected || d.paired || (d.name && !/^([0-9A-F]{2}[-:]){5}[0-9A-F]{2}$/i.test(d.name)))
            .sort((a, b) => (rank(a) - rank(b)) || a.name.localeCompare(b.name));
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
                        Layout.fillWidth: true
                        implicitHeight: col.implicitHeight + 16
                        radius: 10
                        color: rowMouse.containsMouse ? Theme.raised : "transparent"

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (row.d.connected || row.busy) return;
                                if (row.d.paired) row.d.connect();
                                else { row.d.trusted = true; row.d.pair(); }
                            }
                        }

                        ColumnLayout {
                            id: col
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                                      leftMargin: 10; rightMargin: 10 }
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
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
                                Label {
                                    text: row.busy ? "…" : row.d.connected ? "Connected" : row.d.paired ? "Paired" : "Pair"
                                    color: row.d.connected ? Theme.amber : Theme.faint
                                    font.pixelSize: Theme.textSm
                                }
                            }

                            RowLayout { // actions on hover for known devices
                                visible: rowMouse.containsMouse && (row.d.connected || row.d.paired)
                                spacing: 6
                                Repeater {
                                    model: (row.d.connected ? [["Disconnect", () => row.d.disconnect()]] : [])
                                           .concat([["Forget", () => row.d.forget()]])
                                    delegate: Rectangle {
                                        required property var modelData
                                        implicitWidth: actLabel.implicitWidth + 20; implicitHeight: 24; radius: 12
                                        color: actMouse.containsMouse ? Theme.amber : Theme.island
                                        border.color: Theme.line
                                        Label { id: actLabel; anchors.centerIn: parent; text: modelData[0]
                                                font.pixelSize: Theme.textSm; color: actMouse.containsMouse ? Theme.base : Theme.fg }
                                        MouseArea { id: actMouse; anchors.fill: parent; hoverEnabled: true; onClicked: modelData[1]() }
                                    }
                                }
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
