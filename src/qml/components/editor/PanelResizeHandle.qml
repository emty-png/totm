import QtQuick
import Totm

// Shared panel resize handle: 6px grab strip straddling the panel edge,
// hover lights a thin line on the edge itself (like the panel divider),
// drags resize in window-stable global coords so the strip never
// judders under the cursor. Every editor panel uses this so the
// handles match exactly.
MouseArea {
    id: handle

    // "right" (left panel), "left" (right panel) or "top" (timeline).
    property string edge: "right"
    property real minimum: 180
    property real maximum: 480
    // Panel size at rest; drags write back through resized().
    property real size: 275

    signal resized(real value)

    readonly property bool horizontal: handle.edge !== "top"

    x: handle.edge === "right" ? parent.width - 3 : handle.edge === "left" ? -3 : 0
    y: handle.edge === "top" ? -3 : 0
    width: handle.horizontal ? 6 : parent.width
    height: handle.horizontal ? parent.height : 6
    cursorShape: handle.horizontal ? Qt.SplitHCursor : Qt.SplitVCursor
    acceptedButtons: Qt.LeftButton
    hoverEnabled: true

    property real startPos: 0
    property real startSize: 275

    // Thin hover line centered on the edge: 2px inside the 6px grab
    // strip, so it reads as the divider lighting up rather than a bar.
    Rectangle {
        x: handle.horizontal ? 2 : 0
        y: handle.horizontal ? 0 : 2
        width: handle.horizontal ? 2 : parent.width
        height: handle.horizontal ? parent.height : 2
        color: handle.containsMouse || handle.pressed ? AppTheme.border : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }
    }

    onPressed: mouse => {
        var g = handle.mapToGlobal(mouse.x, mouse.y);
        handle.startPos = handle.horizontal ? g.x : g.y;
        handle.startSize = handle.size;
    }
    onPositionChanged: mouse => {
        if (!handle.pressed)
            return;
        var g = handle.mapToGlobal(mouse.x, mouse.y);
        var delta = (handle.horizontal ? g.x : g.y) - handle.startPos;
        var sign = handle.edge === "right" ? 1 : -1;
        handle.resized(Math.min(handle.maximum, Math.max(handle.minimum, handle.startSize + sign * delta)));
    }
}
