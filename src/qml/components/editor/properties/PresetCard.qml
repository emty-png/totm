import QtQuick
import Totm

// One preset tile: looping live thumbnail on a gray swatch plus name.
// The thumbnail samples the real preset math (DocAnimSample) on a mini
// model, so previews match canvas playback. Play phase streams from the
// gallery's shared driver; clicks report preset, options, easing and
// loop through clickPolicy.
// Plain props with defaults (never required): Repeater delegates
// evaluate required bindings before the model context attaches, which
// breaks modelData reads. Same rule as LayersRow/TitleBarTab/DesignCard.
Item {
    id: card

    property string presetId: ""
    property string presetName: ""
    property var thumbOptions: null
    property var applyOptions: null
    property string easingId: "easeOut"
    // Loop for the applied clip (pulse cards repeat). Thumb plays one
    // cycle like every other card; the canvas loops after applying.
    property string loop: "none"
    // Text mode renders a "Text" glyph thumb instead of the rectangle;
    // the frame math (position/opacity/scale) is shared.
    property bool textMode: false

    property var driver: null
    property var clickPolicy: null

    readonly property real phase: card.driver ? card.driver.phase : 0
    readonly property var frame: card.computeFrame()
    readonly property var baseLeaf: ({
            x: 12,
            y: 12,
            w: 56,
            h: 56,
            rotation: 0,
            opacity: 1
        })

    width: (parent.width - 8) / 2
    height: 118

    Column {
        anchors.fill: parent
        spacing: 6

        Rectangle {
            width: parent.width
            height: 96
            radius: AppTheme.radiusMedium
            color: tileMouse.containsMouse || tileMouse.pressed ? AppTheme.hover : AppTheme.surface
            border.width: 1
            border.color: AppTheme.fieldBorder

            Behavior on color {
                ColorAnimation {
                    duration: 100
                    easing.type: Easing.OutCubic
                }
            }

            // Swatch stage: fixed 80px box, clipped so slide presets
            // travel in from the tile edge like the canvas does.
            Item {
                anchors.centerIn: parent
                width: 80
                height: 80
                clip: true

                ShapeItem {
                    visible: !card.textMode
                    uid: -1
                    shapeType: "rectangle"
                    sx: card.frame.x !== undefined ? card.frame.x : 12
                    sy: card.frame.y !== undefined ? card.frame.y : 12
                    sw: Math.max(1, card.frame.w !== undefined ? card.frame.w : 56)
                    sh: Math.max(1, card.frame.h !== undefined ? card.frame.h : 56)
                    shapeRotation: card.frame.rotation !== undefined ? card.frame.rotation : 0
                    // Content gray, not chrome: previews mimic user shapes.
                    fills: [
                        {
                            enabled: true,
                            color: "#9a9a9a",
                            type: "solid",
                            opacity: 1
                        }
                    ]
                    strokes: []
                    shapeOpacity: card.frame.opacity !== undefined ? card.frame.opacity : 1
                    radius: 0
                    points: 5
                    flipH: false
                    flipV: false
                    selected: false
                    shapeVisible: true
                    shapeLocked: false
                    paintDepth: 0
                    zoom: 1
                }

                // Text thumb: glyph scales with the frame box (grow and
                // shrink read as font zoom), positioned and faded like
                // the rectangle above.
                Item {
                    visible: card.textMode
                    x: card.frame.x !== undefined ? card.frame.x : 12
                    y: card.frame.y !== undefined ? card.frame.y : 12
                    width: Math.max(1, card.frame.w !== undefined ? card.frame.w : 56)
                    height: Math.max(1, card.frame.h !== undefined ? card.frame.h : 56)
                    rotation: card.frame.rotation !== undefined ? card.frame.rotation : 0
                    transformOrigin: Item.Center
                    opacity: card.frame.opacity !== undefined ? card.frame.opacity : 1

                    TextGlyphs {
                        anchors.fill: parent
                        text: card.frame.textContent !== undefined ? card.frame.textContent : "Text"
                        color: AppTheme.foreground
                        family: "Inter"
                        weight: 600
                        size: 22 * (parent.width / 56)
                        halign: "center"
                        valign: "middle"
                        wrap: false
                        autoLeading: true
                        leading: 1.2
                    }
                }
            }
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: card.presetName
            font.pixelSize: 12
            elide: Text.ElideRight
            color: AppTheme.muted
        }
    }

    MouseArea {
        id: tileMouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (card.clickPolicy)
                card.clickPolicy(card.presetId, card.applyOptions, card.easingId, card.loop);
        }
    }

    function computeFrame() {
        if (!card.driver)
            return {};
        var e = sampler.easeValue(card.easingId, null, card.phase);
        // Typewriter thumbs need a text base (content to reveal); every
        // other preset samples the shared rectangle base.
        var base = card.baseLeaf;
        if (card.presetId === "type") {
            base = {
                x: 12,
                y: 12,
                w: 56,
                h: 56,
                rotation: 0,
                opacity: 1,
                shapeType: "text",
                fontSize: 22,
                textContent: "Text"
            };
        }
        return sampler.presetOverlay(card.presetId, "in", card.thumbOptions || {}, base, 40, 40, e, card.phase);
    }

    DocAnimSample {
        id: sampler
    }
}
