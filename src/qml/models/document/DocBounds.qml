import QtQuick

// Derived bounds for nodes and selections. Hidden subtrees contribute nothing. Operates on the owning Document via `doc`.
QtObject {
    id: bounds
    required property var doc

    function rotatedBounds(s) {
        var rad = s.rotation * Math.PI / 180;
        var cx = s.x + s.w / 2, cy = s.y + s.h / 2;
        var cos = Math.abs(Math.cos(rad)), sin = Math.abs(Math.sin(rad));
        var w = s.w * cos + s.h * sin, h = s.w * sin + s.h * cos;
        return {
            x: cx - w / 2,
            y: cy - h / 2,
            w: w,
            h: h
        };
    }

    // Fresh bbox for pen nodes so stale x/y never clips new points.
    function penBox(node) {
        var box = doc.factory.penBBoxFor(node.pathData);
        return {
            x: box.x,
            y: box.y,
            w: box.w,
            h: box.h,
            rotation: node.rotation
        };
    }

    function bboxOfNode(node) {
        if (!node)
            return null;
        if (node.kind === "shape") {
            if (!doc.isEffectivelyVisible(node))
                return null;
            if (node.shapeType === "pen")
                return rotatedBounds(penBox(node));
            return rotatedBounds(node);
        }
        var x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        var found = false;
        var leaves = doc._leavesUnder(node);
        for (var i = 0; i < leaves.length; i++) {
            if (!doc.isEffectivelyVisible(leaves[i]))
                continue;
            var b = bboxOfNode(leaves[i]);
            if (!b)
                continue;
            if (b.x < x0)
                x0 = b.x;
            if (b.y < y0)
                y0 = b.y;
            if (b.x + b.w > x1)
                x1 = b.x + b.w;
            if (b.y + b.h > y1)
                y1 = b.y + b.h;
            found = true;
        }
        if (!found)
            return null;
        return {
            x: x0,
            y: y0,
            w: Math.max(1, x1 - x0),
            h: Math.max(1, y1 - y0)
        };
    }

    function _selectionBBox() {
        var tops = doc.selectedTops();
        var x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        var found = false;
        for (var i = 0; i < tops.length; i++) {
            var b = bboxOfNode(tops[i]);
            if (!b)
                continue;
            found = true;
            if (b.x < x0)
                x0 = b.x;
            if (b.y < y0)
                y0 = b.y;
            if (b.x + b.w > x1)
                x1 = b.x + b.w;
            if (b.y + b.h > y1)
                y1 = b.y + b.h;
        }
        if (!found)
            return null;
        return {
            x: x0,
            y: y0,
            w: Math.max(1, x1 - x0),
            h: Math.max(1, y1 - y0)
        };
    }

    function selectionBBox() {
        doc.rev;
        var tops = doc.selectedTops();
        var x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        var found = false, count = 0, rotated = false, singleGroup = false;
        for (var i = 0; i < tops.length; i++) {
            var leaves = doc._leavesUnder(tops[i]);
            var anyVisible = false;
            for (var j = 0; j < leaves.length; j++) {
                if (!doc.isEffectivelyVisible(leaves[j]))
                    continue;
                anyVisible = true;
                if (((leaves[j].rotation % 360) + 360) % 360 !== 0)
                    rotated = true;
                var b = bboxOfNode(leaves[j]);
                if (!b)
                    continue;
                if (b.x < x0)
                    x0 = b.x;
                if (b.y < y0)
                    y0 = b.y;
                if (b.x + b.w > x1)
                    x1 = b.x + b.w;
                if (b.y + b.h > y1)
                    y1 = b.y + b.h;
                found = true;
            }
            if (anyVisible) {
                count++;
                singleGroup = count === 1 && tops[i].kind === "group";
            }
        }
        if (!found)
            return null;
        return {
            x: x0,
            y: y0,
            w: Math.max(1, x1 - x0),
            h: Math.max(1, y1 - y0),
            count: count,
            rotated: rotated,
            singleGroup: singleGroup
        };
    }

    function unselectedSnapBoxes() {
        doc.rev;
        var tops = doc.selectedTops();
        var selIds = {};
        for (var i = 0; i < tops.length; i++) {
            selIds[tops[i].uid] = true;
            var sub = doc._leavesUnder(tops[i]);
            for (var k = 0; k < sub.length; k++)
                selIds[sub[k].uid] = true;
        }
        var out = [];
        var all = doc._allNodes();
        for (var j = 0; j < all.length; j++) {
            var n = all[j];
            if (selIds[n.uid] || !doc.isEffectivelyVisible(n))
                continue;
            if (doc.isEffectivelyLocked(n))
                continue;
            var b = bboxOfNode(n);
            if (b)
                out.push(b);
        }
        return out;
    }
}
