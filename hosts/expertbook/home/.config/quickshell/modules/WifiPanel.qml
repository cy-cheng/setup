import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Networking
import qs.services

// Wi-Fi panel (with VPN toggles): drops down under the status island. Lists networks (connected
// first, then by signal); click to connect, password field for new secured
// networks, disconnect/forget for the current one. Esc or click outside closes.
PanelWindow {
    id: panel
    required property var modelData
    screen: modelData

    readonly property bool onFocusedScreen: Quickshell.screens.length < 2
        || modelData.name === (Hyprland.focusedMonitor?.name ?? "")
    visible: Panels.open === "wifi" && onFocusedScreen

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

    readonly property var wifi: {
        for (const d of Networking.devices.values) if (d.type === DeviceType.Wifi) return d;
        return null;
    }
    // Stable order: sorted once when the panel opens (connected first, then signal);
    // networks found later go to the bottom, so rows don't jump while scanning.
    property var order: []
    readonly property var all: wifi ? wifi.networks.values.filter(n => n.name !== "") : []
    function resort() {
        order = all.slice().sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength))
                   .map(n => n.name);
    }
    readonly property var networks: {
        const byName = {};
        for (const n of all) byName[n.name] = n;
        const out = order.filter(k => byName[k]).map(k => byName[k]);
        for (const n of all) if (!order.includes(n.name)) out.push(n);
        return out;
    }
    property string askingFor: ""          // network name awaiting a password

    // Scan only while the panel is open.
    Binding { target: panel.wifi; property: "scannerEnabled"; value: panel.visible; when: panel.wifi !== null }
    onVisibleChanged: if (visible) resort(); else askingFor = ""

    function bars(n) {
        const s = n.signalStrength > 1 ? n.signalStrength / 100 : n.signalStrength;
        // wifi / wifi_2_bar / wifi_1_bar draw fewer arcs, so they stay distinct at 18px.
        return s > 0.7 ? "wifi" : s > 0.4 ? "wifi_2_bar" : "wifi_1_bar";
    }
    function secured(n) { return n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Unknown; }

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

            RowLayout { // header: title + on/off switch
                Layout.fillWidth: true
                Label { text: "Wi-Fi"; font.pixelSize: Theme.textLg; font.weight: Font.DemiBold }
                Item { Layout.fillWidth: true }
                Rectangle { // switch
                    implicitWidth: 40; implicitHeight: 22; radius: 11
                    color: Networking.wifiEnabled ? Theme.amber : Theme.raised
                    border.color: Networking.wifiEnabled ? "transparent" : Theme.line
                    Rectangle {
                        width: 16; height: 16; radius: 8
                        anchors.verticalCenter: parent.verticalCenter
                        x: Networking.wifiEnabled ? parent.width - width - 3 : 3
                        color: Networking.wifiEnabled ? Theme.base : Theme.muted
                        Behavior on x { NumberAnimation { duration: 120 } }
                    }
                    MouseArea { anchors.fill: parent; onClicked: Networking.wifiEnabled = !Networking.wifiEnabled }
                }
            }

            Label {
                visible: !Networking.wifiEnabled || panel.networks.length === 0
                text: !Networking.wifiEnabled ? "Wi-Fi is off" : "Searching…"
                color: Theme.muted
            }

            ColumnLayout { // networks
                Layout.fillWidth: true
                spacing: 4
                visible: Networking.wifiEnabled
                Repeater {
                    model: panel.networks.slice(0, 6)
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        readonly property bool asking: panel.askingFor === modelData.name
                        Layout.fillWidth: true
                        implicitHeight: col.implicitHeight + 16
                        radius: 10
                        color: rowMouse.containsMouse || forgetMouse.containsMouse || asking ? Theme.raised : "transparent"

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                const n = row.modelData;
                                if (n.connected) { n.disconnect(); return; }
                                if (n.known || !panel.secured(n)) n.connect();
                                else panel.askingFor = (panel.askingFor === n.name) ? "" : n.name;
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
                                Icon { text: panel.bars(row.modelData); color: row.modelData.connected ? Theme.amber : Theme.fg }
                                Label {
                                    Layout.fillWidth: true
                                    text: row.modelData.name
                                    elide: Text.ElideRight
                                    font.weight: row.modelData.connected ? Font.DemiBold : Font.Normal
                                }
                                Icon { visible: panel.secured(row.modelData); size: 14; text: "lock"; color: Theme.faint }
                                Label { // what a click does (or what's happening)
                                    readonly property bool hov: rowMouse.containsMouse || forgetMouse.containsMouse
                                    text: row.modelData.stateChanging ? "…"
                                        : row.modelData.connected ? (hov ? "Disconnect" : "Connected")
                                        : hov ? "Connect" : ""
                                    visible: text !== ""
                                    color: row.modelData.connected && !hov ? Theme.amber : Theme.fg
                                    font.pixelSize: Theme.textSm
                                }
                                Item { // forget (saved networks): fades in on hover, layout never changes
                                    Layout.preferredWidth: 28; Layout.preferredHeight: 28
                                    visible: row.modelData.known || row.modelData.connected
                                    opacity: rowMouse.containsMouse || forgetMouse.containsMouse ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 100 } }
                                    Rectangle { anchors.fill: parent; radius: 14
                                                color: forgetMouse.containsMouse ? Qt.rgba(1, 0.36, 0.34, 0.18) : "transparent" }
                                    Icon { anchors.centerIn: parent; size: 16; text: "delete"
                                           color: forgetMouse.containsMouse ? Theme.red : Theme.muted }
                                    MouseArea { id: forgetMouse; anchors.fill: parent; hoverEnabled: true; onClicked: row.modelData.forget() }
                                }
                            }

                            Rectangle { // password field for a new secured network
                                visible: row.asking
                                Layout.fillWidth: true
                                implicitHeight: 32; radius: 16
                                color: Theme.base; border.color: pw.activeFocus ? Theme.amber : Theme.line
                                TextInput {
                                    id: pw
                                    anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                                    verticalAlignment: TextInput.AlignVCenter
                                    echoMode: TextInput.Password
                                    color: Theme.fg
                                    font { family: Theme.font; pixelSize: Theme.text }
                                    focus: row.asking
                                    onVisibleChanged: if (visible) forceActiveFocus()
                                    onAccepted: { row.modelData.connectWithPsk(text); text = ""; panel.askingFor = ""; }
                                    Label { anchors.verticalCenter: parent.verticalCenter; visible: !pw.text
                                            text: "Password, then Enter"; color: Theme.faint }
                                }
                            }
                        }
                    }
                }
            }

            // ── VPN ──
            Rectangle { visible: Vpn.connections.length > 0; Layout.fillWidth: true; implicitHeight: 1; color: Theme.line }
            Label {
                visible: Vpn.connections.length > 0
                text: "VPN"
                font.pixelSize: Theme.textLg
                font.weight: Font.DemiBold
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: Vpn.connections.length > 0
                Repeater {
                    model: Vpn.connections
                    delegate: Rectangle {
                        id: vrow
                        required property var modelData
                        readonly property string busy: Vpn.pending[modelData.uuid] ?? ""
                        readonly property bool on: busy === "up" || (modelData.active && busy !== "down")
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: 10
                        color: vMouse.containsMouse ? Theme.raised : "transparent"
                        MouseArea {
                            id: vMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: if (vrow.busy === "") Vpn.toggle(vrow.modelData)
                        }
                        RowLayout {
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                            spacing: 10
                            Icon { text: vrow.modelData.active ? "vpn_lock" : "vpn_key"; color: vrow.modelData.active ? Theme.amber : Theme.fg }
                            Label {
                                Layout.fillWidth: true
                                text: vrow.modelData.name
                                elide: Text.ElideRight
                                font.weight: vrow.modelData.active ? Font.DemiBold : Font.Normal
                            }
                            Label {
                                visible: text !== ""
                                text: vrow.busy === "up" ? "Connecting…" : vrow.busy === "down" ? "Disconnecting…"
                                    : vrow.modelData.active ? "Connected" : ""
                                color: Theme.amber
                                font.pixelSize: Theme.textSm
                            }
                            Rectangle { // switch
                                implicitWidth: 34; implicitHeight: 20; radius: 10
                                color: vrow.on ? Theme.amber : Theme.raised
                                border.color: vrow.on ? "transparent" : Theme.line
                                opacity: vrow.busy !== "" ? 0.6 : 1
                                Rectangle {
                                    width: 14; height: 14; radius: 7
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: vrow.on ? parent.width - width - 3 : 3
                                    color: vrow.on ? Theme.base : Theme.muted
                                    Behavior on x { NumberAnimation { duration: 120 } }
                                }
                            }
                        }
                    }
                }
            }
            Label {
                visible: Vpn.lastError !== ""
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Vpn.lastError
                color: Theme.red
                font.pixelSize: Theme.textSm
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.line }

            RowLayout { // footer: full settings app
                Layout.fillWidth: true
                Label { text: "Network settings…"; color: setMouse.containsMouse ? Theme.fg : Theme.muted; font.pixelSize: Theme.textSm
                        MouseArea { id: setMouse; anchors.fill: parent; hoverEnabled: true
                                    onClicked: { Panels.close(); Quickshell.execDetached(["nm-connection-editor"]); } } }
            }
        }
    }
}
