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
            stroke: s.stroke ?? "#000000",
            strokeWidth: s.strokeWidth ?? 0,
            opacity: s.opacity ?? 1,
            radius: s.radius ?? 0,
            independentCorners: s.independentCorners === true,
            cornerRadii: factory._copyRadii(s.cornerRadii),
            points: s.points ?? 5,
            pathData: factory._copyPath(s.pathData),
            flipH: s.flipH ?? false,
            flipV: s.flipV ?? false,
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
}
