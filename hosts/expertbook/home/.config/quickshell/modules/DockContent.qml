import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.services

// Right edge of the frame: a dock of the apps that have windows open (no pinned list),
// ordered by the workspace they're on.
//   dots on the left = open windows (amber = focused app)
//   badge = unread notifications from that app; amber pulsing outline = needs you
//   click: focus (again: next window) · middle: new window · right: clear its notifications
// Notifications from things that aren't apps (scripts, agents) get tiles at the bottom.
Item {
    id: dock
    implicitWidth: 56
    implicitHeight: col.implicitHeight + Theme.gap * 2

    // Window → desktop entry id
    function entryIdFor(t) {
        const app = t.wayland?.appId || t.lastIpcObject?.class || "";
        const e = app ? DesktopEntries.heuristicLookup(app) : null;
        return e?.id ?? app;
    }
    function addr(t) { const a = String(t.address); return a.startsWith("0x") ? a : "0x" + a; }

    readonly property var windowsById: {
        const m = {};
        for (const t of Hyprland.toplevels.values) {
            // Quickshell keeps closed windows in the list; only ones with a live
            // Wayland handle are really open.
            if (!t.wayland) continue;
            const id = entryIdFor(t);
            if (!id) continue;
            (m[id] = m[id] || []).push(t);
        }
        return m;
    }
    readonly property string activeId: Hyprland.activeToplevel ? entryIdFor(Hyprland.activeToplevel) : ""

    // Notification groups, matched to apps by desktop id or name.
    readonly property var groups: { Notifs.rev; return Notifs.groups(); }
    function groupFor(e) {
        const keys = [e.id, e.name, e.startupClass].filter(k => k).map(k => String(k).toLowerCase());
        return groups.find(g => keys.includes(g.key) || keys.includes(g.label.toLowerCase())) ?? null;
    }

    // Workspace order: numbered workspaces first (1, 2, …), scratchpads after.
    function wsRank(t) {
        const id = t.workspace?.id ?? 999;
        return id > 0 ? id : 1000 - id;
    }
    readonly property var apps: {
        const out = [];
        for (const id of Object.keys(windowsById)) {
            const e = DesktopEntries.byId(id) ?? DesktopEntries.heuristicLookup(id);
            if (!e || out.some(a => a.id === e.id)) continue;
            out.push({ id: e.id, entry: e, rank: Math.min(...windowsById[id].map(wsRank)) });
        }
        return out.sort((a, b) => a.rank - b.rank);
    }
    readonly property var strayGroups: {
        const matched = apps.map(a => groupFor(a.entry)).filter(g => g).map(g => g.key);
        return groups.filter(g => !matched.includes(g.key) && (g.tier !== "quiet" || g.unseen > 0));
    }

    // Click: focus the app's window, or the next one if it's already focused; launch if none.
    property var cycleIndex: ({})
    function activate(app) {
        const wins = windowsById[app.id] || [];
        if (wins.length === 0) { app.entry.execute(); return; }
        let i = 0;
        if (activeId === app.id) i = ((cycleIndex[app.id] ?? 0) + 1) % wins.length;
        const c = Object.assign({}, cycleIndex); c[app.id] = i; cycleIndex = c;
        Hyprland.dispatch('hl.dsp.focus({ window = "address:' + addr(wins[i]) + '" })');
        const g = groupFor(app.entry);
        if (g) Notifs.markSeen(g.key);
    }

    Column {
        id: col
        anchors { top: parent.top; topMargin: Theme.gap; horizontalCenter: parent.horizontalCenter; horizontalCenterOffset: 2 }
        spacing: 6

        Repeater { // apps
            model: dock.apps
            delegate: DockTile {
                required property var modelData
                readonly property var app: modelData
                iconName: app.entry.icon
                fallback: app.entry.name
                group: dock.groupFor(app.entry)
                windows: (dock.windowsById[app.id] || []).length
                focused: dock.activeId === app.id
                tip: app.entry.name
                onLeftClicked: dock.activate(app)
                onMiddleClicked: app.entry.execute()
                onRightClicked: if (group) Notifs.dismissGroup(group.key)
            }
        }

        Rectangle { // divider before non-app attention tiles
            visible: dock.strayGroups.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            width: 20; height: 1; color: Theme.line
        }

        Repeater { // notifications from non-apps (scripts, agents)
            model: dock.strayGroups
            delegate: DockTile {
                required property var modelData
                iconName: modelData.icon
                fallback: modelData.label
                group: modelData
                tip: modelData.label
                onLeftClicked: Notifs.activate(modelData.items[0])
                onMiddleClicked: Notifs.activate(modelData.items[0])
                onRightClicked: Notifs.dismissGroup(modelData.key)
            }
        }
    }
}
