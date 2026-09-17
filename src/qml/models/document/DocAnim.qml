import QtQuick

// One Document's animation: composition duration plus preset clips.
// Clips are plain data (target top uid, preset, times, options, easing)
// so the scene JSON stays backend-readable for video rendering later.
// Clip objects are never mutated in place: edits replace them wholesale
// so undo snapshots stay immutable. Mutating ops checkpoint + touch
// (autosave rides rev); selection and transport state do neither.
QtObject {
    id: anim
    required property var doc

    property real duration: 4.0
    property var clips: []
    property int nextClipId: 1

    property var selectedClipIds: []
    // Clip-data revision, bumped by silent in-place nudges (lane drags)
    // that deliberately skip touch(). Panels read this so values follow
    // live; lane delegates never bind it, so no model rebuilds mid-drag.
    property int clipRev: 0

    // Playback transport owns play state, playhead and pre-play values.
    // Aliases keep every reader (timeline, galleries, canvas, history)
    // working unchanged, including direct writes.
    property var transport: DocTransport {
        id: transportState
        doc: anim.doc
    }
    property alias playing: transportState.playing
    property alias currentTime: transportState.currentTime
    property alias playBase: transportState.playBase

    property var presets: DocAnimPresets {
        doc: anim.doc
    }
    property var sampler: DocAnimSample {}

    function clipById(id) {
        for (var i = 0; i < anim.clips.length; i++) {
            if (anim.clips[i].id === id)
                return anim.clips[i];
        }
        return null;
    }

    function clipsForTarget(uid) {
        var out = [];
        for (var i = 0; i < anim.clips.length; i++) {
            if (anim.clips[i].targetUid === uid)
                out.push(anim.clips[i]);
        }
        return out;
    }

    function isClipSelected(id) {
        return anim.selectedClipIds.indexOf(id) >= 0;
    }

    // Applies a preset to each valid target top (groups animate as one
    // unit about their bbox center at sample time). New clips start at
    // t0 (the playhead from the timeline) with the preset default
    // duration unless given. Stagger offsets each next target by that
    // many seconds (cascades), clamped inside the composition.
    // Returns applied clip ids.
    function applyPreset(presetId, targetUids, t0, duration, mode, options, easing, loop, stagger) {
        if (anim.presets.presetIds().indexOf(presetId) < 0)
            return [];
        var valid = [];
        var asked = targetUids || [];
        for (var i = 0; i < asked.length; i++) {
            if (doc.findNode(asked[i]))
                valid.push(asked[i]);
        }
        if (valid.length === 0)
            return [];
        var st = Math.min(1, Math.max(0, Number(stagger) || 0));
        var comp = Math.max(0.5, anim.duration);
        doc.history.checkpoint();
        var made = [];
        var list = anim.clips.slice();
        for (var j = 0; j < valid.length; j++) {
            var nt0 = Math.min(t0 + j * st, Math.max(0, comp - 0.1));
            var clip = anim.presets.buildClip(presetId, anim.nextClipId++, valid[j], nt0, duration, mode, options, easing, loop);
            list.push(clip);
            made.push(clip.id);
        }
        anim.clips = list;
        anim.selectedClipIds = made.slice();
        doc.touch();
        return made;
    }

    function setClipOptions(id, patch) {
        var at = -1;
        for (var i = 0; i < anim.clips.length; i++) {
            if (anim.clips[i].id === id)
                at = i;
        }
        if (at < 0)
            return false;
        var old = anim.clips[at];
        var merged = {};
        var keys = patch || {};
        for (var k in old.options)
            merged[k] = old.options[k];
        for (var p in keys)
            merged[p] = keys[p];
        var fixed = anim.presets.buildClip(old.preset, old.id, old.targetUid, old.t0, old.duration, old.mode, merged, old.easing, old.loop);
        doc.history.checkpoint();
        var list = anim.clips.slice();
        list[at] = fixed;
        anim.clips = list;
        doc.touch();
        return true;
    }

    function retimeClip(id, t0, duration) {
        var at = -1;
        for (var i = 0; i < anim.clips.length; i++) {
            if (anim.clips[i].id === id)
                at = i;
        }
        if (at < 0)
            return false;
        var old = anim.clips[at];
        var nt0 = Math.max(0, Number(t0));
        var nd = Math.min(60, Math.max(0.1, Number(duration)));
        nd = Math.min(nd, Math.max(0.1, anim.duration - nt0));
        if (isNaN(nt0) || isNaN(nd) || (nt0 === old.t0 && nd === old.duration))
            return false;
        var fixed = anim.presets.buildClip(old.preset, old.id, old.targetUid, nt0, nd, old.mode, old.options, old.easing, old.loop);
        doc.history.checkpoint();
        var list = anim.clips.slice();
        list[at] = fixed;
        anim.clips = list;
        doc.touch();
        return true;
    }

    // Silent in-place retime for lane drags: no checkpoint, no touch, so
    // delegates survive the gesture (no model rebuild) while ticks keep
    // previewing the live values. The press-time begin() holds the undo
    // image; release touches once and ends for a single entry. Clamp
    // mirrors retimeClip so drags can never stage invalid times.
    function nudgeClip(id, t0, duration) {
        var at = -1;
        for (var i = 0; i < anim.clips.length; i++) {
            if (anim.clips[i].id === id)
                at = i;
        }
        if (at < 0)
            return false;
        var nt0 = Math.min(anim.duration, Math.max(0, Number(t0)));
        var nd = Math.min(60, Math.max(0.1, Number(duration)));
        nd = Math.min(nd, Math.max(0.1, anim.duration - nt0));
        if (isNaN(nt0) || isNaN(nd))
            return false;
        var c = anim.clips[at];
        if (c.t0 === nt0 && c.duration === nd)
            return false;
        c.t0 = nt0;
        c.duration = nd;
        anim.clipRev++;
        return true;
    }

    function setClipEasing(id, easing) {
        var at = -1;
        for (var i = 0; i < anim.clips.length; i++) {
            if (anim.clips[i].id === id)
                at = i;
        }
        if (at < 0)
            return false;
        var old = anim.clips[at];
        var fixed = anim.presets.buildClip(old.preset, old.id, old.targetUid, old.t0, old.duration, old.mode, old.options, easing, old.loop);
        doc.history.checkpoint();
        var list = anim.clips.slice();
        list[at] = fixed;
        anim.clips = list;
        doc.touch();
        return true;
    }

    function setClipMode(id, mode) {
        var at = -1;
        for (var i = 0; i < anim.clips.length; i++) {
            if (anim.clips[i].id === id)
                at = i;
        }
        if (at < 0)
            return false;
        var old = anim.clips[at];
        var nm = mode === "out" ? "out" : "in";
        if (nm === old.mode)
            return false;
        var fixed = anim.presets.buildClip(old.preset, old.id, old.targetUid, old.t0, old.duration, nm, old.options, old.easing, old.loop);
        doc.history.checkpoint();
        var list = anim.clips.slice();
        list[at] = fixed;
        anim.clips = list;
        doc.touch();
        return true;
    }

    // Loop mode is clip-level like mode (not in options): rebuilds the
    // clip so stored data stays normalized, one undo entry per change.
    function setClipLoop(id, loop) {
        var at = -1;
        for (var i = 0; i < anim.clips.length; i++) {
            if (anim.clips[i].id === id)
                at = i;
        }
        if (at < 0)
            return false;
        var old = anim.clips[at];
        var nl = anim.presets.normalizeLoop(loop);
        if (nl === anim.presets.normalizeLoop(old.loop))
            return false;
        var fixed = anim.presets.buildClip(old.preset, old.id, old.targetUid, old.t0, old.duration, old.mode, old.options, old.easing, nl);
        doc.history.checkpoint();
        var list = anim.clips.slice();
        list[at] = fixed;
        anim.clips = list;
        doc.touch();
        return true;
    }

    function deleteClips(ids) {
        var drop = {};
        var asked = ids || [];
        for (var i = 0; i < asked.length; i++)
            drop[asked[i]] = true;
        var kept = [];
        var removed = [];
        for (var j = 0; j < anim.clips.length; j++) {
            if (drop[anim.clips[j].id])
                removed.push(anim.clips[j].id);
            else
                kept.push(anim.clips[j]);
        }
        if (removed.length === 0)
            return [];
        doc.history.checkpoint();
        anim.clips = kept;
        anim.selectedClipIds = anim.selectedClipIds.filter(id => !drop[id]);
        doc.touch();
        return removed;
    }

    function deleteSelectedClips() {
        return anim.deleteClips(anim.selectedClipIds);
    }

    // Duplicates clips at the playhead, keeping their relative offsets
    // (earliest lands on the playhead). New ids are selected. One undo
    // entry; options deep-copy so later edits never alias the source.
    function duplicateClips(ids) {
        var asked = {};
        var list = ids || [];
        for (var i = 0; i < list.length; i++)
            asked[list[i]] = true;
        var src = [];
        for (var j = 0; j < anim.clips.length; j++) {
            if (asked[anim.clips[j].id])
                src.push(anim.clips[j]);
        }
        if (src.length === 0)
            return [];
        var earliest = src[0].t0;
        for (var k = 1; k < src.length; k++) {
            if (src[k].t0 < earliest)
                earliest = src[k].t0;
        }
        var comp = Math.max(0.5, anim.duration);
        var base = Math.min(anim.currentTime, Math.max(0, comp - 0.1));
        doc.history.checkpoint();
        var out = anim.clips.slice();
        var made = [];
        for (var m = 0; m < src.length; m++) {
            var s = src[m];
            var nt0 = Math.min(s.t0 - earliest + base, Math.max(0, comp - 0.1));
            var copy = anim.presets.buildClip(s.preset, anim.nextClipId++, s.targetUid, nt0, s.duration, s.mode, copyMap(s.options), s.easing, s.loop);
            if (!doc.findNode(copy.targetUid))
                continue;
            out.push(copy);
            made.push(copy.id);
        }
        anim.clips = out;
        anim.selectedClipIds = made.slice();
        doc.touch();
        return made;
    }

    // Clip copy/paste templates: plain data without ids or targets, so
    // they survive across shapes and documents (TabState holds them
    // app-wide). dt preserves relative offsets (earliest = 0); paste
    // re-anchors earliest at the playhead. Options/easing deep-copy so
    // later edits never alias the source.
    function copyClips(ids) {
        var asked = {};
        var list = ids || [];
        for (var i = 0; i < list.length; i++)
            asked[list[i]] = true;
        var src = [];
        for (var j = 0; j < anim.clips.length; j++) {
            if (asked[anim.clips[j].id])
                src.push(anim.clips[j]);
        }
        if (src.length === 0)
            return [];
        src.sort((a, b) => (a.t0 - b.t0) || (a.id - b.id));
        var earliest = src[0].t0;
        var out = [];
        for (var k = 0; k < src.length; k++) {
            var s = src[k];
            var ez = s.easing || {};
            out.push({
                preset: s.preset,
                duration: s.duration,
                dt: Math.max(0, s.t0 - earliest),
                mode: s.mode,
                loop: anim.presets.normalizeLoop(s.loop),
                options: copyMap(s.options),
                easing: {
                    id: ez.id,
                    bezier: ez.bezier ? ez.bezier.slice() : ez.bezier
                }
            });
        }
        return out;
    }

    function copySelectedClips() {
        return anim.copyClips(anim.selectedClipIds);
    }

    // Pastes templates onto each valid target top, earliest at baseTime
    // (default: playhead). Later clips win per property like presets.
    // One undo entry; new ids are selected. Returns made clip ids.
    function pasteClips(templates, targetUids, baseTime) {
        var tmpl = templates || [];
        if (tmpl.length === 0)
            return [];
        var valid = [];
        var asked = targetUids || [];
        for (var i = 0; i < asked.length; i++) {
            if (doc.findNode(asked[i]))
                valid.push(asked[i]);
        }
        if (valid.length === 0)
            return [];
        var comp = Math.max(0.5, anim.duration);
        var base = baseTime !== undefined ? Number(baseTime) : anim.currentTime;
        if (isNaN(base))
            base = anim.currentTime;
        base = Math.min(Math.max(0, base), Math.max(0, comp - 0.1));
        var ordered = tmpl.slice().sort((a, b) => (Number(a.dt) || 0) - (Number(b.dt) || 0));
        doc.history.checkpoint();
        var out = anim.clips.slice();
        var made = [];
        for (var t = 0; t < valid.length; t++) {
            for (var m = 0; m < ordered.length; m++) {
                var s = ordered[m] || {};
                if (anim.presets.presetIds().indexOf(s.preset) < 0)
                    continue;
                var nt0 = Math.min((Number(s.dt) || 0) + base, Math.max(0, comp - 0.1));
                var ez = s.easing || {};
                var clip = anim.presets.buildClip(s.preset, anim.nextClipId++, valid[t], nt0, s.duration, s.mode, copyMap(s.options), {
                    id: ez.id,
                    bezier: ez.bezier ? ez.bezier.slice() : ez.bezier
                }, s.loop);
                if (!doc.findNode(clip.targetUid))
                    continue;
                out.push(clip);
                made.push(clip.id);
            }
        }
        anim.clips = out;
        anim.selectedClipIds = made.slice();
        doc.touch();
        return made;
    }

    function setDuration(v) {
        var nd = Math.min(60, Math.max(0.5, Number(v)));
        if (isNaN(nd) || nd === anim.duration)
            return false;
        doc.history.checkpoint();
        anim.duration = nd;
        if (anim.currentTime > nd)
            anim.currentTime = nd;
        // Shrinking the composition pulls overhanging clips back inside
        // in the same undo entry, so keyframes never stage past the end.
        anim.clips = anim.fitClipsTo(nd, anim.clips);
        doc.touch();
        return true;
    }

    // Clamps every clip into [0, comp]: start slides back, duration
    // shrinks, floor 0.1s. Pure (returns a new array), so callers pick
    // their own checkpointing.
    function fitClipsTo(comp, clips) {
        var out = [];
        for (var i = 0; i < clips.length; i++) {
            var c = clips[i];
            var nt0 = Math.min(c.t0, Math.max(0, comp - 0.1));
            var nd = Math.min(c.duration, Math.max(0.1, comp - nt0));
            if (nt0 === c.t0 && nd === c.duration) {
                out.push(c);
                continue;
            }
            out.push(anim.presets.buildClip(c.preset, c.id, c.targetUid, nt0, nd, c.mode, c.options, c.easing, c.loop));
        }
        return out;
    }

    function selectClip(id, additive) {
        if (additive) {
            if (!anim.isClipSelected(id))
                anim.selectedClipIds = anim.selectedClipIds.concat([id]);
        } else {
            anim.selectedClipIds = anim.clipById(id) ? [id] : [];
        }
    }

    function clearClipSelection() {
        anim.selectedClipIds = [];
    }

    function deselectClip(id) {
        if (anim.isClipSelected(id))
            anim.selectedClipIds = anim.selectedClipIds.filter(kept => kept !== id);
    }

    // Drops clips whose target node is gone (delete/ungroup). Silent:
    // callers already checkpointed for the structural op.
    function pruneTargets() {
        var kept = [];
        for (var i = 0; i < anim.clips.length; i++) {
            if (doc.findNode(anim.clips[i].targetUid))
                kept.push(anim.clips[i]);
        }
        if (kept.length !== anim.clips.length) {
            anim.clips = kept;
            var alive = {};
            for (var j = 0; j < kept.length; j++)
                alive[kept[j].id] = true;
            anim.selectedClipIds = anim.selectedClipIds.filter(id => alive[id]);
        }
    }

    function sampleAt(t) {
        return anim.sampler.sampleAnim(doc, t, anim.playBase);
    }

    function applySample(map) {
        anim.sampler.applySample(doc, map);
    }

    // Transport pass-throughs (state + clockwork live in DocTransport).
    function play() {
        transportState.play();
    }
    function pause() {
        transportState.pause();
    }
    function stop() {
        transportState.stop();
    }
    function tick() {
        transportState.tick();
    }
    function seek(t) {
        transportState.seek(t);
    }
    function settlePreview() {
        transportState.settlePreview();
    }

    // Plain-data snapshot for saves and undo. Clips deep-copy: lane
    // drags mutate live clips in place, which must never rewrite a
    // stored before-image.
    function snapshotData() {
        var out = [];
        for (var i = 0; i < anim.clips.length; i++) {
            var c = anim.clips[i];
            var ez = c.easing || {};
            out.push({
                id: c.id,
                targetUid: c.targetUid,
                preset: c.preset,
                t0: c.t0,
                duration: c.duration,
                mode: c.mode,
                loop: anim.presets.normalizeLoop(c.loop),
                options: copyMap(c.options),
                easing: {
                    id: ez.id,
                    bezier: ez.bezier ? ez.bezier.slice() : ez.bezier
                }
            });
        }
        return {
            version: 2,
            duration: anim.duration,
            nextClipId: anim.nextClipId,
            clips: out
        };
    }

    function copyMap(m) {
        var o = {};
        var s = m || {};
        for (var k in s) {
            if (k === "pts" && Array.isArray(s[k])) {
                var pts = [];
                for (var i = 0; i < s[k].length; i++) {
                    var p = s[k][i] || {};
                    pts.push({
                        x: p.x,
                        y: p.y,
                        smooth: p.smooth === true,
                        inX: p.inX,
                        inY: p.inY,
                        outX: p.outX,
                        outY: p.outY
                    });
                }
                o[k] = pts;
            } else {
                o[k] = s[k];
            }
        }
        return o;
    }

    function restoreData(d) {
        var s = d || {};
        transportState.reset();
        anim.selectedClipIds = [];
        var dur = s.duration > 0 ? Math.min(60, s.duration) : 4.0;
        anim.duration = dur;
        // Silent migration: clips staged under older rules pull inside.
        anim.clips = anim.fitClipsTo(dur, s.clips || []);
        var top = 1;
        for (var i = 0; i < anim.clips.length; i++) {
            if (typeof anim.clips[i].id === "number" && anim.clips[i].id >= top)
                top = anim.clips[i].id + 1;
        }
        anim.nextClipId = Math.max(top, s.nextClipId > 0 ? s.nextClipId : 1);
    }
}
