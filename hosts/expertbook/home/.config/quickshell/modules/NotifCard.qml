import QtQuick
import Quickshell
import qs.services

// One notification. Click: go to the source. ×: dismiss. Action buttons if any.
Rectangle {
    id: card
    required property var rec
    property bool compact: false        // centre list uses the compact form

    readonly property color tint: Theme["tier" + rec.tier.charAt(0).toUpperCase() + rec.tier.slice(1)]
    readonly property var actions: (rec.notif?.actions ?? []).filter(a => a.identifier !== "default")

    width: parent ? parent.width : 360
    implicitHeight: col.implicitHeight + (compact ? 14 : 20)
    radius: Theme.radius
    color: mouse.containsMouse ? Theme.surfaceHi : Theme.surface
    border.color: rec.tier === "needs" ? Theme.tierNeeds : Theme.border
    border.width: rec.tier === "needs" ? 2 : 1

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: Notifs.activate(card.rec)
    }

    Rectangle { // tier stripe
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 6 }
        width: 3; radius: 2
        color: card.tint
    }

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top
                  leftMargin: 16; rightMargin: 28; topMargin: card.compact ? 7 : 10 }
        spacing: 3

        Row {
            spacing: 6
            Text {
                visible: !card.compact
                text: card.rec.appName
                color: Theme.amberDim
                font { family: Theme.font; pixelSize: 10; weight: Font.DemiBold }
            }
            Text {
                text: Qt.formatTime(card.rec.time, "HH:mm") + (card.rec.count > 1 ? "  ×" + card.rec.count : "")
                color: Theme.faint
                font { family: Theme.font; pixelSize: 10 }
            }
        }
        Text {
            width: col.width
            text: card.rec.summary
            color: Theme.fg
            elide: Text.ElideRight
            font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
        }
        Text {
            width: col.width
            visible: text !== ""
            text: card.rec.body
            textFormat: Text.StyledText
            color: Theme.muted
            wrapMode: Text.Wrap
            maximumLineCount: card.compact ? 2 : 4
            elide: Text.ElideRight
            font { family: Theme.font; pixelSize: 12 }
        }
        Row { // action buttons (e.g. "Reply", "Approve")
            visible: card.actions.length > 0 && !card.compact
            spacing: 6
            topPadding: 4
            Repeater {
                model: card.actions
                delegate: Rectangle {
                    required property var modelData
                    width: actText.implicitWidth + 16; height: 22; radius: 6
                    color: actMouse.containsMouse ? Theme.amberDim : Theme.surfaceHi
                    Text {
                        id: actText
                        anchors.centerIn: parent
                        text: modelData.text
                        color: Theme.fg
                        font { family: Theme.font; pixelSize: 11 }
                    }
                    MouseArea {
                        id: actMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: { modelData.invoke(); Notifs.removePopup(card.rec); }
                    }
                }
            }
        }
    }

    Text { // dismiss
        anchors { right: parent.right; top: parent.top; margins: 8 }
        text: ""
        color: closeMouse.containsMouse ? Theme.fg : Theme.faint
        font { family: Theme.mono; pixelSize: 11 }
        MouseArea {
            id: closeMouse
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            onClicked: Notifs.dismiss(card.rec)
        }
    }
}
