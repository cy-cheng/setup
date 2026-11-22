import QtQuick
import QtQuick.Layouts
import qs.services

// Pill-shaped group in the bar. Children are laid out in a centred row.
Rectangle {
    id: island
    default property alias content: row.data
    property int spacing: 10
    Layout.alignment: Qt.AlignVCenter
    implicitHeight: Theme.islandH
    implicitWidth: row.implicitWidth + Theme.pad * 2
    // Sits flush against the top edge of the screen, fully rounded.
    radius: Theme.islandH / 2
    color: Theme.island
    border.color: Theme.line
    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: island.spacing
    }
}
