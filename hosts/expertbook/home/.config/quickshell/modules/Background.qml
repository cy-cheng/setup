import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.services

// Nixie divergence meter as the desktop background (port of nixie-shell's divergence.rs).
// Shows 1.048596; around each minute change it rolls (s53–54, s5–6) and shows the
// clock HH.MM.SS (s55–s4). Unlit "ghost" cathodes glow faintly behind every tube.
PanelWindow {
    id: bg
    required property var modelData
    screen: modelData

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "nixie-background"
    color: "#070605"
    mask: Region {}

    // ── Geometry (same rules as the original) ──
    readonly property real cellFactor: 0.52
    // Smaller than the original (300 px cap): about half the screen width.
    readonly property real size: Math.max(72, Math.min(170, width * 0.55 / (8 * cellFactor), height * 0.35))
    readonly property real cellW: size * cellFactor
    readonly property real cellH: size * 1.35

    // ── Colours ──
    readonly property color ghost: "#35170a"
    readonly property color lit: "#e6945c"
    readonly property color glowColor: "#ca600b"

    readonly property var ghosts: [["4","7","0"], ["3","9","1"], ["3","1","8"], ["2","4","0"],
                                   ["2","6","8"], ["0","2","1"], ["3","1","0"], ["2","8","7"]]
    readonly property var stableDigits: ["1", "", "0", "4", "8", "5", "9", "6"]
    readonly property var stableDots: [false, true, false, false, false, false, false, false]

    // ── State ──
    property var digits: stableDigits
    property var dots: stableDots
    property bool rolling: false
    property int glow: 0                 // 0..3 random glow strength while rolling

    function phaseFor(s) {
        if (s === 53 || s === 54 || s === 5 || s === 6) return "rolling";
        if (s >= 55 || s <= 4) return "clock";
        return "stable";
    }
    function update() {
        const now = Sys.zoned(new Date());
        const phase = phaseFor(now.getSeconds());
        if (phase === "stable") {
            digits = stableDigits; dots = stableDots; rolling = false;
        } else if (phase === "clock") {
            const p = n => String(n).padStart(2, "0");
            const t = p(now.getHours()) + p(now.getMinutes()) + p(now.getSeconds());
            digits = [t[0], t[1], "", t[2], t[3], "", t[4], t[5]];
            dots = [false, false, true, false, false, true, false, false];
            rolling = false;
        } else {
            digits = Array.from({ length: 8 }, () => String(Math.floor(Math.random() * 10)));
            dots = [false, false, false, false, false, false, false, false];
            rolling = true;
            glow = Math.floor(Math.random() * 4);
        }
        // Next tick: fast while rolling, otherwise on the next second boundary.
        tick.interval = rolling ? 70 : 1000 - now.getMilliseconds() + 5;
        tick.restart();
    }
    Timer { id: tick; repeat: false; onTriggered: bg.update() }
    Component.onCompleted: update()

    // Two glow layers: a tight bright halo and a wide soft one. Rolling flickers their strength.
    readonly property real glowTight: rolling ? [0.35, 0.55, 0.25, 0.7][glow] : 0.45
    readonly property real glowWide: rolling ? [0.6, 0.95, 0.45, 1.0][glow] : 0.85

    Item {
        id: meter
        anchors.centerIn: parent
        width: bg.cellW * 8
        height: bg.cellH

        Repeater {
            model: 8
            delegate: Item {
                id: tube
                required property int index
                x: index * bg.cellW
                width: bg.cellW
                height: bg.cellH

                // Unlit cathodes (always there, like a real tube)
                Repeater {
                    model: bg.ghosts[tube.index]
                    delegate: Text {
                        required property string modelData
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: modelData
                        color: bg.ghost
                        font { family: "BO NX"; pixelSize: bg.size }
                    }
                }
                Text { // unlit decimal point
                    x: bg.cellW / 2 + 35 * bg.size / 300 - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 50 * bg.size / 300
                    text: "."
                    color: bg.ghost
                    font { family: "TT Chocolates Trl"; pixelSize: bg.size * 0.55 }
                }

                // Lit digit with an orange glow
                Text {
                    id: digit
                    anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: bg.digits[tube.index]
                    visible: false
                    color: bg.lit
                    font { family: "BO NX"; pixelSize: bg.size }
                    layer.enabled: true
                }
                TubeGlow { src: digit; shown: bg.digits[tube.index] !== ""; tight: bg.glowTight; wide: bg.glowWide; halo: bg.glowColor }

                // Lit decimal point
                Text {
                    id: dot
                    visible: false
                    x: bg.cellW / 2 + 35 * bg.size / 300 - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 50 * bg.size / 300
                    text: "."
                    color: bg.lit
                    font { family: "TT Chocolates Trl"; pixelSize: bg.size * 0.55 }
                    layer.enabled: true
                }
                TubeGlow { src: dot; shown: bg.dots[tube.index]; tight: bg.glowTight; wide: bg.glowWide; halo: bg.glowColor }
            }
        }
    }
}
