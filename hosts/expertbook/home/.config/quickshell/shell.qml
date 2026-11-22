//@ pragma UseQApplication
import QtQuick
import Quickshell
import qs.modules

// Nixie shell: top bar + right-edge attention rail + notification popups/centre.
ShellRoot {
    Variants { model: Quickshell.screens; delegate: Bar {} }
    Variants { model: Quickshell.screens; delegate: Rail {} }
    Variants { model: Quickshell.screens; delegate: Popups {} }
    Variants { model: Quickshell.screens; delegate: Centre {} }
}
