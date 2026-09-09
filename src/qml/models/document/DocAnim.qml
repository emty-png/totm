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

    property bool playing: false
    property real currentTime: 0
    property var selectedClipIds: []
    // Clip-data revision, bumped by silent in-place nudges (lane drags)
    // that deliberately skip touch(). Panels read this so values follow
    // live; lane delegates never bind it, so no model rebuilds mid-drag.
    property int clipRev: 0
    // Pre-play values keyed by node uid. Non-null while a preview frame
    // is on screen (playing or paused): writes stay silent, saves and
    // undo read through this instead of the live frame.
    property var playBase: null
    property double lastTick: 0

    property var presets: DocAnimPresets {
        doc: anim.doc
    }
    property var sampler: AnimSample {}

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
    // duration unless given. Returns applied clip ids.
    function applyPreset(presetId, targetUids, t0, duration, mode, options, easing) {
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
        doc.history.checkpoint();
        var made = [];
        var list = anim.clips.slice();
        for (var j = 0; j < valid.length; j++) {
            var clip = anim.presets.buildClip(presetId, anim.nextClipId++, valid[j], t0, duration, mode, options, easing);
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
        var fixed = anim.presets.buildClip(old.preset, old.id, old.targetUid, old.t0, old.duration, old.mode, merged, old.easing);
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
        var fixed = anim.presets.buildClip(old.preset, old.id, old.targetUid, nt0, nd, old.mode, old.options, old.easing);
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
        var fixed = anim.presets.buildClip(old.preset, old.id, old.targetUid, old.t0, old.duration, old.mode, old.options, easing);
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
        var fixed = anim.presets.buildClip(old.preset, old.id, old.targetUid, old.t0, old.duration, nm, old.options, old.easing);
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
            out.push(anim.presets.buildClip(c.preset, c.id, c.targetUid, nt0, nd, c.mode, c.options, c.easing));
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

    // Transport. play() captures once (resume keeps the old base);
    // pause() freezes the frame; stop() restores base and marks dirty
    // so the next autosave flush writes base values, never a frame.
    function play() {
        if (anim.playing)
            return;
        if (!anim.playBase)
            anim.playBase = captureBase();
        anim.lastTick = 0;
        anim.playing = true;
    }

    function pause() {
        anim.playing = false;
    }

    function stop() {
        if (!anim.playBase && anim.currentTime === 0) {
            anim.playing = false;
            return;
        }
        anim.playing = false;
        restoreBase();
        anim.currentTime = 0;
        doc.touch();
    }

    // One frame step, driven by the editor's 16ms timer. Wall-clock dt
    // clamped so tab-switch stalls never jump the playhead.
    function tick() {
        if (!anim.playing)
            return;
        var now = Date.now();
        var dt = anim.lastTick > 0 ? (now - anim.lastTick) / 1000 : 0.016;
        anim.lastTick = now;
        dt = Math.min(0.1, Math.max(0, dt));
        var d = Math.max(0.5, anim.duration);
        var t = anim.currentTime + dt;
        if (t >= d)
            t = t % d;
        anim.currentTime = t;
        anim.sampler.applySample(doc, anim.sampler.sampleAnim(doc, t, anim.playBase));
    }

    // Jump the playhead (ruler click/drag). Captures base on first use
    // so seeking previews without a transport press; silent like ticks.
    function seek(t) {
        var d = Math.max(0.5, anim.duration);
        var nt = Math.min(d, Math.max(0, Number(t) || 0));
        if (!anim.playBase)
            anim.playBase = captureBase();
        anim.currentTime = nt;
        anim.sampler.applySample(doc, anim.sampler.sampleAnim(doc, nt, anim.playBase));
    }

    // Ends a preview from an edit path (history settles before every
    // mutation): base returns silently, playhead stays for context.
    function settlePreview() {
        if (!anim.playBase)
            return;
        anim.playing = false;
        restoreBase();
    }

    function captureBase() {
        var out = {};
        var leaves = doc.tree.allLeaves();
        for (var i = 0; i < leaves.length; i++) {
            var n = leaves[i];
            var entry = {
                x: n.x,
                y: n.y,
                w: n.w,
                h: n.h,
                rotation: n.rotation,
                opacity: n.opacity,
                fontSize: n.fontSize,
                shapeType: n.shapeType,
                fill: String(n.fill),
                visible: n.visible,
                radius: n.radius,
                strokeWidth: n.strokeWidth,
                independentCorners: n.independentCorners
            };
            if (n.shapeType === "pen")
                entry.pathData = doc.factory._copyPath(n.pathData);
            if (n.independentCorners)
                entry.cornerRadii = (n.cornerRadii || []).slice();
            out[n.uid] = entry;
        }
        return out;
    }

    function restoreBase() {
        var base = anim.playBase;
        anim.playBase = null;
        anim.lastTick = 0;
        if (!base)
            return;
        for (var uid in base) {
            var n = doc.findNode(Number(uid));
            if (!n || n.kind !== "shape")
                continue;
            var b = base[uid];
            n.x = b.x;
            n.y = b.y;
            n.w = b.w;
            n.h = b.h;
            n.rotation = b.rotation;
            n.opacity = b.opacity;
            if (b.fill !== undefined)
                n.fill = b.fill;
            if (b.visible !== undefined)
                n.visible = b.visible;
            if (b.radius !== undefined)
                n.radius = b.radius;
            if (b.strokeWidth !== undefined)
                n.strokeWidth = b.strokeWidth;
            if (b.fontSize !== undefined && n.shapeType === "text")
                n.fontSize = b.fontSize;
            if (b.pathData !== undefined && n.shapeType === "pen")
                n.pathData = doc.factory._copyPath(b.pathData);
            if (b.cornerRadii !== undefined && n.independentCorners)
                n.cornerRadii = b.cornerRadii.slice();
        }
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
        anim.playing = false;
        anim.playBase = null;
        anim.lastTick = 0;
        anim.currentTime = 0;
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
