import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
import qs.services

// Small circular gauge: track, value arc from 12 o'clock, icon in the middle.
Item {
    id: ring
    property real value: 0          // 0..1
    property string icon
    property color tint: Theme.fg
    property int size: 26
    property real stroke: 2.5
    property string tip             // shown on hover
    property bool tipInPanel: false
    property bool charging: false   // spark circling the ring (battery charging)
    signal clicked
    signal scrolled(bool up)

    Layout.alignment: Qt.AlignVCenter
    implicitWidth: size
    implicitHeight: size

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Theme.track; strokeWidth: ring.stroke; fillColor: "transparent"
            PathAngleArc { centerX: ring.size / 2; centerY: ring.size / 2
                           radiusX: (ring.size - ring.stroke) / 2; radiusY: radiusX
                           startAngle: 0; sweepAngle: 360 }
        }
        ShapePath {
            strokeColor: ring.tint; strokeWidth: ring.stroke; fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: ring.size / 2; centerY: ring.size / 2
                           radiusX: (ring.size - ring.stroke) / 2; radiusY: radiusX
                           startAngle: -90; sweepAngle: 360 * Math.max(0, Math.min(1, ring.value)) }
        }
    }
    // Charging: a spark circles the ring with a fading tail and a soft glow,
    // like energy flowing in. Head is white-hot, tail takes the ring colour.
    property real orbit: 0
    NumberAnimation on orbit {
        running: ring.charging && ring.visible
        from: 0; to: 1; duration: 1800; loops: Animation.Infinite
        onRunningChanged: if (!running) ring.orbit = 0
    }
    Item {
        id: comet
        anchors.fill: parent
        visible: ring.charging
        readonly property real r: (ring.size - ring.stroke) / 2
        Repeater {
            model: 7
            delegate: Rectangle {
                required property int index
                readonly property real a: (ring.orbit - index * 0.032) * 2 * Math.PI - Math.PI / 2
                readonly property real d: (ring.stroke + 1.6) * (1 - index * 0.12)
                width: d; height: d; radius: d / 2
                x: ring.size / 2 + comet.r * Math.cos(a) - d / 2
                y: ring.size / 2 + comet.r * Math.sin(a) - d / 2
                color: index === 0 ? "#fffbe8" : ring.tint
                opacity: 1 - index / 7.5
            }
        }
    }
    MultiEffect { // soft glow around the spark and its tail
        anchors.fill: comet
        visible: ring.charging
        source: comet
        blurEnabled: true
        blur: 1.0
        blurMax: Math.round(ring.size / 3)
        brightness: 0.25
        opacity: 0.9
    }
    Icon {
        anchors.centerIn: parent
        size: Math.round(ring.size * 0.54)
        text: ring.icon
        color: ring.tint
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: ring.clicked()
        onWheel: w => ring.scrolled(w.angleDelta.y > 0)
    }
    Tip { text: ring.tip; inPanel: ring.tipInPanel }

}
