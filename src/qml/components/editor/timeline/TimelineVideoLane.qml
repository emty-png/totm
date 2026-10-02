import QtQuick
import Totm

// One video lane row: a moveable span bar for a stored video shape
// (not an anim clip). The bar runs start → start + visibleDur (full
// comp when looping, trimmed footage length otherwise); missing files
// draw pulsing dark-red. Dragging the bar moves the video in time
// (one undo entry, snapped); clicks select the shape, so the Video
// panel owns trim (offset/rate/loop) in one place.
Item {
    id: lane

    property var row: null
    property real pxPerSec: 120
    property real originX: 0
    property real compDuration: 4.0
    property var doc: null
    property var clipPolicy: null
    // Owning timeline: the drag session lives there (not here), so
    // Repeater rebuilds mid-drag rebind instead of killing the gesture.
    property var view: null

    // Whether this row owns the active view session.
    readonly property bool sessionActive: !!lane.view && !!lane.view.videoDrag && lane.view.videoDrag.uid === (lane.row ? lane.row.uid : -1) && lane.view.videoDrag.active === true

    implicitHeight: 30

    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: 1
        color: AppTheme.border
    }

    function barX() {
        var s = lane.sessionActive ? lane.view.videoDrag.cur : (lane.row ? Number(lane.row.start) || 0 : 0);
        return lane.originX + Math.max(0, s) * lane.pxPerSec;
    }

    function barW() {
        var d = lane.row ? Number(lane.row.visibleDur) || 0 : 0;
        return Math.max(14, d * lane.pxPerSec);
    }

    function compW() {
        return Math.max(14, Math.max(0.5, Number(lane.compDuration) || 4) * lane.pxPerSec);
    }

    Rectangle {
        x: lane.barX()
        y: (parent.height - 18) / 2
        width: lane.barW()
        height: 18
        radius: 4
        color: !lane.row ? AppTheme.hover : (lane.row.missing ? "#3a1d1d" : (lane.row.selected ? AppTheme.snapGuide : AppTheme.hover))
        border.width: 1
        border.color: !lane.row ? AppTheme.fieldBorder : (lane.row.missing ? AppTheme.closeHover : (lane.row.selected ? "#ffffff" : AppTheme.fieldBorder))

        Behavior on color {
            ColorAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }

        // Missing-file pulse: state-driven so lane rebuilds never
        // flash it spuriously, only the broken link breathes. Resets
        // to full opacity when the file relinks mid-pulse.
        SequentialAnimation on opacity {
            loops: Animation.Infinite
            running: !!lane.row && lane.row.missing
            onRunningChanged: {
                if (!running)
                    opacity = 1;
            }
            NumberAnimation {
                to: 0.55
                duration: 600
                easing.type: Easing.InOutQuad
            }
            NumberAnimation {
                to: 1
                duration: 600
                easing.type: Easing.InOutQuad
            }
        }

        MouseArea {
            id: barMouse
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: lane.sessionActive ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            preventStealing: true
            onPressed: mouse => {
                if (lane.view)
                    lane.view.beginVideoDrag(lane.row ? lane.row.uid : -1, lane.mapFromItem(barMouse, mouse.x, mouse.y).x);
            }
            onPositionChanged: mouse => {
                if (lane.view)
                    lane.view.moveVideoDrag(lane.mapFromItem(barMouse, mouse.x, mouse.y).x);
            }
            onReleased: {
                if (lane.view)
                    lane.view.endVideoDrag();
            }
            onClicked: mouse => {
                if (lane.clipPolicy && lane.row)
                    lane.clipPolicy(lane.row.uid, !!(mouse.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.ShiftModifier)));
            }
            onDoubleClicked: {
                if (lane.row && lane.doc)
                    lane.doc.selectOnly(lane.row.uid);
            }
        }

        // Loop badge: right-aligned chevron when the footage tiles.
        Text {
            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
                rightMargin: 6
            }
            visible: lane.row && lane.row.loop === true && !lane.row.missing && lane.barW() > 52
            text: "⟳"
            font.pixelSize: 11
            color: lane.row && lane.row.selected ? "#ffffff" : AppTheme.muted
        }

        // Offset tick: where the footage starts inside the file.
        Rectangle {
            x: 4
            y: (parent.height - height) / 2
            width: 2
            height: parent.height - 8
            radius: 1
            visible: lane.row && Number(lane.row.offset) > 0.001 && lane.barW() > 30
            color: lane.row && lane.row.selected ? "#ffffff" : AppTheme.muted
            opacity: 0.7
        }
    }

    // Full-comp outline when a non-looping clip ends early, so the
    // empty tail reads as intentional rather than a broken bar.
    Rectangle {
        x: lane.originX
        y: (parent.height - 18) / 2
        width: lane.compW()
        height: 18
        radius: 4
        visible: lane.row && !lane.row.missing && lane.row.loop !== true && lane.barX() + lane.barW() + 4 < lane.originX + lane.compW()
        color: "transparent"
        border.width: 1
        border.color: AppTheme.fieldBorder
        opacity: 0.5
    }
}
