import QtQuick
import Totm

// Miniature of a stored scene. Scales the full node tree to fit the
// tile, reusing ShapeItem so previews always match canvas rendering.
// Purely visual: the card's own mouse area sits above and owns input.
Item {
    id: preview

    required property var scene

    readonly property real sceneW: preview.scene && preview.scene.sceneWidth > 0 ? preview.scene.sceneWidth : 1920
    readonly property real sceneH: preview.scene && preview.scene.sceneHeight > 0 ? preview.scene.sceneHeight : 1080
    readonly property real fit: Math.min(preview.width / preview.sceneW, preview.height / preview.sceneH)
    readonly property var leaves: preview.collectLeaves()

    clip: true

    function collectLeaves() {
        var s = preview.scene;
        if (!s || !s.nodes)
            return [];
        var out = [];
        var walk = list => {
            for (var i = 0; i < list.length; i++) {
                var n = list[i];
                if (!n)
                    continue;
                if (n.kind === "group") {
                    walk(n.children || []);
                } else if (n.visible !== false) {
                    out.push(n);
                    if (out.length >= 150)
                        return;
                }
            }
        };
        walk(s.nodes);
        return out;
    }

    Rectangle {
        anchors.centerIn: parent
        width: preview.sceneW * preview.fit
        height: preview.sceneH * preview.fit
        color: preview.scene && preview.scene.sceneColor !== undefined ? preview.scene.sceneColor : "#ffffff"

        Repeater {
            model: preview.leaves

            delegate: Item {
                // Scene coords scaled down to the tile.
                scale: preview.fit
                transformOrigin: Item.TopLeft

                ShapeItem {
                    uid: -1
                    shapeType: modelData.type || "rectangle"
                    sx: modelData.x || 0
                    sy: modelData.y || 0
                    sw: Math.max(1, modelData.w || 10)
                    sh: Math.max(1, modelData.h || 10)
                    shapeRotation: modelData.rotation || 0
                    fill: modelData.fill || "#d9d9d9"
                    strokeColor: modelData.stroke || "#000000"
                    strokeWidth: modelData.strokeWidth || 0
                    shapeOpacity: modelData.opacity !== undefined ? modelData.opacity : 1
                    radius: modelData.radius || 0
                    points: modelData.points || 5
                    flipH: modelData.flipH === true
                    flipV: modelData.flipV === true
                    textContent: modelData.textContent !== undefined ? modelData.textContent : ""
                    fontFamily: modelData.fontFamily || "Inter"
                    fontWeight: modelData.fontWeight || 400
                    fontSize: modelData.fontSize || 16
                    lineHeightAuto: modelData.lineHeightAuto !== false
                    lineHeight: modelData.lineHeight || 1.2
                    letterSpacing: modelData.letterSpacing || 0
                    hAlign: modelData.hAlign || "left"
                    vAlign: modelData.vAlign || "top"
                    autoSize: modelData.autoSize === true
                    selected: false
                    shapeVisible: true
                    shapeLocked: false
                    paintDepth: 0
                    zoom: 1
                }
            }
        }
    }
}
