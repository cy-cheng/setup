import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Networking
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

    function appIcon(cls) {
        const e = DesktopEntries.heuristicLookup(cls);
        return Quickshell.iconPath(e?.icon || cls, "application-x-executable");
    }

    // ── Left: workspaces ────────────────────────────────────────────────
    Island {
        anchors { left: parent.left; leftMargin: bar.innerLeft; verticalCenter: parent.verticalCenter }
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
                        if (t.workspace === modelData) out.push(t.lastIpcObject?.class ?? "");
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

    // ── Centre: date · time (centred on the inner area, not the screen) ──
    SystemClock { id: clock; precision: SystemClock.Minutes }
    Island {
        x: (bar.innerLeft + bar.innerRight - width) / 2
        anchors.verticalCenter: parent.verticalCenter
        Label { text: Qt.formatDateTime(clock.date, "ddd d MMM"); color: Theme.muted }
        Label { text: Qt.formatDateTime(clock.date, "HH:mm"); font.pixelSize: Theme.textLg; font.weight: Font.DemiBold }
    }

    // ── Right: status ───────────────────────────────────────────────────
    Island {
        anchors { right: parent.right; rightMargin: parent.width - bar.innerRight; verticalCenter: parent.verticalCenter }
        spacing: 12

        // Input method: Caps Lock or click toggles
        Label {
            text: Sys.imeLabels[Sys.inputMethod] ?? "–"
            color: Sys.inputMethod && Sys.inputMethod !== "keyboard-us" ? Theme.amber : Theme.muted
            font.weight: Font.DemiBold
            MouseArea { anchors.fill: parent; onClicked: Sys.toggleIme() }
        }

        Icon {
            readonly property bool online: Networking.connectivity === NetworkConnectivity.Full
            text: online ? "wifi" : "wifi_off"
            color: online ? Theme.fg : Theme.red
            MouseArea { anchors.fill: parent; onClicked: Quickshell.execDetached(["kitty", "-e", "nmtui"]) }
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

        Ring { // battery
            readonly property real raw: UPower.displayDevice?.percentage ?? 0
            readonly property real frac: raw > 1 ? raw / 100 : raw
            value: frac
            icon: !UPower.onBattery ? "bolt" : "battery_full"
            tint: UPower.onBattery && frac <= 0.15 ? Theme.red : Theme.fg
            tip: "Battery " + Math.round(frac * 100) + "%" + (!UPower.onBattery ? " · plugged in" : "")
        }

        Icon { // power profile: click cycles
            text: ({ "power-saver": "eco", "balanced": "balance", "performance": "speed" })[Sys.powerProfile] ?? "balance"
            color: Sys.powerProfile === "balanced" ? Theme.muted : Theme.amber
            MouseArea { anchors.fill: parent; onClicked: Sys.cycleProfile() }
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
        }
    }
}
