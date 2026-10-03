import QtQuick

// Persistent-asset payloads: detached node snapshots plus optional anim
// clips. Operates on the owner via `doc`. Import always mints fresh
// uids/ids, so assets never alias live nodes.
QtObject {
    id: assets

    required property var doc

    // All uids covered by snapshots (tops + descendants).
    function _uidsOf(snaps) {
        var out = {};
        var walk = list => {
            for (var i = 0; i < list.length; i++) {
                var s = list[i] || {};
                if (s.uid !== undefined)
                    out[s.uid] = true;

                if (s.kind === "group")
                    walk(s.children || []);
            }
        };
        walk(snaps || []);
        return out;
    }

    // Bounding box of top-level snapshots in design coords. Groups
    // contribute via their descendants.
    function _bboxOf(snaps) {
        var minX = 0, minY = 0, maxX = 0, maxY = 0, first = true;
        var acc = (x, y, w, h) => {
            if (first) {
                minX = x;
                minY = y;
                maxX = x + w;
                maxY = y + h;
                first = false;
            } else {
                minX = Math.min(minX, x);
                minY = Math.min(minY, y);
                maxX = Math.max(maxX, x + w);
                maxY = Math.max(maxY, y + h);
            }
        };
        var walk = (s, ox, oy) => {
            if (!s)
                return;

            if (s.kind === "group") {
                var kids = s.children || [];
                for (var i = 0; i < kids.length; i++)
                    walk(kids[i], ox, oy);
                return;
            }
            acc(Number(s.x) || 0, Number(s.y) || 0, Math.max(0, Number(s.w) || 0), Math.max(0, Number(s.h) || 0));
        };
        var list = snaps || [];
        for (var j = 0; j < list.length; j++)
            walk(list[j], 0, 0);
        if (first)
            return null;

        return {
            "x": minX,
            "y": minY,
            "w": Math.max(0, maxX - minX),
            "h": Math.max(0, maxY - minY)
        };
    }

    function _offsetSnapshots(snaps, dx, dy) {
        if (!dx && !dy)
            return;

        var walk = s => {
            if (!s)
                return;

            if (s.kind === "group") {
                var kids = s.children || [];
                for (var i = 0; i < kids.length; i++)
                    walk(kids[i]);
                return;
            }
            s.x = (Number(s.x) || 0) + dx;
            s.y = (Number(s.y) || 0) + dy;
        };
        for (var i = 0; i < snaps.length; i++)
            walk(snaps[i]);
    }

    // Payload for the current selection. Nodes are detached snapshots;
    // clips target snapshot uids with dt relative to the earliest clip.
    function assetPayload(includeAnims) {
        var nodes = doc.copySelected();
        if (!nodes || nodes.length === 0)
            return null;

        var clips = [];
        if (includeAnims) {
            var covered = assets._uidsOf(nodes);
            var src = [];
            var all = doc.anim ? (doc.anim.clips || []) : [];
            for (var i = 0; i < all.length; i++) {
                if (covered[all[i].targetUid])
                    src.push(all[i]);
            }
            src.sort((a, b) => {
                return (a.t0 - b.t0) || (a.id - b.id);
            });
            var earliest = src.length > 0 ? src[0].t0 : 0;
            for (var k = 0; k < src.length; k++) {
                var s = src[k];
                var ez = s.easing || {};
                clips.push({
                    "preset": s.preset,
                    "duration": s.duration,
                    "dt": Math.max(0, s.t0 - earliest),
                    "mode": s.mode,
                    "options": doc.anim.copyMap(s.options),
                    "easing": {
                        "id": ez.id,
                        "bezier": ez.bezier ? ez.bezier.slice() : ez.bezier
                    },
                    "targetUid": s.targetUid
                });
            }
        }
        return {
            "nodes": nodes,
            "clips": clips
        };
    }

    // Suggested asset name from the selection (first top name).
    function suggestedName() {
        var tops = doc.selectedTops();
        if (tops.length === 0)
            return qsTr("Untitled asset");

        var n = tops[0].kind === "group" ? (tops[0].name || "") : (tops[0].name || "");
        n = String(n || "").trim();
        return n === "" ? qsTr("Untitled asset") : n;
    }

    // Insert a stored payload as detached copies. atX/atY are design
    // coords for the asset bbox center; when omitted the asset lands
    // centered on the scene. Clips re-anchor earliest at the playhead.
    function insertAsset(payload, atX, atY) {
        var p = payload || {};
        var snaps = p.nodes || [];
        if (snaps.length === 0)
            return [];

        // Deep copy via JSON so the stored payload never aliases live
        // nodes when offsets apply.
        var copies = JSON.parse(JSON.stringify(snaps));
        var box = assets._bboxOf(copies);
        var cx = box ? box.x + box.w / 2 : 0;
        var cy = box ? box.y + box.h / 2 : 0;
        var tx = atX !== undefined && atX !== null ? Number(atX) : doc.sceneWidth / 2;
        var ty = atY !== undefined && atY !== null ? Number(atY) : doc.sceneHeight / 2;
        if (isNaN(tx))
            tx = doc.sceneWidth / 2;

        if (isNaN(ty))
            ty = doc.sceneHeight / 2;

        assets._offsetSnapshots(copies, tx - cx, ty - cy);
        doc.clearSelection();
        var container = doc._activeContainerUid();
        var list = doc._childrenOf(container).slice();
        // Old uid -> new uid across tops and descendants.
        var uidMap = {};
        var made = [];
        var instantiate = (snap, select) => {
            var before = [];
            var collect = s => {
                if (s.uid !== undefined)
                    before.push(s.uid);

                if (s.kind === "group") {
                    var kids = s.children || [];
                    for (var i = 0; i < kids.length; i++)
                        collect(kids[i]);
                }
            };
            collect(snap);
            var n = doc.clipboard._instantiateSnapshot(snap, select);
            n.visible = true;
            n.locked = false;
            var fix = nd => {
                if (nd.kind === "group") {
                    nd.visible = true;
                    nd.locked = false;
                    for (var i = 0; i < nd.children.length; i++)
                        fix(nd.children[i]);
                } else {
                    nd.visible = true;
                    nd.locked = false;
                }
            };
            fix(n);
            var after = [];
            var collectNew = nd => {
                after.push(nd.uid);
                if (nd.kind === "group") {
                    for (var i = 0; i < nd.children.length; i++)
                        collectNew(nd.children[i]);
                }
            };
            collectNew(n);
            for (var i = 0; i < Math.min(before.length, after.length); i++)
                uidMap[before[i]] = after[i];
            return n;
        };
        for (var k = copies.length - 1; k >= 0; k--) {
            var n = instantiate(copies[k], true);
            made.push(n.uid);
            list.unshift(n);
        }
        doc._setChildren(container, list);
        // Remap stored clips onto the fresh uids, earliest at playhead.
        var templates = p.clips || [];
        if (templates.length > 0 && doc.anim) {
            var comp = Math.max(0.5, doc.anim.duration);
            var base = Math.min(Math.max(0, doc.anim.currentTime), Math.max(0, comp - 0.1));
            var ordered = templates.slice().sort((a, b) => {
                return (Number(a.dt) || 0) - (Number(b.dt) || 0);
            });
            var out = doc.anim.clips.slice();
            for (var m = 0; m < ordered.length; m++) {
                var s = ordered[m] || {};
                if (doc.anim.presets.presetIds().indexOf(s.preset) < 0)
                    continue;

                var target = uidMap[s.targetUid];
                if (target === undefined || !doc.findNode(target))
                    continue;

                var nt0 = Math.min((Number(s.dt) || 0) + base, Math.max(0, comp - 0.1));
                var ez = s.easing || {};
                var clip = doc.anim.presets.buildClip(s.preset, doc.anim.nextClipId++, target, nt0, s.duration, s.mode, doc.anim.copyMap(s.options), {
                    "id": ez.id,
                    "bezier": ez.bezier ? ez.bezier.slice() : ez.bezier
                });
                if (!doc.findNode(clip.targetUid))
                    continue;

                out.push(clip);
            }
            doc.anim.clips = out;
        }
        var tops = doc.selectedTops();
        doc.anchorUid = tops.length > 0 ? tops[0].uid : -1;
        doc._refreshStructural();
        return made;
    }
}
