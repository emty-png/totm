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

    // Resize strip on the top edge, shared with every panel. Hidden
    // while collapsed.
    PanelResizeHandle {
        edge: "top"
        minimum: bottomPanel.minPanelHeight
        maximum: bottomPanel.maxPanelHeight
        size: bottomPanel.panelHeight
        visible: bottomPanel.height > 8
        onResized: v => {
            bottomPanel.panelHeight = v;
        }
    }
}
