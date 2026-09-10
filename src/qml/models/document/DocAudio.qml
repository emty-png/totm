import QtQuick

// One Document's audio: timeline music clips, one lane row per clip.
// Clips are plain data (stored blob name, start time, file offset,
// audible duration) so the scene JSON stays backend-readable for video
// rendering. Rows overlap freely and every audible row mixes, in
// preview and in export. Clip objects are never mutated in place by
// discrete ops: edits replace them wholesale so undo snapshots stay
// immutable; lane drags mutate in place under a passive transaction
// and bump audioRev so lanes follow live.
QtObject {
    id: audio
    required property var doc

    property var clips: []
    property int nextAudioId: 1

    property var selectedAudioIds: []

    function clipById(id) {
        for (var i = 0; i < audio.clips.length; i++) {
            if (audio.clips[i].id === id)
                return audio.clips[i];
        }
        return null;
    }

    function isSelected(id) {
        return audio.selectedAudioIds.indexOf(id) >= 0;
    }

    // Adds a probed file at t0, trimmed to the composition end. offset
    // stays 0 in v1 (no trim handles yet) but rides the model so trim
    // fits later without migration. Lanes show "Sound {id}". Returns
    // the clip id, or -1 when nothing fits.
    function addClip(source, t0, fileDuration) {
        if (!source || !(fileDuration > 0))
            return -1;
        var start = Math.max(0, Number(t0) || 0);
        var room = doc.anim.duration - start;
        if (room <= 0)
            return -1;
        doc.history.checkpoint();
        var clip = {
            id: audio.nextAudioId++,
            source: String(source),
            t0: start,
            offset: 0,
            duration: Math.min(fileDuration, room)
        };
        var list = audio.clips.slice();
        list.push(clip);
        audio.clips = list;
        audio.selectedAudioIds = [clip.id];
        doc.touch();
        return clip.id;
    }

    // Lane-drag move: clamped to the composition start, end overflow is
    // fine (use sites intersect with the composition end). In-place so
    // callers wrap press/release in a passive transaction for one undo
    // entry; lane-local drag state carries the visuals mid-drag.
    function moveClip(id, t0) {
        var c = audio.clipById(id);
        if (!c)
            return false;
        c.t0 = Math.max(0, Number(t0) || 0);
        doc.touch();
        return true;
    }

    // Silent in-place nudge for lane drags (mirrors nudgeClip): no
    // checkpoint, no touch; release touches once for the single entry.
    function nudge(id, t0) {
        var c = audio.clipById(id);
        if (!c)
            return false;
        var nt0 = Math.max(0, Number(t0) || 0);
        if (isNaN(nt0) || c.t0 === nt0)
            return false;
        c.t0 = nt0;
        return true;
    }

    function deleteClips(ids) {
        var gone = {};
        for (var i = 0; i < (ids || []).length; i++)
            gone[ids[i]] = true;
        var kept = [];
        for (var j = 0; j < audio.clips.length; j++) {
            if (!gone[audio.clips[j].id])
                kept.push(audio.clips[j]);
        }
        if (kept.length === audio.clips.length)
            return false;
        doc.history.checkpoint();
        audio.clips = kept;
        audio.selectedAudioIds = audio.selectedAudioIds.filter(id => {
            for (var k = 0; k < kept.length; k++) {
                if (kept[k].id === id)
                    return true;
            }
            return false;
        });
        doc.touch();
        return true;
    }

    function deleteSelected() {
        return audio.deleteClips(audio.selectedAudioIds);
    }

    function selectClip(id, additive) {
        if (additive) {
            var sel = audio.selectedAudioIds.slice();
            var at = sel.indexOf(id);
            if (at >= 0)
                sel.splice(at, 1);
            else
                sel.push(id);
            audio.selectedAudioIds = sel;
        } else {
            audio.selectedAudioIds = [id];
        }
    }

    function clearSelection() {
        audio.selectedAudioIds = [];
    }

    // Marquee pick: adds without toggling, so sweeping an already
    // selected clip never deselects it mid-drag.
    function addToSelection(id) {
        if (audio.selectedAudioIds.indexOf(id) < 0) {
            var sel = audio.selectedAudioIds.slice();
            sel.push(id);
            audio.selectedAudioIds = sel;
        }
    }

    // Plain-data snapshot for saves and undo. Deep copies: lane drags
    // mutate live clips in place, which must never rewrite a stored
    // before-image.
    function snapshotData() {
        var out = [];
        for (var i = 0; i < audio.clips.length; i++) {
            var c = audio.clips[i];
            out.push({
                id: c.id,
                source: c.source,
                t0: c.t0,
                offset: c.offset,
                duration: c.duration
            });
        }
        return {
            nextAudioId: audio.nextAudioId,
            clips: out
        };
    }

    // Restore from a stored scene. Runs after the anim restore (needs
    // the composition duration): clips pull inside it, overlong ones
    // trim, sourceless ones drop.
    function restoreData(d) {
        var s = d || {};
        audio.selectedAudioIds = [];
        var dur = doc.anim ? doc.anim.duration : 0;
        var out = [];
        var top = 1;
        var raws = s.clips || [];
        for (var i = 0; i < raws.length; i++) {
            var r = raws[i] || {};
            if (!r.source)
                continue;
            var start = Math.min(dur, Math.max(0, Number(r.t0) || 0));
            if (start >= dur)
                continue;
            var id = typeof r.id === "number" ? r.id : top;
            out.push({
                id: id,
                source: String(r.source),
                t0: start,
                offset: Math.max(0, Number(r.offset) || 0),
                duration: Math.min(Math.max(0.05, Number(r.duration) || 0), dur - start)
            });
            if (id >= top)
                top = id + 1;
        }
        audio.clips = out;
        audio.nextAudioId = Math.max(top, s.nextAudioId > 0 ? s.nextAudioId : 1);
    }
}
