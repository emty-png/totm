import QtQuick

// One text run with document metrics. ShapeItem instantiates it once
// for the fill plus N rotated copies for the stroke outline, so all
// copies share metrics from a single definition. Sizing anchors are
// left to the use site (fill for glyphs, explicit box for copies).
Text {
    property string family: "Inter"
    property int weight: 400
    property real size: 16
    property real spacingPct: 0
    property string halign: "left"
    property string valign: "top"
    property bool wrap: false
    property bool autoLeading: true
    property real leading: 1.2

    font.family: family
    font.pixelSize: Math.max(1, size)
    font.weight: weight
    font.letterSpacing: size * spacingPct / 100
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
