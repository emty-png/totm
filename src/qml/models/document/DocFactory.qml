import QtQuick

// Node construction for one Document. Fresh uids, defaults for creation snapshots. Operates on the owning Document via `doc`.
QtObject {
    id: factory
    required property var doc

    function _makeShapeNode(type, snap) {
        var uid = doc.nextNodeUid++;
        var s = snap ?? {};
        // Every field defaults: creation snapshots carry geometry only,
        // clipboard snapshots carry the full style set.
        var n = doc.nodeFactory.createObject(doc, {
            uid: uid,
            kind: "shape",
            shapeType: type,
            name: s.name ?? (doc.shapeLabel(type) + " " + uid),
            x: s.x ?? 0,
            y: s.y ?? 0,
            w: s.w ?? 10,
            h: s.h ?? 10,
            rotation: s.rotation ?? 0,
            fill: s.fill ?? "#d9d9d9",
            fillType: s.fillType ?? "solid",
            fillGradient: factory._copyGradient(s.fillGradient),
            stroke: s.stroke ?? "#000000",
            strokeType: s.strokeType ?? "solid",
            strokeGradient: factory._copyGradient(s.strokeGradient),
            strokeWidth: s.strokeWidth ?? 0,
            shadows: factory._copyShadows(s.shadows ?? s.shadow),
            glows: factory._copyGlows(s.glows ?? s.glow),
            layerBlur: factory._copyBlur(s.layerBlur, 8, 1),
            backgroundBlur: factory._copyBlur(s.backgroundBlur, 16, 0.7),
            grain: factory._copyGrain(s.grain),
            opacity: s.opacity ?? 1,
            radius: s.radius ?? 0,
            independentCorners: s.independentCorners === true,
            cornerRadii: factory._copyRadii(s.cornerRadii),
            points: s.points ?? 5,
            pathData: factory._copyPath(s.pathData),
            flipH: s.flipH ?? false,
            flipV: s.flipV ?? false,
            imageSource: s.imageSource ?? "",
            textContent: s.textContent ?? "",
            fontFamily: s.fontFamily ?? "Inter",
            fontWeight: s.fontWeight ?? 400,
            fontSize: s.fontSize ?? 16,
            lineHeightAuto: s.lineHeightAuto !== false,
            lineHeight: s.lineHeight ?? 1.2,
            letterSpacing: s.letterSpacing ?? 0,
            hAlign: s.hAlign ?? "left",
            vAlign: s.vAlign ?? "top",
            autoSize: s.autoSize ?? (type === "text"),
            selected: true,
            visible: s.visible !== false,
            locked: false,
            renaming: false,
            expanded: true,
            children: []
        });
        return n;
    }

    // Number-array copy that also accepts C++ sequence values: after a
    // library round trip Array.isArray is false on them, so copy by
    // length instead of trusting Array methods.
    function _copyRadii(src) {
        var out = [];
        if (!src || typeof src.length !== "number")
            return out;
        for (var i = 0; i < src.length; i++)
            out.push(Math.max(0, Number(src[i]) || 0));
        return out;
    }

    // Deep copy so snapshots never share point objects with live nodes.
    function _copyGradient(src) {
        // 2-stop linear only in v1: angle + exactly two {color,pos}.
        // Missing/invalid input falls back to black->white at 90deg so
        // converts and old scenes always render something sane.
        var d = src ?? {};
        var angle = Number(d.angle);
        if (isNaN(angle))
            angle = 90;
        var raw = d.stops;
        var cols = [], poss = [];
        if (raw && typeof raw.length === "number") {
            for (var i = 0; i < raw.length && cols.length < 2; i++) {
                var st = raw[i] || {};
                cols.push(String(st.color ?? "#000000"));
                var p = Number(st.pos);
                poss.push(isNaN(p) ? (cols.length === 1 ? 0 : 1) : Math.min(1, Math.max(0, p)));
            }
        }
        while (cols.length < 2) {
            cols.push(cols.length === 0 ? "#000000" : "#ffffff");
            poss.push(cols.length === 1 ? 0 : 1);
        }
        return {
            angle: angle,
            stops: [
                {
                    color: cols[0],
                    pos: poss[0]
                },
                {
                    color: cols[1],
                    pos: poss[1]
                }
            ]
        };
    }

    function _copyShadowEntry(src) {
        var d = src ?? {};
        return {
            enabled: d.enabled !== false,
            inner: d.inner === true,
            color: String(d.color ?? "#80000000"),
            x: d.x !== undefined ? (Number(d.x) || 0) : 0,
            y: d.y !== undefined ? (Number(d.y) || 0) : 4,
            blur: d.blur !== undefined ? Math.max(0, Number(d.blur) || 0) : 8,
            spread: d.spread !== undefined ? Math.max(0, Number(d.spread) || 0) : 0
        };
    }

    // Shadows stack: arrays copy per entry. A legacy single map wraps
    // into one entry so old scenes never crash (no migration: params
    // carry over, effectType is ignored).
    function _copyShadows(src) {
        if (!src)
            return [];
        if (typeof src.length !== "number")
            return [factory._copyShadowEntry(src)];
        var out = [];
        for (var i = 0; i < src.length; i++)
            out.push(factory._copyShadowEntry(src[i]));
        return out;
    }

    function _copyBlur(src, defRadius, defOpacity) {
        var d = src ?? {};
        return {
            enabled: d.enabled === true,
            radius: d.radius !== undefined ? Math.max(0, Number(d.radius) || 0) : defRadius,
            opacity: d.opacity !== undefined ? Math.min(1, Math.max(0, Number(d.opacity))) : defOpacity
        };
    }

    function _copyGlowEntry(src) {
        var d = src ?? {};
        return {
            enabled: d.enabled !== false,
            inner: d.inner === true,
            color: String(d.color ?? "#cc00ffff"),
            blur: d.blur !== undefined ? Math.max(0, Number(d.blur) || 0) : 16,
            spread: d.spread !== undefined ? Math.max(0, Number(d.spread) || 0) : 4
        };
    }

    function _copyGlows(src) {
        if (!src)
            return [];
        if (typeof src.length !== "number")
            return [factory._copyGlowEntry(src)];
        var out = [];
        for (var i = 0; i < src.length; i++)
            out.push(factory._copyGlowEntry(src[i]));
        return out;
    }

    function _copyGrain(src) {
        var d = src ?? {};
        return {
            enabled: d.enabled === true,
            amount: d.amount !== undefined ? Math.min(1, Math.max(0, Number(d.amount))) : 0.5,
            size: d.size !== undefined ? Math.min(10, Math.max(1, Number(d.size) || 0)) : 2
        };
    }

    function defaultShadow(inner) {
        return {
            enabled: true,
            inner: inner === true,
            color: "#80000000",
            x: 0,
            y: 4,
            blur: 8,
            spread: 0
        };
    }

    function defaultGlow(inner) {
        return {
            enabled: true,
            inner: inner === true,
            color: "#cc00ffff",
            blur: 16,
            spread: 4
        };
    }

    function _copyPath(pathData) {
        if (!pathData)
            return [];
        var out = [];
        for (var i = 0; i < pathData.length; i++) {
            var sub = pathData[i] || {};
            var pts = [];
            var src = sub.pts || [];
            for (var j = 0; j < src.length; j++) {
                var p = src[j] || {};
                pts.push({
                    x: Number(p.x) || 0,
                    y: Number(p.y) || 0,
                    smooth: p.smooth === true,
                    inX: p.inX !== undefined ? Number(p.inX) : (Number(p.x) || 0),
                    inY: p.inY !== undefined ? Number(p.inY) : (Number(p.y) || 0),
                    outX: p.outX !== undefined ? Number(p.outX) : (Number(p.x) || 0),
                    outY: p.outY !== undefined ? Number(p.outY) : (Number(p.y) || 0)
                });
            }
            out.push({
                closed: sub.closed === true,
                pts: pts
            });
        }
        return out;
    }

    // Tight bbox over anchors and handles in absolute content coords.
    function penBBoxFor(pathData) {
        var x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        var found = false;
        for (var i = 0; i < (pathData || []).length; i++) {
            var pts = (pathData[i] || {}).pts || [];
            for (var j = 0; j < pts.length; j++) {
                var p = pts[j] || {};
                var xs = [p.x, p.inX, p.outX];
                var ys = [p.y, p.inY, p.outY];
                for (var k = 0; k < 3; k++) {
                    if (xs[k] === undefined || ys[k] === undefined)
                        continue;
                    if (xs[k] < x0)
                        x0 = xs[k];
                    if (ys[k] < y0)
                        y0 = ys[k];
                    if (xs[k] > x1)
                        x1 = xs[k];
                    if (ys[k] > y1)
                        y1 = ys[k];
                    found = true;
                }
            }
        }
        if (!found)
            return {
                x: 0,
                y: 0,
                w: 1,
                h: 1
            };
        return {
            x: x0,
            y: y0,
            w: Math.max(1, x1 - x0),
            h: Math.max(1, y1 - y0)
        };
    }

    function _makeGroupNode(name, children) {
        var uid = doc.nextNodeUid++;
        var n = doc.nodeFactory.createObject(doc, {
            uid: uid,
            kind: "group",
            name: name || ("Group " + uid),
            selected: true,
            visible: true,
            locked: false,
            renaming: false,
            expanded: true,
            children: children || []
        });
        return n;
    }

    function addShape(type, x, y, w, h) {
        var container = doc._activeContainerUid();
        doc.clearSelection();
        var n = _makeShapeNode(type, {
            x: Math.round(x),
            y: Math.round(y),
            w: Math.max(1, Math.round(w)),
            h: Math.max(1, Math.round(h))
        });
        var list = doc._childrenOf(container).slice();
        list.unshift(n);
        doc._setChildren(container, list);
        doc.anchorUid = n.uid;
        doc._refreshStructural();
        return n.uid;
    }

    // Pen creation: absolute multi-subpath data, bbox derived so the
    // node selects/snaps like any shape. Rejects empty paths.
    function addPen(pathData) {
        var clean = factory._copyPath(pathData);
        var total = 0;
        for (var i = 0; i < clean.length; i++)
            total += (clean[i].pts || []).length;
        if (total === 0)
            return -1;
        var box = factory.penBBoxFor(clean);
        var container = doc._activeContainerUid();
        doc.clearSelection();
        var n = _makeShapeNode("pen", {
            x: box.x,
            y: box.y,
            w: box.w,
            h: box.h,
            pathData: clean
        });
        var list = doc._childrenOf(container).slice();
        list.unshift(n);
        doc._setChildren(container, list);
        doc.anchorUid = n.uid;
        doc._refreshStructural();
        return n.uid;
    }

    // Text creation: click passes autoSize with a measured box, drag
    // passes a fixed wrapping box. Content starts empty; the canvas
    // opens the inline editor right after.
    function addText(x, y, w, h, auto) {
        var container = doc._activeContainerUid();
        doc.clearSelection();
        var n = _makeShapeNode("text", {
            x: Math.round(x),
            y: Math.round(y),
            w: Math.max(1, Math.round(w)),
            h: Math.max(1, Math.round(h)),
            fill: "#000000",
            autoSize: auto
        });
        var list = doc._childrenOf(container).slice();
        list.unshift(n);
        doc._setChildren(container, list);
        doc.anchorUid = n.uid;
        doc._refreshStructural();
        return n.uid;
    }

    // Image creation: stored blob name plus an explicit box (click stamps
    // natural size, drag stretches to the box). Rejects empty sources.
    function addImage(imageSource, x, y, w, h) {
        if (!imageSource)
            return -1;
        var container = doc._activeContainerUid();
        doc.clearSelection();
        var n = _makeShapeNode("image", {
            x: Math.round(x),
            y: Math.round(y),
            w: Math.max(1, Math.round(w)),
            h: Math.max(1, Math.round(h)),
            imageSource: String(imageSource)
        });
        var list = doc._childrenOf(container).slice();
        list.unshift(n);
        doc._setChildren(container, list);
        doc.anchorUid = n.uid;
        doc._refreshStructural();
        return n.uid;
    }
}
