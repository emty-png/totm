import QtQuick
import Totm

// Scene contents for one canvas. Positions by pan offset and scales
// around top-left so screen = offset + zoom * local.
Item {
    id: layerRoot

    required property var doc
    required property real zoom
    required property real offsetX
    required property real offsetY

    property var activatePolicy: null
    property var pressPolicy: null
    property var movePolicy: null
    property var releasePolicy: null
    property var doublePolicy: null
    // Uid owning the inline text editor (-1 when closed). The matching
    // item hides its static glyphs; others are unaffected.
    property int editingUid: -1
    property var measurePolicy: null
    // Live backdrop for background-blur sampling (hidden duplicate
    // without blur shapes, no recursion). Null inside the duplicate.
    property var backdropItem: null
    // Backdrop duplicates hide blurred shapes so each frosted panel
    // samples only the content behind it (blur-over-blur accumulates
    // in a follow-up).
    property bool hideBlurShapes: false
    // Animated-grain frame number (floor(seconds * 60), shared with the
    // exporter). Reads the transport clock, so it shimmers while playing
    // or scrubbing and freezes on a deterministic field otherwise.
    // Low-spec mode pins it at zero: static grain, no per-frame churn.
    readonly property int grainFrame: SettingsStore.lowSpecMode ? 0 : (layerRoot.doc && layerRoot.doc.anim ? Math.floor(Number(layerRoot.doc.anim.currentTime || 0) * 60) : 0)

    // Plain sampled map for the CPU mask preview (same keys as export
    // snapshots, including kind: ShapePath::isCombinableNode requires
    // kind == "shape", so boolean preview breaks without it). Reads
    // live nodes so animated mask/content geometry follows playback
    // without extra sampling.
    readonly property var boolGeo: ShapePathHelper {}

    // All live boolean groups in the tree (any depth). Children paint
    // only through the combined delegate below, never individually.
    function booleanGroups() {
        var d = layerRoot.doc;
        if (!d)
            return [];
        d.rev;
        d.structRev;
        var out = [];
        var all = d._allNodes();
        for (var i = 0; i < all.length; i++) {
            var n = all[i];
            if (n && n.kind === "group" && n.boolOp !== undefined && n.boolOp !== "none")
                out.push(n);
        }
        return out;
    }

    // Leaf uids hidden inside a boolean group (any depth).
    function booleanLeafIds() {
        var d = layerRoot.doc;
        if (!d)
            return ({});
        d.rev;
        d.structRev;
        var ids = {};
        var groups = layerRoot.booleanGroups();
        for (var i = 0; i < groups.length; i++) {
            var leaves = d._leavesUnder(groups[i]);
            for (var j = 0; j < leaves.length; j++)
                ids[leaves[j].uid] = true;
        }
        return ids;
    }

    // Live child snapshot maps for one boolean group uid.
    function booleanChildrenMaps(uid) {
        var d = layerRoot.doc;
        if (!d)
            return [];
        d.rev;
        var g = d.findNode(uid);
        if (!g || g.kind !== "group")
            return [];
        var out = [];
        var leaves = d._leavesUnder(g);
        for (var i = 0; i < leaves.length; i++)
            out.push(layerRoot.previewMap(leaves[i]));
        return out;
    }

    function booleanBounds(uid) {
        var d = layerRoot.doc;
        if (!d)
            return null;
        d.rev;
        var g = d.findNode(uid);
        if (!g)
            return null;
        var maps = layerRoot.booleanChildrenMaps(uid);
        if (maps.length === 0)
            return null;
        var r = layerRoot.boolGeo.combineBounds(maps, g.boolOp || "union");
        if (!r || !(r.width > 0.01) || !(r.height > 0.01))
            return null;
        return r;
    }

    // True when a leaf paints through a boolean group (any depth).
    function isBooleanLeaf(uid) {
        var d = layerRoot.doc;
        if (!d)
            return false;
        d.rev;
        d.structRev;
        var hit = d._find(uid);
        if (!hit)
            return false;
        var chain = hit.ancestors || [];
        for (var i = 0; i < chain.length; i++) {
            if (chain[i].kind === "group" && chain[i].boolOp !== undefined && chain[i].boolOp !== "none")
                return true;
        }
        return false;
    }

    // Paint order for a boolean group: topmost child wins so the
    // combined silhouette interleaves with siblings like a leaf.
    function booleanPaintZ(uid) {
        var d = layerRoot.doc;
        if (!d)
            return 0;
        d.rev;
        d.structRev;
        var g = d.findNode(uid);
        if (!g)
            return 0;
        var leaves = d._leavesUnder(g);
        var z = 0;
        for (var i = 0; i < leaves.length; i++) {
            if (leaves[i].zOrder > z)
                z = leaves[i].zOrder;
        }
        return z;
    }
    function previewMap(n) {
        if (!n)
            return ({});
        var d = layerRoot.doc;
        return {
            uid: n.uid,
            kind: n.kind ?? "shape",
            type: n.shapeType,
            shapeType: n.shapeType,
            x: n.x,
            y: n.y,
            w: n.w,
            h: n.h,
            rotation: n.rotation,
            opacity: n.opacity,
            visible: n.visible,
            fills: d.factory._copyFills(n.fills, n),
            strokes: d.factory._copyStrokes(n.strokes, n),
            shadows: d.factory._copyShadows(n.shadows),
            glows: d.factory._copyGlows(n.glows),
            layerBlur: d.factory._copyBlur(n.layerBlur, 8, 1),
            backgroundBlur: d.factory._copyBlur(n.backgroundBlur, 16, 0.7),
            grain: d.factory._copyGrain(n.grain),
            radius: n.radius,
            independentCorners: n.independentCorners === true,
            cornerRadii: d.factory._copyRadii(n.cornerRadii),
            points: n.points,
            pathData: d.factory._copyPath(n.pathData),
            flipH: n.flipH === true,
            flipV: n.flipV === true,
            imageSource: n.imageSource ?? "",
            textContent: n.textContent ?? "",
            fontFamily: n.fontFamily || "Inter",
            fontWeight: n.fontWeight || 400,
            fontSize: n.fontSize || 16,
            lineHeightAuto: n.lineHeightAuto !== false,
            lineHeight: n.lineHeight || 1.2,
            letterSpacing: n.letterSpacing || 0,
            hAlign: n.hAlign || "left",
            vAlign: n.vAlign || "top",
            autoSize: n.autoSize !== false,
            penFill: n.penFill !== false,
            strokeCap: n.strokeCap || "round",
            strokeJoin: n.strokeJoin || "round",
            isMask: n.isMask === true,
            maskFeather: Math.max(0, Number(n.maskFeather) || 0),
            maskInverted: n.maskInverted === true
        };
    }

    // Masked non-mask leaves (structural only: uid + paint depth).
    // Geometry/style flows per-delegate through live bindings below,
    // so the Repeater model stays stable across playback ticks and
    // delegates are never rebuilt at 60Hz.
    readonly property var maskedStubs: {
        var d = layerRoot.doc;
        if (!d)
            return [];
        d.rev;
        d.structRev;
        var out = [];
        var leaves = d.leafList || [];
        var hidden = layerRoot.booleanLeafIds();
        for (var i = 0; i < leaves.length; i++) {
            var n = leaves[i];
            if (!n || n.kind !== "shape")
                continue;
            if (hidden[n.uid])
                continue;
            if (n.isMask === true)
                continue;
            var mids = d.maskUidsForLeaf(n.uid);
            if (!mids || mids.length === 0)
                continue;
            out.push({
                uid: n.uid,
                z: n.zOrder
            });
        }
        return out;
    }

    // Live mask maps for one leaf uid. Reads mask node props through
    // previewMap, so animation writes retrace the binding per frame.
    function maskMapsFor(uid) {
        var d = layerRoot.doc;
        if (!d)
            return [];
        d.rev;
        d.structRev;
        var mids = d.maskUidsForLeaf(uid);
        if (!mids || mids.length === 0)
            return [];
        var out = [];
        for (var k = 0; k < mids.length; k++) {
            var mn = d.findNode(mids[k]);
            if (mn)
                out.push(layerRoot.previewMap(mn));
        }
        return out;
    }

    x: layerRoot.offsetX
    y: layerRoot.offsetY
    scale: layerRoot.zoom
    transformOrigin: Item.TopLeft
    // Explicit scene size: blur effects sample this layer as a texture
    // and scale the source to the effect rect, so a 0-size source would
    // sample empty. Children already live in these content coords.
    width: layerRoot.doc ? layerRoot.doc.sceneWidth : 0
    height: layerRoot.doc ? layerRoot.doc.sceneHeight : 0

    Rectangle {
        width: layerRoot.doc ? layerRoot.doc.sceneWidth : 0
        height: layerRoot.doc ? layerRoot.doc.sceneHeight : 0
        visible: layerRoot.doc !== null
        color: layerRoot.doc ? layerRoot.doc.sceneColor : "transparent"
    }

    Repeater {
        model: layerRoot.doc ? layerRoot.doc.leafList : null

        onItemAdded: (index, item) => {
            item.zoom = Qt.binding(() => layerRoot.zoom);
            item.activatePolicy = () => layerRoot.activatePolicy();
            item.pressPolicy = (uid, mods) => layerRoot.pressPolicy(uid, mods);
            item.movePolicy = (dx, dy) => layerRoot.movePolicy(dx, dy);
            item.releasePolicy = (wasMoved, mods) => layerRoot.releasePolicy(wasMoved, mods);
            item.doublePolicy = uid => layerRoot.doublePolicy(uid);
            item.measurePolicy = (uid, w, h) => {
                if (layerRoot.measurePolicy)
                    layerRoot.measurePolicy(uid, w, h);
            };
            item.editing = Qt.binding(() => layerRoot.editingUid === item.uid);
            item.shapeVisible = Qt.binding(() => {
                if (layerRoot.doc)
                    layerRoot.doc.rev;
                var n = layerRoot.doc ? layerRoot.doc.findNode(item.uid) : null;
                return n ? layerRoot.doc.isEffectivelyVisible(n) : true;
            });
            item.shapeLocked = Qt.binding(() => {
                if (layerRoot.doc)
                    layerRoot.doc.rev;
                var m = layerRoot.doc ? layerRoot.doc.findNode(item.uid) : null;
                return m ? layerRoot.doc.isEffectivelyLocked(m) : false;
            });
            item.selected = Qt.binding(() => {
                if (layerRoot.doc)
                    layerRoot.doc.rev;
                var s = layerRoot.doc ? layerRoot.doc.findNode(item.uid) : null;
                if (!s)
                    return false;
                if (s.selected)
                    return true;
                var path = layerRoot.doc.drillPath;
                var hit = layerRoot.doc._find(item.uid);
                if (hit) {
                    for (var i = hit.ancestors.length - 1; i >= 0; i--) {
                        if (hit.ancestors[i].selected)
                            return path.indexOf(hit.ancestors[i].uid) >= 0;
                    }
                }
                return false;
            });
            item.isMaskedContent = Qt.binding(() => {
                if (layerRoot.doc) {
                    layerRoot.doc.rev;
                    layerRoot.doc.structRev;
                }
                var n = layerRoot.doc ? layerRoot.doc.findNode(item.uid) : null;
                if (!n || n.kind !== "shape" || n.isMask === true)
                    return false;
                return layerRoot.doc ? layerRoot.doc.isMaskedLeaf(item.uid) : false;
            });
        }

        ShapeItem {
            uid: modelData.uid
            shapeType: modelData.shapeType
            sx: modelData.x
            sy: modelData.y
            sw: modelData.w
            sh: modelData.h
            shapeRotation: modelData.rotation
            fills: modelData.fills ?? []
            strokes: modelData.strokes ?? []
            penFill: modelData.penFill !== false
            strokeCap: modelData.strokeCap || "round"
            strokeJoin: modelData.strokeJoin || "round"
            shadows: modelData.shadows ?? []
            layerBlur: modelData.layerBlur
            backgroundBlur: modelData.backgroundBlur
            glows: modelData.glows ?? []
            grain: modelData.grain
            grainFrame: layerRoot.grainFrame
            backdropItem: layerRoot.backdropItem
            isBackdropCapture: layerRoot.hideBlurShapes
            shapeOpacity: modelData.opacity
            isMaskShape: modelData.isMask === true
            radius: modelData.radius
            independentCorners: modelData.independentCorners === true
            cornerRadii: modelData.cornerRadii || []
            points: modelData.points
            pathData: modelData.pathData || []
            flipH: modelData.flipH
            flipV: modelData.flipV
            paintDepth: modelData.zOrder
            imageSource: modelData.imageSource ?? ""
            textContent: modelData.textContent !== undefined ? modelData.textContent : ""
            fontFamily: modelData.fontFamily || "Inter"
            fontWeight: modelData.fontWeight || 400
            fontSize: modelData.fontSize || 16
            lineHeightAuto: modelData.lineHeightAuto !== false
            lineHeight: modelData.lineHeight || 1.2
            letterSpacing: modelData.letterSpacing || 0
            hAlign: modelData.hAlign || "left"
            vAlign: modelData.vAlign || "top"
            autoSize: modelData.autoSize !== false
            isBooleanChild: layerRoot.isBooleanLeaf(modelData.uid)
        }
    }

    // Paintable plain groups (any depth): groups carrying fills,
    // strokes, shadows or glows paint a rounded-rect frame behind their
    // children through the shared CPU stack. Children paint and
    // hit-test as usual; the frame sits just below its lowest child.
    // Grain and background blur have no frame path and stay hidden in
    // the panel, so preview matches export by construction.
    function frameHasPaint(g) {
        if (!g)
            return false;
        var fills = g.fills || [];
        for (var i = 0; i < fills.length; i++) {
            if (fills[i] && fills[i].enabled !== false)
                return true;
        }
        var strokes = g.strokes || [];
        for (var j = 0; j < strokes.length; j++) {
            if (strokes[j] && strokes[j].enabled !== false && Number(strokes[j].width) > 0)
                return true;
        }
        var shadows = g.shadows || [];
        for (var k = 0; k < shadows.length; k++) {
            if (shadows[k] && shadows[k].enabled !== false)
                return true;
        }
        var glows = g.glows || [];
        for (var m = 0; m < glows.length; m++) {
            if (glows[m] && glows[m].enabled !== false)
                return true;
        }
        return false;
    }

    function frameGroups() {
        var d = layerRoot.doc;
        if (!d)
            return [];
        d.rev;
        d.structRev;
        var out = [];
        var all = d._allNodes();
        for (var i = 0; i < all.length; i++) {
            var n = all[i];
            if (n && n.kind === "group" && (n.boolOp === undefined || n.boolOp === "none") && layerRoot.frameHasPaint(n))
                out.push(n);
        }
        return out;
    }

    function frameBounds(uid) {
        var d = layerRoot.doc;
        if (!d)
            return null;
        d.rev;
        var g = d.findNode(uid);
        if (!g)
            return null;
        var b = d.bboxOfNode(g);
        if (!b || !(b.w > 0.01) || !(b.h > 0.01))
            return null;
        return b;
    }

    // Frame paints just below its lowest child (group leaves are
    // contiguous in z, so min - 0.5 interleaves with siblings).
    function framePaintZ(uid) {
        var d = layerRoot.doc;
        if (!d)
            return 0;
        d.rev;
        d.structRev;
        var g = d.findNode(uid);
        if (!g)
            return 0;
        var leaves = d._leavesUnder(g);
        var z = Infinity;
        for (var i = 0; i < leaves.length; i++) {
            if (leaves[i].zOrder < z)
                z = leaves[i].zOrder;
        }
        return z === Infinity ? 0 : z - 0.5;
    }

    // CPU preview for live boolean groups (one item per group at the
    // topmost child depth). Children stay hit-testable but hidden via
    // isBooleanChild; this delegate paints the combined silhouette
    // through the shared effect stack so preview matches export.
    Repeater {
        model: layerRoot.booleanGroups()

        BooleanGroupItem {
            readonly property int groupUid: modelData.uid
            readonly property var groupNode: layerRoot.doc ? layerRoot.doc.findNode(groupUid) : null
            readonly property var kidMaps: layerRoot.booleanChildrenMaps(groupUid)
            readonly property var boundRect: layerRoot.booleanBounds(groupUid)

            x: (boundRect ? boundRect.x : 0) - pad
            y: (boundRect ? boundRect.y : 0) - pad
            width: Math.max(1, (boundRect ? boundRect.width : 1) + pad * 2)
            height: Math.max(1, (boundRect ? boundRect.height : 1) + pad * 2)
            z: layerRoot.booleanPaintZ(groupUid)
            visible: {
                if (layerRoot.doc)
                    layerRoot.doc.rev;
                return groupNode ? layerRoot.doc.isEffectivelyVisible(groupNode) : false;
            }
            opacity: groupNode ? (groupNode.opacity ?? 1) : 1
            childMaps: kidMaps
            boolOp: groupNode ? (groupNode.boolOp || "union") : "union"
            boundX: boundRect ? boundRect.x : 0
            boundY: boundRect ? boundRect.y : 0
            fills: groupNode ? (groupNode.fills ?? []) : []
            strokes: groupNode ? (groupNode.strokes ?? []) : []
            shadows: groupNode ? (groupNode.shadows ?? []) : []
            layerBlur: groupNode ? groupNode.layerBlur : null
            glows: groupNode ? (groupNode.glows ?? []) : []
            grain: groupNode ? groupNode.grain : null
            targetUid: groupUid
            grainFrame: layerRoot.grainFrame
        }
    }

    // Frame backgrounds for paintable plain groups (one rounded rect
    // behind the children at the derived box).
    Repeater {
        model: layerRoot.frameGroups()

        EffectItem {
            readonly property int groupUid: modelData.uid
            readonly property var groupNode: layerRoot.doc ? layerRoot.doc.findNode(groupUid) : null
            readonly property var boundRect: layerRoot.frameBounds(groupUid)

            x: (boundRect ? boundRect.x : 0) - pad
            y: (boundRect ? boundRect.y : 0) - pad
            width: Math.max(1, (boundRect ? boundRect.width : 1) + pad * 2)
            height: Math.max(1, (boundRect ? boundRect.height : 1) + pad * 2)
            z: layerRoot.framePaintZ(groupUid)
            visible: {
                if (layerRoot.doc)
                    layerRoot.doc.rev;
                return boundRect && groupNode ? layerRoot.doc.isEffectivelyVisible(groupNode) : false;
            }
            opacity: groupNode ? (groupNode.opacity ?? 1) : 1
            shapeType: "rectangle"
            boxW: boundRect ? boundRect.width : 1
            boxH: boundRect ? boundRect.height : 1
            radius: groupNode ? (groupNode.radius ?? 0) : 0
            independentCorners: groupNode ? groupNode.independentCorners === true : false
            cornerRadii: groupNode ? (groupNode.cornerRadii || []) : []
            fills: groupNode ? (groupNode.fills ?? []) : []
            strokes: groupNode ? (groupNode.strokes ?? []) : []
            penFill: true
            strokeCap: groupNode ? (groupNode.strokeCap || "round") : "round"
            strokeJoin: groupNode ? (groupNode.strokeJoin || "round") : "round"
            shadows: groupNode ? (groupNode.shadows ?? []) : []
            layerBlur: groupNode ? (groupNode.layerBlur ?? {}) : ({})
            backgroundBlur: groupNode ? (groupNode.backgroundBlur ?? {}) : ({})
            glows: groupNode ? (groupNode.glows ?? []) : []
        }
    }

    // CPU preview for masked leaves (one scene-sized item per masked
    // leaf at its own paintDepth, so z interleaves with GPU leaves).
    // Shares FramePaint with export, so preview matches video. The
    // model is structural only; leaf/mask maps bind live per delegate
    // (DocNode props are notifiable, so playback retargets per frame
    // without rebuilding delegates).
    Repeater {
        model: layerRoot.maskedStubs

        MaskLeafItem {
            x: 0
            y: 0
            width: layerRoot.doc ? layerRoot.doc.sceneWidth : 0
            height: layerRoot.doc ? layerRoot.doc.sceneHeight : 0
            z: modelData.z
            readonly property var leafNode: layerRoot.doc ? layerRoot.doc.findNode(modelData.uid) : null
            visible: {
                var d = layerRoot.doc;
                if (d)
                    d.rev;
                return leafNode ? (d ? d.isEffectivelyVisible(leafNode) : true) : false;
            }
            leaf: leafNode ? layerRoot.previewMap(leafNode) : ({})
            masks: layerRoot.maskMapsFor(modelData.uid)
            frameNo: layerRoot.grainFrame
        }
    }
}
