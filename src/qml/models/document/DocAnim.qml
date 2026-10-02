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

    // Auto-key arm: while true, selection edits (canvas moves/scales,
    // panel commits, rotate) capture keys at the playhead on
    // keyframeable clips covering the selection. Toggled from the
    // timeline transport; session-only like selection.
    property bool recordArmed: false

    function toggleRecord() {
        anim.recordArmed = !anim.recordArmed;
    }

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
    property var customDefaults: DocCustomDefaults {}
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
    function applyPreset(presetId, targetUids, t0, duration, mode, options, easing, stagger) {
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
            var clip = anim.presets.buildClip(presetId, anim.nextClipId++, valid[j], nt0, duration, mode, options, easing);
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

    // Converts a clip to another preset, reseeding options from the live
    // target so the new clip starts jump-free. Timing, mode and easing
    // carry over; one undo entry. Used by the style editor to
    // auto-swap solid color clips whose target top entry is linear.
    function convertClipPreset(id, newPreset) {
        var at = -1;
        for (var i = 0; i < anim.clips.length; i++) {
            if (anim.clips[i].id === id) {
                at = i;
                break;
            }
        }
        if (at < 0 || anim.presets.presetIds().indexOf(newPreset) < 0)
            return false;
        var old = anim.clips[at];
        if (old.preset === newPreset)
            return false;
        var node = doc.findNode(old.targetUid);
        var tops = node ? [node] : [];
        var opts = anim.customDefaults.seededOptions(anim.presets, doc, tops, newPreset);
        var fixed = anim.presets.buildClip(newPreset, old.id, old.targetUid, old.t0, old.duration, old.mode, opts, old.easing);
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
        var nd = Math.min(1800, Math.max(0.1, Number(duration)));
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
        var nd = Math.min(1800, Math.max(0.1, Number(duration)));
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

    // Silent in-place key retime for timeline key drags: no
    // checkpoint, no touch, so delegates survive the gesture while
    // ticks follow live. The press-time begin() holds the undo image;
    // release touches once and ends for a single entry. t is
    // clip-local 0..1, clamped between neighbors so order never
    // flips. Mirrors nudgeClip.
    function nudgeKey(id, keyIndex, t) {
        var at = -1;
        for (var i = 0; i < anim.clips.length; i++) {
            if (anim.clips[i].id === id)
                at = i;
        }
        if (at < 0)
            return false;
        var c = anim.clips[at];
        var keys = c.options ? c.options.keys : null;
        if (!keys || typeof keys.length !== "number" || keyIndex < 0 || keyIndex >= keys.length)
            return false;
        var nt = Math.min(1, Math.max(0, Number(t)));
        if (isNaN(nt))
            return false;
        var lo = keyIndex > 0 ? Number(keys[keyIndex - 1].t) : 0;
        var hi = keyIndex < keys.length - 1 ? Number(keys[keyIndex + 1].t) : 1;
        nt = Math.min(hi, Math.max(lo, nt));
        nt = Math.round(nt * 1000) / 1000;
        if (keys[keyIndex].t === nt)
            return false;
        keys[keyIndex].t = nt;
        anim.clipRev++;
        return true;
    }

    // Silent in-place key easing write for curve-strip drags: no
    // checkpoint, no touch, mirroring nudgeKey. The press-time begin()
    // holds the undo image; release touches once and ends for a single
    // entry. Always stores id "custom" with the dragged handles.
    function nudgeKeyBezier(id, keyIndex, bezier) {
        var at = -1;
        for (var i = 0; i < anim.clips.length; i++) {
            if (anim.clips[i].id === id)
                at = i;
        }
        if (at < 0)
            return false;
        var c = anim.clips[at];
        var keys = c.options ? c.options.keys : null;
        if (!keys || typeof keys.length !== "number" || keyIndex < 0 || keyIndex >= keys.length)
            return false;
        var b = bezier || [];
        keys[keyIndex].easing = {
            id: "custom",
            bezier: [Number(b[0]) || 0, Number(b[1]) || 0, Number(b[2]) || 0, Number(b[3]) || 0]
        };
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
            var copy = anim.presets.buildClip(s.preset, anim.nextClipId++, s.targetUid, nt0, s.duration, s.mode, copyMap(s.options), s.easing);
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
                });
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
        var nd = Math.min(1800, Math.max(0.5, Number(v)));
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

    function round2(v) {
        return Math.round(Number(v) * 100) / 100;
    }

    function stackEntry(list, idx) {
        var arr = list || [];
        var i = Math.min(32, Math.max(0, Math.round(Number(idx) || 0)));
        return i < arr.length ? (arr[i] ?? {}) : {};
    }

    function baseFor(leaf) {
        if (!leaf)
            return null;
        var pb = anim.playBase;
        if (pb && pb[leaf.uid])
            return pb[leaf.uid];
        return leaf;
    }

    // First shape leaf under the clip target (groups animate per leaf;
    // keys capture the first leaf so group clips still record), except
    // group style clips, which capture the group's own stacks.
    function captureLeafFor(c) {
        if (!c)
            return null;
        var n = anim.doc.findNode(c.targetUid);
        if (!n)
            return null;
        if (n.kind === "shape")
            return n;
        if (anim.customDefaults.isGroupStylePreset(c.preset))
            return n;
        var leaves = anim.doc._leavesUnder(n);
        return leaves.length > 0 ? leaves[0] : null;
    }

    // Captures the live look at the playhead (sampled frame while
    // previewing, base otherwise) as a canonical key value for one
    // keyframeable preset. Shared by manual + auto keying so both
    // record identical values.
    function captureKeyValue(preset, leaf, opts) {
        var base = anim.baseFor(leaf);
        if (!base)
            return null;
        if (preset === "maskWipe" || preset === "maskIris") {
            return {
                x: anim.round2(leaf.x),
                y: anim.round2(leaf.y),
                w: Math.max(0.01, anim.round2(leaf.w)),
                h: Math.max(0.01, anim.round2(leaf.h)),
                rotation: anim.round2(leaf.rotation),
                opacity: Math.min(1, Math.max(0, Number(leaf.opacity))),
                feather: Math.max(0, Number(leaf.maskFeather) || 0),
                invert: leaf.maskInverted === true
            };
        }
        if (preset === "fade") {
            var bop = Number(base.opacity);
            var lop = Number(leaf.opacity);
            return {
                v: Math.min(1, Math.max(0, anim.round2(bop > 0.001 ? lop / bop : lop)))
            };
        }
        if (preset === "slide") {
            var sv = {
                dx: anim.round2((Number(leaf.x) || 0) - (Number(base.x) || 0)),
                dy: anim.round2((Number(leaf.y) || 0) - (Number(base.y) || 0))
            };
            if (opts.fade !== false) {
                var sbop = Number(base.opacity);
                var slop = Number(leaf.opacity);
                sv.v = Math.min(1, Math.max(0, anim.round2(sbop > 0.001 ? slop / sbop : slop)));
            }
            return sv;
        }
        if (preset === "grow" || preset === "shrink") {
            var gbw = Number(base.w) || 0, glw = Number(leaf.w) || 0;
            var gbh = Number(base.h) || 0, glh = Number(leaf.h) || 0;
            var gs = gbw > 0.001 ? glw / gbw : (gbh > 0.001 ? glh / gbh : 1);
            return {
                s: Math.min(100, Math.max(0.001, anim.round2(gs)))
            };
        }
        if (preset === "spin") {
            return {
                r: anim.round2((Number(leaf.rotation) || 0) - (Number(base.rotation) || 0))
            };
        }
        if (preset === "movescale") {
            var mbw = Number(base.w) || 0, mlw = Number(leaf.w) || 0;
            var mbh = Number(base.h) || 0, mlh = Number(leaf.h) || 0;
            var ms = mbw > 0.001 ? mlw / mbw : (mbh > 0.001 ? mlh / mbh : 1);
            return {
                dx: anim.round2((Number(leaf.x) || 0) - (Number(base.x) || 0)),
                dy: anim.round2((Number(leaf.y) || 0) - (Number(base.y) || 0)),
                s: Math.min(100, Math.max(0.001, anim.round2(ms)))
            };
        }
        if (preset === "type") {
            // Karaoke/sweep clips keep the full text and carry progress in
            // textFx.fxReveal: capture that directly so keyframes hold the
            // reveal fraction instead of a saturated substring ratio.
            if (leaf.textFx && leaf.textFx.fx === true) {
                return {
                    frac: Math.min(1, Math.max(0, anim.round2(Number(leaf.textFx.fxReveal) || 0)))
                };
            }
            var full = String(base.textContent !== undefined ? base.textContent : "");
            var norm = full.split("\r\n").join("\n").split("\r").join("\n");
            var live = String(leaf.textContent !== undefined ? leaf.textContent : "");
            if ((opts.cursor === true) && live.charAt(live.length - 1) === "|")
                live = live.substring(0, live.length - 1);
            var unit = opts.unit === "words" ? "words" : opts.unit === "lines" ? "lines" : "letters";
            var sep = unit === "words" ? " " : "\n";
            // Words split on U+0020 keeping empties (Qt KeepEmptyParts in
            // C++), lines on LF, so preview and export reveal the same
            // chunks even with double/multiple spaces.
            var total = unit === "letters" ? norm.length : norm.split(sep).length;
            if (total <= 0)
                return {
                    frac: 0
                };
            var shown = unit === "letters" ? live.split("\r\n").join("\n").split("\r").join("\n").length : (live === "" ? 0 : live.split(sep).length);
            return {
                frac: Math.min(1, Math.max(0, anim.round2(shown / total)))
            };
        }
        if (preset === "customHide") {
            return {
                v: leaf.visible !== false
            };
        }
        if (preset === "customFlip") {
            var axis = (opts.axis || "h") === "v" ? "flipV" : "flipH";
            return {
                v: leaf[axis] === true,
                axis: (opts.axis || "h") === "v" ? "v" : "h"
            };
        }
        if (preset === "customMove") {
            return {
                dx: anim.round2((Number(leaf.x) || 0) - (Number(base.x) || 0)),
                dy: anim.round2((Number(leaf.y) || 0) - (Number(base.y) || 0))
            };
        }
        if (preset === "customScale") {
            var bw = Number(base.w) || 0, lw = Number(leaf.w) || 0;
            var bh = Number(base.h) || 0, lh = Number(leaf.h) || 0;
            var s = bw > 0.001 ? lw / bw : (bh > 0.001 ? lh / bh : 1);
            return {
                s: Math.min(100, Math.max(0.001, anim.round2(s)))
            };
        }
        if (preset === "customRotate") {
            return {
                r: anim.round2((Number(leaf.rotation) || 0) - (Number(base.rotation) || 0))
            };
        }
        if (preset === "customOpacity") {
            return {
                v: Math.min(1, Math.max(0, Number(leaf.opacity)))
            };
        }
        if (preset === "customResize") {
            return {
                w: Math.max(1, Math.round(Number(leaf.w) || 1)),
                h: Math.max(1, Math.round(Number(leaf.h) || 1))
            };
        }
        if (preset === "customCorner") {
            return {
                v: Math.max(0, anim.round2(leaf.radius))
            };
        }
        if (preset === "customFontSize") {
            return {
                v: Math.min(500, Math.max(1, Math.round(Number(leaf.fontSize) || 16)))
            };
        }
        if (preset === "customFontWeight") {
            return {
                v: Math.min(1000, Math.max(1, Math.round(Number(leaf.fontWeight) || 400)))
            };
        }
        if (preset === "customColor") {
            var fi = Number(opts.fillIndex) || 0;
            var fe = anim.stackEntry(leaf.fills, fi);
            return {
                color: String(fe.color ?? "#000000"),
                opacity: Math.min(1, Math.max(0, Number(fe.opacity ?? 1)))
            };
        }
        if (preset === "customGradient") {
            var gi = Number(opts.fillIndex) || 0;
            var ge = anim.stackEntry(leaf.fills, gi);
            var gg = ge.gradient ?? {};
            var stops = gg.stops ?? [];
            return {
                c1: String((stops[0] ?? {}).color ?? "#000000"),
                c2: String((stops[1] ?? {}).color ?? "#ffffff"),
                angle: anim.round2(gg.angle ?? 90),
                opacity: Math.min(1, Math.max(0, Number(ge.opacity ?? 1)))
            };
        }
        if (preset === "customStroke") {
            var si = Number(opts.strokeIndex) || 0;
            var se = anim.stackEntry(leaf.strokes, si);
            var dash = (se.dash && typeof se.dash.length === "number") ? se.dash : [];
            return {
                width: Math.max(0, anim.round2(se.width ?? 0)),
                opacity: Math.min(1, Math.max(0, Number(se.opacity ?? 1))),
                dash: Math.max(0, anim.round2(dash.length > 0 ? dash[0] : 0)),
                gap: Math.max(0, anim.round2(dash.length > 1 ? dash[1] : 0)),
                position: (se.position === "inside" || se.position === "outside") ? se.position : "center"
            };
        }
        if (preset === "customStrokeColor") {
            var sci = Number(opts.strokeIndex) || 0;
            var sce = anim.stackEntry(leaf.strokes, sci);
            return {
                color: String(sce.color ?? "#000000"),
                opacity: Math.min(1, Math.max(0, Number(sce.opacity ?? 1)))
            };
        }
        if (preset === "customStrokeGradient") {
            var sgi = Number(opts.strokeIndex) || 0;
            var sge = anim.stackEntry(leaf.strokes, sgi);
            var sgg = sge.gradient ?? {};
            var sstops = sgg.stops ?? [];
            var sdash = (sge.dash && typeof sge.dash.length === "number") ? sge.dash : [];
            return {
                c1: String((sstops[0] ?? {}).color ?? "#000000"),
                c2: String((sstops[1] ?? {}).color ?? "#ffffff"),
                angle: anim.round2(sgg.angle ?? 90),
                opacity: Math.min(1, Math.max(0, Number(sge.opacity ?? 1))),
                width: Math.max(0, anim.round2(sge.width ?? 0)),
                dash: Math.max(0, anim.round2(sdash.length > 0 ? sdash[0] : 0)),
                gap: Math.max(0, anim.round2(sdash.length > 1 ? sdash[1] : 0)),
                position: (sge.position === "inside" || sge.position === "outside") ? sge.position : "center"
            };
        }
        if (preset === "customShadow") {
            var shi = Number(opts.shadowIndex) || 0;
            var she = anim.stackEntry(leaf.shadows, shi);
            return {
                color: String(she.color ?? "#80000000"),
                x: anim.round2(she.x ?? 0),
                y: anim.round2(she.y ?? 4),
                blur: Math.max(0, anim.round2(she.blur ?? 8)),
                spread: Math.max(0, anim.round2(she.spread ?? 0)),
                inner: she.inner === true
            };
        }
        if (preset === "customGlow") {
            var gli = Number(opts.glowIndex) || 0;
            var gle = anim.stackEntry(leaf.glows, gli);
            return {
                color: String(gle.color ?? "#cc00ffff"),
                blur: Math.max(0, anim.round2(gle.blur ?? 16)),
                spread: Math.max(0, anim.round2(gle.spread ?? 4)),
                inner: gle.inner === true
            };
        }
        if (preset === "customLayerBlur" || preset === "customBackgroundBlur") {
            var b = preset === "customLayerBlur" ? (leaf.layerBlur ?? {}) : (leaf.backgroundBlur ?? {});
            return {
                radius: Math.max(0, anim.round2(b.radius ?? 0)),
                opacity: Math.min(1, Math.max(0, Number(b.opacity ?? (preset === "customLayerBlur" ? 1 : 0.7))))
            };
        }
        if (preset === "customGrain") {
            var gn = leaf.grain ?? {};
            return {
                amount: Math.min(1, Math.max(0, Number(gn.amount ?? 0))),
                size: Math.min(10, Math.max(1, anim.round2(gn.size ?? 2)))
            };
        }
        if (preset === "customVideoTime") {
            if (!leaf || leaf.shapeType !== "video")
                return null;
            var vt = anim.customDefaults.footageNowAt(anim.doc, leaf, anim.currentTime);
            return {
                v: Math.min(3600, Math.max(0, anim.round2(vt)))
            };
        }
        return null;
    }

    // Manual key at the playhead: captures the live look, replaces any
    // key within 1% of the same t, commits once (undoable). Custom
    // bezier rides along untouched.
    function addKeyAtPlayhead(clipId) {
        var c = anim.clipById(clipId);
        if (!c || !anim.presets.isKeyframeable(c.preset))
            return false;
        var leaf = anim.captureLeafFor(c);
        if (!leaf)
            return false;
        var t = (anim.currentTime - c.t0) / Math.max(0.001, c.duration);
        t = Math.round(Math.min(1, Math.max(0, t)) * 1000) / 1000;
        var v = anim.captureKeyValue(c.preset, leaf, c.options || {});
        if (!v)
            return false;
        var kept = [];
        var cur = (c.options && c.options.keys) || [];
        var replacedEasing = null;
        for (var i = 0; i < cur.length; i++) {
            if (Math.abs(Number(cur[i].t) - t) > 0.01) {
                var ke = (cur[i].easing || {});
                kept.push({
                    t: cur[i].t,
                    value: JSON.parse(JSON.stringify(cur[i].value || {})),
                    easing: {
                        id: ke.id || "easeOut",
                        bezier: ke.bezier ? ke.bezier.slice() : ke.bezier
                    }
                });
            } else if (!replacedEasing) {
                var re = (cur[i].easing || {});
                replacedEasing = {
                    id: re.id || "easeOut",
                    bezier: re.bezier ? re.bezier.slice() : re.bezier
                };
            }
        }
        kept.push({
            t: t,
            value: v,
            easing: replacedEasing || {
                id: "easeOut"
            }
        });
        return anim.setClipOptions(clipId, {
            keys: kept
        });
    }

    // Auto-key: captures the selection's live look at the playhead on
    // every keyframeable clip covering it. Silent in-place upserts (no
    // checkpoint, no touch): the outer gesture transaction — or the
    // wrapper's pre-checkpoint for discrete commits — owns the single
    // undo entry. Bumps clipRev so panels follow, touches for preview
    // refresh. Times past a clip hold its end (local t clamps to 1);
    // times before a clip stay silent. No-op unless record is armed.
    function autocapture() {
        if (!anim.recordArmed)
            return false;
        var t = anim.currentTime;
        var sel = {};
        var tops = anim.doc.selectedTops();
        for (var s = 0; s < tops.length; s++) {
            var top = tops[s];
            if (top.kind === "shape") {
                sel[top.uid] = true;
            } else {
                var under = anim.doc._leavesUnder(top);
                for (var u = 0; u < under.length; u++)
                    sel[under[u].uid] = true;
            }
        }
        var done = false;
        for (var i = 0; i < anim.clips.length; i++) {
            var c = anim.clips[i];
            if (!anim.presets.isKeyframeable(c.preset))
                continue;
            if (t < c.t0)
                continue;
            var target = anim.doc.findNode(c.targetUid);
            if (!target)
                continue;
            var tleaves = target.kind === "group" ? anim.doc._leavesUnder(target) : [target];
            var hit = false;
            for (var j = 0; j < tleaves.length; j++) {
                if (sel[tleaves[j].uid]) {
                    hit = true;
                    break;
                }
            }
            if (!hit)
                continue;
            var dur = Math.max(0.001, c.duration);
            var lt = Math.round(Math.min(1, Math.max(0, (t - c.t0) / dur)) * 1000) / 1000;
            var leaf = anim.captureLeafFor(c);
            if (!leaf)
                continue;
            var v = anim.captureKeyValue(c.preset, leaf, c.options || {});
            if (!v)
                continue;
            if (!c.options)
                c.options = {};
            var next = [];
            var raw = (c.options && c.options.keys) || [];
            var carriedEasing = null;
            for (var k = 0; k < raw.length; k++) {
                if (Math.abs(Number(raw[k].t) - lt) > 0.01)
                    next.push(raw[k]);
                else if (!carriedEasing) {
                    var ce = (raw[k].easing || {});
                    carriedEasing = {
                        id: ce.id || "easeOut",
                        bezier: ce.bezier ? ce.bezier.slice() : ce.bezier
                    };
                }
            }
            next.push({
                t: lt,
                value: v,
                easing: carriedEasing || {
                    id: "easeOut"
                }
            });
            var norm = anim.presets.normalizeKeysFor(c.preset, {
                keys: next
            });
            if (norm !== undefined)
                c.options.keys = norm;
            else
                c.options.keys = next;
            anim.clipRev++;
            done = true;
        }
        if (done)
            anim.doc.touch();
        return done;
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
            } else if (k === "keys" && Array.isArray(s[k])) {
                // Mask keyframes: deep-copy so duplicate/paste/undo
                // never alias the source list.
                var keys = [];
                for (var j = 0; j < s[k].length; j++) {
                    var kk = s[k][j] || {};
                    var kv = kk.value || {};
                    var ke = kk.easing || {};
                    keys.push({
                        t: kk.t,
                        value: JSON.parse(JSON.stringify(kv)),
                        easing: {
                            id: ke.id,
                            bezier: ke.bezier ? ke.bezier.slice() : ke.bezier
                        }
                    });
                }
                o[k] = keys;
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
        var dur = s.duration > 0 ? Math.min(1800, s.duration) : 4.0;
        anim.duration = dur;
        // Silent migration: clips staged under older rules pull inside.
        // Stale `loop` fields are dropped eagerly (sampler ignores them;
        // snapshot would strip on next save anyway).
        var fitted = anim.fitClipsTo(dur, s.clips || []);
        for (var fi = 0; fi < fitted.length; fi++) {
            if (fitted[fi] && fitted[fi].loop !== undefined)
                delete fitted[fi].loop;
        }
        anim.clips = fitted;
        var top = 1;
        for (var i = 0; i < anim.clips.length; i++) {
            if (typeof anim.clips[i].id === "number" && anim.clips[i].id >= top)
                top = anim.clips[i].id + 1;
        }
        anim.nextClipId = Math.max(top, s.nextClipId > 0 ? s.nextClipId : 1);
    }
}
