import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.services

// Dashboard: a drawer that slides down out of the bar under the clock (click the clock,
// or qs ipc call panels toggle dashboard). Time, media, big gauges, quick toggles.
// Esc or a click outside closes it.
PanelWindow {
    id: dash
    required property var modelData
    screen: modelData

    readonly property bool onFocusedScreen: Quickshell.screens.length < 2
        || modelData.name === (Hyprland.focusedMonitor?.name ?? "")
    readonly property bool open: Panels.open === "dashboard" && onFocusedScreen
    visible: open || card.y > -card.height

    anchors { top: true }
    exclusionMode: ExclusionMode.Ignore
    margins.top: Theme.barH                 // flush with the bar: the drawer comes out of it
    implicitWidth: 500
    implicitHeight: card.height + 2
    color: "transparent"
    WlrLayershell.namespace: "nixie-centre"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    HyprlandFocusGrab { windows: [dash]; active: dash.open; onCleared: Panels.close() }

    // ── Data ──
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [dash.sink, dash.source] }
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var battery: UPower.displayDevice
    readonly property var player: {
        const ps = Mpris.players.values;
        return ps.find(p => p.isPlaying) ?? ps[0] ?? null;
    }
    Timer { // MPRIS position is not pushed; poll it while visible
        interval: 1000; repeat: true
        running: dash.open && (dash.player?.isPlaying ?? false)
        onTriggered: dash.player.positionChanged()
    }

    property real uptime: 0
    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        onLoaded: dash.uptime = parseFloat(text().split(" ")[0]) || 0
    }
    onOpenChanged: if (open) { uptimeFile.reload(); card.forceActiveFocus(); }

    function dur(s) {
        s = Math.max(0, Math.round(s));
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60);
        return h > 0 ? h + "h " + m + "m" : m + "m";
    }
    function mmss(s) {
        s = Math.max(0, Math.floor(s));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }
    readonly property string batteryLine: {
        if (!battery?.ready) return "";
        if (!UPower.onBattery)
            return battery.timeToFull > 0 ? "full in " + dur(battery.timeToFull) : "plugged in";
        return battery.timeToEmpty > 0 ? dur(battery.timeToEmpty) + " left" : "on battery";
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // ── Drawer ──
    Item {
        anchors.fill: parent
        clip: true                       // the card slides out from behind the bar

        Rectangle {
            id: card
            width: parent.width
            height: col.implicitHeight + 36
            y: dash.open ? 0 : -height - 2
            Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            radius: Theme.radius + 6
            topLeftRadius: 0
            topRightRadius: 0
            color: Theme.glass
            border.color: Theme.line
            focus: true
            Keys.onEscapePressed: Panels.close()

            ColumnLayout {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
                spacing: 18

                // ── Time ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14
                    Label {
                        text: Qt.formatDateTime(Sys.zoned(clock.date), "HH:mm")
                        font.pixelSize: 40
                        font.weight: Font.DemiBold
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.maximumWidth: 100000
                        spacing: 4
                        Label { text: Qt.formatDateTime(Sys.zoned(clock.date), "dddd"); font.pixelSize: Theme.textLg; font.weight: Font.DemiBold }
                        Label { text: Qt.formatDateTime(Sys.zoned(clock.date), "d MMMM yyyy"); color: Theme.muted; font.pixelSize: Theme.textSm }
                    }
                    ColumnLayout {
                        spacing: 4
                        Label { Layout.alignment: Qt.AlignRight; text: "up " + dash.dur(dash.uptime); color: Theme.muted; font.pixelSize: Theme.textSm }
                        Label { Layout.alignment: Qt.AlignRight; text: dash.batteryLine; color: Theme.faint; font.pixelSize: Theme.textSm; visible: text !== "" }
                    }
                }

                // ── Media ──
                Rectangle {
                    Layout.fillWidth: true
                    visible: dash.player !== null
                    implicitHeight: 96
                    radius: Theme.radius
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.color: Theme.line

                    Image {
                        id: art
                        visible: false
                        source: dash.player?.trackArtUrl ?? ""
                        sourceSize: Qt.size(144, 144)
                        fillMode: Image.PreserveAspectCrop
                        width: 72; height: 72
                        layer.enabled: true
                    }
                    Rectangle {
                        id: artMask
                        visible: false
                        width: 72; height: 72; radius: 10
                        layer.enabled: true
                    }
                    RowLayout {
                        anchors { fill: parent; margins: 12 }
                        spacing: 14
                        Item {
                            Layout.preferredWidth: 72; Layout.preferredHeight: 72
                            Rectangle {
                                anchors.fill: parent; radius: 10
                                color: Theme.raised
                                visible: art.status !== Image.Ready
                                Icon { anchors.centerIn: parent; size: 28; text: "music_note"; color: Theme.muted }
                            }
                            MultiEffect {
                                anchors.fill: parent
                                visible: art.status === Image.Ready
                                source: art
                                maskEnabled: true
                                maskSource: artMask
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: dash.player?.trackTitle || dash.player?.identity || ""
                                font.weight: Font.DemiBold
                            }
                            Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: dash.player?.trackArtist || (dash.player?.trackTitle ? dash.player?.identity ?? "" : "")
                                visible: text !== ""
                                color: Theme.muted
                                font.pixelSize: Theme.textSm
                            }
                            Item { Layout.fillHeight: true }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Rectangle { // progress
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    implicitHeight: 4; radius: 2
                                    color: Theme.track
                                    readonly property real frac: (dash.player?.length ?? 0) > 0
                                        ? Math.min(1, dash.player.position / dash.player.length) : 0
                                    Rectangle { height: parent.height; radius: 2; width: parent.width * parent.frac; color: Theme.fg }
                                }
                                Label {
                                    visible: (dash.player?.length ?? 0) > 0
                                    text: dash.mmss(dash.player?.position ?? 0) + " / " + dash.mmss(dash.player?.length ?? 0)
                                    color: Theme.faint
                                    font.pixelSize: 9
                                }
                            }
                        }
                        RowLayout {
                            spacing: 2
                            Icon {
                                size: 22; text: "skip_previous"
                                color: dash.player?.canGoPrevious ? Theme.fg : Theme.faint
                                MouseArea { anchors.fill: parent; onClicked: dash.player?.previous() }
                            }
                            Rectangle {
                                implicitWidth: 40; implicitHeight: 40; radius: 20
                                color: Theme.fg
                                Icon {
                                    anchors.centerIn: parent; size: 24
                                    text: dash.player?.isPlaying ? "pause" : "play_arrow"
                                    color: Theme.base
                                }
                                MouseArea { anchors.fill: parent; onClicked: dash.player?.togglePlaying() }
                            }
                            Icon {
                                size: 22; text: "skip_next"
                                color: dash.player?.canGoNext ? Theme.fg : Theme.faint
                                MouseArea { anchors.fill: parent; onClicked: dash.player?.next() }
                            }
                        }
                    }
                }

                // ── Gauges ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    DashGauge {
                        readonly property var audio: dash.sink?.audio
                        value: audio?.muted ? 0 : (audio?.volume ?? 0)
                        text: audio?.muted ? "—" : Math.round((audio?.volume ?? 0) * 100)
                        name: "Volume"; icon: audio?.muted ? "volume_off" : "volume_up"
                        tint: audio?.muted ? Theme.faint : (audio?.volume ?? 0) > 1.001 ? Theme.amber : Theme.fg
                        tip: "Scroll to change · click to mute"
                        onClicked: if (audio) audio.muted = !audio.muted
                        onScrolled: up => { if (audio) audio.volume = Math.max(0, Math.min(1.5, audio.volume + (up ? 0.05 : -0.05))); }
                    }
                    DashGauge {
                        value: Sys.brightness
                        text: Math.round(Sys.brightness * 100)
                        name: "Light"; icon: "light_mode"
                        tip: "Scroll to change"
                        onScrolled: up => Sys.stepBrightness(up)
                    }
                    DashGauge {
                        value: Sys.cpu
                        text: Math.round(Sys.cpu * 100)
                        name: "CPU"; icon: "memory"
                        tint: Sys.cpu > 0.85 ? Theme.amber : Theme.fg
                    }
                    DashGauge {
                        value: Sys.mem
                        text: Math.round(Sys.mem * 100)
                        name: "RAM"; icon: "memory_alt"
                        tint: Sys.mem > 0.85 ? Theme.amber : Theme.fg
                        tip: (Sys.mem * Sys.memTotalGiB).toFixed(1) + " of " + Sys.memTotalGiB.toFixed(0) + " GiB used"
                    }
                    DashGauge {
                        readonly property real frac: dash.battery?.percentage ?? 0
                        value: (!UPower.onBattery && !isCharging) ? 1 : frac   // full when held at the limit
                        text: Math.round(frac * 100)
                        readonly property bool isCharging: dash.battery?.state === UPowerDeviceState.Charging
                        charging: isCharging
                        name: "Battery"; icon: isCharging ? "bolt" : !UPower.onBattery ? "power" : "battery_full"
                        tint: (isCharging || !UPower.onBattery) ? Theme.yellow
                            : UPower.onBattery && frac <= 0.15 ? Theme.red
                            : Sys.powerProfile === "power-saver" ? Theme.green
                            : Sys.powerProfile === "performance" ? Theme.amber : Theme.fg
                        tip: "Click to change power mode"
                        onClicked: Sys.cycleProfile()
                    }
                }

                // ── Quick toggles ──
                GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    rowSpacing: 8
                    columnSpacing: 8

                    DashToggle {
                        readonly property string ssid: {
                            for (const d of Networking.devices.values)
                                if (d.type === DeviceType.Wifi)
                                    for (const n of d.networks.values) if (n.connected) return n.name;
                            return "";
                        }
                        icon: Networking.wifiEnabled ? "wifi" : "wifi_off"
                        name: "Wi-Fi"
                        detail: !Networking.wifiEnabled ? "Off" : ssid || "Not connected"
                        on: Networking.wifiEnabled
                        hasPanel: true
                        onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
                        onOpenPanel: Panels.toggle("wifi")
                    }
                    DashToggle {
                        readonly property var linked: dash.adapter ? dash.adapter.devices.values.filter(d => d.connected) : []
                        icon: !(dash.adapter?.enabled) ? "bluetooth_disabled" : linked.length ? "bluetooth_connected" : "bluetooth"
                        name: "Bluetooth"
                        detail: !(dash.adapter?.enabled) ? "Off" : linked.length ? linked.map(d => d.name).join(", ") : "On"
                        on: dash.adapter?.enabled ?? false
                        hasPanel: true
                        onToggled: if (dash.adapter) dash.adapter.enabled = !dash.adapter.enabled
                        onOpenPanel: Panels.toggle("bluetooth")
                    }
                    DashToggle {
                        readonly property bool muted: dash.source?.audio?.muted ?? true
                        icon: muted ? "mic_off" : "mic"
                        name: "Microphone"
                        detail: muted ? "Muted" : Math.round((dash.source?.audio?.volume ?? 0) * 100) + "%"
                        on: !muted
                        onToggled: if (dash.source?.audio) dash.source.audio.muted = !dash.source.audio.muted
                    }
                    DashToggle {
                        icon: Notifs.focusMode ? "do_not_disturb_on" : "do_not_disturb_off"
                        name: "Focus"
                        detail: Notifs.focusMode ? "Only what needs you" : "Off"
                        on: Notifs.focusMode
                        onToggled: Notifs.focusMode = !Notifs.focusMode
                    }
                    DashToggle {
                        icon: "coffee"
                        name: "Keep awake"
                        detail: Sys.keepAwake ? "No auto-lock" : "Off"
                        on: Sys.keepAwake
                        onToggled: Sys.keepAwake = !Sys.keepAwake
                    }
                    DashToggle {
                        icon: ({ "power-saver": "eco", "balanced": "balance", "performance": "speed" })[Sys.powerProfile] ?? "balance"
                        name: "Power mode"
                        detail: ({ "power-saver": "Power saver", "balanced": "Balanced", "performance": "Performance" })[Sys.powerProfile] ?? ""
                        on: Sys.powerProfile !== "balanced"
                        onToggled: Sys.cycleProfile()
                    }
                }
            }
        }
    }
}
