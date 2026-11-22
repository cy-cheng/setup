import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// Attention rail: permanent strip on the right edge. One icon per source that
// wants you (agent session, app). Badge = unseen count, colour = tier.
// Click: go to the source · Right-click: dismiss the group · Hover: preview.
PanelWindow {
    id: rail
    required property var modelData
    screen: modelData

    anchors { top: true; bottom: true; right: true }
    implicitWidth: Theme.railWidth
    color: "transparent"
    WlrLayershell.namespace: "nixie-rail"

    // Only sources with something not yet dismissed; quiet ones only while unseen.
    readonly property var groups: { Notifs.rev; return Notifs.groups().filter(g => g.tier !== "quiet" || g.unseen > 0); }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        Rectangle { // hairline on the inner edge
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: 1
            color: Theme.border
        }
    }

    Column {
        anchors { top: parent.top; topMargin: Theme.gap; horizontalCenter: parent.horizontalCenter }
        spacing: 8

        Repeater {
            model: rail.groups
            delegate: Item {
                id: slot
                required property var modelData
                width: 30; height: 30
                readonly property color tint: Theme["tier" + modelData.tier.charAt(0).toUpperCase() + modelData.tier.slice(1)]

                Rectangle {
                    id: tile
                    anchors.fill: parent
                    radius: 8
                    color: mouse.containsMouse ? Theme.surfaceHi : Theme.surface
                    border.color: slot.tint
                    border.width: slot.modelData.tier === "needs" ? 2 : 1

                    // "Needs you" breathes gently until handled.
                    SequentialAnimation on opacity {
                        running: slot.modelData.tier === "needs"
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.55; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                    }

                    Image {
                        id: icon
                        anchors.centerIn: parent
                        width: 20; height: 20
                        sourceSize: Qt.size(40, 40)
                        source: slot.modelData.icon ? Quickshell.iconPath(slot.modelData.icon, true) : ""
                        visible: status === Image.Ready
                    }
                    Text { // fallback: first letter of the app
                        anchors.centerIn: parent
                        visible: !icon.visible
                        text: slot.modelData.label.charAt(0).toUpperCase()
                        color: slot.tint
                        font { family: Theme.font; pixelSize: 14; bold: true }
                    }
                }

                Rectangle { // badge
                    visible: slot.modelData.unseen > 0
                    anchors { right: parent.right; top: parent.top; rightMargin: -4; topMargin: -4 }
                    width: Math.max(14, badgeText.implicitWidth + 6); height: 14
                    radius: 7
                    color: slot.tint
                    Text {
                        id: badgeText
                        anchors.centerIn: parent
                        text: slot.modelData.unseen
                        color: "#070605"
                        font { family: Theme.font; pixelSize: 9; bold: true }
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

                // Hover preview: latest few messages from this source.
                PopupWindow {
                    visible: mouse.containsMouse
                    anchor.item: slot
                    anchor.edges: Edges.Left
                    anchor.gravity: Edges.Left
                    anchor.margins.left: -8
                    implicitWidth: 300
                    implicitHeight: previewCol.implicitHeight + 20
                    color: "transparent"
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radius
                        color: Theme.surface
                        border.color: Theme.border
                        Column {
                            id: previewCol
                            anchors { fill: parent; margins: 10 }
                            spacing: 6
                            Text {
                                text: slot.modelData.label
                                color: Theme.amber
                                font { family: Theme.font; pixelSize: 11; weight: Font.DemiBold }
                            }
                            Repeater {
                                model: slot.modelData.items.slice(0, 3)
                                delegate: Column {
                                    required property var modelData
                                    width: previewCol.width
                                    Text {
                                        width: parent.width
                                        text: modelData.summary + (modelData.count > 1 ? "  ×" + modelData.count : "")
                                        color: Theme.fg
                                        elide: Text.ElideRight
                                        font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold }
                                    }
                                    Text {
                                        width: parent.width
                                        visible: text !== ""
                                        text: modelData.body
                                        textFormat: Text.StyledText
                                        color: Theme.muted
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                        font { family: Theme.font; pixelSize: 11 }
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
