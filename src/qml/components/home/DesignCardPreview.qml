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
