import QtQuick
import QtQuick.Effects

// Nixie tube glow for one glyph: a wide soft halo plus a tight bright one.
// Both layers use the same blurMax so their padding (and the glyph) line up exactly.
Item {
    id: g
    required property Item src
    property bool shown: true
    property real tight: 0.45
    property real wide: 0.85
    property color halo: "#ca600b"
    anchors.fill: src
    visible: shown
    MultiEffect { // wide soft halo
        source: g.src; anchors.fill: parent
        shadowEnabled: true; shadowColor: g.halo
        shadowBlur: g.wide; shadowOpacity: 0.75
        shadowHorizontalOffset: 0; shadowVerticalOffset: 0
        blurMax: 64; autoPaddingEnabled: true
    }
    MultiEffect { // tight bright halo + the glyph itself
        source: g.src; anchors.fill: parent
        shadowEnabled: true; shadowColor: "#ff8a2a"
        shadowBlur: g.tight; shadowOpacity: 1.0
        shadowHorizontalOffset: 0; shadowVerticalOffset: 0
        blurMax: 64; autoPaddingEnabled: true
    }
}
