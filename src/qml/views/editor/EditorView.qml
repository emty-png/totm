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

    // Debounced autosave: every mutation queues its own tab, the queue
    // flushes 800ms after the user settles. Saving the queued ids (not
    // the current tab) survives tab switches in between. Tab closes and
    // app quit save synchronously, so this only covers the idle path.
    property var pendingSaves: []

    Connections {
        target: TabStore.documentFor(TabStore.currentIndex)
        function onRevChanged() {
            if (TabStore.currentIndex > 0) {
                var id = TabStore.designIdAt(TabStore.currentIndex);
                if (id !== "" && pendingSaves.indexOf(id) < 0)
                    pendingSaves.push(id);
            }
            saveTimer.restart();
        }
    }

    Timer {
        id: saveTimer

        interval: 800
        onTriggered: {
            for (var i = 0; i < pendingSaves.length; i++)
                TabStore.saveOpenDesign(pendingSaves[i]);
            pendingSaves = [];
        }
    }
}
