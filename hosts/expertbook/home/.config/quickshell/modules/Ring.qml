import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
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
    property bool charging: false   // animated highlight sweeping through the empty part
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
    // Charging: a short bright segment runs from the current level to full, fading out.
    property real sweep: 0
    NumberAnimation on sweep {
        running: ring.charging && ring.visible
        from: 0; to: 1; duration: 1400; loops: Animation.Infinite
        easing.type: Easing.InOutSine
        onRunningChanged: if (!running) ring.sweep = 0
    }
    Shape {
        id: chargeArc
        anchors.fill: parent
        visible: ring.charging && ring.value < 0.995
        preferredRendererType: Shape.CurveRenderer
        readonly property real rest: 360 * (1 - Math.max(0, Math.min(1, ring.value)))
        readonly property real seg: Math.min(48, rest)
        ShapePath {
            strokeColor: Qt.rgba(ring.tint.r, ring.tint.g, ring.tint.b, 0.85 * (1 - ring.sweep))
            strokeWidth: ring.stroke; fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: ring.size / 2; centerY: ring.size / 2
                           radiusX: (ring.size - ring.stroke) / 2; radiusY: radiusX
                           startAngle: -90 + 360 * Math.max(0, Math.min(1, ring.value)) + (chargeArc.rest - chargeArc.seg) * ring.sweep
                           sweepAngle: chargeArc.seg }
        }
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
