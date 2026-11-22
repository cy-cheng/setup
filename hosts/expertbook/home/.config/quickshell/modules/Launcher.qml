import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// Launcher: drops down from the frame's top edge (Super+R).
//   type to search apps · "2*(3+4)" shows the result (Enter copies it)
//   "> cmd" runs a shell command · ↑/↓ or Tab move · Enter opens · Esc closes
PanelWindow {
    id: launcher
    required property var modelData
    screen: modelData

    readonly property bool onFocusedScreen: Quickshell.screens.length < 2
        || modelData.name === (Hyprland.focusedMonitor?.name ?? "")
    readonly property bool open: Panels.open === "launcher" && onFocusedScreen
    visible: open || card.opacity > 0

    // Centred on the screen (under the clock), not on the window area beside the rail.
    anchors { top: true }
    exclusionMode: ExclusionMode.Ignore
    margins.top: Theme.barH + Theme.gap
    implicitWidth: 560
    implicitHeight: card.implicitHeight + 24
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.namespace: "nixie-centre"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    HyprlandFocusGrab { windows: [launcher]; active: launcher.open; onCleared: Panels.close() }

    // Launch counts, so the apps you use most come first.
    property var usage: ({})
    FileView {
        id: usageFile
        path: Quickshell.env("HOME") + "/.local/state/nixie-launcher.json"
        onLoaded: { try { launcher.usage = JSON.parse(text()) || {}; } catch (e) { launcher.usage = {}; } }
    }
    function count(id) {
        const u = Object.assign({}, usage);
        u[id] = (u[id] || 0) + 1;
        usage = u;
        usageFile.setText(JSON.stringify(u));
    }

    // Chrome profiles (from Chrome's own "Local State"): each gets its own entry that opens
    // straight into that profile, skipping the profile picker.
    property var chromeProfiles: []
    FileView {
        path: Quickshell.env("HOME") + "/.config/google-chrome/Local State"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const cache = JSON.parse(text()).profile?.info_cache ?? {};
                launcher.chromeProfiles = Object.keys(cache).map(dir => ({ dir: dir, name: cache[dir].name || dir }))
                                                .sort((a, b) => a.name.localeCompare(b.name));
            } catch (e) { launcher.chromeProfiles = []; }
        }
    }
    // Looks enough like a DesktopEntry for the rows below.
    function profileEntry(p) {
        return { id: "chrome:" + p.dir, name: "Chrome · " + p.name, genericName: "Chrome profile",
                 comment: "", icon: "google-chrome", keywords: ["chrome", "google", "browser", p.name],
                 noDisplay: false, profileDir: p.dir };
    }

    property string query: ""
    property int selected: 0
    readonly property int maxRows: 8

    onOpenChanged: if (open) { query = ""; input.text = ""; selected = 0; input.forceActiveFocus(); }

    // ── Results ──
    function score(e, q) {
        const name = (e.name || "").toLowerCase();
        if (e.profileDir !== undefined && ("chrome " + name.slice(9)).includes(q)) return 3.2;
        if (name.startsWith(q)) return 3;
        if (name.split(/[\s\-_.]/).some(w => w.startsWith(q))) return 2.5;
        if (name.includes(q)) return 2;
        const extra = [e.genericName, e.comment, (e.keywords || []).join(" "), e.id].join(" ").toLowerCase();
        return extra.includes(q) ? 1 : 0;
    }
    function calc(q) {
        if (!/^[\d\s.+\-*/%()^]+$/.test(q) || !/\d/.test(q) || !/[+\-*/%^]/.test(q)) return null;
        try {
            const v = Function('"use strict"; return (' + q.replace(/\^/g, "**") + ")")();
            return (typeof v === "number" && isFinite(v)) ? +v.toPrecision(12) : null;
        } catch (e) { return null; }
    }
    readonly property var results: {
        const q = query.trim().toLowerCase();
        const out = [];
        if (q.startsWith(">")) {
            const cmd = query.trim().slice(1).trim();
            if (cmd) out.push({ kind: "cmd", title: cmd, subtitle: "Run command", icon: "terminal" });
            return out;
        }
        const c = calc(q);
        if (c !== null) out.push({ kind: "calc", title: String(c), subtitle: "= " + query.trim() + "  ·  Enter copies", icon: "calculate" });
        const apps = DesktopEntries.applications.values.filter(e => !e.noDisplay)
                         .concat(chromeProfiles.map(profileEntry));
        const used = e => usage[e.id] || 0;
        if (q === "") { // most used first, then alphabetical
            for (const e of apps.slice().sort((a, b) => (used(b) - used(a)) || a.name.localeCompare(b.name)).slice(0, maxRows))
                out.push({ kind: "app", entry: e });
        } else {
            const scored = apps.map(e => ({ e: e, s: score(e, q) })).filter(x => x.s > 0)
                               .sort((a, b) => (b.s - a.s) || (used(b.e) - used(a.e)) || a.e.name.localeCompare(b.e.name));
            for (const x of scored.slice(0, maxRows)) out.push({ kind: "app", entry: x.e });
        }
        return out;
    }
    onResultsChanged: selected = Math.min(selected, Math.max(0, results.length - 1))

    function run(r) {
        if (!r) return;
        if (r.kind === "app" && r.entry.profileDir !== undefined) {
            count(r.entry.id);
            Quickshell.execDetached(["google-chrome-stable", "--profile-directory=" + r.entry.profileDir]);
        }
        else if (r.kind === "app") { count(r.entry.id); r.entry.execute(); }
        else if (r.kind === "calc") Quickshell.execDetached(["wl-copy", r.title]);
        else if (r.kind === "cmd") Quickshell.execDetached(["sh", "-c", r.title]);
        Panels.close();
    }

    // ── Card (slides down + fades in) ──
    Rectangle {
        id: card
        anchors { left: parent.left; right: parent.right; top: parent.top }
        implicitHeight: col.implicitHeight + 24
        radius: Theme.radius + 6
        color: Theme.glass
        border.color: Theme.line
        opacity: launcher.open ? 1 : 0
        transform: Translate { y: launcher.open ? 0 : -12; Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } } }
        Behavior on opacity { NumberAnimation { duration: 140 } }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 8

            Rectangle { // search field
                Layout.fillWidth: true
                implicitHeight: 44
                radius: 22
                color: Theme.base
                border.color: input.activeFocus ? Theme.amberDim : Theme.line
                RowLayout {
                    anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                    spacing: 10
                    Icon { text: launcher.query.trim().startsWith(">") ? "terminal" : "search"; color: Theme.muted }
                    TextInput {
                        id: input
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        color: Theme.fg
                        font { family: Theme.font; pixelSize: Theme.textLg }
                        selectionColor: Theme.amberDim
                        clip: true
                        onTextChanged: { launcher.query = text; launcher.selected = 0; }
                        Keys.onEscapePressed: Panels.close()
                        Keys.onReturnPressed: launcher.run(launcher.results[launcher.selected])
                        Keys.onEnterPressed: launcher.run(launcher.results[launcher.selected])
                        Keys.onDownPressed: launcher.selected = Math.min(launcher.results.length - 1, launcher.selected + 1)
                        Keys.onUpPressed: launcher.selected = Math.max(0, launcher.selected - 1)
                        Keys.onTabPressed: launcher.selected = (launcher.selected + 1) % Math.max(1, launcher.results.length)
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !input.text
                            text: "Search apps · 2*(3+4) · > command"
                            color: Theme.faint
                            font.pixelSize: Theme.textLg
                        }
                    }
                }
            }

            ColumnLayout { // results
                Layout.fillWidth: true
                spacing: 2
                visible: launcher.results.length > 0
                Repeater {
                    model: launcher.results
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool sel: index === launcher.selected
                        readonly property bool isApp: modelData.kind === "app"
                        Layout.fillWidth: true
                        implicitHeight: 48
                        radius: 12
                        color: sel ? Theme.raised : "transparent"

                        Rectangle { // amber marker on the selected row
                            visible: row.sel
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 4 }
                            width: 3; height: 20; radius: 2
                            color: Theme.amber
                        }
                        RowLayout {
                            anchors { fill: parent; leftMargin: 16; rightMargin: 14 }
                            spacing: 12
                            Image {
                                visible: row.isApp
                                Layout.preferredWidth: 28; Layout.preferredHeight: 28
                                Layout.alignment: Qt.AlignVCenter
                                sourceSize: Qt.size(56, 56)
                                source: row.isApp ? Quickshell.iconPath(row.modelData.entry.icon, "application-x-executable") : ""
                            }
                            Icon {
                                visible: !row.isApp
                                size: 24
                                Layout.preferredWidth: 28
                                text: row.modelData.icon ?? ""
                                color: Theme.amber
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: row.isApp ? row.modelData.entry.name : row.modelData.title
                                    font.weight: row.sel ? Font.DemiBold : Font.Normal
                                }
                                Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    visible: text !== ""
                                    text: row.isApp ? (row.modelData.entry.genericName || row.modelData.entry.comment || "") : row.modelData.subtitle
                                    color: Theme.muted
                                    font.pixelSize: Theme.textSm
                                }
                            }
                            Label { visible: row.sel; text: "↵"; color: Theme.faint }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: launcher.selected = row.index
                            onClicked: launcher.run(row.modelData)
                        }
                    }
                }
            }

            Label {
                visible: launcher.results.length === 0 && launcher.query.trim() !== ""
                Layout.leftMargin: 8
                text: "Nothing found"
                color: Theme.faint
            }
        }
    }
}
