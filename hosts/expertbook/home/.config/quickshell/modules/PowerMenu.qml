import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// Power / session menu (power key, or the power icon in the bar).
// Lock · Sleep · Hibernate · Log out · Reboot · Power off. The last three need a second
// press within 5 s. ←/→ or 1–6 to choose, Enter to run, Esc to close.
PanelWindow {
    id: menu
    required property var modelData
    screen: modelData

    readonly property bool onFocusedScreen: Quickshell.screens.length < 2
        || modelData.name === (Hyprland.focusedMonitor?.name ?? "")
    readonly property bool open: Panels.open === "power" && onFocusedScreen
    visible: open || card.opacity > 0

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "nixie-power"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property var actions: [
        { label: "Lock",      icon: "lock",               confirm: false, cmd: ["loginctl", "lock-session"] },
        // Sleep works since BIOS .312 (2026-11-25). Hibernate saves the session to
        // /swapfile and powers off (power button restores).
        { label: "Sleep",     icon: "bedtime",            confirm: false, cmd: ["sh", "-c", "loginctl lock-session; sleep 1; systemctl suspend"] },
        { label: "Hibernate", icon: "downloading",        confirm: false, cmd: ["sh", "-c", "loginctl lock-session; sleep 1; systemctl hibernate"] },
        { label: "Log out",   icon: "logout",             confirm: true,  cmd: ["hyprctl", "dispatch", "hl.dsp.exit()"] },
        { label: "Reboot",    icon: "restart_alt",        confirm: true,  cmd: ["systemctl", "reboot"] },
        { label: "Power off", icon: "power_settings_new", confirm: true,  cmd: ["systemctl", "poweroff"] },
    ]
    property int selected: 0
    property int armed: -1                  // index waiting for its second press

    onOpenChanged: if (open) { selected = 0; armed = -1; keys.forceActiveFocus(); }

    function trigger(i) {
        const a = actions[i];
        if (a.confirm && armed !== i) { armed = i; disarm.restart(); return; }
        Panels.close();
        Quickshell.execDetached(a.cmd);
    }
    Timer { id: disarm; interval: 5000; onTriggered: menu.armed = -1 }

    // Dim the screen behind the menu; click outside closes it.
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: menu.open ? 0.45 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
        MouseArea { anchors.fill: parent; onClicked: Panels.close() }
    }

    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: Panels.close()
        Keys.onLeftPressed: menu.selected = (menu.selected + menu.actions.length - 1) % menu.actions.length
        Keys.onRightPressed: menu.selected = (menu.selected + 1) % menu.actions.length
        Keys.onTabPressed: menu.selected = (menu.selected + 1) % menu.actions.length
        Keys.onReturnPressed: menu.trigger(menu.selected)
        Keys.onEnterPressed: menu.trigger(menu.selected)
        Keys.onPressed: e => {
            const n = e.key - Qt.Key_1;
            if (n >= 0 && n < menu.actions.length) { menu.selected = n; menu.trigger(n); e.accepted = true; }
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: row.implicitWidth + 32
        height: row.implicitHeight + 32
        radius: Theme.radius + 10
        color: Theme.glass
        border.color: Theme.line
        opacity: menu.open ? 1 : 0
        scale: menu.open ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 10
            Repeater {
                model: menu.actions
                delegate: Rectangle {
                    id: btn
                    required property var modelData
                    required property int index
                    readonly property bool sel: index === menu.selected
                    readonly property bool armed: index === menu.armed
                    implicitWidth: 104; implicitHeight: 104
                    radius: Theme.radius + 4
                    color: armed ? Theme.amber : sel ? Theme.raised : "transparent"
                    border.color: sel && !armed ? Theme.line : "transparent"
                    Behavior on color { ColorAnimation { duration: 100 } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 10
                        Icon {
                            Layout.alignment: Qt.AlignHCenter
                            size: 30
                            text: btn.modelData.icon
                            color: btn.armed ? Theme.base : Theme.fg
                        }
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: btn.armed ? "Again" : btn.modelData.label
                            color: btn.armed ? Theme.base : btn.sel ? Theme.fg : Theme.muted
                            font.pixelSize: Theme.textSm
                            font.weight: Font.DemiBold
                        }
                    }
                    Label { // number hint
                        anchors { top: parent.top; right: parent.right; margins: 8 }
                        text: btn.index + 1
                        color: btn.armed ? Theme.base : Theme.faint
                        font.pixelSize: 9
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: menu.selected = btn.index
                        onClicked: menu.trigger(btn.index)
                    }
                }
            }
        }
    }
}
