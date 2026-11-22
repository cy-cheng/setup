import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// The screen frame (Caelestia-style): one continuous border around the screen.
// Top edge = bar, right edge = attention rail, thin left/bottom edges, rounded
// inner corners. Only the frame strips take input; the inside clicks through.
PanelWindow {
    id: frame
    required property var modelData
    screen: modelData

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore      // Reserve.qml holds the space instead
    color: "transparent"
    WlrLayershell.namespace: "nixie-frame"
    WlrLayershell.layer: WlrLayer.Top

    readonly property real innerX: Theme.edge
    readonly property real innerY: Theme.barH
    readonly property real innerW: width - Theme.edge - Theme.railW
    readonly property real innerH: height - Theme.barH - Theme.edge

    // Frame = full rectangle minus a rounded inner rectangle (odd-even fill).
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: Theme.frame
            strokeColor: "transparent"
            fillRule: ShapePath.OddEvenFill
            PathRectangle { x: 0; y: 0; width: frame.width; height: frame.height }
            PathRectangle {
                x: frame.innerX; y: frame.innerY
                width: frame.innerW; height: frame.innerH
                radius: Theme.frameRadius
            }
        }
        ShapePath { // hairline along the inner edge
            fillColor: "transparent"
            strokeColor: Theme.line
            strokeWidth: 1
            PathRectangle {
                x: frame.innerX - 0.5; y: frame.innerY - 0.5
                width: frame.innerW + 1; height: frame.innerH + 1
                radius: Theme.frameRadius + 0.5
            }
        }
    }

    BarContent {
        id: top
        x: 0; y: 0
        width: frame.width; height: Theme.barH
        monitor: Hyprland.monitorFor(frame.screen)
        innerLeft: frame.innerX + 6
        innerRight: frame.innerX + frame.innerW - 6
    }

    RailContent {
        id: right
        x: frame.width - Theme.railW; y: Theme.barH
        width: Theme.railW; height: frame.height - Theme.barH
    }

    // Input only on the top and right strips.
    mask: Region {
        item: top
        Region { item: right }
    }
}
