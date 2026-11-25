import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import qs.services

// On-screen display: a small glass pill near the bottom of the screen that appears for
// ~1.5 s whenever volume or brightness changes (keys, bar scroll, anything else).
PanelWindow {
    id: osd
    required property var modelData
    screen: modelData

    readonly property bool onFocusedScreen: Quickshell.screens.length < 2
        || modelData.name === (Hyprland.focusedMonitor?.name ?? "")

    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [osd.sink] }
    readonly property var audio: sink?.audio

    property string kind: "volume"          // volume | brightness
    property bool shown: false
    property bool armed: false              // ignore the initial values at start-up
    Timer { interval: 1500; running: true; onTriggered: osd.armed = true }
    Timer { id: hide; interval: 1500; onTriggered: osd.shown = false }

    function show(k) {
        if (!armed || !onFocusedScreen) return;
        kind = k; shown = true; hide.restart();
    }
    Connections {
        target: osd.audio
        ignoreUnknownSignals: true          // audio is null until the sink is bound
        function onVolumeChanged() { osd.show("volume"); }
        function onMutedChanged() { osd.show("volume"); }
    }
    Connections {
        target: Sys
        function onBrightnessChanged() { osd.show("brightness"); }
    }

    readonly property bool muted: kind === "volume" && (audio?.muted ?? false)
    readonly property real value: kind === "volume" ? (audio?.volume ?? 0) : Sys.brightness
    readonly property string icon: kind === "brightness"
        ? (value < 0.34 ? "brightness_5" : value < 0.67 ? "brightness_6" : "brightness_7")
        : muted || value === 0 ? "volume_off" : value < 0.34 ? "volume_mute" : value < 0.67 ? "volume_down" : "volume_up"

    visible: shown || pill.opacity > 0
    anchors.bottom: true
    margins.bottom: Theme.edge + 64
    implicitWidth: 280
    implicitHeight: 48
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}
    WlrLayershell.namespace: "nixie-popups"
    WlrLayershell.layer: WlrLayer.Overlay

    Rectangle {
        id: pill
        anchors.fill: parent
        radius: height / 2
        color: Theme.glass
        border.color: Theme.line
        opacity: osd.shown ? 1 : 0
        scale: osd.shown ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        RowLayout {
            anchors { fill: parent; leftMargin: 16; rightMargin: 18 }
            spacing: 12

            Icon {
                text: osd.icon
                color: osd.muted ? Theme.faint : Theme.fg
            }
            Rectangle { // track
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: 6
                radius: 3
                color: Theme.track
                Rectangle { // fill; above 100 % (volume boost) it turns amber
                    height: parent.height; radius: 3
                    width: parent.width * Math.min(1, osd.value)
                    color: osd.muted ? Theme.faint : osd.value > 1.001 ? Theme.amber : Theme.fg
                    Behavior on width { NumberAnimation { duration: 90 } }
                }
            }
            Label {
                Layout.preferredWidth: 34
                horizontalAlignment: Text.AlignRight
                text: osd.muted ? "—" : Math.round(osd.value * 100)
                color: osd.muted ? Theme.faint : osd.value > 1.001 ? Theme.amber : Theme.fg
                font.pixelSize: Theme.textSm
                font.weight: Font.DemiBold
            }
        }
    }
}
