import QtQuick

// Undo/redo for one Document. Snapshot-based: entries hold a full
// scene (uids preserved) plus selection, so undo restores exact
// nodes. Discrete edits checkpoint once; drags and scrubs wrap in
// nested begin/end so each gesture commits a single entry.
QtObject {
    id: history
    required property var doc

    property var undoStack: []
    property var redoStack: []
    property var pending: null
    property int pendingRev: -1
    // Nesting depth for gesture coalescing: only the outermost begin
    // snapshots, only the outermost end commits, so wrapped helpers
    // (aspect-locked commits, fill loops) join the outer entry.
    property int depth: 0
    property bool applying: false
    property int maxDepth: 50

    readonly property bool canUndo: history.undoStack.length > 0
    readonly property bool canRedo: history.redoStack.length > 0

    function _selectedUids() {
        var tops = doc.selectedTops();
        var out = [];
        for (var i = 0; i < tops.length; i++)
            out.push(tops[i].uid);
        return out;
    }

    function capture() {
        return {
            scene: doc.snapshotScene(),
            selected: _selectedUids(),
            anchor: doc.anchorUid,
            next: doc.nextNodeUid
        };
    }

    function restore(entry) {
        history.applying = true;
        doc.clipboard.restoreScene(entry.scene);
        if (entry.next > 0)
            doc.nextNodeUid = entry.next;
        doc.clearSelectionSilent();
        var sel = entry.selected || [];
        for (var i = 0; i < sel.length; i++) {
            var n = doc.findNode(sel[i]);
            if (n)
                n.selected = true;
        }
        doc.anchorUid = entry.anchor ?? -1;
        doc.pruneDrillPath();
        doc._refreshStructural();
        // Rebase an in-flight gesture (undo pressed mid-drag): the drag
        // continues from the restored state as a single entry.
        if (history.depth > 0) {
            history.pending = capture();
            history.pendingRev = doc.rev;
        }
        history.applying = false;
    }

    function _pushUndo(entry) {
        var s = history.undoStack.slice();
        s.push(entry);
        while (s.length > history.maxDepth)
            s.shift();
        history.undoStack = s;
        history.redoStack = [];
    }

    // Unconditional checkpoint before a discrete mutation. No-op while
    // applying history or inside a gesture transaction (the outer end
    // commits once for the whole gesture).
    function checkpoint() {
        if (history.applying || !doc)
            return;
        if (history.depth > 0)
            return;
        _pushUndo(capture());
    }

    // Gesture coalescing: snapshot once at the outermost press, commit
    // once at the outermost release.
    function begin() {
        if (history.applying || !doc)
            return;
        if (history.depth === 0) {
            history.pending = capture();
            history.pendingRev = doc.rev;
        }
        history.depth++;
    }

    function end() {
        if (history.depth === 0 || history.applying || !doc)
            return;
        history.depth--;
        if (history.depth > 0)
            return;
        var before = history.pending;
        history.pending = null;
        if (doc.rev === history.pendingRev)
            return;
        _pushUndo(before);
    }

    function undo() {
        if (!history.canUndo || history.applying || !doc)
            return;
        var cur = capture();
        var s = history.undoStack.slice();
        var entry = s.pop();
        history.undoStack = s;
        var r = history.redoStack.slice();
        r.push(cur);
        history.redoStack = r;
        restore(entry);
    }

    function redo() {
        if (!history.canRedo || history.applying || !doc)
            return;
        var cur = capture();
        var r = history.redoStack.slice();
        var entry = r.pop();
        history.redoStack = r;
        var s = history.undoStack.slice();
        s.push(cur);
        history.undoStack = s;
        restore(entry);
    }

    function clear() {
        history.undoStack = [];
        history.redoStack = [];
        history.pending = null;
        history.depth = 0;
    }
}
