import QtQuick

// Undo/redo for one Document. Snapshot-based: entries hold a full
// scene (uids preserved) plus selection, so undo restores exact
// nodes. Discrete edits checkpoint once; drags and scrubs wrap in
// nested begin/end so each gesture commits a single entry. Depth is
// capped at 50 entries and 256MB (never below 5 entries), so heavy
// designs bound memory instead of growing with the session.
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
    // Memory budget: entries hold full scenes, so a count cap alone can
    // still pin hundreds of MB on blob-heavy designs. Sizes ride a
    // parallel array (bytes ≈ JSON length); pushes evict oldest while
    // over budget, never below minEntries so undo never vanishes.
    property int maxBytes: 268435456
    property int minEntries: 5
    property var undoSizes: []
    property var redoSizes: []

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
            next: doc.nextNodeUid,
            clips: doc.anim ? doc.anim.selectedClipIds.slice() : [],
            aclips: doc.audio ? doc.audio.selectedAudioIds.slice() : [],
            time: doc.anim ? doc.anim.currentTime : 0
        };
    }

    function restore(entry) {
        history.applying = true;
        doc.clipboard.restoreScene(entry.scene);
        if (entry.next > 0)
            doc.nextNodeUid = entry.next;
        // Undo never resumes playback, but the stale base (if any) must
        // go: nodes were just rebuilt from base values, so dropping it
        // changes nothing visible and keeps later captures honest.
        if (doc.anim)
            doc.anim.playBase = null;
        doc.clearSelectionSilent();
        var sel = entry.selected || [];
        for (var i = 0; i < sel.length; i++) {
            var n = doc.findNode(sel[i]);
            if (n)
                n.selected = true;
        }
        // Clip selection and playhead ride along, so the panel and the
        // timeline stay where the user was. Dead clip ids (nothing to
        // point at anymore) fall away.
        if (doc.anim) {
            var alive = {};
            var clips = doc.anim.clips;
            for (var j = 0; j < clips.length; j++)
                alive[clips[j].id] = true;
            var kept = [];
            var wanted = entry.clips || [];
            for (var k = 0; k < wanted.length; k++) {
                if (alive[wanted[k]])
                    kept.push(wanted[k]);
            }
            doc.anim.selectedClipIds = kept;
            doc.anim.currentTime = Math.min(doc.anim.duration, Math.max(0, Number(entry.time) || 0));
        }
        // Audio selection rides along too; dead ids fall away like clips.
        if (doc.audio) {
            var aalive = {};
            var aclips = doc.audio.clips;
            for (var m = 0; m < aclips.length; m++)
                aalive[aclips[m].id] = true;
            var akept = [];
            var awanted = entry.aclips || [];
            for (var n = 0; n < awanted.length; n++) {
                if (aalive[awanted[n]])
                    akept.push(awanted[n]);
            }
            doc.audio.selectedAudioIds = akept;
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

    function _bytesOf(entry) {
        try {
            var s = JSON.stringify(entry ? entry.scene : null);
            return s ? s.length : 0;
        } catch (e) {
            return 1048576;
        }
    }

    function _pushUndo(entry) {
        var s = history.undoStack.slice();
        var sizes = history.undoSizes.slice();
        s.push(entry);
        sizes.push(history._bytesOf(entry));
        var bytes = 0;
        for (var i = 0; i < sizes.length; i++)
            bytes += sizes[i];
        while ((s.length > history.maxDepth || (bytes > history.maxBytes && s.length > history.minEntries)) && s.length > 0) {
            bytes -= sizes[0];
            s.shift();
            sizes.shift();
        }
        history.undoStack = s;
        history.undoSizes = sizes;
        history.redoStack = [];
        history.redoSizes = [];
    }

    // Unconditional checkpoint before a discrete mutation. Settles any
    // preview first so the capture holds base values, never a frame.
    // No-op while applying history or inside a gesture transaction (the
    // outer end commits once for the whole gesture).
    function checkpoint() {
        if (history.applying || !doc)
            return;
        if (doc.anim)
            doc.anim.settlePreview();
        if (history.depth > 0)
            return;
        _pushUndo(capture());
    }

    // Gesture coalescing: snapshot once at the outermost press, commit
    // once at the outermost release.
    function begin() {
        if (history.applying || !doc)
            return;
        if (doc.anim)
            doc.anim.settlePreview();
        beginPassive();
    }

    // Same coalescing without touching playback: timeline keyframe
    // presses use this so a mere click-select never stops the player;
    // the first real drag move settles explicitly instead.
    function beginPassive() {
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
        var sizes = history.undoSizes.slice();
        var entry = s.pop();
        sizes.pop();
        history.undoStack = s;
        history.undoSizes = sizes;
        var r = history.redoStack.slice();
        var rsizes = history.redoSizes.slice();
        r.push(cur);
        rsizes.push(history._bytesOf(cur));
        history.redoStack = r;
        history.redoSizes = rsizes;
        restore(entry);
    }

    function redo() {
        if (!history.canRedo || history.applying || !doc)
            return;
        var cur = capture();
        var r = history.redoStack.slice();
        var rsizes = history.redoSizes.slice();
        var entry = r.pop();
        rsizes.pop();
        history.redoStack = r;
        history.redoSizes = rsizes;
        var s = history.undoStack.slice();
        var sizes = history.undoSizes.slice();
        s.push(cur);
        sizes.push(history._bytesOf(cur));
        history.undoStack = s;
        history.undoSizes = sizes;
        restore(entry);
    }

    function clear() {
        history.undoStack = [];
        history.redoStack = [];
        history.undoSizes = [];
        history.redoSizes = [];
        history.pending = null;
        history.depth = 0;
    }
}
