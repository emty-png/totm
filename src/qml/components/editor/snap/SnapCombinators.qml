import QtQuick

// Combined move, resize, point and create snaps. Picks winners per axis. Operates via `engine` facade.
QtObject {
    id: snapCombinators
    required property var engine

    function snapMove(doc, box, zoom) {
        var thresh = engine.threshFor(zoom);
        var others = engine.collectOthers(doc);
        var targets = engine.targetLists(doc, others);
        var edge = engine.edgeMove(box, targets, thresh);
        var space = engine.spacingMove(box, others, thresh);
        var dx = 0, dy = 0, xG = [], yG = [];
        if (edge.hasX && space.hasX)
            dx = Math.abs(space.dx) < Math.abs(edge.dx) - 0.001 ? space.dx : edge.dx;
        else if (edge.hasX)
            dx = edge.dx;
        else if (space.hasX)
            dx = space.dx;
        if (edge.hasY && space.hasY)
            dy = Math.abs(space.dy) < Math.abs(edge.dy) - 0.001 ? space.dy : edge.dy;
        else if (edge.hasY)
            dy = edge.dy;
        else if (space.hasY)
            dy = space.dy;
        // Guides follow the winner per axis.
        var useEdgeX = edge.hasX && (!space.hasX || Math.abs(edge.dx) <= Math.abs(space.dx) + 0.001);
        var useEdgeY = edge.hasY && (!space.hasY || Math.abs(edge.dy) <= Math.abs(space.dy) + 0.001);
        xG = dx === 0 ? [] : (useEdgeX ? edge.xGuides : space.xGuides);
        yG = dy === 0 ? [] : (useEdgeY ? edge.yGuides : space.yGuides);
        // If both snapped the same axis (edge picked but spacing also tied),
        // merge spacing guides so equal gaps still read.
        if (dx !== 0 && edge.hasX && space.hasX && Math.abs(edge.dx - space.dx) < 0.5)
            xG = engine.dedup(edge.xGuides.concat(space.xGuides));
        if (dy !== 0 && edge.hasY && space.hasY && Math.abs(edge.dy - space.dy) < 0.5)
            yG = engine.dedup(edge.yGuides.concat(space.yGuides));
        // Gap labels follow the spacing side whenever its gaps read,
        // including the tied merge above.
        var tieX = dx !== 0 && edge.hasX && space.hasX && Math.abs(edge.dx - space.dx) < 0.5;
        var tieY = dy !== 0 && edge.hasY && space.hasY && Math.abs(edge.dy - space.dy) < 0.5;
        var xGap = dx === 0 ? null : (!useEdgeX || tieX ? space.xGap : null);
        var yGap = dy === 0 ? null : (!useEdgeY || tieY ? space.yGap : null);
        return {
            x: box.x + dx,
            y: box.y + dy,
            dx: dx,
            dy: dy,
            xGuides: xG,
            yGuides: yG,
            xGap: xGap,
            yGap: yGap
        };
    }

    function snapResize(doc, newBox, hid, zoom) {
        var thresh = engine.threshFor(zoom);
        var others = engine.collectOthers(doc);
        var targets = engine.targetLists(doc, others);
        var box = {
            x: newBox.x,
            y: newBox.y,
            w: newBox.w,
            h: newBox.h
        };
        var xG = [], yG = [];
        var moveL = hid.indexOf("w") >= 0, moveR = hid.indexOf("e") >= 0;
        var moveT = hid.indexOf("n") >= 0, moveB = hid.indexOf("s") >= 0;
        if (moveR) {
            var edgeR = box.x + box.w, best = 0, found = false;
            for (var i = 0; i < targets.xs.length; i++) {
                var dr = targets.xs[i] - edgeR;
                if (Math.abs(dr) <= thresh && (!found || Math.abs(dr) < Math.abs(best))) {
                    best = dr;
                    found = true;
                }
            }
            if (found && box.w + best >= 1) {
                box.w += best;
                xG.push(edgeR + best);
            }
        } else if (moveL) {
            var edgeL = box.x, bestL = 0, foundL = false;
            for (var j = 0; j < targets.xs.length; j++) {
                var dl = targets.xs[j] - edgeL;
                if (Math.abs(dl) <= thresh && (!foundL || Math.abs(dl) < Math.abs(bestL))) {
                    bestL = dl;
                    foundL = true;
                }
            }
            if (foundL && box.w - bestL >= 1) {
                box.x += bestL;
                box.w -= bestL;
                xG.push(box.x);
            }
        }
        if (moveB) {
            var edgeB = box.y + box.h, bestB = 0, foundB = false;
            for (var k = 0; k < targets.ys.length; k++) {
                var db = targets.ys[k] - edgeB;
                if (Math.abs(db) <= thresh && (!foundB || Math.abs(db) < Math.abs(bestB))) {
                    bestB = db;
                    foundB = true;
                }
            }
            if (foundB && box.h + bestB >= 1) {
                box.h += bestB;
                yG.push(edgeB + bestB);
            }
        } else if (moveT) {
            var edgeT = box.y, bestT = 0, foundT = false;
            for (var l = 0; l < targets.ys.length; l++) {
                var dt = targets.ys[l] - edgeT;
                if (Math.abs(dt) <= thresh && (!foundT || Math.abs(dt) < Math.abs(bestT))) {
                    bestT = dt;
                    foundT = true;
                }
            }
            if (foundT && box.h - bestT >= 1) {
                box.y += bestT;
                box.h -= bestT;
                yG.push(box.y);
            }
        }
        return {
            box: box,
            xGuides: engine.dedup(xG),
            yGuides: engine.dedup(yG)
        };
    }

    function snapPoint(doc, px, py, zoom) {
        var thresh = engine.threshFor(zoom);
        var others = engine.collectOthers(doc);
        var targets = engine.targetLists(doc, others);
        var nx = px, ny = py;
        var bx = 0, by = 0, fx = false, fy = false;
        for (var i = 0; i < targets.xs.length; i++) {
            var dx = targets.xs[i] - px;
            if (Math.abs(dx) <= thresh && (!fx || Math.abs(dx) < Math.abs(bx))) {
                bx = dx;
                fx = true;
            }
        }
        for (var j = 0; j < targets.ys.length; j++) {
            var dy = targets.ys[j] - py;
            if (Math.abs(dy) <= thresh && (!fy || Math.abs(dy) < Math.abs(by))) {
                by = dy;
                fy = true;
            }
        }
        if (fx)
            nx = px + bx;
        if (fy)
            ny = py + by;
        return {
            x: nx,
            y: ny
        };
    }

    function snapCreate(doc, sx, sy, cx, cy, zoom) {
        var thresh = engine.threshFor(zoom);
        var others = engine.collectOthers(doc);
        var targets = engine.targetLists(doc, others);
        var nx = cx, ny = cy, xG = [], yG = [];
        var bdx = 0, fx = false, gx = 0;
        for (var i = 0; i < targets.xs.length; i++) {
            var t = targets.xs[i];
            var de = t - cx;
            if (Math.abs(de) <= thresh && (!fx || Math.abs(de) < Math.abs(bdx))) {
                bdx = de;
                fx = true;
                gx = t;
            }
            var dc = 2 * t - sx - cx;
            if (Math.abs(dc) <= thresh && (!fx || Math.abs(dc) < Math.abs(bdx))) {
                bdx = dc;
                fx = true;
                gx = t;
            }
        }
        if (fx) {
            nx = cx + bdx;
            xG.push(gx);
        }
        var bdy = 0, fy = false, gy = 0;
        for (var j = 0; j < targets.ys.length; j++) {
            var u = targets.ys[j];
            var ve = u - cy;
            if (Math.abs(ve) <= thresh && (!fy || Math.abs(ve) < Math.abs(bdy))) {
                bdy = ve;
                fy = true;
                gy = u;
            }
            var vc = 2 * u - sy - cy;
            if (Math.abs(vc) <= thresh && (!fy || Math.abs(vc) < Math.abs(bdy))) {
                bdy = vc;
                fy = true;
                gy = u;
            }
        }
        if (fy) {
            ny = cy + bdy;
            yG.push(gy);
        }
        return {
            x: nx,
            y: ny,
            xGuides: engine.dedup(xG),
            yGuides: engine.dedup(yG)
        };
    }
}
