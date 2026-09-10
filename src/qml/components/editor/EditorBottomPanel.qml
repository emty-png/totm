import QtQuick
import QtQuick.Layouts
import Totm

// Editor bottom panel: timeline transport plus ruler and lanes.
// Collapses to zero when closed (design mode), expands with a smooth
// slide when opened (animate mode). panelHeight (user size) is kept
// while closed so it reopens at the same size.
Item {
    id: bottomPanel

    property bool open: false
    property int panelHeight: 300
    readonly property int minPanelHeight: 80
    readonly property int maxPanelHeight: 400
    property var doc: null

    Layout.preferredHeight: bottomPanel.open ? bottomPanel.panelHeight : 0
    Layout.fillWidth: true

    Behavior on Layout.preferredHeight {
        NumberAnimation {
            duration: 250
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        anchors.fill: parent
        color: AppTheme.background
    }

    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: 1
        visible: bottomPanel.height > 1
        color: AppTheme.border
    }

    // Timeline content. Fills to the panel top so the divider and the
    // playhead touch the edge; handle clearance lives inside the view
    // (transparent spacer) to keep buttons clear of the resize strip.
    // Hidden below a pixel sliver when collapsed so nothing paints out.
    // No marquee overlay here on purpose. A full-panel mouse area above
    // the timeline would swallow every transport, ruler and keyframe
    // press; timeline marquee stays dead by design.
    TimelineView {
        anchors.fill: parent
        visible: bottomPanel.height > 8
        doc: bottomPanel.doc
    }

    // Resize handle straddling the top edge. Hidden while collapsed.
    MouseArea {
        id: handle
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            topMargin: -3
        }
        height: 6
        visible: bottomPanel.height > 8
        cursorShape: Qt.SplitVCursor
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true

        property real startY: 0
        property real startH: 300

        Rectangle {
            anchors.fill: parent
            color: handle.containsMouse || handle.pressed ? AppTheme.border : "transparent"

            Behavior on color {
                ColorAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                }
            }
        }

        onPressed: mouse => {
            // Window-stable coordinates: the handle moves with the panel,
            // so measuring in handle space would feed back and judder.
            handle.startY = handle.mapToGlobal(mouse.x, mouse.y).y;
            handle.startH = bottomPanel.panelHeight;
        }
        onPositionChanged: mouse => {
            if (!handle.pressed)
                return;
            var globalY = handle.mapToGlobal(mouse.x, mouse.y).y;
            bottomPanel.panelHeight = Math.min(bottomPanel.maxPanelHeight, Math.max(bottomPanel.minPanelHeight, handle.startH - (globalY - handle.startY)));
        }
    }
}
