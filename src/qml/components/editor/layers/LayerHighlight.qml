import QtQuick
import Totm

// Inset card behind a layers row. Selected uses the solid row fill,
// hover stays neutral, lifted rows gain a selection outline.
Rectangle {
    id: highlight

    required property bool selected
    required property bool hovered
    required property bool lifted

    anchors.fill: parent
    anchors.leftMargin: 8
    anchors.rightMargin: 8
    anchors.topMargin: 2
    anchors.bottomMargin: 2
    radius: 6
    color: highlight.selected ? AppTheme.layerSelected : highlight.hovered ? AppTheme.hover : "transparent"
    border.width: highlight.lifted ? 1 : 0
    border.color: AppTheme.selection

    Behavior on color {
        ColorAnimation {
            duration: 100
            easing.type: Easing.OutCubic
        }
    }
}
