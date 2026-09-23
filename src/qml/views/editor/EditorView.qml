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
            id: canvasView
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
        id: bottomPanel
        Layout.fillWidth: true
        doc: TabState.documentFor(TabState.currentIndex)
        open: rightPanel.mode === "animate"
    }

    // Document driving canvas and panels (null on home).
    readonly property var playDoc: TabState.documentFor(TabState.currentIndex)
    // Canvas item for window-level drop mapping (Main wires it in).
    property alias canvas: canvasView

    // Playback clock: one 16ms timer for the visible tab. Transport state
    // lives per document, so tab switches park and resume with no
    // bookkeeping here. Audio preview conducts itself off the same
    // transport clock beside it.
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

    AudioPreview {
        doc: view.playDoc
    }

    // Undo/redo for the current document. Skipped inside text inputs so
    // fields keep their native undo.
    function focusInTextInput() {
        var w = view.Window.window;
        var f = w ? w.activeFocusItem : null;
        return !!f && typeof f.text !== "undefined" && typeof f.undo === "function" && typeof f.selectAll === "function";
    }

    // All editor keyboard shortcuts live in one helper so this screen
    // stays a thin composition of panels + canvas + timeline.
    // externalDrop is set by Main (window-level image intake); the
    // paste shortcut falls back to it when the internal clipboards
    // are empty.
    property var externalDrop: null

    EditorShortcuts {
        view: view
        panel: rightPanel
        dropHandler: view.externalDrop
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
