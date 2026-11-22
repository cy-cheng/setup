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
