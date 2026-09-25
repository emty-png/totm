import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Preset gallery for the animate tab: category sections of live tiles.
// Clicking a tile applies the preset to the current selection at the
// playhead (0.8s, entrance) and starts playback from there. One shared
// phase driver loops all thumbnails; cards bind it directly like the
// FillSection delegates bind their section.
ScrollView {
    id: gallery

    required property var doc
    property bool playing: false
    // Stagger between targets when applying to a multi-selection:
    // each next shape starts this many seconds later (cascade).
    property real stagger: 0
    // Text mode: Basic/Slide/Scale sections for text selections. Slide
    // cards share the slide preset with fixed directions (the clip
    // editor still lets users retarget after applying).
    property bool textMode: false

    // Pick flow: opened from the shape panel, back returns there and a
    // successful apply reports through appliedPolicy (the new clip
    // selection routes onward to the clip editor).
    property bool showBack: false
    property var backPolicy: null
    property var appliedPolicy: null

    // Shared thumbnail clock: plays the effect, holds the base frame,
    // then loops. One driver for every card keeps thumbs in sync.
    property real phase: 0

    SequentialAnimation on phase {
        running: gallery.playing
        loops: Animation.Infinite

        NumberAnimation {
            from: 0
            to: 1
            duration: 1300
            easing.type: Easing.Linear
        }

        PauseAnimation {
            duration: 500
        }
    }

    contentWidth: availableWidth
    clip: true

    Column {
        width: gallery.availableWidth
        spacing: 0

        // Back to the shape panel when picking (hidden by default).
        RowLayout {
            visible: gallery.showBack
            width: parent.width
            height: visible ? 48 : 0
            spacing: 4

            Item {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                Layout.leftMargin: 4

                AppIcon {
                    anchors.centerIn: parent
                    kind: "caret"
                    rotation: 90
                    width: 14
                    height: 14
                    iconColor: galleryBackMouse.containsMouse || galleryBackMouse.pressed ? AppTheme.foreground : AppTheme.muted
                }

                MouseArea {
                    id: galleryBackMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (gallery.backPolicy)
                            gallery.backPolicy();
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                verticalAlignment: Text.AlignVCenter
                text: qsTr("Presets")
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                color: AppTheme.foreground
            }
        }

        Text {
            visible: !gallery.hasSelection()
            width: parent.width - 32
            x: 16
            text: gallery.textMode ? qsTr("Select text on the canvas to apply a preset.") : qsTr("Select a shape on the canvas to apply a preset.")
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            color: AppTheme.muted
        }

        // Cascade offset for multi-selections. Hidden for single
        // selections where it would do nothing.
        RowLayout {
            visible: gallery.hasMultiSelection()
            width: parent.width - 24
            x: 12
            spacing: 8

            Text {
                text: qsTr("Stagger")
                font.pixelSize: 11
                color: AppTheme.muted
            }

            NumberField {
                Layout.fillWidth: true
                suffix: qsTr("s")
                scrubStep: 0.05
                minimum: 0
                maximum: 1
                value: gallery.stagger
                onCommitted: v => gallery.stagger = v
            }
        }

        Repeater {
            model: gallery.sections()

            Column {
                width: parent.width
                spacing: 8
                visible: modelData.visible !== false

                Text {
                    visible: modelData.title !== ""
                    width: parent.width - 24
                    x: 12
                    text: modelData.title
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    color: AppTheme.foreground
                }

                Grid {
                    width: parent.width - 24
                    x: 12
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 12

                    Repeater {
                        model: modelData.cards

                        PresetCard {
                            presetId: modelData.id
                            presetName: modelData.name
                            thumbOptions: modelData.options
                            applyOptions: modelData.apply
                            textMode: gallery.textMode
                            easingId: modelData.easing
                            loop: modelData.loop || "none"
                            driver: gallery
                            clickPolicy: (presetId, apply, easingId, loop) => gallery.applyPreset(presetId, apply, easingId, loop)
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 12
                }
            }
        }

        Item {
            width: parent.width
            height: 12
        }
    }

    // Category sections with per-card thumbnail options (small travel
    // so slide presets stay inside the tile).
    function sections() {
        if (gallery.textMode) {
            return [
                {
                    title: qsTr("Basic"),
                    cards: [gallery.cardFor("appear", qsTr("Appear")), gallery.cardFor("fade", qsTr("Fade"))]
                },
                {
                    title: qsTr("Type"),
                    cards: [gallery.typeCard(qsTr("Type · Letters"), "letters"), gallery.typeCard(qsTr("Type · Words"), "words"), gallery.typeCard(qsTr("Type · Lines"), "lines")]
                },
                {
                    title: qsTr("Slide"),
                    cards: [gallery.textSlideCard(qsTr("Slide ↑"), "up"), gallery.textSlideCard(qsTr("Slide ↓"), "down"), gallery.textSlideCard(qsTr("Slide ←"), "left"), gallery.textSlideCard(qsTr("Slide →"), "right")]
                },
                {
                    title: qsTr("Scale"),
                    cards: [gallery.cardFor("grow", qsTr("Grow")), gallery.cardFor("shrink", qsTr("Shrink"))]
                },
                {
                    title: qsTr("Expressive"),
                    cards: [gallery.textBlurCard(), gallery.textWaveCard(), gallery.popCard()]
                }
            ];
        }
        return [
            {
                title: qsTr("Fade"),
                cards: [gallery.cardFor("fade", qsTr("Fade")), gallery.cardFor("slide", qsTr("Slide")), gallery.wipeCard()]
            },
            {
                title: qsTr("Scale"),
                cards: [gallery.cardFor("grow", qsTr("Grow")), gallery.cardFor("shrink", qsTr("Shrink"))]
            },
            {
                title: qsTr("Pop"),
                cards: [gallery.popCard(), gallery.bounceCard(), gallery.elasticCard()]
            },
            {
                title: qsTr("Soft"),
                cards: [gallery.blurInCard(), gallery.pulseCard()]
            },
            {
                title: "",
                cards: [gallery.cardFor("spin", qsTr("Spin")), gallery.cardFor("twist", qsTr("Twist")), gallery.cardFor("movescale", qsTr("Move & Scale"))]
            },
            {
                title: qsTr("Mask"),
                visible: gallery.maskTargetUids().length > 0,
                cards: [gallery.maskWipeCard(), gallery.maskIrisCard()]
            }
        ];
    }

    function cardFor(id, name) {
        var options = {};
        var easing = "easeOut";
        if (id === "slide")
            options = {
                direction: "left",
                distance: 34,
                fade: true
            };
        else if (id === "spin") {
            options = {
                direction: "cw",
                turns: 1
            };
            easing = "linear";
        } else if (id === "twist") {
            options = {
                direction: "cw"
            };
            easing = "easeInOut";
        } else if (id === "movescale")
            options = {
                direction: "left",
                distance: 34,
                scale: 0
            };
        return {
            id: id,
            name: name,
            options: options,
            easing: easing
        };
    }

    // Directional slide shortcut for the text gallery: thumbnail-only
    // travel plus the applied direction (distance/fade fall back to the
    // shared slide defaults, fade stays toggleable in the clip editor).
    function textSlideCard(name, direction) {
        return {
            id: "slide",
            name: name,
            options: {
                direction: direction,
                distance: 34,
                fade: true
            },
            apply: {
                direction: direction
            },
            easing: "easeOut"
        };
    }

    // Typewriter card per reveal unit. Thumbnail and apply share the
    // default 20 chars/sec; duration auto-sizes from the selection at
    // apply time (see applyPreset), the clip editor retimes after.
    function typeCard(name, unit) {
        return {
            id: "type",
            name: name,
            options: {
                unit: unit,
                cps: 20,
                cursor: false
            },
            apply: {
                unit: unit,
                cps: 20,
                cursor: false
            },
            easing: "linear"
        };
    }

    // Blur-in for text: whole-glyph layer blur relaxing to sharp.
    // Reuses the custom blur pipeline (preview and export already
    // paint it on text), so no new sampler math is needed.
    function textBlurCard() {
        return {
            id: "customLayerBlur",
            name: qsTr("Blur"),
            options: {
                fromRadius: 12,
                fromOpacity: 1,
                toRadius: 0,
                toOpacity: 1
            },
            apply: {
                fromRadius: 12,
                fromOpacity: 1,
                toRadius: 0,
                toOpacity: 1
            },
            easing: "easeOut"
        };
    }

    // Wave for text: whole-glyph rotation wobble (the twist preset).
    function textWaveCard() {
        return {
            id: "twist",
            name: qsTr("Wave"),
            options: {
                direction: "cw"
            },
            apply: {
                direction: "cw"
            },
            easing: "easeInOut"
        };
    }

    // Logo/UI pack, all reusing the preset pipeline (no new sampler
    // math): overshoot scales for pops, an unfaded slide for wipes, a
    // relaxing blur and a ping-pong opacity pulse for loops.
    function wipeCard() {
        return {
            id: "slide",
            name: qsTr("Wipe"),
            options: {
                direction: "left",
                distance: 34,
                fade: false
            },
            apply: {
                fade: false
            },
            easing: "easeOut"
        };
    }

    function popCard() {
        var o = {
            from: 0.5,
            to: 1
        };
        return {
            id: "customScale",
            name: qsTr("Pop"),
            options: o,
            apply: o,
            easing: "backOut"
        };
    }

    function bounceCard() {
        var o = {
            from: 0,
            to: 1
        };
        return {
            id: "customScale",
            name: qsTr("Bounce"),
            options: o,
            apply: o,
            easing: "bounceOut"
        };
    }

    function elasticCard() {
        var o = {
            from: 0,
            to: 1
        };
        return {
            id: "customScale",
            name: qsTr("Elastic"),
            options: o,
            apply: o,
            easing: "elasticOut"
        };
    }

    function blurInCard() {
        var o = {
            fromRadius: 12,
            fromOpacity: 1,
            toRadius: 0,
            toOpacity: 1
        };
        return {
            id: "customLayerBlur",
            name: qsTr("Blur in"),
            options: o,
            apply: o,
            easing: "easeOut"
        };
    }

    function pulseCard() {
        var o = {
            from: 0.25,
            to: 1
        };
        return {
            id: "customOpacity",
            name: qsTr("Pulse"),
            options: o,
            apply: o,
            easing: "easeInOut",
            loop: "pingpong"
        };
    }

    // Mask reveals: one-click wipe / iris on the selected masks. Thumb
    // and apply share plain options (direction + soft edge); the clip
    // editor retargets direction/feather/invert and holds keyframes.
    function maskWipeCard() {
        var o = {
            direction: "left",
            feather: 0,
            invert: false
        };
        return {
            id: "maskWipe",
            name: qsTr("Mask Wipe"),
            options: o,
            apply: o,
            easing: "easeOut",
            mask: true
        };
    }

    function maskIrisCard() {
        var o = {
            feather: 0,
            invert: false
        };
        return {
            id: "maskIris",
            name: qsTr("Mask Iris"),
            options: o,
            apply: o,
            easing: "easeOut",
            mask: true
        };
    }

    // Mask uids under the current selection: selected mask shapes plus
    // every direct mask of each selected group (stacked masks each own
    // a band). Mask cards apply here, never onto content (which would
    // squash instead of reveal).
    function maskTargetUids() {
        var d = gallery.doc;
        if (!d)
            return [];
        d.rev;
        var out = [];
        var tops = d.selectedTops();
        for (var i = 0; i < tops.length; i++) {
            var t = tops[i];
            if (t.kind === "shape" && t.isMask === true) {
                out.push(t.uid);
            } else if (t.kind === "group") {
                var kids = t.children || [];
                for (var k = 0; k < kids.length; k++) {
                    if (kids[k].kind === "shape" && kids[k].isMask === true)
                        out.push(kids[k].uid);
                }
            }
        }
        return out;
    }

    // Longest selected text length in chars (groups count their longest
    // leaf), for auto-sizing Type durations from chars/sec.
    function selectionTextLen() {
        var d = gallery.doc;
        if (!d)
            return 0;
        var best = 0;
        var tops = d.selectedTops();
        for (var i = 0; i < tops.length; i++) {
            var leaves = tops[i].kind === "group" ? d._leavesUnder(tops[i]) : [tops[i]];
            for (var j = 0; j < leaves.length; j++) {
                if (leaves[j].shapeType !== "text")
                    continue;
                var len = String(leaves[j].textContent || "").length;
                if (len > best)
                    best = len;
            }
        }
        return best;
    }

    function applyPreset(presetId, apply, easingId, loop) {
        var d = gallery.doc;
        if (!d)
            return;
        var uids = [];
        if (presetId === "maskWipe" || presetId === "maskIris") {
            // Mask reveals land on masks, never content: content would
            // squash its box instead of clipping the reveal.
            uids = gallery.maskTargetUids();
            if (uids.length === 0)
                return;
        } else {
            var tops = d.selectedTops();
            if (tops.length === 0)
                return;
            for (var i = 0; i < tops.length; i++)
                uids.push(tops[i].uid);
        }
        var t0 = d.anim.currentTime;
        var dur = 0.8;
        if (presetId === "type") {
            // cps paces the clip: duration covers the longest selection
            // at the card speed, so typing lands exactly at the tail.
            var cps = 20;
            if (apply && Number(apply.cps) > 0)
                cps = Math.min(120, Math.max(1, Number(apply.cps)));
            var len = gallery.selectionTextLen();
            dur = len > 0 ? Math.min(60, Math.max(0.5, len / cps)) : 0.8;
        }
        var easing = typeof easingId === "string" && easingId !== "" ? {
            id: easingId
        } : null;
        var made = d.applyPreset(presetId, uids, t0, dur, "in", apply || {}, easing, loop || "none", gallery.stagger);
        if (made.length > 0) {
            d.anim.currentTime = t0;
            d.anim.play();
            if (gallery.appliedPolicy)
                gallery.appliedPolicy();
        }
    }

    function hasSelection() {
        var d = gallery.doc;
        if (!d)
            return false;
        d.rev;
        return d.selectedTops().length > 0;
    }

    function hasMultiSelection() {
        var d = gallery.doc;
        if (!d)
            return false;
        d.rev;
        return d.selectedTops().length > 1;
    }
}
