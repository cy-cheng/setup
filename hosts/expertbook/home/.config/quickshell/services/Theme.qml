pragma Singleton
import QtQuick
import Quickshell

// Design tokens. Greyscale surfaces, amber only for emphasis.
// Layout rules: 4px grid, fixed heights, everything vertically centred, tabular digits.
Singleton {
    // ── Colour ──
    readonly property color base: "#0b0a09"        // frame
    // Translucent surfaces: Hyprland blurs what is behind them (frosted glass).
    readonly property color frame: "#b80b0a09"     // frame ~72%
    readonly property color island: "#a61a1918"    // bar islands ~65%, sit on the frame
    readonly property color glass: "#d11a1918"     // centre, panels ~82%
    readonly property color notif: "#8c1a1918"     // notification cards ~55%, blurred behind
    readonly property color raised: "#cc2c2a27"    // pills inside islands, hover
    readonly property color line: "#3dffffff"      // hairlines: light edge reads better on glass
    readonly property color track: "#34312e"       // gauge tracks
    readonly property color fg: "#e9e6e1"
    readonly property color muted: "#8f8a84"
    readonly property color faint: "#5c5853"
    readonly property color amber: "#ffac32"       // emphasis only
    readonly property color amberDim: "#c97824"
    readonly property color green: "#8fd18b"
    readonly property color yellow: "#ffd84d"     // charging
    readonly property color red: "#ff5c57"

    // Tier accents (used as small dots/rings, never as full outlines)
    function tierColor(tier) {
        return tier === "needs" ? amber : tier === "fyi" ? fg : tier === "system" ? muted : faint;
    }

    // ── Type ──
    readonly property string font: "Unbounded"
    readonly property string icons: "Material Symbols Rounded"
    readonly property int textSm: 10
    readonly property int text: 11
    readonly property int textLg: 13
    readonly property int icon: 18

    // ── Geometry (logical px, 4px grid) ──
    readonly property int barH: 36          // top frame edge: islands (32) hug the top, 4px below
    readonly property int railW: 6          // right frame edge (dock is a slide-in overlay)
    readonly property int edge: 6           // left/bottom frame edges
    readonly property int frameRadius: 20   // inner rounded corners of the frame
    readonly property int islandH: 32
    readonly property int pillH: 24
    readonly property int pad: 12
    readonly property int gap: 8
    readonly property int radius: 14
}
