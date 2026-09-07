import QtQuick
import QtQuick.Layouts
import Totm

// Editor view: side panels + canvas on top, full-width bottom panel below
// (like web, where the timeline spans under everything).
// All panels empty for now.
ColumnLayout {
    id: view

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
        doc: TabStore.documentFor(TabStore.currentIndex)
        open: rightPanel.mode === "animate"
    }

    // Document driving the canvas and panels (null on home).
    readonly property var playDoc: TabStore.documentFor(TabStore.currentIndex)

    // Playback clock: one 16ms timer for the visible tab. Each document
    // owns its transport state, so switching tabs parks the old playhead
    // and picks up the new one with no extra bookkeeping.
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

    // Document undo/redo. Per-tab history; no-op on home or empty stack.
    // Skipped while typing in a text field so the field keeps its own
    // native undo (rename, hex and number fields).
    function focusInTextInput() {
        var w = view.Window.window;
        var f = w ? w.activeFocusItem : null;
        return !!f && typeof f.text !== "undefined" && typeof f.undo === "function" && typeof f.selectAll === "function";
    }

    Shortcut {
        sequences: [StandardKey.Undo]
        enabled: !TabStore.isHomeSelected
        onActivated: {
            if (view.focusInTextInput())
                return;
            var d = TabStore.documentFor(TabStore.currentIndex);
            if (d)
                d.undo();
        }
    }

    Shortcut {
        sequences: [StandardKey.Redo, "Ctrl+Y"]
        enabled: !TabStore.isHomeSelected
        onActivated: {
            if (view.focusInTextInput())
                return;
            var d = TabStore.documentFor(TabStore.currentIndex);
            if (d)
                d.redo();
        }
    }

    // Timeline keyframe delete. Same text-field guard as undo/redo so
    // typing Delete in a field never eats selected clips.
    Shortcut {
        sequences: ["Delete"]
        enabled: !TabStore.isHomeSelected && rightPanel.mode === "animate" && view.hasSelectedClips()
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
