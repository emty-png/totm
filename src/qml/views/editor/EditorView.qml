import QtQuick
import QtQuick.Layouts
import Totm

// Editor screen: side panels + canvas on top, full-width timeline panel
// below. The bottom panel opens in animate mode.
ColumnLayout {
    id: view

    spacing: 0

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 0

        EditorLeftPanel {
            Layout.fillHeight: true
            doc: TabState.documentFor(TabState.currentIndex)
        }

        EditorCanvas {
            Layout.fillWidth: true
            Layout.fillHeight: true
            doc: TabState.documentFor(TabState.currentIndex)
        }

        EditorRightPanel {
            id: rightPanel
            Layout.fillHeight: true
        }
    }

    EditorBottomPanel {
        Layout.fillWidth: true
        doc: TabState.documentFor(TabState.currentIndex)
        open: rightPanel.mode === "animate"
    }

    // Document driving canvas and panels (null on home).
    readonly property var playDoc: TabState.documentFor(TabState.currentIndex)

    // Playback clock: one 16ms timer for the visible tab. Transport state
    // lives per document, so tab switches park and resume with no
    // bookkeeping here.
    Timer {
        id: playTimer

        interval: 16
        repeat: true
        running: !!view.playDoc && view.playDoc.anim.playing
        onTriggered: {
            if (view.playDoc)
                view.playDoc.anim.tick();
        }
    }

    // Undo/redo for the current document. Skipped inside text inputs so
    // fields keep their native undo.
    function focusInTextInput() {
        var w = view.Window.window;
        var f = w ? w.activeFocusItem : null;
        return !!f && typeof f.text !== "undefined" && typeof f.undo === "function" && typeof f.selectAll === "function";
    }

    Shortcut {
        sequences: [StandardKey.Undo]
        enabled: !TabState.isHomeSelected
        onActivated: {
            if (view.focusInTextInput())
                return;
            var d = TabState.documentFor(TabState.currentIndex);
            if (d)
                d.undo();
        }
    }

    Shortcut {
        sequences: [StandardKey.Redo, "Ctrl+Y"]
        enabled: !TabState.isHomeSelected
        onActivated: {
            if (view.focusInTextInput())
                return;
            var d = TabState.documentFor(TabState.currentIndex);
            if (d)
                d.redo();
        }
    }

    // Timeline clip delete. Same text-input guard as undo/redo.
    Shortcut {
        sequences: ["Delete"]
        enabled: !TabState.isHomeSelected && rightPanel.mode === "animate" && view.hasSelectedClips()
        onActivated: {
            if (view.focusInTextInput())
                return;
            if (view.playDoc)
                view.playDoc.deleteSelectedClips();
        }
    }

    function hasSelectedClips() {
        var d = view.playDoc;
        return !!d && d.anim.selectedClipIds.length > 0;
    }

    // Debounced autosave: each mutation queues its tab id; the queue
    // flushes 800ms after the user settles. Queued ids (not the current
    // tab) survive tab switches. Tab close and app quit save
    // synchronously; this covers the idle path only.
    property var pendingSaves: []

    Connections {
        target: TabState.documentFor(TabState.currentIndex)
        function onRevChanged() {
            if (TabState.currentIndex > 0) {
                var id = TabState.designIdAt(TabState.currentIndex);
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
                TabState.saveOpenDesign(pendingSaves[i]);
            pendingSaves = [];
        }
    }
}
