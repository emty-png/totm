import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

// Procedural monochrome film grain confined to the shape silhouette
// (fill plus stroke, like the export clip). Dots derive from an integer
// hash shared bit-for-bit with the C++ exporter (see
// Effects::grainHash), so preview matches video exactly; seed picks the
// frame's noise field, reseeding every frame while playing. Mask kinds:
// "rect" (uniform radius), "path" (vector outline) or "custom" (caller
// nests the white silhouette, e.g. glyphs, inside).
Item {
    id: overlay

    required property int uid
    required property int frameNo
    required property real amount
    required property real grainSize
    required property string maskKind
    property real maskRadius: 0
    property string maskPath: ""
    property real maskStroke: 0

    readonly property double seed: overlay.seedFor(overlay.uid, overlay.frameNo)

    default property alias maskContent: customMask.data

    // seedFor mirrors Effects::grainSeed (Math.imul keeps 32-bit wrap
    // exact; >>> 0 reinterprets as unsigned for the uint uniform).
    function seedFor(uid, frameNo) {
        return (Math.imul(uid, 73856093) ^ Math.imul(frameNo, 19349663)) >>> 0;
    }

    // Invisible but layer-backed like every mask source: MultiEffect
    // samples the layer texture, so no raw noise ever reaches the canvas.
    // Shaders ship precompiled (.qsb via qt_add_shaders): Qt6 resolves
    // these URLs beside this file, inline source is not supported.
    ShaderEffect {
        id: dots

        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true
        vertexShader: "grain.vert.qsb"
        fragmentShader: "grain.frag.qsb"
        property vector2d itemSize: Qt.vector2d(overlay.width, overlay.height)
        property double seed: overlay.seed
        property real amount: overlay.amount
        property real cellSize: Math.max(1, overlay.grainSize)
    }

    MultiEffect {
        anchors.fill: parent
        source: dots
        autoPaddingEnabled: false
        maskEnabled: true
        maskSource: silhouette
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }

    // White silhouette (fill plus stroke, matching the export clip).
    Item {
        id: silhouette

        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true

        Rectangle {
            anchors.fill: parent
            visible: overlay.maskKind === "rect"
            radius: Math.min(overlay.maskRadius, Math.min(overlay.width, overlay.height) / 2)
            color: "white"
            border.width: overlay.maskStroke
            border.color: "white"
        }

        Shape {
            anchors.fill: parent
            visible: overlay.maskKind === "path"
            antialiasing: true
            ShapePath {
                fillColor: "white"
                strokeColor: "white"
                strokeWidth: overlay.maskStroke
                joinStyle: ShapePath.RoundJoin
                capStyle: ShapePath.RoundCap
                PathSvg {
                    path: overlay.maskPath
                }
            }
        }

        Item {
            id: customMask

            anchors.fill: parent
            visible: overlay.maskKind === "custom"
        }
    }
}
