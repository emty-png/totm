import QtQuick
import QtQuick.Layouts
import Totm

// Editor right panel. Holds the mode switcher; content below is empty.
// Matches web `.editor-right-sidebar`: 280px, background fill, 1px left
// border, 6px resize handle on the left edge.
Item {
    id: rightPanel

    property int panelWidth: 280
    readonly property int minPanelWidth: 180
    readonly property int maxPanelWidth: 480

    // Editor mode, owned by the switcher below.
    readonly property alias mode: modeSwitcher.mode

    Layout.preferredWidth: rightPanel.panelWidth
    Layout.fillHeight: true

    Rectangle {
        anchors.fill: parent
        color: AppTheme.background
    }

    Rectangle {
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
        }
        width: 1
        color: AppTheme.border
    }

    Column {
        anchors.fill: parent
        spacing: 0

        EditorModeSwitcher {
            id: modeSwitcher
            width: parent.width
            height: 48
        }

        // Design properties for the selection.
        DesignPanel {
            width: parent.width
            height: parent.height - 48
            visible: modeSwitcher.mode === "design"
            doc: TabStore.documentFor(TabStore.currentIndex)
        }

        // Animate mode placeholder.
        Text {
            width: parent.width
            height: parent.height - 48
            visible: modeSwitcher.mode === "animate"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            leftPadding: 16
            rightPadding: 16
            text: qsTr("Nothing to see here...")
            font.pixelSize: 13
            color: AppTheme.muted
        }
    }

    // Resize handle straddling the left edge, like web `.resize-handle`.
    MouseArea {
        id: handle
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
            leftMargin: -3
        }
        width: 6
        cursorShape: Qt.SplitHCursor
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true

        property real startX: 0
        property real startW: 280

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
            handle.startW = rightPanel.panelWidth;
        }
        onPositionChanged: mouse => {
            if (!handle.pressed)
                return;
            var globalX = handle.mapToGlobal(mouse.x, mouse.y).x;
            rightPanel.panelWidth = Math.min(rightPanel.maxPanelWidth, Math.max(rightPanel.minPanelWidth, handle.startW - (globalX - handle.startX)));
        }
    }
}
