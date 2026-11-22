import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// Invisible strips that reserve the frame's space, so tiled windows sit inside it.
Scope {
    id: root
    required property var modelData

    component Strip: PanelWindow {
        screen: root.modelData
        color: "transparent"
        mask: Region {}                 // no input
        WlrLayershell.namespace: "nixie-reserve"
        WlrLayershell.layer: WlrLayer.Bottom
    }

    Strip {
        anchors { top: true; left: true; right: true }
        implicitHeight: Theme.barH
        exclusiveZone: Theme.barH
    }
    Strip {
        anchors { top: true; bottom: true; right: true }
        implicitWidth: Theme.railW
        exclusiveZone: Theme.railW
    }
    Strip {
        anchors { top: true; bottom: true; left: true }
        implicitWidth: Theme.edge
        exclusiveZone: Theme.edge
    }
    Strip {
        anchors { left: true; right: true; bottom: true }
        implicitHeight: Theme.edge
        exclusiveZone: Theme.edge
    }
}
