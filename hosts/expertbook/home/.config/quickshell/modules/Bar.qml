import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Networking
import qs.services

PanelWindow {
    id: bar
    required property var modelData
    screen: modelData

    anchors { top: true; left: true; right: true }
    implicitHeight: Theme.barHeight
    color: "transparent"
    WlrLayershell.namespace: "nixie-bar"

    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [bar.sink] }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        Rectangle { // hairline under the bar
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1
            color: Theme.border
        }
    }

    // ── Left: workspaces ────────────────────────────────────────────────
    Row {
        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
        spacing: 4
        Repeater {
            model: Hyprland.workspaces
            delegate: Rectangle {
                id: ws
                required property var modelData
                visible: modelData.id > 0 && modelData.monitor === bar.monitor
                width: visible ? (modelData.active ? 26 : 18) : 0
                height: 18
                radius: 9
                color: modelData.active ? Theme.amber
                     : modelData.urgent ? Theme.amberDim
                     : wsMouse.containsMouse ? Theme.surfaceHi : "transparent"
                border.color: modelData.active ? "transparent" : Theme.border
                border.width: 1
                Behavior on width { NumberAnimation { duration: 120 } }
                Text {
                    anchors.centerIn: parent
                    text: ws.modelData.name
                    color: ws.modelData.active ? "#070605" : Theme.muted
                    font { family: Theme.mono; pixelSize: 11; bold: ws.modelData.active }
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

    // ── Centre: clock ───────────────────────────────────────────────────
    SystemClock { id: clock; precision: SystemClock.Minutes }
    Text {
        anchors.centerIn: parent
        text: Qt.formatDateTime(clock.date, "ddd d MMM   HH:mm")
        color: Theme.fg
        font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
    }

    // ── Right: status ───────────────────────────────────────────────────
    component Item_: Text {
        color: Theme.fg
        font { family: Theme.mono; pixelSize: 12 }
        verticalAlignment: Text.AlignVCenter
    }

    RowLayout {
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 14

        // Input method
        Item_ {
            readonly property var names: ({ "keyboard-us": "EN", "rime": "注", "mozc": "あ", "keyboard-de": "DE" })
            text: names[Sys.inputMethod] ?? (Sys.inputMethod || "–")
            color: Sys.inputMethod === "keyboard-us" ? Theme.muted : Theme.amber
        }

        // Network
        Item_ {
            readonly property bool online: Networking.connectivity === NetworkConnectivity.Full
            text: online ? "" : ""
            color: online ? Theme.fg : Theme.red
            MouseArea { anchors.fill: parent; onClicked: Quickshell.execDetached(["kitty", "-e", "nmtui"]) }
        }

        // Volume: scroll to change, click to mute
        Item_ {
            readonly property var audio: bar.sink?.audio
            readonly property int pct: Math.round((audio?.volume ?? 0) * 100)
            text: (audio?.muted ? " " : " ") + pct + "%"
            color: audio?.muted ? Theme.faint : Theme.fg
            MouseArea {
                anchors.fill: parent
                onClicked: if (parent.audio) parent.audio.muted = !parent.audio.muted
                onWheel: w => {
                    if (!parent.audio) return;
                    const v = parent.audio.volume + (w.angleDelta.y > 0 ? 0.05 : -0.05);
                    parent.audio.volume = Math.max(0, Math.min(1.5, v));
                }
            }
        }

        // Battery
        Item_ {
            readonly property var dev: UPower.displayDevice
            readonly property real raw: dev?.percentage ?? 0
            readonly property int pct: Math.round(raw > 1 ? raw : raw * 100)
            readonly property bool plugged: !UPower.onBattery
            text: (plugged ? " " : ["", "", "", "", ""][Math.min(4, Math.floor(pct / 21))] + " ") + pct + "%"
            color: !plugged && pct <= 15 ? Theme.red : Theme.fg
        }

        // Power profile: click cycles power-saver → balanced → performance
        Item_ {
            text: ({ "power-saver": "", "balanced": "", "performance": "" })[Sys.powerProfile] ?? ""
            color: Sys.powerProfile === "performance" ? Theme.amber
                 : Sys.powerProfile === "power-saver" ? Theme.green : Theme.fg
            MouseArea { anchors.fill: parent; onClicked: Sys.cycleProfile() }
        }

        // Notifications: bell with unseen count; moon in focus mode. Click opens the centre.
        Item_ {
            text: (Notifs.focusMode ? "" : "") + (Notifs.unseen > 0 ? " " + Notifs.unseen : "")
            color: Notifs.focusMode ? Theme.amberDim : Notifs.unseen > 0 ? Theme.amber : Theme.muted
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: m => m.button === Qt.RightButton ? Notifs.focusMode = !Notifs.focusMode
                                                             : Notifs.centreOpen = !Notifs.centreOpen
            }
        }
    }
}
