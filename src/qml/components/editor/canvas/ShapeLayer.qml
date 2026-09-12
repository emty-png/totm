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
    readonly property int grainFrame: layerRoot.doc && layerRoot.doc.anim ? Math.floor(Number(layerRoot.doc.anim.currentTime || 0) * 60) : 0

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
        }

        ShapeItem {
            uid: modelData.uid
            shapeType: modelData.shapeType
            sx: modelData.x
            sy: modelData.y
            sw: modelData.w
            sh: modelData.h
            shapeRotation: modelData.rotation
            fill: modelData.fill
            fillType: modelData.fillType ?? "solid"
            fillGradient: modelData.fillGradient
            strokeColor: modelData.stroke
            strokeType: modelData.strokeType ?? "solid"
            strokeGradient: modelData.strokeGradient
            strokeWidth: modelData.strokeWidth
            shadows: modelData.shadows ?? []
            layerBlur: modelData.layerBlur
            backgroundBlur: modelData.backgroundBlur
            glows: modelData.glows ?? []
            grain: modelData.grain
            grainFrame: layerRoot.grainFrame
            backdropItem: layerRoot.backdropItem
            isBackdropCapture: layerRoot.hideBlurShapes
            shapeOpacity: modelData.opacity
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
        }
    }
}
