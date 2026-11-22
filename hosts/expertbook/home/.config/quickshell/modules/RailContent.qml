import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

// Contents of the frame's right edge: one tile per source that wants attention.
// Greyscale tiles; "needs you" gets an amber ring that breathes, counts are small badges.
Item {
    id: rail

    readonly property var groups: { Notifs.rev; return Notifs.groups().filter(g => g.tier !== "quiet" || g.unseen > 0); }

    Column {
        anchors { top: parent.top; topMargin: Theme.gap; horizontalCenter: parent.horizontalCenter }
        spacing: Theme.gap

        Repeater {
            model: rail.groups
            delegate: Item {
                id: slot
                required property var modelData
                readonly property bool needs: modelData.tier === "needs"
                width: 36; height: 36

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: mouse.containsMouse ? Theme.raised : Theme.island
                    border.color: slot.needs ? Theme.amber : Theme.line
                    border.width: slot.needs ? 1.5 : 1
                    SequentialAnimation on border.color {
                        running: slot.needs
                        loops: Animation.Infinite
                        ColorAnimation { to: Theme.amberDim; duration: 900; easing.type: Easing.InOutSine }
                        ColorAnimation { to: Theme.amber; duration: 900; easing.type: Easing.InOutSine }
                    }

                    Image {
                        id: icon
                        anchors.centerIn: parent
                        width: 20; height: 20
                        sourceSize: Qt.size(40, 40)
                        source: slot.modelData.icon ? Quickshell.iconPath(slot.modelData.icon, true) : ""
                        visible: status === Image.Ready
                    }
                    Label { // fallback: first letter
                        anchors.centerIn: parent
                        visible: !icon.visible
                        text: slot.modelData.label.charAt(0).toUpperCase()
                        color: slot.needs ? Theme.amber : Theme.fg
                        font.pixelSize: Theme.textLg
                        font.weight: Font.DemiBold
                    }
                }

                Rectangle { // badge
                    visible: slot.modelData.unseen > 0
                    anchors { right: parent.right; top: parent.top; rightMargin: -4; topMargin: -4 }
                    width: Math.max(16, badge.implicitWidth + 8); height: 16
                    radius: 8
                    color: slot.needs ? Theme.amber : Theme.raised
                    border.color: slot.needs ? "transparent" : Theme.line
                    Label {
                        id: badge
                        anchors.centerIn: parent
                        text: slot.modelData.unseen
                        color: slot.needs ? Theme.base : Theme.fg
                        font.pixelSize: 9
                        font.weight: Font.Bold
                    }
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: m => m.button === Qt.RightButton
                        ? Notifs.dismissGroup(slot.modelData.key)
                        : Notifs.activate(slot.modelData.items[0])
                }

                // Hover preview, opening to the left of the rail
                PopupWindow {
                    visible: mouse.containsMouse
                    anchor.item: slot
                    anchor.edges: Edges.Left
                    anchor.gravity: Edges.Left
                    anchor.margins.left: -12
                    implicitWidth: 320
                    implicitHeight: preview.implicitHeight + 24
                    color: "transparent"
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radius
                        color: Theme.glass
                        border.color: Theme.line
                        ColumnLayout {
                            id: preview
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 8
                            Label {
                                text: slot.modelData.label
                                color: slot.needs ? Theme.amber : Theme.muted
                                font.pixelSize: Theme.textSm
                                font.weight: Font.DemiBold
                            }
                            Repeater {
                                model: slot.modelData.items.slice(0, 3)
                                delegate: ColumnLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Label {
                                        Layout.fillWidth: true
                                        text: modelData.summary + (modelData.count > 1 ? "  ×" + modelData.count : "")
                                        elide: Text.ElideRight
                                        font.weight: Font.DemiBold
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        text: modelData.body
                                        textFormat: Text.StyledText
                                        color: Theme.muted
                                        font.pixelSize: Theme.textSm
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
