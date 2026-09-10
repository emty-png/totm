import QtQuick

// Equal-gap snapping for moving boxes (between and outside cases).
// Operates via `engine` facade.
QtObject {
    id: snapSpacing
    required property var engine

    function spacingMove(box, others, thresh) {
        var bestDx = 0, bestDy = 0, foundX = false, foundY = false;
        var bxG = [], byG = [];
        // Winning gap segments in content coords (the gap touching the
        // moving box); the overlay measures and labels these.
        var bxGap = null, byGap = null;
        var mw = box.w, mh = box.h;
        var mx = box.x, my = box.y;
        var mr = mx + mw, mb = my + mh;

        // X between.
        for (var i = 0; i < others.length; i++) {
            for (var j = 0; j < others.length; j++) {
                if (i === j)
                    continue;
                var a = others[i], b = others[j];
                var ar = a.x + a.w;
                if (ar <= mx + 0.001 && b.x >= mr - 0.001) {
                    var g1 = mx - ar, g2 = b.x - mr;
                    if (g1 >= 0 && g2 >= 0) {
                        var tx = (ar + b.x - mw) / 2;
                        var dx = tx - mx;
                        if (Math.abs(dx) <= thresh && (!foundX || Math.abs(dx) < Math.abs(bestDx))) {
                            bestDx = dx;
                            foundX = true;
                            bxG = [ar, tx, tx + mw, b.x];
                            bxGap = {
                                x0: tx + mw,
                                x1: b.x,
                                y: my + mh / 2
                            };
                        }
                    }
                }
                // Y between.
                var ab = a.y + a.h;
                if (ab <= my + 0.001 && b.y >= mb - 0.001) {
                    var v1 = my - ab, v2 = b.y - mb;
                    if (v1 >= 0 && v2 >= 0) {
                        var ty = (ab + b.y - mh) / 2;
                        var dy = ty - my;
                        if (Math.abs(dy) <= thresh && (!foundY || Math.abs(dy) < Math.abs(bestDy))) {
                            bestDy = dy;
                            foundY = true;
                            byG = [ab, ty, ty + mh, b.y];
                            byGap = {
                                y0: ty + mh,
                                y1: b.y,
                                x: mx + mw / 2
                            };
                        }
                    }
                }
            }
        }
        // X outside (pair left of M, or pair right of M).
        for (var k = 0; k < others.length; k++) {
            for (var l = 0; l < others.length; l++) {
                if (k === l)
                    continue;
                var p = others[k], q = others[l];
                var pr = p.x + p.w, qr = q.x + q.w;
                // Both left: p left of q left of M.
                if (pr <= q.x + 0.001 && qr <= mx + 0.001) {
                    var gab = q.x - pr, gbm = mx - qr;
                    if (gab >= 0 && gbm >= 0) {
                        var ddx = gab - gbm;
                        if (Math.abs(ddx) <= thresh && (!foundX || Math.abs(ddx) < Math.abs(bestDx))) {
                            bestDx = ddx;
                            foundX = true;
                            bxG = [pr, q.x, qr, mx + ddx];
                            bxGap = {
                                x0: qr,
                                x1: mx + ddx,
                                y: my + mh / 2
                            };
                        }
                    }
                }
                // Both right: M right of p right of q ordering (M < p < q).
                if (mr <= p.x + 0.001 && (p.x + p.w) <= q.x + 0.001) {
                    var gma = p.x - mr, gab2 = q.x - (p.x + p.w);
                    if (gma >= 0 && gab2 >= 0) {
                        var ddx2 = gab2 - gma;
                        // Moving M left/right changes mr equally: target so gma == gab2.
                        // mr_target = p.x - gab2 -> dx = -ddx2.
                        var cand = -ddx2;
                        if (Math.abs(cand) <= thresh && (!foundX || Math.abs(cand) < Math.abs(bestDx))) {
                            bestDx = cand;
                            foundX = true;
                            bxG = [mx + cand + mw, p.x, p.x + p.w, q.x];
                            bxGap = {
                                x0: mx + cand + mw,
                                x1: p.x,
                                y: my + mh / 2
                            };
                        }
                    }
                }
                // Y outside (both above, or both below).
                var pb = p.y + p.h, qb = q.y + q.h;
                if (pb <= q.y + 0.001 && qb <= my + 0.001) {
                    var vab = q.y - pb, vbm = my - qb;
                    if (vab >= 0 && vbm >= 0) {
                        var ddy = vab - vbm;
                        if (Math.abs(ddy) <= thresh && (!foundY || Math.abs(ddy) < Math.abs(bestDy))) {
                            bestDy = ddy;
                            foundY = true;
                            byG = [pb, q.y, qb, my + ddy];
                            byGap = {
                                y0: qb,
                                y1: my + ddy,
                                x: mx + mw / 2
                            };
                        }
                    }
                }
                if (mb <= p.y + 0.001 && (p.y + p.h) <= q.y + 0.001) {
                    var vma = p.y - mb, vab2 = q.y - (p.y + p.h);
                    if (vma >= 0 && vab2 >= 0) {
                        var candY = -(vab2 - vma);
                        if (Math.abs(candY) <= thresh && (!foundY || Math.abs(candY) < Math.abs(bestDy))) {
                            bestDy = candY;
                            foundY = true;
                            byG = [my + candY + mh, p.y, p.y + p.h, q.y];
                            byGap = {
                                y0: my + candY + mh,
                                y1: p.y,
                                x: mx + mw / 2
                            };
                        }
                    }
                }
            }
        }
        return {
            dx: foundX ? bestDx : 0,
            dy: foundY ? bestDy : 0,
            xGuides: engine.dedup(bxG),
            yGuides: engine.dedup(byG),
            xGap: foundX ? bxGap : null,
            yGap: foundY ? byGap : null,
            hasX: foundX,
            hasY: foundY
        };
    }
}
