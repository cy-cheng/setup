pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// Notification server + model.
// Tiers:  needs (sticky, gets through focus mode) · fyi (brief popup) ·
//         quiet (no popup, history + badge only) · system (small, brief)
Singleton {
    id: root

    property bool focusMode: false     // only "needs" pops up
    property bool centreOpen: false
    property int rev: 0                // bumped on every change; views bind to it
    property var history: []           // records, newest first
    property var popups: []            // records currently shown as popups

    readonly property int unseen: { rev; return history.filter(r => !r.seen && r.tier !== "quiet").length; }
    readonly property var rank: ({ needs: 0, fyi: 1, system: 2, quiet: 3 })

    // ── Rules ─────────────────────────────────────────────────────────────
    // Per-app policy; first match wins. Match is a regex on desktop entry or app name.
    readonly property var appRules: [
        { match: /onedrive/i, tier: "quiet" },
        { match: /^(networkmanager|nm-applet|blueberry|blueman|udiskie)$/i, tier: "system" },
    ]

    function tierFor(n) {
        const h = n.hints || {};
        if (h["x-nixie-tier"]) return h["x-nixie-tier"];
        if (h["x-agent-state"] === "waiting") return "needs";
        if (h["x-agent-state"] === "done") return "fyi";
        for (const r of appRules)
            if (r.match.test(n.desktopEntry || "") || r.match.test(n.appName || "")) return r.tier;
        if (n.urgency === NotificationUrgency.Critical) return "needs";
        if (n.urgency === NotificationUrgency.Low) return "quiet";
        const cat = String(h["category"] || "");
        if (/^(device|network|presence)/.test(cat)) return "system";
        return "fyi";
    }

    function keyFor(n) {
        const h = n.hints || {};
        if (h["x-agent-session"]) return "agent:" + h["x-agent-session"];
        return (n.desktopEntry || n.appName || "unknown").toLowerCase();
    }

    function iconFor(n) {
        if (n.appIcon) return n.appIcon;
        const e = n.desktopEntry ? DesktopEntries.byId(n.desktopEntry) : null;
        return e?.icon ?? "";
    }

    // ── Server ────────────────────────────────────────────────────────────
    NotificationServer {
        keepOnReload: true
        persistenceSupported: true
        actionsSupported: true
        bodyMarkupSupported: true
        imageSupported: true
        onNotification: n => root.add(n)
    }

    function add(n) {
        n.tracked = true;
        const key = keyFor(n), tier = tierFor(n);
        // Collapse repeats: same source + same summary just updates the existing entry.
        let rec = history.find(r => r.key === key && r.summary === n.summary && !r.dismissed);
        if (rec) {
            rec.count += 1;
            rec.body = n.body;
            rec.time = new Date();
            rec.notif = n;
            rec.seen = false;
            history = [rec].concat(history.filter(r => r !== rec));
        } else {
            rec = {
                id: n.id, key: key, tier: tier, count: 1, seen: false, dismissed: false,
                appName: n.appName || "Unknown", desktopEntry: n.desktopEntry || "",
                icon: iconFor(n), summary: n.summary, body: n.body, time: new Date(),
                hints: n.hints || {}, notif: n,
            };
            history = [rec].concat(history).slice(0, 200);
        }
        // Progress / replaced notifications update in place.
        n.summaryChanged.connect(() => { rec.summary = n.summary; bump(); });
        n.bodyChanged.connect(() => { rec.body = n.body; bump(); });
        n.closed.connect(() => { rec.notif = null; removePopup(rec); });

        const shows = tier === "needs" || (!focusMode && (tier === "fyi" || tier === "system"));
        if (shows) {
            const ms = tier === "needs" ? 0 : tier === "system" ? 3000 : 6000;
            rec.expireAt = ms ? Date.now() + ms : 0;
            popups = [rec].concat(popups.filter(p => p !== rec)).slice(0, 4);
        }
        bump();
    }

    function bump() { rev += 1; }
    function removePopup(rec) { popups = popups.filter(p => p !== rec); bump(); }

    Timer {
        interval: 500; running: root.popups.length > 0; repeat: true
        onTriggered: {
            const now = Date.now();
            const keep = root.popups.filter(p => !p.expireAt || p.expireAt > now);
            if (keep.length !== root.popups.length) { root.popups = keep; root.bump(); }
        }
    }

    // ── Actions ───────────────────────────────────────────────────────────
    // Click: run the app's default action, then focus the window that sent it.
    function activate(rec) {
        const n = rec.notif;
        if (n) {
            const def = n.actions.find(a => a.identifier === "default");
            if (def) def.invoke();
        }
        const pid = rec.hints["sender-pid"];
        Quickshell.execDetached(["nixie-focus",
            "--pid", pid ? String(pid) : "",
            "--desktop", rec.desktopEntry, "--app", rec.appName]);
        markSeen(rec.key);
        removePopup(rec);
    }

    function dismiss(rec) {
        rec.dismissed = true;
        if (rec.notif) rec.notif.dismiss();
        history = history.filter(r => r !== rec);
        removePopup(rec);
    }

    function dismissGroup(key) {
        for (const r of history.filter(r => r.key === key)) dismiss(r);
    }

    function clearAll() {
        for (const r of history.slice()) dismiss(r);
    }

    function markSeen(key) {
        for (const r of history) if (!key || r.key === key) r.seen = true;
        bump();
    }

    onCentreOpenChanged: if (centreOpen) markSeen("")

    // Groups for the rail and centre: one per source, "needs" first, then newest.
    function groups() {
        const map = {};
        for (const r of history) {
            const g = map[r.key] ?? (map[r.key] = {
                key: r.key, label: r.appName, icon: r.icon, tier: r.tier,
                items: [], unseen: 0, latest: r.time });
            g.items.push(r);
            if (!r.seen) g.unseen += 1;
            if (rank[r.tier] < rank[g.tier]) g.tier = r.tier;
        }
        return Object.values(map).sort((a, b) =>
            (rank[a.tier] - rank[b.tier]) || (b.latest - a.latest));
    }

    // `qs ipc call notifs toggle` etc. (bound to keys in Hyprland)
    IpcHandler {
        target: "notifs"
        function toggle(): void { root.centreOpen = !root.centreOpen; }
        function focus(): void { root.focusMode = !root.focusMode; }
        function clear(): void { root.clearAll(); }
    }
}
