import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

// One notification: app icon · (dot) app name · meta / summary / body / actions.
// Greyscale card; amber only for the "needs you" dot and app name.
Rectangle {
    id: card
    required property var rec
    property bool compact: false

    readonly property bool needs: rec.tier === "needs"
    readonly property var actions: (rec.notif?.actions ?? []).filter(a => a.identifier !== "default")

    width: parent ? parent.width : 380
    implicitHeight: body.implicitHeight + (compact ? 20 : 28)
    radius: Theme.radius
    color: mouse.containsMouse ? Theme.raised : Theme.notif
    border.color: Theme.line
    Behavior on color { ColorAnimation { duration: 100 } }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: Notifs.activate(card.rec)
    }

    RowLayout {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top
                  margins: card.compact ? 10 : 14 }
        spacing: 12

        Item { // app icon (or first letter)
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: card.compact ? 24 : 32
            Layout.preferredHeight: Layout.preferredWidth
            Image {
                id: appIcon
                anchors.fill: parent
                sourceSize: Qt.size(64, 64)
                source: card.rec.icon ? Quickshell.iconPath(card.rec.icon, true) : ""
                visible: status === Image.Ready
            }
            Rectangle {
                anchors.fill: parent
                visible: !appIcon.visible
                radius: 8
                color: Theme.raised
                Label { anchors.centerIn: parent; text: card.rec.appName.charAt(0).toUpperCase()
                        font.weight: Font.DemiBold; color: card.needs ? Theme.amber : Theme.fg }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            RowLayout { // meta line
                spacing: 6
                Rectangle { visible: card.needs; Layout.alignment: Qt.AlignVCenter
                            width: 6; height: 6; radius: 3; color: Theme.amber }
                Label { text: card.rec.appName; color: card.needs ? Theme.amber : Theme.muted
                        font.pixelSize: Theme.textSm; font.weight: Font.DemiBold }
                Label { text: "· " + Qt.formatTime(card.rec.time, "HH:mm") + (card.rec.count > 1 ? " · ×" + card.rec.count : "")
                        color: Theme.faint; font.pixelSize: Theme.textSm }
            }
            Label {
                Layout.fillWidth: true
                text: card.rec.summary
                elide: Text.ElideRight
                font.pixelSize: card.compact ? Theme.text : Theme.textLg - 1
                font.weight: Font.DemiBold
            }
            Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: card.rec.body
                textFormat: Text.StyledText
                color: Theme.muted
                wrapMode: Text.Wrap
                maximumLineCount: card.compact ? 2 : 4
                elide: Text.ElideRight
            }
            RowLayout { // actions
                visible: card.actions.length > 0 && !card.compact
                Layout.topMargin: 6
                spacing: 6
                Repeater {
                    model: card.actions
                    delegate: Rectangle {
                        required property var modelData
                        implicitWidth: act.implicitWidth + 20; implicitHeight: 26; radius: 13
                        color: actMouse.containsMouse ? Theme.amber : Theme.raised
                        Label { id: act; anchors.centerIn: parent; text: modelData.text
                                color: actMouse.containsMouse ? Theme.base : Theme.fg; font.pixelSize: Theme.textSm }
                        MouseArea { id: actMouse; anchors.fill: parent; hoverEnabled: true
                                    onClicked: { modelData.invoke(); Notifs.removePopup(card.rec); } }
                    }
                }
            }
        }

        Icon { // dismiss
            Layout.alignment: Qt.AlignTop
            size: 16
            text: "close"
            color: closeMouse.containsMouse ? Theme.fg : Theme.faint
            MouseArea { id: closeMouse; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true
                        onClicked: Notifs.dismiss(card.rec) }
        }
    }
}
