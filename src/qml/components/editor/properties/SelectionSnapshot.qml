import QtQuick

// Snapshot of the current selection for the design panel. Re-collected
// on every document mutation; editors bind to `sel` and helpers.
QtObject {
    id: snapshot

    required property var doc

    readonly property var tops: collectTops()
    readonly property bool hasGroup: checkHasGroup()
    readonly property var selLeaves: collectLeaves()
    readonly property var sel: collectSelected()
    readonly property bool allLocked: checkAllLocked()

    function collectTops() {
        if (!snapshot.doc)
            return [];
        snapshot.doc.rev;
        return snapshot.doc.selectedTops();
    }

    function checkHasGroup() {
        for (var i = 0; i < snapshot.tops.length; i++) {
            if (snapshot.tops[i].kind === "group")
                return true;
        }
        return false;
    }

    function collectLeaves() {
        if (!snapshot.doc)
            return [];
        snapshot.doc.rev;
        var single = snapshot.singleGroupTop();
        if (single)
            return [snapshot.groupProxyEntry(single)];
        var tops = snapshot.doc.selectedTops();
        var out = [];
        for (var i = 0; i < tops.length; i++) {
            var leaves = tops[i].kind === "shape" ? [tops[i]] : snapshot.doc._leavesUnder(tops[i]);
            for (var j = 0; j < leaves.length; j++) {
                var s = leaves[j];
                out.push({
                    uid: s.uid,
                    type: s.shapeType,
                    x: s.x,
                    y: s.y,
                    w: s.w,
                    h: s.h,
                    rotation: s.rotation,
                    fills: snapshot.doc.factory._copyFills(s.fills, s),
                    strokes: snapshot.doc.factory._copyStrokes(s.strokes, s),
                    penFill: s.penFill !== false,
                    strokeCap: s.strokeCap ?? "round",
                    strokeJoin: s.strokeJoin ?? "round",
                    shadows: snapshot.doc.factory._copyShadows(s.shadows),
                    glows: snapshot.doc.factory._copyGlows(s.glows),
                    layerBlur: snapshot.doc.factory._copyBlur(s.layerBlur, 8, 1),
                    backgroundBlur: snapshot.doc.factory._copyBlur(s.backgroundBlur, 16, 0.7),
                    grain: snapshot.doc.factory._copyGrain(s.grain),
                    shaderId: String(s.shaderId ?? ""),
                    shaderMode: (s.shaderMode === "overlay") ? "overlay" : "fill",
                    shaderParams: snapshot.doc.factory._copyShaderParams(s.shaderParams),
                    opacity: s.opacity,
                    radius: s.radius,
                    independentCorners: s.independentCorners === true,
                    cornerRadii: snapshot.doc.factory._copyRadii(s.cornerRadii),
                    points: s.points,
                    flipH: s.flipH,
                    flipV: s.flipV,
                    imageSource: s.imageSource ?? "",
                    imageFit: (s.imageFit === "cover" || s.imageFit === "fit") ? s.imageFit : "fill",
                    videoSource: s.videoSource ?? "",
                    videoDuration: Math.max(0, Number(s.videoDuration) || 0),
                    videoOffset: Math.max(0, Number(s.videoOffset) || 0),
                    videoStart: Math.max(0, Number(s.videoStart) || 0),
                    videoMuted: s.videoMuted === true,
                    videoVolume: Math.min(1, Math.max(0, s.videoVolume !== undefined ? Number(s.videoVolume) : 1)),
                    playbackRate: Math.min(4, Math.max(0.25, Number(s.playbackRate) || 1)),
                    videoLoop: s.videoLoop !== false,
                    videoFit: (s.videoFit === "cover" || s.videoFit === "fill") ? s.videoFit : "fit",
                    textContent: s.textContent,
                    fontFamily: s.fontFamily,
                    fontWeight: s.fontWeight,
                    fontSize: s.fontSize,
                    fontItalic: s.fontItalic === true,
                    fontUnderline: s.fontUnderline === true,
                    fontStrike: s.fontStrike === true,
                    fontCaps: s.fontCaps ?? "none",
                    textRuns: snapshot.doc.factory._copyRuns(s.textRuns),
                    lineHeightAuto: s.lineHeightAuto,
                    lineHeight: s.lineHeight,
                    letterSpacing: s.letterSpacing,
                    hAlign: s.hAlign,
                    vAlign: s.vAlign,
                    autoSize: s.autoSize,
                    locked: snapshot.doc.isEffectivelyLocked(s)
                });
            }
        }
        return out;
    }

    // The single selected group top, or null. Style sections edit this
    // group's own stacks through it (see DocEdits.styleTargets).
    function singleGroupTop() {
        if (!snapshot.doc)
            return null;
        var tops = snapshot.tops;
        if (tops.length !== 1 || tops[0].kind !== "group")
            return null;
        return tops[0];
    }

    // Plain-object style proxy for one group: same entry shape as leaf
    // snapshots so fill/stroke/effect sections bind unchanged. Copies,
    // never live refs. Type is "boolean" for live booleans, "frame"
    // for plain groups.
    function groupProxyEntry(g) {
        var d = snapshot.doc;
        var box = d._selectionBBox();
        if (!box)
            box = {
                x: 0,
                y: 0,
                w: 1,
                h: 1
            };
        return {
            uid: g.uid,
            type: (g.boolOp !== undefined && g.boolOp !== "none") ? "boolean" : "frame",
            x: box.x,
            y: box.y,
            w: box.w,
            h: box.h,
            rotation: 0,
            fills: d.factory._copyFills(g.fills, g),
            strokes: d.factory._copyStrokes(g.strokes, g),
            penFill: g.penFill !== false,
            strokeCap: g.strokeCap ?? "round",
            strokeJoin: g.strokeJoin ?? "round",
            shadows: d.factory._copyShadows(g.shadows),
            glows: d.factory._copyGlows(g.glows),
            layerBlur: d.factory._copyBlur(g.layerBlur, 8, 1),
            backgroundBlur: d.factory._copyBlur(g.backgroundBlur, 16, 0.7),
            grain: d.factory._copyGrain(g.grain),
            shaderId: String(g.shaderId ?? ""),
            shaderMode: (g.shaderMode === "overlay") ? "overlay" : "fill",
            shaderParams: d.factory._copyShaderParams(g.shaderParams),
            opacity: g.opacity ?? 1,
            radius: g.radius ?? 0,
            independentCorners: g.independentCorners === true,
            cornerRadii: d.factory._copyRadii(g.cornerRadii),
            points: 5,
            flipH: false,
            flipV: false,
            textContent: "",
            locked: d.isEffectivelyLocked(g)
        };
    }

    function collectSelected() {
        if (!snapshot.doc)
            return [];
        snapshot.doc.rev;
        var single = snapshot.singleGroupTop();
        if (single)
            return [snapshot.groupProxyEntry(single)];
        if (snapshot.hasGroup) {
            var box = snapshot.doc._selectionBBox();
            if (!box)
                return [];
            return [
                {
                    uid: -1,
                    type: "group",
                    x: box.x,
                    y: box.y,
                    w: box.w,
                    h: box.h,
                    rotation: 0,
                    fills: [],
                    strokes: [],
                    opacity: 1,
                    radius: 0,
                    independentCorners: false,
                    cornerRadii: [],
                    points: 5,
                    flipH: false,
                    flipV: false,
                    locked: checkAllLocked()
                }
            ];
        }
        return snapshot.selLeaves;
    }

    function checkAllLocked() {
        if (snapshot.selLeaves.length === 0)
            return false;
        for (var i = 0; i < snapshot.selLeaves.length; i++) {
            if (!snapshot.selLeaves[i].locked)
                return false;
        }
        return true;
    }

    function commonOf(role) {
        if (snapshot.sel.length === 0)
            return {
                mixed: true,
                value: 0
            };
        var v = snapshot.sel[0][role];
        // Group snapshots carry geometry only (no text props): report a
        // missing role as mixed so numeric bindings never see undefined.
        // Callers showing these roles are hidden for groups anyway.
        if (v === undefined)
            return {
                mixed: true,
                value: 0
            };
        for (var i = 1; i < snapshot.sel.length; i++) {
            if (snapshot.sel[i][role] !== v)
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

    function distinctFills() {
        var out = [];
        for (var i = 0; i < snapshot.sel.length; i++) {
            var fills = snapshot.sel[i].fills || [];
            for (var j = 0; j < fills.length; j++) {
                var f = String((fills[j] || {}).color ?? "");
                if (f !== "" && out.indexOf(f) < 0)
                    out.push(f);
            }
        }
        return out;
    }

    // First enabled fill/stroke color for animation seeding and
    // legacy single-value callers. Empty string when none applies.
    function firstFillColor() {
        for (var i = 0; i < snapshot.sel.length; i++) {
            var fills = snapshot.sel[i].fills || [];
            for (var j = 0; j < fills.length; j++) {
                if (fills[j] && fills[j].enabled !== false)
                    return String(fills[j].color ?? "");
            }
        }
        return "";
    }

    function firstStrokeColor() {
        for (var k = 0; k < snapshot.sel.length; k++) {
            var strokes = snapshot.sel[k].strokes || [];
            for (var m = 0; m < strokes.length; m++) {
                if (strokes[m] && strokes[m].enabled !== false)
                    return String(strokes[m].color ?? "");
            }
        }
        return "";
    }

    function allOfType(type) {
        if (snapshot.sel.length === 0)
            return false;
        for (var i = 0; i < snapshot.sel.length; i++) {
            if (snapshot.sel[i].type !== type)
                return false;
        }
        return true;
    }

    // Corner radius applies to every pointed shape except the ellipse.
    // Images and videos support uniform radius only (no per-corner UI).
    function supportsRadius() {
        if (snapshot.sel.length === 0)
            return false;
        for (var j = 0; j < snapshot.sel.length; j++) {
            var t = snapshot.sel[j].type;
            if (t !== "rectangle" && t !== "triangle" && t !== "star" && t !== "image" && t !== "video")
                return false;
        }
        return true;
    }

    function setAll(role, value) {
        if (snapshot.doc)
            snapshot.doc.setPropSelected(role, value);
    }

    // Scrub bounds for panel fields: one undo entry per drag.
    function beginScrub() {
        if (snapshot.doc)
            snapshot.doc.beginTransaction();
    }

    function endScrub() {
        if (snapshot.doc)
            snapshot.doc.endTransaction();
    }
}
