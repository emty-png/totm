import QtQuick
import QtQuick.Layouts
import Totm

// Editor view: side panels + canvas on top, full-width bottom panel below
// (like web, where the timeline spans under everything).
// All panels empty for now.
ColumnLayout {
    spacing: 0

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 0

        EditorLeftPanel {
            Layout.fillHeight: true
            doc: TabStore.documentFor(TabStore.currentIndex)
        }

        EditorCanvas {
            Layout.fillWidth: true
            Layout.fillHeight: true
            doc: TabStore.documentFor(TabStore.currentIndex)
        }

        EditorRightPanel {
            id: rightPanel
            Layout.fillHeight: true
        }
    }

    EditorBottomPanel {
        Layout.fillWidth: true
        open: rightPanel.mode === "animate"
    }
}
