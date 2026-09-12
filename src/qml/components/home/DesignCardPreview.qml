import QtQuick
import Totm

// Miniature of a stored scene. Scales the full node tree to fit the
// tile, reusing ShapeItem so previews always match canvas rendering.
// Purely visual: the card's own mouse area sits above and owns input.
// Single ancestor scale keeps text/effects crisp; a hidden backdrop
// duplicate feeds background-blur sampling like the canvas layers.
Item {
    id: preview

    required property var scene

    readonly property real sceneW: preview.scene && preview.scene.sceneWidth > 0 ? preview.scene.sceneWidth : 1920
    readonly property real sceneH: preview.scene && preview.scene.sceneHeight > 0 ? preview.scene.sceneHeight : 1080
    readonly property real fit: Math.min(preview.width / preview.sceneW, preview.height / preview.sceneH)
    readonly property var leaves: preview.collectLeaves()
    readonly property var backdropLeaves: preview.leaves.filter(n => !preview.isBackgroundBlurred(n))
    readonly property bool hasBackdrop: preview.backdropLeaves.length !== preview.leaves.length

    clip: true

    Rectangle {
        id: sceneBox

        anchors.centerIn: parent
        width: preview.sceneW * preview.fit
        height: preview.sceneH * preview.fit
        color: preview.scene && preview.scene.sceneColor !== undefined ? preview.scene.sceneColor : "#ffffff"
        clip: true

        // Scene-sized content scaled once: ShapeItems stay siblings so
        // paintDepth orders them exactly like the canvas layer.
        Item {
            id: scaleRoot

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
                        fill: modelData.fill || "#d9d9d9"
                        fillType: modelData.fillType || "solid"
                        fillGradient: modelData.fillGradient
                        strokeColor: modelData.stroke || "#000000"
                        strokeType: modelData.strokeType || "solid"
                        strokeGradient: modelData.strokeGradient
                        strokeWidth: modelData.strokeWidth || 0
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
                    fill: modelData.fill || "#d9d9d9"
                    fillType: modelData.fillType || "solid"
                    fillGradient: modelData.fillGradient
                    strokeColor: modelData.stroke || "#000000"
                    strokeType: modelData.strokeType || "solid"
                    strokeGradient: modelData.strokeGradient
                    strokeWidth: modelData.strokeWidth || 0
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
                    out.push(n);
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
}
