import QtQuick
import QtQuick.Layouts
import qs.services

// UI text: Unbounded, tabular digits, vertically centred.
Text {
    Layout.alignment: Qt.AlignVCenter
    verticalAlignment: Text.AlignVCenter
    font.family: Theme.font
    font.pixelSize: Theme.text
    font.features: { "tnum": 1 }
    color: Theme.fg
}
