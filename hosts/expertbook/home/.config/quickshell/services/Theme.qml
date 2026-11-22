pragma Singleton
import QtQuick
import Quickshell

// Nixie palette: near-black + amber. One place for every colour, size and font.
Singleton {
    readonly property color bg: "#e6070605"          // bar / rail background (slightly translucent)
    readonly property color surface: "#f015120f"     // cards, centre
    readonly property color surfaceHi: "#ff241d17"   // hover
    readonly property color border: "#33ffe2b8"
    readonly property color fg: "#e8ded1"
    readonly property color muted: "#b8ab9b"
    readonly property color faint: "#6f655a"
    readonly property color amber: "#ffac32"
    readonly property color amberDim: "#c97824"
    readonly property color green: "#8fd18b"
    readonly property color red: "#ff5c57"

    // Tier colours (notifications / rail badges)
    readonly property color tierNeeds: amber
    readonly property color tierFyi: green
    readonly property color tierQuiet: faint
    readonly property color tierSystem: muted

    readonly property string font: "Adwaita Sans"
    readonly property string mono: "CaskaydiaMono NFM"
    readonly property int fontSize: 11
    readonly property int barHeight: 30
    readonly property int railWidth: 40
    readonly property int radius: 10
    readonly property int gap: 8
}
