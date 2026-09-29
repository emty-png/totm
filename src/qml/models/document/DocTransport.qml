import QtQuick

// Playback transport for one Document's animation: play state, playhead
// and the pre-play snapshot. Frames derive from playBase (never the
// live tree) and write silently, so playback never dirties the doc,
// never triggers autosave, never pollutes undo. Owned by DocAnim,
// which keeps aliases + pass-throughs so callers never change.
QtObject {
    id: transport
    required property var doc

    property bool playing: false
    property real currentTime: 0
    // Pre-play values keyed by node uid. Non-null while a preview frame
    // is on screen (playing or paused): writes stay silent, saves and
    // undo read through this instead of the live frame.
    property var playBase: null
    property double lastTick: 0

    // play() captures once (resume keeps the old base); pause() freezes
    // the frame; stop() restores base and marks dirty so the next
    // autosave flush writes base values, never a frame.
    function play() {
        if (transport.playing)
            return;
        if (!transport.playBase)
            transport.playBase = captureBase();
        transport.lastTick = 0;
        transport.playing = true;
    }

    function pause() {
        transport.playing = false;
    }

    function stop() {
        if (!transport.playBase && transport.currentTime === 0) {
            transport.playing = false;
            return;
        }
        transport.playing = false;
        restoreBase();
        transport.currentTime = 0;
        transport.doc.touch();
    }

    // One frame step, driven by the editor's 16ms timer. Wall-clock dt
    // clamped so tab-switch stalls never jump the playhead. Loop wraps
    // restore authored values first (see seek): without it the new
    // loop inherits the old loop's frame (notably a stale hidden flag
    // that gates every other clip off).
    function tick() {
        if (!transport.playing)
            return;
        var now = Date.now();
        var dt = transport.lastTick > 0 ? (now - transport.lastTick) / 1000 : 0.016;
        transport.lastTick = now;
        dt = Math.min(0.1, Math.max(0, dt));
        var anim = transport.doc.anim;
        var d = Math.max(0.5, anim.duration);
        var t = transport.currentTime + dt;
        var wrapped = false;
        if (t >= d) {
            t = t % d;
            wrapped = true;
        }
        transport.currentTime = t;
        if (wrapped)
            transport.restoreBaseValues();
        anim.sampler.applySample(transport.doc, anim.sampler.sampleAnim(transport.doc, t, transport.playBase));
    }

    // Jump the playhead (ruler click/drag). Captures base on first use
    // so seeking previews without a transport press; silent like ticks.
    // Backward jumps restore authored values first: samples only carry
    // active clips, so a seek before a clip's start would otherwise
    // leave that clip's stale frame behind — and a stale hidden flag
    // gates every other clip off, freezing the shape. The restore makes
    // the new frame absolute, like export.
    function seek(t) {
        var anim = transport.doc.anim;
        var d = Math.max(0.5, anim.duration);
        var nt = Math.min(d, Math.max(0, Number(t) || 0));
        var hadBase = !!transport.playBase;
        if (!transport.playBase)
            transport.playBase = captureBase();
        if (hadBase && nt < transport.currentTime)
            transport.restoreBaseValues();
        transport.currentTime = nt;
        anim.sampler.applySample(transport.doc, anim.sampler.sampleAnim(transport.doc, nt, transport.playBase));
    }

    // Ends a preview from an edit path (history settles before every
    // mutation): base returns silently, playhead stays for context.
    function settlePreview() {
        if (!transport.playBase)
            return;
        transport.playing = false;
        restoreBase();
    }

    // Full reset for loads: transport parks, playhead returns to zero.
    function reset() {
        transport.playing = false;
        transport.playBase = null;
        transport.lastTick = 0;
        transport.currentTime = 0;
    }

    function captureBase() {
        var doc = transport.doc;
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
                fontWeight: n.fontWeight,
                shapeType: n.shapeType,
                textContent: n.textContent,
                fills: doc.factory._copyFills(n.fills, n),
                strokes: doc.factory._copyStrokes(n.strokes, n),
                flipH: n.flipH === true,
                flipV: n.flipV === true,
                shadows: doc.factory._copyShadows(n.shadows),
                glows: doc.factory._copyGlows(n.glows),
                layerBlur: doc.factory._copyBlur(n.layerBlur, 8, 1),
                backgroundBlur: doc.factory._copyBlur(n.backgroundBlur, 16, 0.7),
                grain: doc.factory._copyGrain(n.grain),
                visible: n.visible,
                radius: n.radius,
                penFill: n.penFill !== false,
                strokeCap: n.strokeCap ?? "round",
                strokeJoin: n.strokeJoin ?? "round",
                independentCorners: n.independentCorners,
                isMask: n.isMask === true,
                maskMode: n.maskMode === "luminance" ? "luminance" : "alpha",
                maskFeather: Math.max(0, Number(n.maskFeather) || 0),
                maskInverted: n.maskInverted === true
            };
            if (n.shapeType === "pen")
                entry.pathData = doc.factory._copyPath(n.pathData);
            if (n.independentCorners)
                entry.cornerRadii = (n.cornerRadii || []).slice();
            out[n.uid] = entry;
        }
        // Group style bases for group-targeted style clips: stacks plus
        // opacity/visibility only (geometry and text stay leaf-owned).
        var groups = doc.tree._allNodes();
        for (var gi = 0; gi < groups.length; gi++) {
            var g = groups[gi];
            if (!g || g.kind !== "group")
                continue;
            out[g.uid] = {
                kind: "group",
                boolOp: g.boolOp ?? "none",
                opacity: g.opacity ?? 1,
                fills: doc.factory._copyFills(g.fills, g),
                strokes: doc.factory._copyStrokes(g.strokes, g),
                penFill: g.penFill !== false,
                strokeCap: g.strokeCap ?? "round",
                strokeJoin: g.strokeJoin ?? "round",
                shadows: doc.factory._copyShadows(g.shadows),
                glows: doc.factory._copyGlows(g.glows),
                layerBlur: doc.factory._copyBlur(g.layerBlur, 8, 1),
                backgroundBlur: doc.factory._copyBlur(g.backgroundBlur, 16, 0.7),
                grain: doc.factory._copyGrain(g.grain),
                visible: g.visible
            };
        }
        return out;
    }

    function restoreBase() {
        transport.restoreBaseValues();
        transport.playBase = null;
        transport.lastTick = 0;
    }

    // Silent authored-value restore that keeps the preview open
    // (playBase stays): tick wraps and backward seeks call this so the
    // next sample applies onto clean values instead of the old frame.
    function restoreBaseValues() {
        var doc = transport.doc;
        var base = transport.playBase;
        if (!base)
            return;
        for (var uid in base) {
            var n = doc.findNode(Number(uid));
            if (!n)
                continue;
            var b = base[uid];
            if (n.kind === "group") {
                // Group style restore only (geometry/text stay leaf-owned).
                if (b.opacity !== undefined)
                    n.opacity = b.opacity;
                if (b.fills !== undefined)
                    n.fills = doc.factory._copyFills(b.fills, b);
                if (b.strokes !== undefined)
                    n.strokes = doc.factory._copyStrokes(b.strokes, b);
                if (b.shadows !== undefined)
                    n.shadows = doc.factory._copyShadows(b.shadows);
                if (b.glows !== undefined)
                    n.glows = doc.factory._copyGlows(b.glows);
                if (b.layerBlur !== undefined)
                    n.layerBlur = doc.factory._copyBlur(b.layerBlur, 8, 1);
                if (b.backgroundBlur !== undefined)
                    n.backgroundBlur = doc.factory._copyBlur(b.backgroundBlur, 16, 0.7);
                if (b.grain !== undefined)
                    n.grain = doc.factory._copyGrain(b.grain);
                if (b.visible !== undefined)
                    n.visible = b.visible;
                continue;
            }
            if (n.kind !== "shape")
                continue;
            n.x = b.x;
            n.y = b.y;
            n.w = b.w;
            n.h = b.h;
            n.rotation = b.rotation;
            n.opacity = b.opacity;
            if (b.fills !== undefined)
                n.fills = doc.factory._copyFills(b.fills, b);
            else {
                if (b.fill !== undefined)
                    n.fills = doc.factory._copyFills(undefined, b);
            }
            if (b.strokes !== undefined)
                n.strokes = doc.factory._copyStrokes(b.strokes, b);
            else {
                if (b.stroke !== undefined)
                    n.strokes = doc.factory._copyStrokes(undefined, b);
            }
            if (b.flipH !== undefined)
                n.flipH = b.flipH === true;
            if (b.flipV !== undefined)
                n.flipV = b.flipV === true;
            if (b.shadows !== undefined)
                n.shadows = doc.factory._copyShadows(b.shadows);
            if (b.glows !== undefined)
                n.glows = doc.factory._copyGlows(b.glows);
            if (b.layerBlur !== undefined)
                n.layerBlur = doc.factory._copyBlur(b.layerBlur, 8, 1);
            if (b.backgroundBlur !== undefined)
                n.backgroundBlur = doc.factory._copyBlur(b.backgroundBlur, 16, 0.7);
            if (b.grain !== undefined)
                n.grain = doc.factory._copyGrain(b.grain);
            if (b.visible !== undefined)
                n.visible = b.visible;
            if (b.radius !== undefined)
                n.radius = b.radius;
            if (b.penFill !== undefined)
                n.penFill = b.penFill !== false;
            if (b.strokeCap !== undefined)
                n.strokeCap = b.strokeCap ?? "round";
            if (b.strokeJoin !== undefined)
                n.strokeJoin = b.strokeJoin ?? "round";
            if (b.fontSize !== undefined && n.shapeType === "text")
                n.fontSize = b.fontSize;
            if (b.fontWeight !== undefined && n.shapeType === "text")
                n.fontWeight = b.fontWeight;
            if (b.textContent !== undefined && n.shapeType === "text")
                n.textContent = b.textContent;
            if (b.pathData !== undefined && n.shapeType === "pen")
                n.pathData = doc.factory._copyPath(b.pathData);
            if (b.cornerRadii !== undefined && n.independentCorners)
                n.cornerRadii = b.cornerRadii.slice();
            if (b.maskFeather !== undefined)
                n.maskFeather = Math.max(0, Number(b.maskFeather) || 0);
            if (b.maskInverted !== undefined)
                n.maskInverted = b.maskInverted === true;
        }
    }
}
