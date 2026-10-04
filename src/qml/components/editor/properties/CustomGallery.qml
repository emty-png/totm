import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Custom animation gallery: grouped Add list (Transform / Style / Other
// plus motion Path) with existing custom clips below. From-to clips reuse
// the preset pipeline; Path enters canvas draw mode through drawPolicy.
// Seeded from the live selection so new clips start jump-free.
ScrollView {
    id: gallery

    required property var doc

    property var drawPolicy: null
    // Cascade offset for multi-selections, like the preset gallery.
    property real stagger: 0

    readonly property var defaults: DocCustomDefaults {}

    contentWidth: availableWidth
    clip: true

    Column {
        width: gallery.availableWidth
        spacing: 0

        // Breathing room below the switcher divider (matches the 12px
        // rhythm between sections); without it the first title sits
        // flush against the top edge.
        Item {
            width: parent.width
            height: 12
        }

        Text {
            visible: !gallery.hasSelection()
            width: parent.width - 32
            x: 16
            text: qsTr("Select a shape on the canvas to add a custom animation.")
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            color: AppTheme.muted
        }

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

                Text {
                    width: parent.width - 24
                    x: 12
                    text: modelData.title
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    color: AppTheme.foreground
                }

                Column {
                    width: parent.width - 24
                    x: 12
                    spacing: 2

                    Repeater {
                        model: modelData.rows

                        Rectangle {
                            width: parent.width
                            height: 34
                            radius: AppTheme.radiusSmall
                            color: rowMouse.containsMouse || rowMouse.pressed ? AppTheme.hover : "transparent"

                            Behavior on color {
                                ColorAnimation {
                                    duration: 100
                                    easing.type: Easing.OutCubic
                                }
                            }

                            RowLayout {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: 10
                                    rightMargin: 10
                                }
                                spacing: 8

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                    color: AppTheme.foreground
                                }

                                Text {
                                    visible: modelData.id === "customPath"
                                    text: qsTr("Draw")
                                    font.pixelSize: 11
                                    color: AppTheme.muted
                                }
                            }

                            MouseArea {
                                id: rowMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: gallery.activateRow(modelData)
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 12
                }
            }
        }

        Text {
            visible: gallery.hasSelection() && gallery.customCards().length > 0
            width: parent.width - 24
            x: 12
            text: qsTr("On this selection")
            font.pixelSize: 12
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            color: AppTheme.foreground
        }

        Item {
            visible: gallery.hasSelection() && gallery.customCards().length > 0
            width: parent.width
            height: 8
        }

        Column {
            width: parent.width - 24
            x: 12
            spacing: 8

            Repeater {
                model: gallery.customCards()

                Rectangle {
                    width: parent.width
                    height: 48
                    radius: AppTheme.radiusMedium
                    color: cardMouse.containsMouse || cardMouse.pressed ? AppTheme.hover : AppTheme.surface
                    border.width: 1
                    border.color: AppTheme.fieldBorder

                    Behavior on color {
                        ColorAnimation {
                            duration: 100
                            easing.type: Easing.OutCubic
                        }
                    }

                    Column {
                        anchors {
                            left: parent.left
                            right: deleteButton.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: 12
                            rightMargin: 8
                        }
                        spacing: 2

                        Text {
                            width: parent.width
                            text: modelData.name
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            color: AppTheme.foreground
                        }

                        Text {
                            width: parent.width
                            text: modelData.detail
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            color: AppTheme.muted
                        }
                    }

                    MouseArea {
                        id: cardMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (gallery.doc)
                                gallery.doc.selectClip(modelData.id, false);
                        }
                    }

                    PanelIconButton {
                        id: deleteButton

                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            rightMargin: 8
                        }
                        iconKind: "close"
                        filled: false
                        iconSize: 12
                        onClicked: {
                            if (gallery.doc)
                                gallery.doc.deleteClips([modelData.id]);
                        }
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: 12
        }
    }

    function sections() {
        var all = [
            {
                title: qsTr("Transform"),
                rows: [
                    {
                        id: "customScale",
                        name: qsTr("Scale"),
                        icon: "square"
                    },
                    {
                        id: "customRotate",
                        name: qsTr("Rotate"),
                        icon: "rotate"
                    },
                    {
                        id: "customMove",
                        name: qsTr("Move"),
                        icon: "cursor"
                    },
                    {
                        id: "customFontSize",
                        name: qsTr("Font size"),
                        icon: "text"
                    },
                    {
                        id: "customFontWeight",
                        name: qsTr("Font weight"),
                        icon: "text"
                    }
                ]
            },
            {
                title: qsTr("Style"),
                rows: [
                    {
                        id: "customOpacity",
                        name: qsTr("Opacity"),
                        icon: "contrast"
                    },
                    {
                        id: "customColor",
                        name: qsTr("Color"),
                        icon: "apps"
                    },
                    {
                        id: "customGradient",
                        name: qsTr("Gradient"),
                        icon: "circle"
                    },
                    {
                        id: "customStrokeGradient",
                        name: qsTr("Stroke gradient"),
                        icon: "circle"
                    },
                    {
                        id: "customStrokeColor",
                        name: qsTr("Stroke color"),
                        icon: "pen"
                    }
                ]
            },
            {
                title: qsTr("Other"),
                rows: [
                    {
                        id: "customHide",
                        name: qsTr("Hide / Show"),
                        icon: "eye"
                    },
                    {
                        id: "customResize",
                        name: qsTr("Resize"),
                        icon: "maximize"
                    },
                    {
                        id: "customCorner",
                        name: qsTr("Corner Radius"),
                        icon: "corner"
                    },
                    {
                        id: "customStroke",
                        name: qsTr("Stroke"),
                        icon: "minimize"
                    },
                    {
                        id: "customFlip",
                        name: qsTr("Flip"),
                        icon: "flipH"
                    },
                    {
                        id: "customShadow",
                        name: qsTr("Shadow"),
                        icon: "square"
                    },
                    {
                        id: "customLayerBlur",
                        name: qsTr("Layer Blur"),
                        icon: "contrast"
                    },
                    {
                        id: "customBackgroundBlur",
                        name: qsTr("Background Blur"),
                        icon: "apps"
                    },
                    {
                        id: "customGlow",
                        name: qsTr("Glow"),
                        icon: "sun"
                    },
                    {
                        id: "customGrain",
                        name: qsTr("Grain"),
                        icon: "contrast"
                    }
                ]
            },
            {
                title: qsTr("Motion Path"),
                rows: [
                    {
                        id: "customPath",
                        name: qsTr("Path"),
                        icon: "pen"
                    }
                ]
            }
        ];
        // Videos paint decoded frames, so fill/stroke/text customs are
        // dead ends on them: hide those rows when every target is video
        // rather than minting no-op clips. Mixed selections keep them.
        if (gallery.allVideoTargets())
            return [gallery.videoSection()].concat(gallery.filterVideoRows(all));
        if (gallery.anyVideoTargets())
            return [gallery.videoSection()].concat(all);
        return all;
    }

    // Video section: footage-time templates plus Ken Burns, shown when
    // any selected leaf is video. Rows carry a variant; activation
    // builds specific options (freeze/scrub/reverse/boomerang/kenburns)
    // instead of the generic seed.
    function videoSection() {
        return {
            title: qsTr("Video"),
            rows: [
                {
                    id: "customVideoTime",
                    variant: "freeze",
                    name: qsTr("Freeze frame"),
                    icon: "pause"
                },
                {
                    id: "customVideoTime",
                    variant: "scrub",
                    name: qsTr("Scrub forward"),
                    icon: "film"
                },
                {
                    id: "customVideoTime",
                    variant: "reverse",
                    name: qsTr("Reverse"),
                    icon: "undo"
                },
                {
                    id: "customVideoTime",
                    variant: "boomerang",
                    name: qsTr("Boomerang"),
                    icon: "redo"
                },
                {
                    id: "customVideoZoom",
                    variant: "in",
                    name: qsTr("Zoom in"),
                    icon: "plus"
                },
                {
                    id: "customVideoZoom",
                    variant: "out",
                    name: qsTr("Zoom out"),
                    icon: "minimize"
                },
                {
                    id: "kenburns",
                    name: qsTr("Ken Burns"),
                    icon: "fit"
                }
            ]
        };
    }

    function anyVideoTargets() {
        var d = gallery.doc;
        if (!d)
            return false;
        var tops = d.selectedTops();
        if (tops.length === 0)
            return false;
        for (var i = 0; i < tops.length; i++) {
            var leaves = tops[i].kind === "group" ? d._leavesUnder(tops[i]) : [tops[i]];
            for (var j = 0; j < leaves.length; j++) {
                if (leaves[j].shapeType === "video")
                    return true;
            }
        }
        return false;
    }

    function firstVideoLeaf() {
        var d = gallery.doc;
        if (!d)
            return null;
        var tops = d.selectedTops();
        for (var i = 0; i < tops.length; i++) {
            var leaves = tops[i].kind === "group" ? d._leavesUnder(tops[i]) : [tops[i]];
            for (var j = 0; j < leaves.length; j++) {
                if (leaves[j].shapeType === "video")
                    return leaves[j];
            }
        }
        return null;
    }

    function allVideoTargets() {
        var d = gallery.doc;
        if (!d)
            return false;
        var tops = d.selectedTops();
        if (tops.length === 0)
            return false;
        for (var i = 0; i < tops.length; i++) {
            var leaves = tops[i].kind === "group" ? d._leavesUnder(tops[i]) : [tops[i]];
            if (leaves.length === 0)
                return false;
            for (var j = 0; j < leaves.length; j++) {
                if (leaves[j].shapeType !== "video")
                    return false;
            }
        }
        return true;
    }

    function filterVideoRows(all) {
        var dead = {
            "customColor": true,
            "customGradient": true,
            "customStroke": true,
            "customStrokeColor": true,
            "customStrokeGradient": true,
            "customFontSize": true,
            "customFontWeight": true
        };
        var out = [];
        for (var s = 0; s < all.length; s++) {
            var rows = [];
            var src = all[s].rows || [];
            for (var r = 0; r < src.length; r++) {
                if (!dead[src[r].id])
                    rows.push(src[r]);
            }
            if (rows.length > 0) {
                out.push({
                    title: all[s].title,
                    rows: rows
                });
            }
        }
        return out;
    }

    function activateRow(row) {
        var pid = typeof row === "string" ? row : (row ? row.id : "");
        var variant = (row && typeof row === "object") ? row.variant : undefined;
        if (pid === "customPath") {
            if (gallery.drawPolicy)
                gallery.drawPolicy();
            return;
        }
        if (pid === "kenburns") {
            gallery.applyKenBurns();
            return;
        }
        if (pid === "customVideoTime" && variant) {
            gallery.applyVideoTime(variant);
            return;
        }
        if (pid === "customVideoZoom" && variant) {
            gallery.applyVideoZoom(variant);
            return;
        }
        gallery.applyCustom(pid);
    }

    function round2(v) {
        return Math.round(Number(v) * 100) / 100;
    }

    // Footage-time template: builds variant-specific options (and keys
    // for boomerang) seeded from the first video leaf at the playhead.
    function applyVideoTime(variant) {
        var d = gallery.doc;
        if (!d)
            return;
        var tops = d.selectedTops();
        if (tops.length === 0)
            return;
        var leaf = gallery.firstVideoLeaf();
        if (!leaf)
            return;
        var t0 = d.anim.currentTime;
        var f = gallery.round2(gallery.defaults.footageNowAt(d, leaf, t0));
        var dur = Math.max(0, Number(leaf.videoDuration) || 0);
        var options = null;
        var clipDur = 1.6;
        if (variant === "freeze") {
            clipDur = 2.0;
            options = {
                from: f,
                to: f
            };
        } else if (variant === "reverse") {
            options = {
                from: f,
                to: gallery.round2(Math.max(0, f - 2))
            };
        } else if (variant === "boomerang") {
            var peak = dur > 0.05 ? Math.min(dur - 0.04, f + 1) : f + 1;
            peak = gallery.round2(Math.max(0, peak));
            // Degenerate at the tail (no room ahead): freeze instead of
            // a zero-width out-and-back.
            if (!(peak > f + 0.05)) {
                clipDur = 2.0;
                options = {
                    from: f,
                    to: f
                };
            } else {
                options = {
                    from: f,
                    to: f,
                    keys: [
                        {
                            t: 0,
                            value: {
                                v: f
                            },
                            easing: {
                                id: "easeInOut"
                            }
                        },
                        {
                            t: 0.5,
                            value: {
                                v: peak
                            },
                            easing: {
                                id: "easeInOut"
                            }
                        },
                        {
                            t: 1,
                            value: {
                                v: f
                            },
                            easing: {
                                id: "easeInOut"
                            }
                        }
                    ]
                };
            }
        } else {
            // Scrub forward (default): eased ramp over ~2s of footage,
            // freezing at the tail when nothing lies ahead.
            var end = dur > 0.05 ? Math.min(dur - 0.04, f + 2) : f + 2;
            end = gallery.round2(Math.max(0, end));
            options = {
                from: f,
                to: end > f + 0.05 ? end : f
            };
        }
        var uids = [];
        for (var i = 0; i < tops.length; i++)
            uids.push(tops[i].uid);
        var made = d.applyPreset("customVideoTime", uids, t0, clipDur, "in", options, null, gallery.stagger);
        if (made.length > 0) {
            d.anim.currentTime = t0;
            d.anim.play();
        }
    }

    // Video zoom template: content punch-in/out on the frame (box stays).
    // Seeded from the live zoom so the first frame never jumps.
    function applyVideoZoom(variant) {
        var d = gallery.doc;
        if (!d)
            return;
        var tops = d.selectedTops();
        if (tops.length === 0)
            return;
        var leaf = gallery.firstVideoLeaf();
        if (!leaf)
            return;
        var t0 = d.anim.currentTime;
        var cur = Math.min(8, Math.max(1, Number(leaf.videoZoom) || 1));
        var options = null;
        if (variant === "out")
            options = {
                from: gallery.round2(Math.max(1, cur)),
                to: 1,
                focusX: 0.5,
                focusY: 0.5
            };
        else
            options = {
                from: gallery.round2(cur),
                to: gallery.round2(Math.min(8, Math.max(cur, cur > 1 ? cur * 1.5 : 2))),
                focusX: 0.5,
                focusY: 0.5
            };
        var uids = [];
        for (var i = 0; i < tops.length; i++)
            uids.push(tops[i].uid);
        var made = d.applyPreset("customVideoZoom", uids, t0, 1.6, "in", options, null, gallery.stagger);
        if (made.length > 0) {
            d.anim.currentTime = t0;
            d.anim.play();
        }
    }

    // Ken Burns: slow zoom + drift from one transaction (scale and move
    // clips sharing t0/duration), seeded explicitly so images and video
    // alike start at their live look.
    function applyKenBurns() {
        var d = gallery.doc;
        if (!d)
            return;
        var tops = d.selectedTops();
        if (tops.length === 0)
            return;
        var uids = [];
        for (var i = 0; i < tops.length; i++)
            uids.push(tops[i].uid);
        var t0 = d.anim.currentTime;
        d.beginTransaction();
        var madeA = d.applyPreset("customScale", uids, t0, 3.0, "in", {
            from: 1,
            to: 1.15
        }, null, gallery.stagger);
        var madeB = d.applyPreset("customMove", uids, t0, 3.0, "in", {
            fromX: 0,
            fromY: 0,
            toX: -60,
            toY: -34
        }, null, 0);
        d.endTransaction();
        if (madeA.length + madeB.length > 0) {
            d.anim.currentTime = t0;
            d.anim.play();
        }
    }

    function applyCustom(presetId) {
        var d = gallery.doc;
        if (!d)
            return;
        var tops = d.selectedTops();
        if (tops.length === 0)
            return;
        var uids = [];
        for (var i = 0; i < tops.length; i++)
            uids.push(tops[i].uid);
        // Route solid rows to their gradient sibling when the target's
        // top entry is linear: a gradient fill/stroke would otherwise
        // land in a solid hex editor whose output stays invisible.
        var pid = presetId;
        if (pid === "customColor" && gallery.defaults.topFillType(d, tops) === "linear")
            pid = "customGradient";
        else if (pid === "customStrokeColor" && gallery.defaults.topStrokeType(d, tops) === "linear")
            pid = "customStrokeGradient";
        var options = gallery.defaults.seededOptions(d.anim.presets, d, tops, pid);
        var t0 = d.anim.currentTime;
        var made = d.applyPreset(pid, uids, t0, 0.8, "in", options, null, gallery.stagger);
        if (made.length > 0) {
            d.anim.currentTime = t0;
            d.anim.play();
        }
    }

    function customCards() {
        var d = gallery.doc;
        if (!d)
            return [];
        d.rev;
        d.anim.clipRev;
        var tops = d.selectedTops();
        var ids = {};
        for (var i = 0; i < tops.length; i++)
            ids[tops[i].uid] = true;
        var out = [];
        var clips = d.anim.clips;
        for (var j = 0; j < clips.length; j++) {
            if (!ids[clips[j].targetUid])
                continue;
            if (!d.anim.presets.isCustom(clips[j].preset))
                continue;
            var detail = clips[j].t0.toFixed(1) + "s – " + (clips[j].t0 + clips[j].duration).toFixed(1) + "s · " + d.anim.presets.easingName(clips[j].easing.id);
            if (d.anim.presets.isStepped(clips[j].preset))
                detail = qsTr("at %1s · Instant").arg(clips[j].t0.toFixed(1));
            out.push({
                id: clips[j].id,
                name: d.anim.presets.presetName(clips[j].preset) + d.anim.presets.entrySuffix(clips[j].preset, clips[j].options),
                detail: detail
            });
        }
        out.sort((a, b) => a.id - b.id);
        return out;
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
