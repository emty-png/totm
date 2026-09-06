import QtQuick
import QtQuick.Layouts
import Totm

// Editor left panel: layers list for the active document.
// Matches web `.editor-sidebar`: 275px, background fill, 1px right
// border, 6px resize handle on the right edge.
Item {
    id: leftPanel

    required property var doc

    property int panelWidth: 275
    readonly property int minPanelWidth: 180
    readonly property int maxPanelWidth: 480

    Layout.preferredWidth: leftPanel.panelWidth
    Layout.fillHeight: true

    Rectangle {
        anchors.fill: parent
        color: AppTheme.background
    }

    Rectangle {
        anchors {
            right: parent.right
            top: parent.top
            bottom: parent.bottom
        }
        width: 1
        color: AppTheme.border
    }

    // Deselect on empty-area click. Declared below the list so rows and
    // buttons above win their presses; presses elsewhere fall through
    // the list (nothing there claims them) to here: steal focus (settles
    // any open rename editor) and clear.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onClicked: {
            leftPanel.forceActiveFocus();
            if (leftPanel.doc)
                leftPanel.doc.clearSelection();
        }
    }

    // Empty-area right-click opens the context menu without touching the
    // selection (only Paste can apply there).
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onPressed: mouse => leftPanel.openContext(-1, mouse.x, mouse.y)
    }

    LayersView {
        id: list
        anchors.fill: parent
        doc: leftPanel.doc
        contextPolicy: (uid, x, y) => leftPanel.openContext(uid, x, y)
    }

    // Drag-reorder insertion line, fed live by the list (view coords
    // equal panel coords). Above the rows so it draws over the gap.
    // Only same-parent gaps mark (see LayersView.dropValid).
    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            leftMargin: 8
            rightMargin: 8
        }
        y: list.dropY - 1
        height: 2
        radius: 1
        visible: list.dragging && list.dropValid
        color: AppTheme.selection
    }

    // Sidebar context menu (Copy / Paste / Duplicate / Group / Arrange /
    // Rename / Delete). Popup overlay, so declaration order is free.
    LayersContextMenu {
        id: contextMenu
        doc: leftPanel.doc
    }

    function openContext(uid, x, y) {
        leftPanel.forceActiveFocus();
        contextMenu.openFor(uid, x, y);
    }

    // Resize handle straddling the right edge, like web `.resize-handle`.
    MouseArea {
        id: handle
        anchors {
            right: parent.right
            top: parent.top
            bottom: parent.bottom
            rightMargin: -3
        }
        width: 6
        cursorShape: Qt.SplitHCursor
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true

        property real startX: 0
        property real startW: 275

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
            handle.startX = handle.mapToGlobal(mouse.x, mouse.y).x;
            handle.startW = leftPanel.panelWidth;
        }
        onPositionChanged: mouse => {
            if (!handle.pressed)
                return;
            var globalX = handle.mapToGlobal(mouse.x, mouse.y).x;
            leftPanel.panelWidth = Math.min(leftPanel.maxPanelWidth, Math.max(leftPanel.minPanelWidth, handle.startW + globalX - handle.startX));
        }
    }
}
