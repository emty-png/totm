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

    // Debounced autosave: every mutation restarts the clock, the scene
    // lands on disk 800ms after the user settles. Tab closes and app
    // quit save synchronously, so this only covers the idle path.
    Connections {
        target: TabStore.documentFor(TabStore.currentIndex)
        function onRevChanged() {
            saveTimer.restart();
        }
    }

    Timer {
        id: saveTimer

        interval: 800
        onTriggered: {
            if (TabStore.currentIndex > 0)
                TabStore.saveOpenDesign(TabStore.designIdAt(TabStore.currentIndex));
        }
    }
}
