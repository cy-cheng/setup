pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// VPN connections from NetworkManager (OpenVPN, WireGuard, …) via nmcli.
// Re-read whenever `nmcli monitor` reports a change, so it is event-driven.
Singleton {
    id: root

    // [{ name, uuid, type, active, busy }]
    property var connections: []
    property var pending: ({})          // uuid -> "up" | "down" while nmcli is working
    readonly property var activeOnes: connections.filter(c => c.active)
    readonly property bool anyActive: activeOnes.length > 0

    function toggle(c) {
        const verb = c.active ? "down" : "up";
        lastError = "";
        const p = Object.assign({}, pending); p[c.uuid] = verb; pending = p;
        const proc = runner.createObject(root, { uuid: c.uuid, command: ["nmcli", "connection", verb, "uuid", c.uuid] });
        proc.running = true;
    }

    function refresh() { if (!lister.running) lister.running = true; else again = true; }
    property bool again: false

    Process {
        id: lister
        command: ["nmcli", "-t", "-f", "NAME,UUID,TYPE,ACTIVE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    // NAME may contain ':' (escaped as '\:'); UUID, TYPE and ACTIVE never do,
                    // so take those from the right.
                    const f = line.split(":");
                    if (f.length < 4) continue;
                    const active = f.pop(), type = f.pop(), uuid = f.pop();
                    if (type !== "vpn" && type !== "wireguard") continue;
                    out.push({ name: f.join(":").replace(/\\:/g, ":").replace(/\\$/, ""), uuid: uuid, type: type, active: active === "yes" });
                }
                out.sort((a, b) => a.name.localeCompare(b.name));
                root.connections = out;
            }
        }
        onExited: if (root.again) { root.again = false; running = true; }
    }

    // Any NetworkManager change → re-read (debounced).
    Process {
        id: monitor
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser { onRead: debounce.restart() }
        onExited: restartMonitor.start()
    }
    Timer { id: restartMonitor; interval: 3000; onTriggered: { monitor.running = true; root.refresh(); } }
    Timer { id: debounce; interval: 300; onTriggered: root.refresh() }

    Component {
        id: runner
        Process {
            property string uuid
            stderr: StdioCollector { id: err }
            onExited: code => {
                const p = Object.assign({}, root.pending); delete p[uuid]; root.pending = p;
                if (code !== 0) root.lastError = err.text.trim().split("\n").pop();
                root.refresh();
                destroy();
            }
        }
    }
    property string lastError: ""

    IpcHandler { // qs ipc call vpn list
        target: "vpn"
        function list(): string { return JSON.stringify(root.connections); }
        function refresh(): void { root.refresh(); }
        function toggle(name: string): void {
            const c = root.connections.find(x => x.name === name);
            if (c) root.toggle(c);
        }
    }

    Component.onCompleted: refresh()
}
