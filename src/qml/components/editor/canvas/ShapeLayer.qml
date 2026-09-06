import QtQuick
import Totm

// Scene contents for one canvas. Positions by pan offset and scales
// around top-left so screen = offset + zoom * local.
Item {
    id: layer

    required property var doc
    required property real zoom
    required property real offsetX
    required property real offsetY

    property var activatePolicy: null
    property var pressPolicy: null
    property var movePolicy: null
    property var releasePolicy: null
    property var doublePolicy: null

    x: layer.offsetX
    y: layer.offsetY
    scale: layer.zoom
    transformOrigin: Item.TopLeft

    Rectangle {
        width: layer.doc ? layer.doc.sceneWidth : 0
        height: layer.doc ? layer.doc.sceneHeight : 0
        visible: layer.doc !== null
        color: layer.doc ? layer.doc.sceneColor : "transparent"
    }

    Repeater {
        model: layer.doc ? layer.doc.leafList : null

        onItemAdded: (index, item) => {
            item.zoom = Qt.binding(() => layer.zoom);
            item.activatePolicy = () => layer.activatePolicy();
            item.pressPolicy = (uid, mods) => layer.pressPolicy(uid, mods);
            item.movePolicy = (dx, dy) => layer.movePolicy(dx, dy);
            item.releasePolicy = (wasMoved, mods) => layer.releasePolicy(wasMoved, mods);
            item.doublePolicy = uid => layer.doublePolicy(uid);
            item.shapeVisible = Qt.binding(() => {
                layer.doc.rev;
                var n = layer.doc ? layer.doc.findNode(item.uid) : null;
                return n ? layer.doc.isEffectivelyVisible(n) : true;
            });
            item.shapeLocked = Qt.binding(() => {
                layer.doc.rev;
                var m = layer.doc ? layer.doc.findNode(item.uid) : null;
                return m ? layer.doc.isEffectivelyLocked(m) : false;
            });
            item.selected = Qt.binding(() => {
                layer.doc.rev;
                var s = layer.doc ? layer.doc.findNode(item.uid) : null;
                if (!s)
                    return false;
                if (s.selected)
                    return true;
                var path = layer.doc.drillPath;
                var hit = layer.doc._find(item.uid);
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
            strokeColor: modelData.stroke
            strokeWidth: modelData.strokeWidth
            shapeOpacity: modelData.opacity
            radius: modelData.radius
            paintDepth: modelData.zOrder
        }
    }
}
