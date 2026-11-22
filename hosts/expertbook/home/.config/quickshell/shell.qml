//@ pragma UseQApplication
import QtQuick
import Quickshell
import qs.modules

// Nixie shell: screen frame (bar on top, attention rail on the right),
// notification popups and centre.
ShellRoot {
    Variants { model: Quickshell.screens; delegate: Background {} }
    Variants { model: Quickshell.screens; delegate: Reserve {} }
    Variants { model: Quickshell.screens; delegate: Frame {} }
    Variants { model: Quickshell.screens; delegate: Popups {} }
    Variants { model: Quickshell.screens; delegate: Centre {} }
    Variants { model: Quickshell.screens; delegate: WifiPanel {} }
    Variants { model: Quickshell.screens; delegate: BluetoothPanel {} }
    Variants { model: Quickshell.screens; delegate: Launcher {} }
    Variants { model: Quickshell.screens; delegate: Clipboard {} }
    Variants { model: Quickshell.screens; delegate: DockWindow {} }
    Variants { model: Quickshell.screens; delegate: PowerMenu {} }
    Variants { model: Quickshell.screens; delegate: Osd {} }
}
