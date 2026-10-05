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
            duration: Math.min(fileDuration, room),
            volume: 1,
            fadeIn: 0,
            fadeOut: 0,
            muted: false
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

    // Silent in-place trim for lane trim drags: t0/offset/duration move
    // together (left trim advances offset, right trim keeps it). No
    // checkpoint, no touch; release touches once. Floor 0.05s.
    function nudgeTrim(id, t0, offset, duration) {
        var c = audio.clipById(id);
        if (!c)
            return false;
        var nt0 = Math.max(0, Number(t0) || 0);
        var noff = Math.max(0, Number(offset) || 0);
        var nd = Math.max(0.05, Number(duration) || 0);
        if (isNaN(nt0) || isNaN(noff) || isNaN(nd))
            return false;
        if (c.t0 === nt0 && Number(c.offset || 0) === noff && c.duration === nd)
            return false;
        c.t0 = nt0;
        c.offset = noff;
        c.duration = nd;
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

    // Duplicates clips at the playhead, keeping relative offsets
    // (earliest lands on the playhead). Mirrors DocAnim.duplicateClips:
    // one undo entry, new ids selected.
    function duplicateClips(ids) {
        var asked = {};
        var list = ids || [];
        for (var i = 0; i < list.length; i++)
            asked[list[i]] = true;
        var src = [];
        for (var j = 0; j < audio.clips.length; j++) {
            if (asked[audio.clips[j].id])
                src.push(audio.clips[j]);
        }
        if (src.length === 0)
            return [];
        var earliest = src[0].t0;
        for (var k = 1; k < src.length; k++) {
            if (src[k].t0 < earliest)
                earliest = src[k].t0;
        }
        var comp = Math.max(0.5, doc.anim.duration);
        var base = Math.min(doc.anim.currentTime, Math.max(0, comp - 0.05));
        doc.history.checkpoint();
        var out = audio.clips.slice();
        var made = [];
        for (var m = 0; m < src.length; m++) {
            var s = src[m];
            var nt0 = Math.min(Math.max(0, s.t0 - earliest + base), Math.max(0, comp - 0.05));
            if (nt0 >= comp)
                continue;
            var copy = {
                id: audio.nextAudioId++,
                source: String(s.source),
                t0: nt0,
                offset: Math.max(0, Number(s.offset) || 0),
                duration: Math.min(Math.max(0.05, Number(s.duration) || 0), Math.max(0.05, comp - nt0)),
                volume: s.volume === undefined ? 1 : s.volume,
                fadeIn: s.fadeIn === undefined ? 0 : s.fadeIn,
                fadeOut: s.fadeOut === undefined ? 0 : s.fadeOut,
                muted: s.muted === true
            };
            out.push(copy);
            made.push(copy.id);
        }
        audio.clips = out;
        audio.selectedAudioIds = made.slice();
        doc.touch();
        return made;
    }

    function duplicateSelected() {
        return audio.duplicateClips(audio.selectedAudioIds);
    }

    // Clip copy/paste templates: plain data without ids, so they survive
    // across documents (TabState.audioClipboard holds them app-wide).
    // dt preserves relative offsets (earliest = 0); paste re-anchors
    // earliest at the playhead.
    function copyClips(ids) {
        var asked = {};
        var list = ids || [];
        for (var i = 0; i < list.length; i++)
            asked[list[i]] = true;
        var src = [];
        for (var j = 0; j < audio.clips.length; j++) {
            if (asked[audio.clips[j].id])
                src.push(audio.clips[j]);
        }
        if (src.length === 0)
            return [];
        src.sort((a, b) => (a.t0 - b.t0) || (a.id - b.id));
        var earliest = src[0].t0;
        var out = [];
        for (var k = 0; k < src.length; k++) {
            var s = src[k];
            out.push({
                source: String(s.source),
                duration: Math.max(0.05, Number(s.duration) || 0),
                offset: Math.max(0, Number(s.offset) || 0),
                dt: Math.max(0, s.t0 - earliest),
                volume: s.volume === undefined ? 1 : s.volume,
                fadeIn: s.fadeIn === undefined ? 0 : s.fadeIn,
                fadeOut: s.fadeOut === undefined ? 0 : s.fadeOut,
                muted: s.muted === true
            });
        }
        return out;
    }

    function copySelectedClips() {
        return audio.copyClips(audio.selectedAudioIds);
    }

    // Pastes templates at baseTime (default: playhead), earliest at base.
    // One undo entry; new ids selected. Clips past the end are skipped.
    function pasteClips(templates, baseTime) {
        var tmpl = templates || [];
        if (tmpl.length === 0)
            return [];
        var comp = Math.max(0.5, doc.anim.duration);
        var base = baseTime !== undefined ? Number(baseTime) : doc.anim.currentTime;
        if (isNaN(base))
            base = doc.anim.currentTime;
        base = Math.min(Math.max(0, base), Math.max(0, comp - 0.05));
        var ordered = tmpl.slice().sort((a, b) => (Number(a.dt) || 0) - (Number(b.dt) || 0));
        doc.history.checkpoint();
        var out = audio.clips.slice();
        var made = [];
        for (var m = 0; m < ordered.length; m++) {
            var s = ordered[m] || {};
            if (!s.source)
                continue;
            var nt0 = Math.max(0, (Number(s.dt) || 0) + base);
            if (nt0 >= comp)
                continue;
            var clip = {
                id: audio.nextAudioId++,
                source: String(s.source),
                t0: nt0,
                offset: Math.max(0, Number(s.offset) || 0),
                duration: Math.min(Math.max(0.05, Number(s.duration) || 0), Math.max(0.05, comp - nt0)),
                volume: s.volume === undefined ? 1 : Math.min(1, Math.max(0, Number(s.volume) || 0)),
                fadeIn: Math.max(0, Number(s.fadeIn) || 0),
                fadeOut: Math.max(0, Number(s.fadeOut) || 0),
                muted: s.muted === true
            };
            out.push(clip);
            made.push(clip.id);
        }
        audio.clips = out;
        audio.selectedAudioIds = made.slice();
        doc.touch();
        return made;
    }

    // Splits one clip at composition time t: left keeps [t0, t),
    // right keeps [t, end) with offset advanced. One undo entry.
    // Returns [leftId, rightId] or [] when t is not interior.
    // Both halves floor at 0.05s, so nubs shorter than 0.1s refuse.
    function splitClip(id, t) {
        var at = -1;
        for (var i = 0; i < audio.clips.length; i++) {
            if (audio.clips[i].id === id) {
                at = i;
                break;
            }
        }
        if (at < 0)
            return [];
        var c = audio.clips[at];
        var tt = Number(t);
        if (isNaN(tt) || tt - c.t0 < 0.05 || (c.t0 + c.duration) - tt < 0.05)
            return [];
        var leftDur = Math.max(0.05, tt - c.t0);
        var rightDur = Math.max(0.05, (c.t0 + c.duration) - tt);
        var rightOffset = Math.max(0, (Number(c.offset) || 0) + (tt - c.t0));
        doc.history.checkpoint();
        var list = audio.clips.slice();
        var left = Object.assign({}, c);
        left.duration = leftDur;
        var right = Object.assign({}, c);
        right.id = audio.nextAudioId++;
        right.t0 = tt;
        right.offset = rightOffset;
        right.duration = rightDur;
        list[at] = left;
        list.splice(at + 1, 0, right);
        audio.clips = list;
        audio.selectedAudioIds = [left.id, right.id];
        doc.touch();
        return [left.id, right.id];
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

    // Selected clip objects in lane order. Empty when nothing fits.
    function selectedList() {
        var out = [];
        for (var i = 0; i < audio.clips.length; i++) {
            if (audio.selectedAudioIds.indexOf(audio.clips[i].id) >= 0)
                out.push(audio.clips[i]);
        }
        return out;
    }

    // Mixed-value read over the selection for the audio panel (mirrors
    // SelectionSnapshot.commonOf). Missing roles and empty selections
    // read as mixed so bindings never see undefined.
    function commonOf(role) {
        var sel = audio.selectedList();
        if (sel.length === 0 || sel[0][role] === undefined)
            return {
                mixed: true,
                value: 0
            };
        var v = sel[0][role];
        for (var i = 1; i < sel.length; i++) {
            if (sel[i][role] !== v)
                return {
                    mixed: true,
                    value: v
                };
        }
        return {
            mixed: false,
            value: v
        };
    }

    // Panel write: replaces clips wholesale so undo snapshots stay
    // immutable. Timing clamps to the composition start and positive
    // lengths; fades floor at zero (the exporter fits them to the
    // take). Checkpoints once; scrub gestures coalesce via depth.
    function setProp(role, value) {
        var sel = audio.selectedList();
        if (sel.length === 0)
            return false;
        var v = value;
        if (role === "t0" || role === "duration" || role === "offset" || role === "fadeIn" || role === "fadeOut")
            v = Math.max(role === "duration" ? 0.05 : 0, Number(value) || 0);
        else if (role === "volume")
            v = Math.min(1, Math.max(0, Number(value) || 0));
        else if (role === "muted")
            v = value === true;
        else
            return false;
        doc.history.checkpoint();
        var ids = {};
        for (var i = 0; i < sel.length; i++)
            ids[sel[i].id] = true;
        var list = audio.clips.slice();
        for (var j = 0; j < list.length; j++) {
            if (ids[list[j].id]) {
                var next = Object.assign({}, list[j]);
                next[role] = v;
                list[j] = next;
            }
        }
        audio.clips = list;
        doc.touch();
        return true;
    }

    // Mute toggle for the selection: clears when all are muted, else
    // mutes everything (mirrors multi-row toggle affordances).
    function toggleMuted() {
        var sel = audio.selectedList();
        if (sel.length === 0)
            return false;
        var all = true;
        for (var i = 0; i < sel.length; i++) {
            if (sel[i].muted !== true)
                all = false;
        }
        return audio.setProp("muted", !all);
    }

    // Swaps the file under the selected clips, keeping each clip's
    // timing. Trims to the new file so offset + duration never overrun;
    // returns the replaced count, or -1 when the file holds nothing.
    function replaceSource(source, fileDuration) {
        var sel = audio.selectedList();
        if (sel.length === 0 || !source || !(fileDuration > 0))
            return -1;
        doc.history.checkpoint();
        var ids = {};
        for (var i = 0; i < sel.length; i++)
            ids[sel[i].id] = true;
        var list = audio.clips.slice();
        for (var j = 0; j < list.length; j++) {
            if (ids[list[j].id]) {
                var next = Object.assign({}, list[j]);
                next.source = String(source);
                next.offset = Math.min(Math.max(0, Number(next.offset) || 0), Math.max(0, fileDuration - 0.05));
                next.duration = Math.min(Math.max(0.05, Number(next.duration) || 0), Math.max(0.05, fileDuration - next.offset));
                list[j] = next;
            }
        }
        audio.clips = list;
        doc.touch();
        return sel.length;
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
                duration: c.duration,
                volume: c.volume === undefined ? 1 : c.volume,
                fadeIn: c.fadeIn === undefined ? 0 : c.fadeIn,
                fadeOut: c.fadeOut === undefined ? 0 : c.fadeOut,
                muted: c.muted === true
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
                duration: Math.min(Math.max(0.05, Number(r.duration) || 0), dur - start),
                volume: r.volume === undefined ? 1 : Math.min(1, Math.max(0, Number(r.volume) || 0)),
                fadeIn: Math.max(0, Number(r.fadeIn) || 0),
                fadeOut: Math.max(0, Number(r.fadeOut) || 0),
                muted: r.muted === true
            });
            if (id >= top)
                top = id + 1;
        }
        audio.clips = out;
        audio.nextAudioId = Math.max(top, s.nextAudioId > 0 ? s.nextAudioId : 1);
    }
}
