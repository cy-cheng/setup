import QtQuick
import QtQuick.Layouts
import qs.services

// Dashboard gauge: a large ring with its value in the middle and a name below.
ColumnLayout {
    id: g
    property real value: 0              // 0..1 (arc)
    property string text                // centre text, e.g. "42"
    property string name                // label under the ring
    property string icon
    property color tint: Theme.fg
    property string tip
    signal clicked
    signal scrolled(bool up)

    spacing: 8
    Layout.alignment: Qt.AlignTop
    Layout.fillWidth: true
    Layout.maximumWidth: 100000         // a layout caps itself at its children's width otherwise

    Ring {
        id: ring
        Layout.alignment: Qt.AlignHCenter
        size: 64
        stroke: 5
        value: g.value
        tint: g.tint
        icon: ""
        tip: g.tip
        tipInPanel: true
        onClicked: g.clicked()
        onScrolled: up => g.scrolled(up)
        Label {
            anchors.centerIn: parent
            text: g.text
            color: g.tint
            font.pixelSize: Theme.textLg
            font.weight: Font.DemiBold
        }
    }
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: 4
        Icon { size: 14; text: g.icon; color: Theme.muted }
        Label { text: g.name; color: Theme.muted; font.pixelSize: Theme.textSm }
    }
}
