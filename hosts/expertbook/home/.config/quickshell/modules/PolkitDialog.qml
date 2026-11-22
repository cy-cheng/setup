import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// Authentication dialog for polkit requests (Auth.qml is the agent).
// Fingerprint first (PAM asks the sensor; no input needed), then the password field
// appears if the fingerprint times out or is skipped. Enter submits, Esc cancels.
PanelWindow {
    id: dlg
    required property var modelData
    screen: modelData

    readonly property bool onFocusedScreen: Quickshell.screens.length < 2
        || modelData.name === (Hyprland.focusedMonitor?.name ?? "")
    readonly property var flow: Auth.flow
    readonly property bool open: Auth.active && flow !== null && onFocusedScreen
    readonly property bool needsInput: flow?.isResponseRequired ?? false
    visible: open || card.opacity > 0

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "nixie-auth"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function submit() {
        if (!flow || !needsInput) return;
        flow.submit(input.text);
        input.text = "";
    }
    function cancel() { if (flow) flow.cancelAuthenticationRequest(); }

    onOpenChanged: if (open) { input.text = ""; focusTimer.restart(); }
    onNeedsInputChanged: if (needsInput) focusTimer.restart()
    Timer { id: focusTimer; interval: 50; onTriggered: needsInput ? input.forceActiveFocus() : keys.forceActiveFocus() }

    // Dim the screen; clicking outside does nothing (an auth request shouldn't vanish by accident).
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: dlg.open ? 0.45 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
        MouseArea { anchors.fill: parent }
    }

    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: dlg.cancel()
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 440
        height: col.implicitHeight + 40
        radius: Theme.radius + 10
        color: "#f21a1918"      // nearly solid: a security prompt should be easy to read
        border.color: Theme.line
        opacity: dlg.open ? 1 : 0
        scale: dlg.open ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: 14

            RowLayout { // icon + title
                Layout.fillWidth: true
                spacing: 14
                Rectangle {
                    Layout.preferredWidth: 48; Layout.preferredHeight: 48
                    Layout.alignment: Qt.AlignTop
                    radius: 24
                    color: Qt.rgba(1, 0.675, 0.196, 0.14)
                    border.color: Qt.rgba(1, 0.675, 0.196, 0.45)
                    Icon {
                        anchors.centerIn: parent
                        size: 26
                        text: dlg.needsInput ? "lock" : "fingerprint"
                        color: Theme.amber
                        SequentialAnimation on opacity { // breathing while waiting for the sensor
                            running: dlg.open && !dlg.needsInput
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.45; duration: 800; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                            onRunningChanged: if (!running) parent.opacity = 1
                        }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Label {
                        text: "Authentication required"
                        font.pixelSize: Theme.textLg + 2
                        font.weight: Font.DemiBold
                    }
                    Label {
                        Layout.fillWidth: true
                        text: dlg.flow?.actionId ?? ""
                        visible: text !== ""
                        elide: Text.ElideMiddle
                        color: Theme.faint
                        font.pixelSize: Theme.textSm
                    }
                }
            }

            Label { // what is being asked for
                Layout.fillWidth: true
                text: dlg.flow?.message ?? ""
                wrapMode: Text.Wrap
                color: Theme.fg
                lineHeight: 1.25
            }

            Label { // fingerprint prompt / errors from PAM
                Layout.fillWidth: true
                readonly property string msg: dlg.flow?.supplementaryMessage ?? ""
                text: msg !== "" ? msg
                    : dlg.needsInput ? "" : "Touch the fingerprint sensor, or wait for the password field"
                visible: text !== ""
                wrapMode: Text.Wrap
                color: (dlg.flow?.supplementaryIsError ?? false) ? Theme.red : Theme.muted
                font.pixelSize: Theme.textSm
            }

            Rectangle { // password
                Layout.fillWidth: true
                visible: dlg.needsInput
                implicitHeight: 44
                radius: 22
                color: Theme.base
                border.color: input.activeFocus ? Theme.amberDim : Theme.line
                RowLayout {
                    anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                    spacing: 10
                    Icon { text: "key"; color: Theme.muted }
                    TextInput {
                        id: input
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        echoMode: (dlg.flow?.responseVisible ?? false) ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "•"
                        color: Theme.fg
                        font { family: Theme.font; pixelSize: Theme.textLg }
                        selectionColor: Theme.amberDim
                        clip: true
                        Keys.onReturnPressed: dlg.submit()
                        Keys.onEnterPressed: dlg.submit()
                        Keys.onEscapePressed: dlg.cancel()
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !input.text
                            text: (dlg.flow?.inputPrompt ?? "Password").replace(/:\s*$/, "")
                            color: Theme.faint
                            font.pixelSize: Theme.textLg
                        }
                    }
                }
            }

            RowLayout { // buttons
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 8
                Item { Layout.fillWidth: true }
                Rectangle {
                    implicitWidth: cancelLabel.implicitWidth + 32; implicitHeight: 36; radius: 18
                    color: cancelMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                    border.color: Theme.line
                    Label { id: cancelLabel; anchors.centerIn: parent; text: "Cancel"; font.pixelSize: Theme.textSm; font.weight: Font.DemiBold }
                    MouseArea { id: cancelMouse; anchors.fill: parent; hoverEnabled: true; onClicked: dlg.cancel() }
                }
                Rectangle {
                    visible: dlg.needsInput
                    implicitWidth: okLabel.implicitWidth + 32; implicitHeight: 36; radius: 18
                    readonly property bool ready: input.text !== ""
                    color: ready ? (okMouse.containsMouse ? "#ffbd57" : Theme.amber) : Qt.rgba(1, 0.675, 0.196, 0.25)
                    Label { id: okLabel; anchors.centerIn: parent; text: "Authenticate"; color: Theme.base; font.pixelSize: Theme.textSm; font.weight: Font.DemiBold }
                    MouseArea { id: okMouse; anchors.fill: parent; hoverEnabled: true; onClicked: dlg.submit() }
                }
            }
        }
    }
}
