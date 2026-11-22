import QtQuick
import QtQuick.Layouts
import qs.services

// Material Symbols icon, sized on the grid and centred in its box.
Text {
    property int size: Theme.icon
    Layout.alignment: Qt.AlignVCenter
    Layout.preferredWidth: size
    Layout.preferredHeight: size
    width: size; height: size
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    font.family: Theme.icons
    font.pixelSize: size
    color: Theme.fg
}
