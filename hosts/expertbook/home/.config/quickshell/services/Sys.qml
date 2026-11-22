pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Small system states that have no Quickshell service: power profile, input method.
Singleton {
    id: root

    property string powerProfile: "balanced"   // power-saver | balanced | performance
    property string inputMethod: ""            // fcitx5 im name, e.g. keyboard-us, rime

    readonly property var profiles: ["power-saver", "balanced", "performance"]

    function cycleProfile() {
        const i = profiles.indexOf(powerProfile);
        setProfile.command = ["powerprofilesctl", "set", profiles[(i + 1) % profiles.length]];
        setProfile.running = true;
    }

    Process {
        id: getProfile
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            onStreamFinished: root.powerProfile = text.trim() || root.powerProfile
        }
    }
    Process {
        id: setProfile
        onExited: getProfile.running = true
    }
    Process {
        id: getIme
        command: ["fcitx5-remote", "-n"]
        stdout: StdioCollector {
            onStreamFinished: root.inputMethod = text.trim()
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!getIme.running) getIme.running = true;
            if (!getProfile.running && Date.now() % 5000 < 1000) getProfile.running = true;
        }
    }
    Component.onCompleted: getProfile.running = true
}
