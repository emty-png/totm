import QtQuick
import Totm

// Inset pill behind a layers row, matching the reference sidebar:
// 8px side insets, 2px vertical gaps, 10px rounding. Selected uses
// the solid row fill, hover stays neutral, lifted rows gain a
// selection outline so the dragged ghost reads floating.
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
    radius: AppTheme.radiusLarge
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
