pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// System states without a Quickshell service: power profile, input method,
// CPU usage, panel brightness.
Singleton {
    id: root

    property string powerProfile: "balanced"   // power-saver | balanced | performance
    property string inputMethod: ""            // fcitx5 im name: keyboard-us, rime, mozc, keyboard-de
    property real cpu: 0                        // 0..1
    property real mem: 0                        // 0..1 used (MemTotal - MemAvailable)
    property real memTotalGiB: 0
    property real brightness: 0.6               // 0..1 (from ~/.local/bin/brightness state)
    property bool keepAwake: false              // holds an idle inhibitor (hypridle honours it)

    // ── Timezone ──
    // Qt caches the timezone at start-up, so a later change (travel; the NetworkManager
    // hook sets it from the IP) wouldn't show. Track the real UTC offset and shift times.
    property int tzOffsetMin: -(new Date()).getTimezoneOffset()
    function zoned(d) {
        if (!d) return d;
        return new Date(d.getTime() + (tzOffsetMin + d.getTimezoneOffset()) * 60000);
    }
    Process {
        id: tzProbe
        command: ["date", "+%z"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.trim().match(/^([+-])(\d\d)(\d\d)$/);
                if (m) root.tzOffsetMin = (m[1] === "-" ? -1 : 1) * (parseInt(m[2]) * 60 + parseInt(m[3]));
            }
        }
    }
    Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: tzProbe.running = true }

    // Keep awake: a systemd idle inhibitor lives as long as this process runs.
    Process {
        running: root.keepAwake
        command: ["systemd-inhibit", "--what=idle", "--who=Nixie", "--why=Keep awake", "--mode=block", "sleep", "infinity"]
    }

    readonly property var profiles: ["power-saver", "balanced", "performance"]
    readonly property var imeLabels: ({ "keyboard-us": "EN", "rime": "注", "mozc": "あ", "keyboard-de": "DE" })

    function cycleProfile() {
        setProfileTo(profiles[(profiles.indexOf(powerProfile) + 1) % profiles.length]);
    }
    function stepBrightness(up) {
        Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/brightness", up ? "up" : "down"]);
    }
    function toggleIme() { Quickshell.execDetached(["fcitx5-remote", "-t"]); }
    function setProfileTo(p) {
        Quickshell.execDetached(["powerprofilesctl", "set", p]);
        root.powerProfile = p;
        reread.restart();
    }
    Timer { id: reread; interval: 600; onTriggered: getProfile.running = true }

    // ── Automatic power saver on battery ──
    // Unplug: remember the current profile and switch to power-saver.
    // Plug in: restore what you had. Manual changes in between still work.
    property string acProfile: ""
    property var lastOnBattery: null       // last real AC state; startup flicker is ignored
    Connections {
        target: UPower
        function onOnBatteryChanged() {
            if (!root.startChecked || UPower.onBattery === root.lastOnBattery) return;
            root.lastOnBattery = UPower.onBattery;
            if (UPower.onBattery) {
                root.acProfile = root.powerProfile !== "power-saver" ? root.powerProfile : (root.acProfile || "balanced");
                root.setProfileTo("power-saver");
            } else {
                root.setProfileTo(root.acProfile || "balanced");
            }
        }
    }

    // ── Power profile ──
    Process {
        id: getProfile
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.powerProfile = text.trim() || root.powerProfile;
                // Starting on battery (login, resume): apply the battery rule once.
                if (!root.startChecked && (UPower.displayDevice?.ready ?? false)) {
                    root.startChecked = true;
                    root.lastOnBattery = UPower.onBattery;
                    if (UPower.onBattery && root.powerProfile !== "power-saver") {
                        root.acProfile = root.powerProfile;
                        root.setProfileTo("power-saver");
                    }
                }
            }
        }
    }
    property bool startChecked: false
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

    // ── Memory from /proc/meminfo ──
    FileView {
        id: memInfo
        path: "/proc/meminfo"
        onLoaded: {
            const kb = k => { const m = text().match(new RegExp("^" + k + ":\\s+(\\d+)", "m")); return m ? +m[1] : 0; };
            const total = kb("MemTotal"), avail = kb("MemAvailable");
            if (total > 0) { root.mem = 1 - avail / total; root.memTotalGiB = total / 1048576; }
        }
    }

    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        property int tick: 0
        onTriggered: {
            tick += 1;
            if (!getIme.running) getIme.running = true;
            if (tick % 2 === 0) { procStat.reload(); memInfo.reload(); }
            if (tick % 5 === 0 && !getProfile.running) getProfile.running = true;
        }
    }
    Component.onCompleted: { getProfile.running = true; procStat.reload(); }

    IpcHandler { // qs ipc call awake toggle
        target: "awake"
        function toggle(): void { root.keepAwake = !root.keepAwake; }
    }
    IpcHandler { // qs ipc call power cycle | set power-saver
        target: "power"
        function cycle(): void { root.cycleProfile(); }
        function set(profile: string): void { root.setProfileTo(profile); }
    }
}
