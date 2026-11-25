import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// Clipboard history (Super+V), backed by cliphist.
//   type to filter · ↑/↓ move · Enter copies the entry back · Shift+Del forgets it · Esc closes
PanelWindow {
    id: cb
    required property var modelData
    screen: modelData

    readonly property bool onFocusedScreen: Quickshell.screens.length < 2
        || modelData.name === (Hyprland.focusedMonitor?.name ?? "")
    readonly property bool open: Panels.open === "clipboard" && onFocusedScreen
    visible: open || card.opacity > 0

    anchors { top: true }
    exclusionMode: ExclusionMode.Ignore
    margins.top: Theme.barH + Theme.gap
    implicitWidth: 560
    implicitHeight: card.implicitHeight + 24
    color: "transparent"
    WlrLayershell.namespace: "nixie-centre"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    HyprlandFocusGrab { windows: [cb]; active: cb.open; onCleared: Panels.close() }

    readonly property string thumbDir: Quickshell.env("XDG_RUNTIME_DIR") + "/nixie-clip"
    property var entries: []          // { line, id, text, image, w, h }
    property string query: ""
    property int selected: 0
    readonly property int maxRows: 8

    onOpenChanged: if (open) { query = ""; input.text = ""; selected = 0; input.forceActiveFocus(); lister.running = true; }

    // cliphist list → "id<TAB>preview"; images look like "[[ binary data 12 KiB png 640x480 ]]".
    Process {
        id: lister
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t");
                    if (tab < 0) continue;
                    const id = line.slice(0, tab), body = line.slice(tab + 1);
                    const m = body.match(/^\[\[ binary data (.+?) (png|jpe?g|webp|gif|bmp) (\d+)x(\d+) \]\]$/);
                    out.push({ line: line, id: id, text: m ? "Image · " + m[3] + "×" + m[4] + " · " + m[1] : body.trim(),
                               image: !!m, ext: m ? m[2] : "" });
                }
                cb.entries = out;
                thumbs.running = true;
            }
        }
    }
    // Decode the newest images once into $XDG_RUNTIME_DIR/nixie-clip/<id>.<ext> for thumbnails.
    Process {
        id: thumbs
        command: ["sh", "-c", 'd="$1"; shift; mkdir -p "$d"; for e; do f="$d/${e%%:*}.${e#*:}"; [ -s "$f" ] || cliphist decode "${e%%:*}" > "$f"; done; echo done',
                  "_", cb.thumbDir].concat(cb.entries.filter(e => e.image).slice(0, 40).map(e => e.id + ":" + e.ext))
        stdout: StdioCollector { onStreamFinished: cb.thumbRev++ }
    }
    property int thumbRev: 0

    readonly property var results: {
        const q = query.trim().toLowerCase();
        const r = q ? entries.filter(e => e.text.toLowerCase().includes(q)) : entries;
        return r.slice(0, 50);
    }
    onResultsChanged: selected = Math.min(selected, Math.max(0, results.length - 1))

    function pick(e) {
        if (!e) return;
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | cliphist decode | wl-copy', "_", e.line]);
        Panels.close();
    }
    function forget(e) {
        if (!e) return;
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | cliphist delete', "_", e.line]);
        entries = entries.filter(x => x.id !== e.id);
    }

    Rectangle {
        id: card
        anchors { left: parent.left; right: parent.right; top: parent.top }
        implicitHeight: col.implicitHeight + 24
        radius: Theme.radius + 6
        color: Theme.glass
        border.color: Theme.line
        opacity: cb.open ? 1 : 0
        transform: Translate { y: cb.open ? 0 : -12; Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } } }
        Behavior on opacity { NumberAnimation { duration: 140 } }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 8

            Rectangle { // search field
                Layout.fillWidth: true
                implicitHeight: 44
                radius: 22
                color: Theme.base
                border.color: input.activeFocus ? Theme.amberDim : Theme.line
                RowLayout {
                    anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                    spacing: 10
                    Icon { text: "content_paste"; color: Theme.muted }
                    TextInput {
                        id: input
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        color: Theme.fg
                        font { family: Theme.font; pixelSize: Theme.textLg }
                        selectionColor: Theme.amberDim
                        clip: true
                        onTextChanged: { cb.query = text; cb.selected = 0; }
                        Keys.onEscapePressed: Panels.close()
                        Keys.onReturnPressed: cb.pick(cb.results[cb.selected])
                        Keys.onEnterPressed: cb.pick(cb.results[cb.selected])
                        Keys.onDownPressed: cb.selected = Math.min(cb.results.length - 1, cb.selected + 1)
                        Keys.onUpPressed: cb.selected = Math.max(0, cb.selected - 1)
                        Keys.onTabPressed: cb.selected = (cb.selected + 1) % Math.max(1, cb.results.length)
                        Keys.onPressed: e => {
                            if (e.key === Qt.Key_Delete && (e.modifiers & Qt.ShiftModifier)) {
                                cb.forget(cb.results[cb.selected]); e.accepted = true;
                            }
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !input.text
                            text: "Clipboard history · Shift+Del forgets"
                            color: Theme.faint
                            font.pixelSize: Theme.textLg
                        }
                    }
                }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(cb.results.length, cb.maxRows) * 50
                visible: cb.results.length > 0
                clip: true
                spacing: 2
                model: cb.results
                currentIndex: cb.selected
                highlightMoveDuration: 0
                boundsBehavior: Flickable.StopAtBounds
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool sel: index === cb.selected
                    width: list.width
                    height: 48
                    radius: 12
                    color: sel ? Theme.raised : "transparent"

                    Rectangle {
                        visible: row.sel
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 4 }
                        width: 3; height: 20; radius: 2
                        color: Theme.amber
                    }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 16; rightMargin: 14 }
                        spacing: 12
                        Item {
                            Layout.preferredWidth: 28; Layout.preferredHeight: 28
                            Layout.alignment: Qt.AlignVCenter
                            Icon {
                                anchors.centerIn: parent
                                visible: !row.modelData.image || thumb.status !== Image.Ready
                                text: row.modelData.image ? "image" : "notes"
                                color: Theme.muted
                            }
                            Image {
                                id: thumb
                                anchors.fill: parent
                                visible: row.modelData.image
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize: Qt.size(56, 56)
                                source: row.modelData.image && cb.thumbRev > 0
                                    ? "file://" + cb.thumbDir + "/" + row.modelData.id + "." + row.modelData.ext : ""
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            text: row.modelData.text.replace(/\s+/g, " ")
                            color: row.modelData.image ? Theme.muted : Theme.fg
                            font.weight: row.sel ? Font.DemiBold : Font.Normal
                        }
                        Label { visible: row.sel; text: "↵"; color: Theme.faint }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onEntered: cb.selected = row.index
                        onClicked: m => m.button === Qt.MiddleButton ? cb.forget(row.modelData) : cb.pick(row.modelData)
                    }
                }
            }

            Label {
                visible: cb.results.length === 0
                Layout.leftMargin: 8
                Layout.bottomMargin: 4
                text: cb.entries.length === 0 ? "Nothing copied yet" : "No match"
                color: Theme.faint
            }
        }
    }
}
