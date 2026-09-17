import QtQuick
import Totm

// Editor keyboard shortcuts. Sequences come from ShortcutState (single
// source with the Shortcut tab, editable + persisted via SettingsStore);
// actions stay thin calls into the doc, ToolState and the right panel.
// Text inputs win via focusInTextInput, mirroring the undo guard, so
// typing never triggers canvas work. All shortcuts suspend while the
// Shortcut tab captures a new sequence.
Item {
    id: shortcuts

    required property var view
    required property var panel

    function doc() {
        return shortcuts.view ? shortcuts.view.playDoc : null;
    }

    function guarded() {
        return !shortcuts.view || shortcuts.view.focusInTextInput();
    }

    function hasShapes() {
        var d = shortcuts.doc();
        if (!d)
            return false;
        d.rev;
        return d.selectedTops().length > 0;
    }

    function hasClips() {
        var d = shortcuts.doc();
        return !!d && d.anim.selectedClipIds.length > 0;
    }

    function hasAudioSel() {
        var d = shortcuts.doc();
        return !!d && d.audio.selectedAudioIds.length > 0;
    }

    function canPasteShapes() {
        return TabState.clipboard.length > 0;
    }

    function canPasteClips() {
        var d = shortcuts.doc();
        return TabState.animClipboard.length > 0 && !!d && d.selectedTops().length > 0;
    }

    function canPaste() {
        return shortcuts.canPasteShapes() || shortcuts.canPasteClips();
    }

    function doCopy() {
        var d = shortcuts.doc();
        if (!d)
            return;
        // Copy whatever is selected: clips go to the animation clipboard
        // (cross-shape/design templates), shapes to the shape clipboard.
        // Both can fill on one press when both selections exist.
        if (shortcuts.hasClips())
            TabState.animClipboard = d.copySelectedClips();
        if (shortcuts.hasShapes())
            TabState.clipboard = d.copySelected();
    }

    function doPaste() {
        var d = shortcuts.doc();
        if (!d)
            return;
        // Animate mode pastes clips onto the selected tops (earliest at
        // the playhead); design mode (or no clip targets) pastes shapes.
        if (shortcuts.panel && shortcuts.panel.mode === "animate" && shortcuts.canPasteClips()) {
            var tops = d.selectedTops();
            var uids = [];
            for (var i = 0; i < tops.length; i++)
                uids.push(tops[i].uid);
            d.pasteClips(TabState.animClipboard, uids);
        } else if (shortcuts.canPasteShapes()) {
            d.insertCopies(TabState.clipboard);
        }
    }

    function doDuplicate() {
        var d = shortcuts.doc();
        if (!d)
            return;
        // Animate mode with a clip selection duplicates clips at the
        // playhead; otherwise duplicate the selected shapes.
        if (shortcuts.panel && shortcuts.panel.mode === "animate" && shortcuts.hasClips())
            d.duplicateClips(d.anim.selectedClipIds);
        else if (shortcuts.hasShapes())
            d.duplicateSelected();
    }

    function doNudge(dx, dy) {
        var d = shortcuts.doc();
        if (d)
            d.moveSelected(dx, dy);
    }

    function doSeek(t) {
        var d = shortcuts.doc();
        if (d)
            d.seekPlayhead(t);
    }

    function doTogglePlay() {
        var d = shortcuts.doc();
        if (!d)
            return;
        if (d.anim.playing)
            d.anim.pause();
        else
            d.anim.play();
    }

    // Global new design (home instance covers home; this covers editor).
    Shortcut {
        sequences: [ShortcutState.homeNew]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing
        onActivated: {
            if (shortcuts.guarded())
                return;
            TabState.addUntitled();
        }
    }

    Shortcut {
        sequences: [ShortcutState.editUndo]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing
        onActivated: {
            if (shortcuts.guarded())
                return;
            var d = shortcuts.doc();
            if (d)
                d.undo();
        }
    }

    Shortcut {
        sequences: [ShortcutState.editRedo, StandardKey.Redo]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing
        onActivated: {
            if (shortcuts.guarded())
                return;
            var d = shortcuts.doc();
            if (d)
                d.redo();
        }
    }

    Shortcut {
        sequences: [ShortcutState.editCopy]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing && (shortcuts.hasShapes() || shortcuts.hasClips())
        onActivated: {
            if (shortcuts.guarded())
                return;
            shortcuts.doCopy();
        }
    }

    Shortcut {
        sequences: [ShortcutState.editPaste]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing && (shortcuts.canPasteShapes() || shortcuts.canPasteClips())
        onActivated: {
            if (shortcuts.guarded())
                return;
            shortcuts.doPaste();
        }
    }

    Shortcut {
        sequences: [ShortcutState.editDuplicate]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing && (shortcuts.hasShapes() || shortcuts.hasClips())
        onActivated: {
            if (shortcuts.guarded())
                return;
            shortcuts.doDuplicate();
        }
    }

    Shortcut {
        sequences: [ShortcutState.editDelete, "Backspace"]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing && shortcuts.hasShapes()
        onActivated: {
            if (shortcuts.guarded())
                return;
            var d = shortcuts.doc();
            if (d)
                d.deleteSelected();
        }
    }

    Shortcut {
        sequences: [ShortcutState.editGroup]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing && shortcuts.hasShapes()
        onActivated: {
            if (shortcuts.guarded())
                return;
            var d = shortcuts.doc();
            if (d && d.canGroup())
                d.groupSelected();
        }
    }

    Shortcut {
        sequences: [ShortcutState.editUngroup]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing && shortcuts.hasShapes()
        onActivated: {
            if (shortcuts.guarded())
                return;
            var d = shortcuts.doc();
            if (d && d.canUngroup())
                d.ungroupSelected();
        }
    }

    Shortcut {
        sequences: [ShortcutState.arrangeFront]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing && shortcuts.hasShapes()
        onActivated: {
            if (shortcuts.guarded())
                return;
            var d = shortcuts.doc();
            if (d)
                d.bringToFront();
        }
    }

    Shortcut {
        sequences: [ShortcutState.arrangeBack]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing && shortcuts.hasShapes()
        onActivated: {
            if (shortcuts.guarded())
                return;
            var d = shortcuts.doc();
            if (d)
                d.sendToBack();
        }
    }

    Shortcut {
        sequences: [ShortcutState.arrangeForward]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing && shortcuts.hasShapes()
        onActivated: {
            if (shortcuts.guarded())
                return;
            var d = shortcuts.doc();
            if (d)
                d.moveForward();
        }
    }

    Shortcut {
        sequences: [ShortcutState.arrangeBackward]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing && shortcuts.hasShapes()
        onActivated: {
            if (shortcuts.guarded())
                return;
            var d = shortcuts.doc();
            if (d)
                d.moveBackward();
        }
    }

    Shortcut {
        sequences: [ShortcutState.layersRename]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing && shortcuts.hasShapes()
        onActivated: {
            if (shortcuts.guarded())
                return;
            var d = shortcuts.doc();
            if (d)
                d.beginRename(d.selectedTops()[0].uid);
        }
    }

    // Tools.
    Shortcut {
        sequences: [ShortcutState.toolSelect]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing
        onActivated: {
            if (shortcuts.guarded())
                return;
            ToolState.setActiveTool("select");
        }
    }

    Shortcut {
        sequences: [ShortcutState.toolRect]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing
        onActivated: {
            if (shortcuts.guarded())
                return;
            ToolState.setActiveShapeType("rectangle");
        }
    }

    Shortcut {
        sequences: [ShortcutState.toolEllipse]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing
        onActivated: {
            if (shortcuts.guarded())
                return;
            ToolState.setActiveShapeType("ellipse");
        }
    }

    Shortcut {
        sequences: [ShortcutState.toolTriangle]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing
        onActivated: {
            if (shortcuts.guarded())
                return;
            ToolState.setActiveShapeType("triangle");
        }
    }

    Shortcut {
        sequences: [ShortcutState.toolStar]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing
        onActivated: {
            if (shortcuts.guarded())
                return;
            ToolState.setActiveShapeType("star");
        }
    }

    Shortcut {
        sequences: [ShortcutState.toolPen]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing
        onActivated: {
            if (shortcuts.guarded())
                return;
            ToolState.setActiveTool("pen");
        }
    }

    Shortcut {
        sequences: [ShortcutState.toolText]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing
        onActivated: {
            if (shortcuts.guarded())
                return;
            ToolState.setActiveTool("text");
        }
    }

    Shortcut {
        sequences: [ShortcutState.toolImage]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing
        onActivated: {
            if (shortcuts.guarded())
                return;
            ToolState.setActiveTool("image");
        }
    }

    // Design / Animate.
    Shortcut {
        sequences: [ShortcutState.modeToggle]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing
        onActivated: {
            if (shortcuts.guarded())
                return;
            shortcuts.panel.toggleMode();
        }
    }

    Shortcut {
        sequences: [ShortcutState.modeDesign]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing
        onActivated: {
            if (shortcuts.guarded())
                return;
            shortcuts.panel.setMode("design");
        }
    }

    Shortcut {
        sequences: [ShortcutState.modeAnimate]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing
        onActivated: {
            if (shortcuts.guarded())
                return;
            shortcuts.panel.setMode("animate");
        }
    }

    // Canvas nudge (Shift is 10x).
    Shortcut {
        sequences: [ShortcutState.nudgeLeft]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing && shortcuts.hasShapes()
        onActivated: {
            if (shortcuts.guarded())
                return;
            shortcuts.doNudge(-1, 0);
        }
    }

    Shortcut {
        sequences: [ShortcutState.nudgeLeftBig]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing && shortcuts.hasShapes()
        onActivated: {
            if (shortcuts.guarded())
                return;
            shortcuts.doNudge(-10, 0);
        }
    }

    Shortcut {
        sequences: [ShortcutState.nudgeRight]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing && shortcuts.hasShapes()
        onActivated: {
            if (shortcuts.guarded())
                return;
            shortcuts.doNudge(1, 0);
        }
    }

    Shortcut {
        sequences: [ShortcutState.nudgeRightBig]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing && shortcuts.hasShapes()
        onActivated: {
            if (shortcuts.guarded())
                return;
            shortcuts.doNudge(10, 0);
        }
    }

    Shortcut {
        sequences: [ShortcutState.nudgeUp]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing && shortcuts.hasShapes()
        onActivated: {
            if (shortcuts.guarded())
                return;
            shortcuts.doNudge(0, -1);
        }
    }

    Shortcut {
        sequences: [ShortcutState.nudgeUpBig]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing && shortcuts.hasShapes()
        onActivated: {
            if (shortcuts.guarded())
                return;
            shortcuts.doNudge(0, -10);
        }
    }

    Shortcut {
        sequences: [ShortcutState.nudgeDown]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing && shortcuts.hasShapes()
        onActivated: {
            if (shortcuts.guarded())
                return;
            shortcuts.doNudge(0, 1);
        }
    }

    Shortcut {
        sequences: [ShortcutState.nudgeDownBig]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing && shortcuts.hasShapes()
        onActivated: {
            if (shortcuts.guarded())
                return;
            shortcuts.doNudge(0, 10);
        }
    }

    // Timeline transport.
    Shortcut {
        sequences: [ShortcutState.transportPlay]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing && shortcuts.panel.mode === "animate"
        onActivated: {
            if (shortcuts.guarded())
                return;
            shortcuts.doTogglePlay();
        }
    }

    Shortcut {
        sequences: [ShortcutState.transportStepBack]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing && shortcuts.panel.mode === "animate"
        onActivated: {
            if (shortcuts.guarded())
                return;
            var d = shortcuts.doc();
            if (d)
                shortcuts.doSeek(Math.max(0, d.anim.currentTime - 0.1));
        }
    }

    Shortcut {
        sequences: [ShortcutState.transportStepFwd]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing && shortcuts.panel.mode === "animate"
        onActivated: {
            if (shortcuts.guarded())
                return;
            var d = shortcuts.doc();
            if (d)
                shortcuts.doSeek(Math.min(d.anim.duration, d.anim.currentTime + 0.1));
        }
    }

    Shortcut {
        sequences: [ShortcutState.transportStart]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing && shortcuts.panel.mode === "animate"
        onActivated: {
            if (shortcuts.guarded())
                return;
            shortcuts.doSeek(0);
        }
    }

    Shortcut {
        sequences: [ShortcutState.transportEnd]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing && shortcuts.panel.mode === "animate"
        onActivated: {
            if (shortcuts.guarded())
                return;
            var d = shortcuts.doc();
            if (d)
                shortcuts.doSeek(d.anim.duration);
        }
    }

    // Timeline clip + audio delete (each side no-ops quietly when empty).
    Shortcut {
        sequences: [ShortcutState.editDelete]
        enabled: !TabState.isHomeSelected && !ShortcutState.capturing && shortcuts.panel.mode === "animate" && (shortcuts.hasClips() || shortcuts.hasAudioSel())
        onActivated: {
            if (shortcuts.guarded())
                return;
            if (shortcuts.hasClips() && shortcuts.doc())
                shortcuts.doc().deleteSelectedClips();
            if (shortcuts.hasAudioSel() && shortcuts.doc())
                shortcuts.doc().deleteSelectedAudio();
        }
    }
}
