import QtQuick
import Totm

// One text run with document metrics. Fast GPU fill for plain text;
// stroked/effected text rides the CPU vector path (no fake outline).
// The font value comes from TextRuns so variable families interpolate
// the wght axis (plain weight bindings render their default instance
// at every weight).
Text {
    property string family: "Inter"
    property int weight: 400
    property real size: 16
    property bool italic: false
    property bool underline: false
    property bool strike: false
    property string caps: "none"
    property real spacingPct: 0
    property string halign: "left"
    property string valign: "top"
    property bool wrap: false
    property bool autoLeading: true
    property real leading: 1.2

    font: TextRuns.textFont(family, weight, size, italic, underline, strike, caps, size * spacingPct / 100)
    horizontalAlignment: {
        switch (halign) {
        case "center":
            return Text.AlignHCenter;
        case "right":
            return Text.AlignRight;
        case "justify":
            return Text.AlignJustify;
        default:
            return Text.AlignLeft;
        }
    }
    verticalAlignment: {
        switch (valign) {
        case "middle":
            return Text.AlignVCenter;
        case "bottom":
            return Text.AlignBottom;
        default:
            return Text.AlignTop;
        }
    }
    wrapMode: wrap ? Text.WordWrap : Text.NoWrap
    elide: Text.ElideNone
    lineHeightMode: autoLeading ? Text.ProportionalHeight : Text.FixedHeight
    lineHeight: autoLeading ? 1 : Math.max(0.5, leading * size)
}
