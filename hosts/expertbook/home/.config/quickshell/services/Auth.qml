pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Polkit

// Polkit agent: the shell answers "authentication required" requests (pkexec, systemd,
// NetworkManager…) itself instead of hyprpolkitagent. PolkitDialog.qml draws the UI.
// PAM decides the methods: /etc/pam.d/polkit-1 tries the fingerprint first.
Singleton {
    id: root
    readonly property var flow: agent.flow
    readonly property bool active: agent.isActive
    readonly property bool registered: agent.isRegistered

    PolkitAgent { id: agent }
}
