import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.services

// Right edge of the frame: a dock of pinned + running apps.
//   dots on the left = open windows (amber = focused app)
//   badge = unread notifications from that app; amber pulsing outline = needs you
//   click: focus (again: next window) or launch · middle: new window · right: clear its notifications
// Notifications from things that aren't apps (scripts, agents) get tiles at the bottom.
Item {
    id: dock

    // ── Pinned apps (~/.local/state/nixie-dock.json → {"pinned": [...desktop ids]}) ──
    property var pinned: ["kitty", "google-chrome", "discord", "slack", "obsidian", "thunar"]
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/nixie-dock.json"
        onLoaded: { try { const p = JSON.parse(text()).pinned; if (Array.isArray(p)) dock.pinned = p; } catch (e) {} }
    }

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

    readonly property var apps: {
        const out = [], seen = {};
        const push = (id, pinnedFlag) => {
            if (seen[id]) return;
            const e = DesktopEntries.byId(id) ?? DesktopEntries.heuristicLookup(id);
            if (!e) return;
            seen[id] = seen[e.id] = true;
            out.push({ id: e.id, entry: e, pinned: pinnedFlag });
        };
        for (const id of pinned) push(id, true);
        for (const id of Object.keys(windowsById)) push(id, false);
        return out;
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
