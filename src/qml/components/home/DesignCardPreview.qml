import QtQuick
import Totm

// Miniature of a stored scene. Scales the full node tree to fit the
// tile, reusing ShapeItem so previews always match canvas rendering.
// Purely visual: the card's own mouse area sits above and owns input.
// Single ancestor scale keeps text/effects crisp; a hidden backdrop
// duplicate feeds background-blur sampling like the canvas layers.
// fitContent zooms to the union box of visible leaves (padded) instead
// of the whole scene, so small tiles of sparse scenes stay legible;
// the home grid keeps the full-scene fit.
Item {
    id: preview

    required property var scene
    property bool fitContent: false

    readonly property real sceneW: preview.scene && preview.scene.sceneWidth > 0 ? preview.scene.sceneWidth : 1920
    readonly property real sceneH: preview.scene && preview.scene.sceneHeight > 0 ? preview.scene.sceneHeight : 1080
    readonly property var leaves: preview.collectLeaves()
    // Snapshot tree index for mask resolution ({byUid, kids}),
    // rebuilt with the scene. Mirrors the DocTree structure over
    // plain snapshot nodes.
    readonly property var treeIndex: preview.buildIndex()
    // Masked non-mask leaves (uid + paint depth matching the main
    // repeater), driving the MaskLeafItem repeater below.
    readonly property var maskedStubs: preview.collectMaskedStubs()
    // Union box of visible leaves with a 6% pad, or null when it cannot
    // apply (disabled, empty scene): callers fall back to full-scene fit.
    readonly property var contentBox: preview.fitContent ? preview.unionBox() : null
    readonly property real viewX: preview.contentBox ? preview.contentBox.x : 0
    readonly property real viewY: preview.contentBox ? preview.contentBox.y : 0
    readonly property real viewW: preview.contentBox ? preview.contentBox.w : preview.sceneW
    readonly property real viewH: preview.contentBox ? preview.contentBox.h : preview.sceneH
    readonly property real fit: Math.min(preview.width / preview.viewW, preview.height / preview.viewH)
    readonly property var backdropLeaves: preview.leaves.filter(n => !preview.isBackgroundBlurred(n))
    readonly property bool hasBackdrop: preview.backdropLeaves.length !== preview.leaves.length

    clip: true

    Rectangle {
        id: sceneBox

        anchors.centerIn: parent
        width: preview.viewW * preview.fit
        height: preview.viewH * preview.fit
        color: preview.scene && preview.scene.sceneColor !== undefined ? preview.scene.sceneColor : "#ffffff"
        clip: true

        // Scene-sized content scaled once: ShapeItems stay siblings so
        // paintDepth orders them exactly like the canvas layer. The
        // content-box offset pans the cropped region into view.
        Item {
            id: scaleRoot

            x: -preview.viewX * preview.fit
            y: -preview.viewY * preview.fit
            width: preview.sceneW
            height: preview.sceneH
            scale: preview.fit
            transformOrigin: Item.TopLeft
            enabled: false

            // Frosted-glass source (hidden when no blur needs it).
            // Carries the scene map as `doc` so ShapeItem resolves the
            // backdrop size the same way it does on the canvas.
            Item {
                id: backdropSrc

                property var doc: preview.scene

                width: preview.sceneW
                height: preview.sceneH
                z: -1
                visible: preview.hasBackdrop
                enabled: false

                Rectangle {
                    width: preview.sceneW
                    height: preview.sceneH
                    color: preview.scene && preview.scene.sceneColor !== undefined ? preview.scene.sceneColor : "#ffffff"
                }

                Repeater {
                    model: preview.backdropLeaves

                    ShapeItem {
                        uid: modelData.uid ?? -1
                        shapeType: modelData.type || "rectangle"
                        sx: modelData.x || 0
                        sy: modelData.y || 0
                        sw: Math.max(1, modelData.w || 10)
                        sh: Math.max(1, modelData.h || 10)
                        shapeRotation: modelData.rotation || 0
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
                        grainFrame: 0
                        isBackdropCapture: true
                        isMaskShape: modelData.isMask === true
                        isMaskedContent: preview.isMaskedUid(modelData.uid ?? -1)
                        shapeOpacity: modelData.opacity !== undefined ? modelData.opacity : 1
                        radius: modelData.radius || 0
                        independentCorners: modelData.independentCorners === true
                        cornerRadii: modelData.cornerRadii || []
                        points: modelData.points || 5
                        pathData: modelData.pathData || []
                        flipH: modelData.flipH === true
                        flipV: modelData.flipV === true
                        paintDepth: preview.backdropLeaves.length - index
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
                        interactive: false
                        selected: false
                        shapeVisible: true
                        shapeLocked: false
                        zoom: 1
                    }
                }
            }

            Repeater {
                model: preview.leaves

                ShapeItem {
                    uid: modelData.uid ?? -1
                    shapeType: modelData.type || "rectangle"
                    sx: modelData.x || 0
                    sy: modelData.y || 0
                    sw: Math.max(1, modelData.w || 10)
                    sh: Math.max(1, modelData.h || 10)
                    shapeRotation: modelData.rotation || 0
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
                    grainFrame: 0
                    backdropItem: preview.hasBackdrop ? backdropSrc : null
                    isBackdropCapture: false
                    isMaskShape: modelData.isMask === true
                    isMaskedContent: preview.isMaskedUid(modelData.uid ?? -1)
                    shapeOpacity: modelData.opacity !== undefined ? modelData.opacity : 1
                    radius: modelData.radius || 0
                    independentCorners: modelData.independentCorners === true
                    cornerRadii: modelData.cornerRadii || []
                    points: modelData.points || 5
                    pathData: modelData.pathData || []
                    flipH: modelData.flipH === true
                    flipV: modelData.flipV === true
                    paintDepth: preview.leaves.length - index
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
                    interactive: false
                    selected: false
                    shapeVisible: true
                    shapeLocked: false
                    zoom: 1
                }
            }

            // CPU preview for masked leaves (one scene-sized item per
            // masked leaf at its own paint depth, like the canvas
            // layer): masks never paint, masked content paints here.
            Repeater {
                model: preview.maskedStubs

                MaskLeafItem {
                    x: 0
                    y: 0
                    width: preview.sceneW
                    height: preview.sceneH
                    z: modelData.z
                    leaf: preview.previewMapFor(modelData.uid)
                    masks: preview.maskMapsFor(modelData.uid)
                    frameNo: 0
                }
            }
        }

        // Blank scenes keep their color but say so, so an empty
        // design never reads as a broken thumbnail.
        Column {
            anchors.centerIn: parent
            visible: preview.leaves.length === 0
            spacing: 4

            AppIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 22
                height: 22
                kind: "image"
                iconColor: AppTheme.muted
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Empty canvas")
                font.pixelSize: 11
                color: AppTheme.muted
            }
        }
    }

    // Top-first walk that hides a whole branch when any ancestor is
    // hidden, mirroring Document.isEffectivelyVisible over snapshots.
    // Pre-stack scenes carry single fill/stroke keys: fold them into
    // one-entry stacks so old library entries still paint (new code
    // writes stacks; the factory folds the same way for live nodes).
    function foldStacks(n) {
        if (!n || n.kind === "group")
            return n;
        if (n.fills !== undefined && n.strokes !== undefined)
            return n;
        var c = Object.assign({}, n);
        if (c.fills === undefined) {
            if (c.fill !== undefined || c.fillType !== undefined || c.fillGradient !== undefined) {
                c.fills = [
                    {
                        enabled: true,
                        color: c.fill ?? "#d9d9d9",
                        type: c.fillType ?? "solid",
                        gradient: c.fillGradient,
                        opacity: 1
                    }
                ];
            } else {
                c.fills = [
                    {
                        enabled: true,
                        color: "#d9d9d9",
                        type: "solid",
                        opacity: 1
                    }
                ];
            }
        }
        if (c.strokes === undefined) {
            if (c.stroke !== undefined || c.strokeType !== undefined || c.strokeWidth !== undefined || c.strokeDash !== undefined || c.strokeGradient !== undefined) {
                c.strokes = [
                    {
                        enabled: true,
                        color: c.stroke ?? "#000000",
                        type: c.strokeType ?? "solid",
                        gradient: c.strokeGradient,
                        width: c.strokeWidth ?? 0,
                        dash: c.strokeDash,
                        position: "center",
                        opacity: 1
                    }
                ];
            } else {
                c.strokes = [
                    {
                        enabled: true,
                        color: "#000000",
                        type: "solid",
                        width: 0,
                        position: "center",
                        opacity: 1
                    }
                ];
            }
        }
        return c;
    }

    function collectLeaves() {
        var s = preview.scene;
        if (!s || !s.nodes)
            return [];
        var out = [];
        var walk = (list, hiddenAbove) => {
            if (!list)
                return;
            for (var i = 0; i < list.length && out.length < 150; i++) {
                var n = list[i];
                if (!n)
                    continue;
                var hidden = hiddenAbove || n.visible === false;
                if (hidden)
                    continue;
                if (n.kind === "group")
                    walk(n.children || [], false);
                else
                    out.push(preview.foldStacks(n));
            }
        };
        walk(s.nodes, false);
        return out;
    }

    function isBackgroundBlurred(n) {
        var kind = (n && (n.type || n.shapeType)) || "";
        if (kind === "text")
            return false;
        var b = n ? n.backgroundBlur : null;
        return !!b && b.enabled === true && Number(b.radius) > 0;
    }

    // Snapshot tree index: uid -> {node, parentUid, index} plus
    // per-parent child lists ("root" for top level). Skips hidden
    // branches and caps at 150 leaves, like collectLeaves.
    function buildIndex() {
        var byUid = {};
        var kids = {
            "root": []
        };
        var s = preview.scene;
        if (!s || !s.nodes)
            return {
                byUid: byUid,
                kids: kids
            };
        var leaves = 0;
        var walk = (list, parentUid) => {
            if (!list || leaves >= 150)
                return;
            var arr = [];
            for (var i = 0; i < list.length && leaves < 150; i++) {
                var n = list[i];
                if (!n || n.visible === false)
                    continue;
                var entry = {
                    node: n,
                    parentUid: parentUid,
                    index: arr.length
                };
                arr.push(entry);
                byUid[n.uid] = entry;
                if (n.kind === "group")
                    walk(n.children || [], n.uid);
                else
                    leaves++;
            }
            kids[parentUid] = arr;
        };
        walk(s.nodes, "root");
        return {
            byUid: byUid,
            kids: kids
        };
    }

    // Nearest mask below branchIndex in a top-first child list
    // (Figma segmentation, mirrors DocTree.maskBelowIn).
    function maskBelowIn(list, branchIndex) {
        var kids = list || [];
        for (var i = branchIndex + 1; i < kids.length; i++) {
            var n = kids[i] ? kids[i].node : null;
            if (n && n.kind === "shape" && n.isMask === true)
                return kids[i];
        }
        return null;
    }

    // All mask uids clipping the given leaf uid, walking up the
    // ancestor chain (nested masks intersect). Masks never clip
    // sibling masks at their own level. Mirrors DocTree.
    function maskUidsForUid(uid) {
        var idx = preview.treeIndex;
        var hit = idx.byUid[uid];
        if (!hit)
            return [];
        var out = [];
        var selfIsMask = hit.node.kind === "shape" && hit.node.isMask === true;
        var parentUid = hit.parentUid, branchIndex = hit.index, level = 0;
        while (true) {
            if (!(level === 0 && selfIsMask)) {
                var m = preview.maskBelowIn(idx.kids[parentUid] || [], branchIndex);
                if (m)
                    out.push(m.node.uid);
            }
            if (parentUid === "root")
                break;
            var parentHit = idx.byUid[parentUid];
            if (!parentHit)
                break;
            branchIndex = parentHit.index;
            parentUid = parentHit.parentUid;
            level++;
        }
        return out;
    }

    function isMaskedUid(uid) {
        return preview.maskUidsForUid(uid).length > 0;
    }

    function collectMaskedStubs() {
        var out = [];
        var leaves = preview.leaves;
        for (var i = 0; i < leaves.length; i++) {
            var n = leaves[i];
            if (!n || n.kind === "group" || n.isMask === true)
                continue;
            if (preview.maskUidsForUid(n.uid).length === 0)
                continue;
            out.push({
                uid: n.uid,
                z: leaves.length - i
            });
        }
        return out;
    }

    function leafByUid(uid) {
        var leaves = preview.leaves;
        for (var i = 0; i < leaves.length; i++) {
            if (leaves[i] && leaves[i].uid === uid)
                return leaves[i];
        }
        return null;
    }

    // Plain sampled map for the CPU mask preview (same keys as the
    // canvas previewMap / export snapshots).
    function previewMapFor(uid) {
        var n = preview.leafByUid(uid);
        if (!n)
            return ({});
        return {
            uid: n.uid,
            type: n.type || n.shapeType || "rectangle",
            shapeType: n.type || n.shapeType || "rectangle",
            x: n.x || 0,
            y: n.y || 0,
            w: Math.max(1, n.w || 10),
            h: Math.max(1, n.h || 10),
            rotation: n.rotation || 0,
            opacity: n.opacity !== undefined ? n.opacity : 1,
            visible: n.visible !== false,
            fills: n.fills ?? [],
            strokes: n.strokes ?? [],
            shadows: n.shadows ?? [],
            glows: n.glows ?? [],
            layerBlur: n.layerBlur,
            backgroundBlur: n.backgroundBlur,
            grain: n.grain,
            radius: n.radius || 0,
            independentCorners: n.independentCorners === true,
            cornerRadii: n.cornerRadii || [],
            points: n.points || 5,
            pathData: n.pathData || [],
            flipH: n.flipH === true,
            flipV: n.flipV === true,
            imageSource: n.imageSource ?? "",
            textContent: n.textContent !== undefined ? n.textContent : "",
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

    function maskMapsFor(uid) {
        var out = [];
        var mids = preview.maskUidsForUid(uid);
        for (var k = 0; k < mids.length; k++)
            out.push(preview.previewMapFor(mids[k]));
        return out;
    }

    // Union box of the visible leaves (rotation ignored, like the
    // selection bbox), padded 6% and floored at 1px. Null when empty so
    // the empty-canvas placeholder keeps the full-scene fit.
    function unionBox() {
        var leaves = preview.leaves;
        if (leaves.length === 0)
            return null;
        var x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        for (var i = 0; i < leaves.length; i++) {
            var n = leaves[i] || {};
            var x = Number(n.x) || 0, y = Number(n.y) || 0;
            var w = Math.max(1, Number(n.w) || 0), h = Math.max(1, Number(n.h) || 0);
            if (x < x0)
                x0 = x;
            if (y < y0)
                y0 = y;
            if (x + w > x1)
                x1 = x + w;
            if (y + h > y1)
                y1 = y + h;
        }
        var pad = Math.max((x1 - x0) * 0.06, (y1 - y0) * 0.06, 8);
        return {
            x: x0 - pad,
            y: y0 - pad,
            w: Math.max(1, (x1 - x0) + pad * 2),
            h: Math.max(1, (y1 - y0) + pad * 2)
        };
    }
}
