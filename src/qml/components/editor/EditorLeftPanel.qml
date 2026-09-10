import QtQuick
import QtQuick.Layouts
import Totm

// Editor left panel: layers list for the active document. 275px,
// background fill, 1px right border, shared resize strip on the right.
Item {
    id: leftPanel

    required property var doc

    property int panelWidth: 275
    readonly property int minPanelWidth: 180
    readonly property int maxPanelWidth: 480

    Layout.preferredWidth: leftPanel.panelWidth
    Layout.fillHeight: true

    Behavior on Layout.preferredWidth {
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

    // Resize strip on the right edge, shared with every panel.
    PanelResizeHandle {
        edge: "right"
        minimum: leftPanel.minPanelWidth
        maximum: leftPanel.maxPanelWidth
        size: leftPanel.panelWidth
        onResized: v => {
            leftPanel.panelWidth = v;
        }
    }
}
