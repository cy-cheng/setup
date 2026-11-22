pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Which drop-down panels are open. Opening one closes the others.
Singleton {
    id: root
    property string open: ""        // "", "wifi", "dashboard"

    function toggle(name) { open = (open === name) ? "" : name; }
    function close() { open = ""; }

    IpcHandler { // qs ipc call panels toggle wifi
        target: "panels"
        function toggle(name: string): void { root.toggle(name); }
        function close(): void { root.close(); }
        function state(): string { return root.open; }
    }
}
