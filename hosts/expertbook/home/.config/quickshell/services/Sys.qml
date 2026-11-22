pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// System states without a Quickshell service: power profile, input method,
// CPU usage, panel brightness.
Singleton {
    id: root

    property string powerProfile: "balanced"   // power-saver | balanced | performance
    property string inputMethod: ""            // fcitx5 im name: keyboard-us, rime, mozc, keyboard-de
    property real cpu: 0                        // 0..1
    property real brightness: 0.6               // 0..1 (from ~/.local/bin/brightness state)

    readonly property var profiles: ["power-saver", "balanced", "performance"]
    readonly property var imeLabels: ({ "keyboard-us": "EN", "rime": "注", "mozc": "あ", "keyboard-de": "DE" })

    function cycleProfile() {
        const i = profiles.indexOf(powerProfile);
        setProfile.command = ["powerprofilesctl", "set", profiles[(i + 1) % profiles.length]];
        setProfile.running = true;
    }
    function stepBrightness(up) {
        Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/brightness", up ? "up" : "down"]);
    }
    function toggleIme() { Quickshell.execDetached(["fcitx5-remote", "-t"]); }

    // ── Power profile ──
    Process {
        id: getProfile
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector { onStreamFinished: root.powerProfile = text.trim() || root.powerProfile }
    }
    Process { id: setProfile; onExited: getProfile.running = true }

    // ── Input method ──
    Process {
        id: getIme
        command: ["fcitx5-remote", "-n"]
        stdout: StdioCollector { onStreamFinished: root.inputMethod = text.trim() }
    }

    // ── Brightness: the brightness script writes its level (5..100) here ──
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/brightness"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { const v = parseInt(text()); if (!isNaN(v)) root.brightness = v / 100; }
    }

    // ── CPU usage from /proc/stat deltas ──
    property var lastCpu: null
    FileView {
        id: procStat
        path: "/proc/stat"
        onLoaded: {
            const f = text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
            const idle = f[3] + f[4], total = f.reduce((a, b) => a + b, 0);
            if (root.lastCpu) {
                const dt = total - root.lastCpu.total, di = idle - root.lastCpu.idle;
                if (dt > 0) root.cpu = Math.max(0, Math.min(1, 1 - di / dt));
            }
            root.lastCpu = { total: total, idle: idle };
        }
    }

    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        property int tick: 0
        onTriggered: {
            tick += 1;
            if (!getIme.running) getIme.running = true;
            if (tick % 2 === 0) procStat.reload();
            if (tick % 5 === 0 && !getProfile.running) getProfile.running = true;
        }
    }
    Component.onCompleted: { getProfile.running = true; procStat.reload(); }
}
