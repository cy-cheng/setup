import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Io
import qs.services

// Wi-Fi panel (with VPN toggles): drops down under the status island. Lists every network
// (connected first, then by signal; scrolls past ~7); click to connect. New secured networks
// ask for a password, enterprise ones (eduroam, 802.1X) for username + password; "Hidden
// network…" for ones that don't broadcast; a "Sign in" row when the network has a login page.
// Esc or click outside closes.
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
    property string askingFor: ""          // network name awaiting a password (or hiddenKey)
    readonly property string hiddenKey: "\u0000hidden"
    property var status: ({})              // network name -> last error
    property string busyFor: ""            // network wifi-connect is working on
    function setStatus(name, text) { const s = Object.assign({}, status); s[name] = text; status = s; }

    // WPA/WPA2/WPA3-Enterprise (eduroam, campus 802.1X): username + password.
    function enterprise(n) {
        return n.security === WifiSecurityType.Wpa2Eap || n.security === WifiSecurityType.WpaEap
            || n.security === WifiSecurityType.Wpa3SuiteB192 || n.security === WifiSecurityType.Leap
            || n.security === WifiSecurityType.DynamicWep;
    }

    // Connections Quickshell.Networking can't make itself go through ~/.local/bin/wifi-connect.
    // The secret is written to its stdin, never put on the command line.
    Process {
        id: connector
        property string target: ""
        property string secret: ""
        stdinEnabled: true
        stdout: StdioCollector { id: connectorOut }
        onStarted: { write(secret); secret = ""; stdinEnabled = false; }
        onExited: code => {
            panel.setStatus(target, code === 0 ? "" : (connectorOut.text.trim() || "Couldn't connect"));
            panel.busyFor = "";
            stdinEnabled = true;
        }
    }
    function runConnect(mode, ssid, secret) {
        if (connector.running) return;
        connector.target = mode === "hidden" ? hiddenKey : ssid;
        connector.secret = secret;
        connector.command = [Quickshell.env("HOME") + "/.local/bin/wifi-connect", mode, ssid];
        busyFor = ssid;
        setStatus(connector.target, "");
        connector.running = true;
    }

    // Scan only while the panel is open.
    Binding { target: panel.wifi; property: "scannerEnabled"; value: panel.visible; when: panel.wifi !== null }
    onVisibleChanged: if (visible) resort(); else { askingFor = ""; status = ({}); }

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

            Rectangle { // captive portal: connected, but the network wants a browser login first
                visible: Networking.wifiEnabled && Networking.connectivity === NetworkConnectivity.Portal
                Layout.fillWidth: true
                implicitHeight: 40; radius: 10
                color: portalMouse.containsMouse ? Qt.rgba(1, 0.67, 0.2, 0.22) : Qt.rgba(1, 0.67, 0.2, 0.12)
                RowLayout {
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    spacing: 10
                    Icon { text: "login"; color: Theme.amber }
                    Label { Layout.fillWidth: true; text: "Sign in to this network"; elide: Text.ElideRight }
                    Label { text: "Open login page"; color: Theme.amber; font.pixelSize: Theme.textSm }
                }
                MouseArea {
                    id: portalMouse; anchors.fill: parent; hoverEnabled: true
                    // Any plain-http page gets redirected to the login page; use NetworkManager's own check URL.
                    onClicked: { Panels.close(); Qt.openUrlExternally("http://ping.archlinux.org/nm-check.txt"); }
                }
            }

            Flickable { // networks: all of them, scrolling past ~7 rows
                id: scroller
                visible: Networking.wifiEnabled
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(netList.implicitHeight, 300)
                contentHeight: netList.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Rectangle { // scroll indicator
                    visible: scroller.interactive
                    parent: scroller
                    anchors.right: parent.right
                    width: 3; radius: 1.5
                    color: Theme.faint; opacity: 0.6
                    height: Math.max(24, scroller.height * scroller.height / scroller.contentHeight)
                    y: (scroller.height - height) * scroller.contentY / Math.max(1, scroller.contentHeight - scroller.height)
                }

            ColumnLayout {
                id: netList
                width: scroller.width - (scroller.interactive ? 8 : 0)
                spacing: 4
                Repeater {
                    model: panel.networks
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        readonly property bool asking: panel.askingFor === modelData.name
                        readonly property bool eap: panel.enterprise(modelData)
                        readonly property bool busy: modelData.stateChanging || panel.busyFor === modelData.name
                        readonly property string error: panel.status[modelData.name] ?? ""
                        Layout.fillWidth: true
                        implicitHeight: col.implicitHeight + 16
                        radius: 10
                        color: rowMouse.containsMouse || forgetMouse.containsMouse || asking ? Theme.raised : "transparent"

                        Connections {
                            target: row.modelData
                            function onConnectionFailed(reason) {
                                panel.setStatus(row.modelData.name,
                                    reason === ConnectionFailReason.NoSecrets ? "Wrong password"
                                    : reason === ConnectionFailReason.WifiNetworkLost ? "Network out of range"
                                    : reason === ConnectionFailReason.WifiAuthTimeout ? "No answer from the network"
                                    : "Couldn't connect");
                            }
                            function onConnectedChanged() { if (row.modelData.connected) panel.setStatus(row.modelData.name, ""); }
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                const n = row.modelData;
                                if (row.busy) return;
                                if (n.connected) { n.disconnect(); return; }
                                panel.setStatus(n.name, "");
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
                                Icon { // lock; a person badge for networks that want a username too
                                    visible: panel.secured(row.modelData); size: 14
                                    text: row.eap ? "badge" : "lock"; color: Theme.faint
                                }
                                Label { // what a click does (or what's happening)
                                    readonly property bool hov: rowMouse.containsMouse || forgetMouse.containsMouse
                                    text: row.busy ? "Connecting…"
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

                            Label {
                                visible: row.error !== ""
                                Layout.fillWidth: true
                                text: row.error
                                color: Theme.red
                                font.pixelSize: Theme.textSm
                                wrapMode: Text.Wrap
                            }

                            Rectangle { // text field
                                visible: row.asking && row.eap
                                Layout.fillWidth: true
                                implicitHeight: 32; radius: 16
                                color: Theme.base; border.color: user.activeFocus ? Theme.amber : Theme.line
                                TextInput {
                                    id: user
                                    anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                                    verticalAlignment: TextInput.AlignVCenter
                                    echoMode: TextInput.Normal
                                    color: Theme.fg; clip: true
                                    font { family: Theme.font; pixelSize: Theme.text }
                                    onVisibleChanged: if (visible) forceActiveFocus()
                                    onAccepted: pw.forceActiveFocus()
                                    Label { anchors.verticalCenter: parent.verticalCenter; visible: !user.text
                                            text: "Username"; color: Theme.faint }
                                }
                            }
                            Rectangle { // text field
                                visible: row.asking
                                Layout.fillWidth: true
                                implicitHeight: 32; radius: 16
                                color: Theme.base; border.color: pw.activeFocus ? Theme.amber : Theme.line
                                TextInput {
                                    id: pw
                                    anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                                    verticalAlignment: TextInput.AlignVCenter
                                    echoMode: TextInput.Password
                                    color: Theme.fg; clip: true
                                    font { family: Theme.font; pixelSize: Theme.text }
                                    onVisibleChanged: if (visible && !row.eap) forceActiveFocus()
                                    onAccepted: {
                                        if (row.eap) {
                                            if (user.text === "") { user.forceActiveFocus(); return; }
                                            panel.runConnect("eap", row.modelData.name, user.text + "\n" + text + "\n");
                                        } else {
                                            row.modelData.connectWithPsk(text);
                                        }
                                        user.text = ""; text = ""; panel.askingFor = "";
                                    }
                                    Label { anchors.verticalCenter: parent.verticalCenter; visible: !pw.text
                                            text: "Password, then Enter"; color: Theme.faint }
                                }
                            }
                        }
                    }
                }
            }
            }

            ColumnLayout { // hidden network (not broadcasting its name)
                visible: Networking.wifiEnabled && panel.askingFor === panel.hiddenKey
                Layout.fillWidth: true
                spacing: 8
                Label { text: "Hidden network"; font.weight: Font.DemiBold }
                Rectangle { // text field
                    Layout.fillWidth: true
                    implicitHeight: 32; radius: 16
                    color: Theme.base; border.color: hidSsid.activeFocus ? Theme.amber : Theme.line
                    TextInput {
                        id: hidSsid
                        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Normal
                        color: Theme.fg; clip: true
                        font { family: Theme.font; pixelSize: Theme.text }
                        onVisibleChanged: if (visible) forceActiveFocus()
                        onAccepted: hidPw.forceActiveFocus()
                        Label { anchors.verticalCenter: parent.verticalCenter; visible: !hidSsid.text
                                text: "Network name"; color: Theme.faint }
                    }
                }
                Rectangle { // text field
                    Layout.fillWidth: true
                    implicitHeight: 32; radius: 16
                    color: Theme.base; border.color: hidPw.activeFocus ? Theme.amber : Theme.line
                    TextInput {
                        id: hidPw
                        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        color: Theme.fg; clip: true
                        font { family: Theme.font; pixelSize: Theme.text }
                        onAccepted: {
                            if (hidSsid.text === "") { hidSsid.forceActiveFocus(); return; }
                            panel.runConnect("hidden", hidSsid.text, text + "\n");
                            hidSsid.text = ""; text = ""; panel.askingFor = "";
                        }
                        Label { anchors.verticalCenter: parent.verticalCenter; visible: !hidPw.text
                                text: "Password (empty if open), then Enter"; color: Theme.faint }
                    }
                }
                Label { visible: panel.status[panel.hiddenKey] !== undefined && panel.status[panel.hiddenKey] !== ""
                        text: panel.status[panel.hiddenKey] ?? ""; color: Theme.red; font.pixelSize: Theme.textSm }
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
                Label { text: "Hidden network…"; color: hidMouse.containsMouse ? Theme.fg : Theme.muted; font.pixelSize: Theme.textSm
                        visible: Networking.wifiEnabled
                        MouseArea { id: hidMouse; anchors.fill: parent; hoverEnabled: true
                                    onClicked: panel.askingFor = panel.askingFor === panel.hiddenKey ? "" : panel.hiddenKey } }
                Item { Layout.fillWidth: true }
                Label { text: "Network settings…"; color: setMouse.containsMouse ? Theme.fg : Theme.muted; font.pixelSize: Theme.textSm
                        MouseArea { id: setMouse; anchors.fill: parent; hoverEnabled: true
                                    onClicked: { Panels.close(); Quickshell.execDetached(["nm-connection-editor"]); } } }
            }
        }
    }
}
