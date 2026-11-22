import QtQuick
import QtQuick.Layouts
import qs.services

// Dashboard quick toggle: icon + name + state line. Click toggles; when it has a
// panel, the chevron (or right-click) opens it.
Rectangle {
    id: t
    property string icon
    property string name
    property string detail
    property bool on: false
    property bool hasPanel: false
    signal toggled
    signal openPanel

    Layout.fillWidth: true
    implicitHeight: 56
    radius: Theme.radius
    color: on ? Qt.rgba(1, 0.675, 0.196, 0.16) : mouse.containsMouse ? Theme.raised : Qt.rgba(1, 1, 1, 0.04)
    border.color: on ? Qt.rgba(1, 0.675, 0.196, 0.45) : Theme.line
    Behavior on color { ColorAnimation { duration: 120 } }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: m => (m.button === Qt.RightButton && t.hasPanel) ? t.openPanel() : t.toggled()
    }

    RowLayout {
        anchors { fill: parent; leftMargin: 12; rightMargin: 4 }
        spacing: 8
        Icon { text: t.icon; color: t.on ? Theme.amber : Theme.muted }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: t.name
                font.pixelSize: Theme.textSm
                font.weight: Font.DemiBold
                color: Theme.fg
            }
            Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                visible: text !== ""
                text: t.detail
                font.pixelSize: 9
                color: Theme.muted
            }
        }
        Item {
            visible: t.hasPanel
            Layout.preferredWidth: 22; Layout.preferredHeight: 40
            Rectangle {
                anchors.fill: parent
                radius: Theme.radius - 4
                color: chev.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
            }
            Icon { anchors.centerIn: parent; size: 16; text: "chevron_right"; color: Theme.muted }
            MouseArea { id: chev; anchors.fill: parent; hoverEnabled: true; onClicked: t.openPanel() }
        }
    }
}
