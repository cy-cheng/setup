import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

// One dock tile: app (or notification source) icon, window dots, unread badge,
// amber pulsing outline for "needs you", hover preview of the latest messages.
Item {
    id: tile
    property string iconName
    property string fallback
    property var group: null
    property int windows: 0
    property bool focused: false
    property string tip
    signal leftClicked
    signal middleClicked
    signal rightClicked

    readonly property bool needs: group?.tier === "needs"
    width: 40; height: 40

    Row { // window dots
        anchors { right: parent.left; rightMargin: 2; verticalCenter: parent.verticalCenter }
        visible: tile.windows > 0
        spacing: 2
        Column {
            spacing: 3
            Repeater {
                model: Math.min(3, tile.windows)
                delegate: Rectangle { width: 3; height: 3; radius: 1.5; color: tile.focused ? Theme.amber : Theme.muted }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: mouse.containsMouse ? Theme.raised : (tile.focused ? Theme.island : "transparent")
        border.color: tile.needs ? Theme.amber : (tile.focused ? Theme.line : "transparent")
        border.width: tile.needs ? 1.5 : 1
        SequentialAnimation on border.color {
            running: tile.needs
            loops: Animation.Infinite
            ColorAnimation { to: Theme.amberDim; duration: 900; easing.type: Easing.InOutSine }
            ColorAnimation { to: Theme.amber; duration: 900; easing.type: Easing.InOutSine }
        }
        Image {
            id: img
            anchors.centerIn: parent
            width: 26; height: 26
            sourceSize: Qt.size(52, 52)
            source: tile.iconName ? Quickshell.iconPath(tile.iconName, true) : ""
            visible: status === Image.Ready
            opacity: tile.windows > 0 || tile.group ? 1 : 0.55
        }
        Label {
            anchors.centerIn: parent
            visible: !img.visible
            text: tile.fallback.charAt(0).toUpperCase()
            color: tile.needs ? Theme.amber : Theme.fg
            font.pixelSize: Theme.textLg
            font.weight: Font.DemiBold
        }
    }

    Rectangle { // unread badge
        visible: (tile.group?.unseen ?? 0) > 0
        anchors { right: parent.right; top: parent.top; rightMargin: -3; topMargin: -3 }
        width: Math.max(16, badge.implicitWidth + 8); height: 16; radius: 8
        color: tile.needs ? Theme.amber : Theme.fg
        Label { id: badge; anchors.centerIn: parent; text: tile.group?.unseen ?? 0
                color: Theme.base; font.pixelSize: 9; font.weight: Font.Bold }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: m => m.button === Qt.MiddleButton ? tile.middleClicked()
                      : m.button === Qt.RightButton ? tile.rightClicked() : tile.leftClicked()
    }

    // Hover: name + latest messages from this source
    PopupWindow {
        visible: mouse.containsMouse
        anchor.item: tile
        anchor.edges: Edges.Left
        anchor.gravity: Edges.Left
        anchor.margins.left: -14
        implicitWidth: tile.group ? 320 : nameOnly.implicitWidth + 24
        implicitHeight: (tile.group ? preview.implicitHeight : nameOnly.implicitHeight) + 20
        color: "transparent"
        Rectangle {
            anchors.fill: parent
            radius: tile.group ? Theme.radius : height / 2
            color: Theme.glass
            border.color: Theme.line
            Label { id: nameOnly; visible: !tile.group; anchors.centerIn: parent; text: tile.tip; font.pixelSize: Theme.textSm }
            ColumnLayout {
                id: preview
                visible: tile.group !== null
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                spacing: 6
                Label { text: tile.tip; color: tile.needs ? Theme.amber : Theme.muted; font.pixelSize: Theme.textSm; font.weight: Font.DemiBold }
                Repeater {
                    model: tile.group ? tile.group.items.slice(0, 3) : []
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 1
                        Label { Layout.fillWidth: true; elide: Text.ElideRight; font.weight: Font.DemiBold
                                text: modelData.summary + (modelData.count > 1 ? "  ×" + modelData.count : "") }
                        Label { Layout.fillWidth: true; visible: text !== ""; text: modelData.body; textFormat: Text.StyledText
                                color: Theme.muted; font.pixelSize: Theme.textSm; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
                    }
                }
            }
        }
    }
}
