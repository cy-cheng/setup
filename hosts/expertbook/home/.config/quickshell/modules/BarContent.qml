import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.SystemTray
import qs.services

// Contents of the frame's top edge: three islands.
//   left: workspaces (number + app icons)   centre: date · time   right: status
Item {
    id: bar
    required property var monitor          // HyprlandMonitor of this screen
    property real innerLeft: 0             // x of the frame's inner left edge
    property real innerRight: width        // x of the frame's inner right edge

    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [bar.sink] }

    // Keep window → workspace info fresh as windows open, close and move.
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (["openwindow", "closewindow", "movewindow", "movewindowv2", "windowtitle"].includes(ev.name))
                Hyprland.refreshToplevels();
        }
    }

    function appIcon(cls) {
        const e = DesktopEntries.heuristicLookup(cls);
        return Quickshell.iconPath(e?.icon || cls, "application-x-executable");
    }

    // ── Left: workspaces ────────────────────────────────────────────────
    Island {
        anchors { left: parent.left; leftMargin: bar.innerLeft; top: parent.top }
        spacing: 4
        Repeater {
            model: Hyprland.workspaces
            delegate: Rectangle {
                id: ws
                required property var modelData
                readonly property bool mine: modelData.id > 0 && modelData.monitor === bar.monitor
                readonly property var apps: {
                    const out = [];
                    for (const t of Hyprland.toplevels.values)
                        // Live Wayland app id first; Hyprland's IPC class only fills in after a refresh.
                        if (t.workspace === modelData) out.push(t.wayland?.appId || t.lastIpcObject?.class || "");
                    return out.filter(c => c !== "");
                }
                visible: mine
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: Theme.pillH
                implicitWidth: mine ? wsRow.implicitWidth + 16 : 0
                radius: Theme.pillH / 2
                color: modelData.active ? Theme.amber : wsMouse.containsMouse ? Theme.raised : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }

                RowLayout {
                    id: wsRow
                    anchors.centerIn: parent
                    spacing: 5
                    Label {
                        text: ws.modelData.name
                        color: ws.modelData.active ? Theme.base : ws.apps.length ? Theme.fg : Theme.muted
                        font.weight: Font.DemiBold
                    }
                    Repeater {
                        model: ws.apps.slice(0, 3)
                        delegate: Image {
                            required property string modelData
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 16; Layout.preferredHeight: 16
                            sourceSize: Qt.size(32, 32)
                            source: bar.appIcon(modelData)
                        }
                    }
                    Label {
                        visible: ws.apps.length > 3
                        text: "+" + (ws.apps.length - 3)
                        color: ws.modelData.active ? Theme.base : Theme.muted
                        font.pixelSize: Theme.textSm
                    }
                }
                MouseArea {
                    id: wsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: ws.modelData.activate()
                }
            }
        }
    }

    // ── Centre: date · time ──
    SystemClock { id: clock; precision: SystemClock.Minutes }
    Island {
        id: clockIsland
        x: (bar.width - width) / 2          // centred on the screen, so the bar reads symmetric
        anchors.top: parent.top
        Label { Layout.alignment: Qt.AlignBaseline; text: Qt.formatDateTime(clock.date, "ddd d MMM"); color: Theme.muted }
        Label { Layout.alignment: Qt.AlignBaseline; text: Qt.formatDateTime(clock.date, "HH:mm")
                font.pixelSize: Theme.textLg; font.weight: Font.DemiBold }
    }
    MouseArea { parent: clockIsland; anchors.fill: parent; onClicked: Panels.toggle("dashboard") }
    Tip { parent: clockIsland; text: Qt.formatDateTime(clock.date, "dddd, d MMMM yyyy") + " · click for dashboard" }  // outside the row: no extra gap

    // ── Right: system tray (only when apps put icons there) ─────────────
    Island {
        anchors { right: statusIsland.left; rightMargin: Theme.gap; top: parent.top }
        visible: SystemTray.items.values.length > 0
        spacing: 10
        Repeater {
            model: SystemTray.items
            delegate: Item {
                id: trayItem
                required property var modelData
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 18; implicitHeight: 18
                Image {
                    anchors.fill: parent
                    sourceSize: Qt.size(36, 36)
                    source: trayItem.modelData.icon
                }
                QsMenuAnchor {
                    id: menuAnchor
                    menu: trayItem.modelData.menu
                    anchor.item: trayItem
                    anchor.edges: Edges.Bottom
                    anchor.gravity: Edges.Bottom
                    anchor.margins.top: 12
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: m => {
                        const it = trayItem.modelData;
                        if (m.button === Qt.MiddleButton) it.secondaryActivate();
                        else if (m.button === Qt.RightButton || it.onlyMenu) { if (it.hasMenu) menuAnchor.open(); }
                        else it.activate();
                    }
                    onWheel: w => trayItem.modelData.scroll(w.angleDelta.y, false)
                }
                Tip { text: trayItem.modelData.tooltipTitle || trayItem.modelData.title || trayItem.modelData.id }
            }
        }
    }

    // ── Right: status ───────────────────────────────────────────────────
    Island {
        id: statusIsland
        anchors { right: parent.right; rightMargin: parent.width - bar.innerRight; top: parent.top }
        spacing: 12

        // Input method: Caps Lock or click toggles
        Label {
            text: Sys.imeLabels[Sys.inputMethod] ?? "–"
            color: Sys.inputMethod && Sys.inputMethod !== "keyboard-us" ? Theme.amber : Theme.muted
            font.weight: Font.DemiBold
            MouseArea { anchors.fill: parent; onClicked: Sys.toggleIme() }
            Tip { text: ({ "keyboard-us": "English", "rime": "注音 (Rime)", "mozc": "日本語 (Mozc)", "keyboard-de": "Deutsch" })[Sys.inputMethod] + " · Caps Lock switches" }
        }

        Icon {
            readonly property bool online: Networking.connectivity === NetworkConnectivity.Full
            text: online ? "wifi" : "wifi_off"
            color: online ? Theme.fg : Theme.red
            MouseArea { anchors.fill: parent; onClicked: Panels.toggle("wifi") }
            Tip {
                text: {
                    for (const d of Networking.devices.values)
                        if (d.type === DeviceType.Wifi)
                            for (const n of d.networks.values) if (n.connected) return "Wi-Fi · " + n.name;
                    return Networking.wifiEnabled ? "Wi-Fi · not connected" : "Wi-Fi off";
                }
            }
        }

        Icon { // Bluetooth: off / on / connected (amber)
            readonly property var adapter: Bluetooth.defaultAdapter
            readonly property bool on: adapter?.enabled ?? false
            readonly property bool linked: on && (adapter?.devices.values.some(d => d.connected) ?? false)
            text: !on ? "bluetooth_disabled" : linked ? "bluetooth_connected" : "bluetooth"
            color: !on ? Theme.faint : linked ? Theme.amber : Theme.fg
            MouseArea { anchors.fill: parent; onClicked: Panels.toggle("bluetooth") }
            Tip {
                text: !parent.on ? "Bluetooth off"
                    : parent.linked ? "Bluetooth · " + parent.adapter.devices.values.filter(d => d.connected).map(d => d.name).join(", ")
                    : "Bluetooth on · nothing connected"
            }
        }

        Ring { // volume: scroll to change, click to mute
            readonly property var audio: bar.sink?.audio
            value: audio?.muted ? 0 : (audio?.volume ?? 0)
            icon: audio?.muted ? "volume_off" : "volume_up"
            tint: audio?.muted ? Theme.faint : Theme.fg
            tip: audio?.muted ? "Muted" : "Volume " + Math.round((audio?.volume ?? 0) * 100) + "%"
            onClicked: if (audio) audio.muted = !audio.muted
            onScrolled: up => { if (audio) audio.volume = Math.max(0, Math.min(1.5, audio.volume + (up ? 0.05 : -0.05))); }
        }

        Ring { // brightness: scroll to change
            value: Sys.brightness
            icon: "light_mode"
            tip: "Brightness " + Math.round(Sys.brightness * 100) + "%"
            onScrolled: up => Sys.stepBrightness(up)
        }

        Ring { // CPU
            value: Sys.cpu
            icon: "memory"
            tint: Sys.cpu > 0.85 ? Theme.amber : Theme.fg
            tip: "CPU " + Math.round(Sys.cpu * 100) + "%"
        }

        Ring { // battery level + power mode in one: click cycles power-saver → balanced → performance
            readonly property real raw: UPower.displayDevice?.percentage ?? 0
            readonly property real frac: raw > 1 ? raw / 100 : raw
            readonly property string mode: ({ "power-saver": "Power saver", "balanced": "Balanced", "performance": "Performance" })[Sys.powerProfile] ?? "Balanced"
            value: frac
            icon: !UPower.onBattery ? "bolt"
                : ({ "power-saver": "eco", "balanced": "balance", "performance": "speed" })[Sys.powerProfile] ?? "balance"
            tint: UPower.onBattery && frac <= 0.15 ? Theme.red
                : Sys.powerProfile === "performance" ? Theme.amber : Theme.fg
            tip: "Battery " + Math.round(frac * 100) + "%" + (!UPower.onBattery ? " · charging" : "")
                 + " · " + mode + " · click to change"
            onClicked: Sys.cycleProfile()
        }

        Icon { // keep awake: blocks idle lock / screen off while on
            text: "coffee"
            color: Sys.keepAwake ? Theme.amber : Theme.faint
            MouseArea { anchors.fill: parent; onClicked: Sys.keepAwake = !Sys.keepAwake }
            Tip { text: Sys.keepAwake ? "Keeping awake · no auto-lock or screen off" : "Keep awake: off" }
        }

        Icon { // notifications: left = centre, right = focus mode
            text: Notifs.focusMode ? "do_not_disturb_on" : Notifs.unseen > 0 ? "notifications_unread" : "notifications"
            color: Notifs.focusMode ? Theme.muted : Notifs.unseen > 0 ? Theme.amber : Theme.fg
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: m => m.button === Qt.RightButton ? Notifs.focusMode = !Notifs.focusMode
                                                             : Notifs.centreOpen = !Notifs.centreOpen
            }
            Tip { text: (Notifs.focusMode ? "Focus mode · " : "") + (Notifs.unseen ? Notifs.unseen + " unread" : "No new notifications") + " · right-click: focus" }
        }

        Icon { // session: lock, suspend, log out, reboot, power off
            text: "power_settings_new"
            color: Theme.muted
            MouseArea { anchors.fill: parent; onClicked: Panels.toggle("power") }
            Tip { text: "Lock, suspend, log out, reboot, power off" }
        }
    }
}
