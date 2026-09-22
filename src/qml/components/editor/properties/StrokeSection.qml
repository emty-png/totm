import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Stacked strokes per shape (Figma-style, index 0 paints topmost,
// above all fills). Each entry carries its own color/gradient,
// width, center/inside/outside position, opacity %, dash pair, eye
// toggle and order. Per-index values collect across the selection
// with mixed flags (see EffectShadowCard); edits apply where the
// index exists, adds apply to every leaf. On text the stroke
// outlines the glyphs; images paint stacked borders. Shapes only.
PanelSection {
    id: section

    required property var snapshot
    required property var doc

    // Picker entry being live-recolored. Drags stream committed()
    // between scrubStarted/scrubFinished so each gesture stays one
    // undo entry; typed hex commits discretely on its own.
    property int pickerStrokeIndex: -1

    // Widest stack in the selection; cards past a leaf's own length
    // show defaults with everything mixed and skip it on commit.
    readonly property int strokeCount: {
        var m = 0;
        var leaves = section.snapshot.selLeaves;
        for (var i = 0; i < leaves.length; i++) {
            var n = (leaves[i].strokes || []).length;
            if (n > m)
                m = n;
        }
        return m;
    }

    title: qsTr("Stroke")
    visible: section.snapshot.sel.length > 0 && !section.snapshot.hasGroup && !section.snapshot.allOfType("image")
    enabled: !section.snapshot.allLocked
    compact: section.strokeCount === 0
    showAdd: true
    showRemove: false
    onAddClicked: section.addStroke()

    Repeater {
        model: section.strokeCount

        onItemAdded: (at, item) => {
            item.section = section;
            item.entryIndex = at;
        }

        StrokeEntryCard {
            Layout.fillWidth: true
        }
    }

    // Picker flow: swatch seeds the popup, drags stream through one
    // scrub transaction, typed hex commits discretely on its own.
    // Solid picks land as solid (converting linear entries back);
    // gradient picks land as linear. Gradient tabs only for vector
    // shapes (glyph outlines stay solid).
    ColorPickerPopup {
        id: picker

        allowGradient: !section.snapshot.allOfType("text") && !section.snapshot.allOfType("image")
        onScrubStarted: section.snapshot.beginScrub()
        onCommitted: c => {
            if (section.pickerStrokeIndex >= 0)
                section.patchStrokeAt(section.pickerStrokeIndex, {
                    color: String(c),
                    type: "solid"
                });
        }
        onGradientCommitted: g => {
            if (section.pickerStrokeIndex >= 0)
                section.patchStrokeAt(section.pickerStrokeIndex, {
                    gradient: {
                        angle: Number(g.angle) || 0,
                        stops: [
                            {
                                color: String(g.stops[0].color),
                                pos: 0
                            },
                            {
                                color: String(g.stops[1].color),
                                pos: 1
                            }
                        ]
                    },
                    type: "linear"
                });
        }
        onScrubFinished: section.snapshot.endScrub()
    }

    function openStrokePickerAt(at, color, anchor, ax, ay) {
        section.pickerStrokeIndex = at;
        picker.openFor(color, anchor, ax, ay);
    }

    function openStrokeGradientPickerAt(at, anchor, ax, ay) {
        section.pickerStrokeIndex = at;
        var cur = section.collectStrokeAt(at).value.gradient ?? {};
        picker.openForGradient(cur, anchor, ax, ay);
    }

    // Advanced per-entry settings live in a popup behind the row's
    // ... button (Figma-style): color hex, type, angle, width,
    // position, dash style, order, delete. It opens below the button
    // when it fits, above otherwise, like the color picker. The popup
    // follows the entry across reorders and closes on delete.
    function openStrokeMenuAt(at, anchor, ax, ay) {
        entryMenu.openFor(at, anchor, ax, ay);
    }

    // Centered entry menu for one stroke. Opens from the row's ...
    // button via openStrokeMenuAt.
    Popup {
        id: entryMenu

        parent: Overlay.overlay

        property int entryIndex: -1
        property var current: entryMenu.entryIndex >= 0 ? section.collectStrokeAt(entryMenu.entryIndex) : null
        readonly property var value: entryMenu.current ? entryMenu.current.value : ({
                enabled: true,
                color: "#000000",
                type: "solid",
                gradient: {
                    angle: 90
                },
                width: 1,
                dash: [],
                position: "center",
                opacity: 1
            })
        readonly property bool isLinear: entryMenu.current ? !entryMenu.current.mixedType && entryMenu.value.type === "linear" : false
        readonly property bool isText: section.snapshot.allOfType("text")
        readonly property bool isImage: section.snapshot.allOfType("image")
        readonly property real dashLen: {
            var dd = section.dashOf(entryMenu.value);
            return dd.dash;
        }
        readonly property real dashGap: {
            var dd = section.dashOf(entryMenu.value);
            return dd.gap;
        }
        readonly property bool isDashed: entryMenu.dashLen > 0 || entryMenu.dashGap > 0

        width: 264
        padding: 12
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        enter: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: 120
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                property: "scale"
                from: 0.97
                to: 1
                duration: 120
                easing.type: Easing.OutCubic
            }
        }
        exit: Transition {
            NumberAnimation {
                property: "opacity"
                from: 1
                to: 0
                duration: 100
                easing.type: Easing.InCubic
            }
        }

        background: Rectangle {
            radius: AppTheme.radiusLarge
            color: AppTheme.surface
            border.width: 1
            border.color: AppTheme.border
        }

        contentItem: ColumnLayout {
            width: parent.width
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: qsTr("Stroke %1").arg(entryMenu.entryIndex + 1)
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: AppTheme.foreground
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    id: menuSwatch

                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    Layout.alignment: Qt.AlignVCenter
                    radius: AppTheme.radiusSmall
                    color: entryMenu.value.color
                    border.width: 1
                    border.color: AppTheme.border

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => section.openStrokePickerAt(entryMenu.entryIndex, String(entryMenu.value.color), menuSwatch, mouse.x, mouse.y)
                    }
                }

                HexField {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    value: String(entryMenu.value.color)
                    mixed: entryMenu.current ? entryMenu.current.mixedColor : true
                    onCommitted: c => section.patchStrokeAt(entryMenu.entryIndex, {
                            color: c,
                            type: "solid"
                        })
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                SegmentedOption {
                    label: qsTr("Solid")
                    active: entryMenu.current ? !entryMenu.current.mixedType && entryMenu.value.type !== "linear" : false
                    onClicked: section.setStrokeTypeAt(entryMenu.entryIndex, "solid")
                }

                SegmentedOption {
                    visible: !entryMenu.isText && !entryMenu.isImage
                    label: qsTr("Gradient")
                    active: entryMenu.isLinear
                    onClicked: section.setStrokeTypeAt(entryMenu.entryIndex, "linear")
                }
            }

            NumberField {
                Layout.fillWidth: true
                visible: entryMenu.isLinear
                prefix: qsTr("A")
                suffix: qsTr("°")
                minimum: 0
                maximum: 360
                scrubStep: 1
                value: Number(entryMenu.value.gradient.angle) || 0
                mixed: entryMenu.current ? entryMenu.current.mixedAngle : true
                onCommitted: v => section.setStrokeAngleAt(entryMenu.entryIndex, v)
                onScrubStarted: section.snapshot.beginScrub()
                onScrubFinished: section.snapshot.endScrub()
            }

            NumberField {
                Layout.fillWidth: true
                visible: !entryMenu.isText
                prefix: "S"
                suffix: qsTr("px")
                minimum: 0
                scrubStep: 0.5
                value: Number(entryMenu.value.width) || 0
                mixed: entryMenu.current ? entryMenu.current.mixedWidth : true
                onCommitted: v => section.patchStrokeAt(entryMenu.entryIndex, {
                        width: v
                    })
                onScrubStarted: section.snapshot.beginScrub()
                onScrubFinished: section.snapshot.endScrub()
            }

            RowLayout {
                visible: !entryMenu.isText && !entryMenu.isImage
                Layout.fillWidth: true
                spacing: 8

                SegmentedOption {
                    label: qsTr("Center")
                    active: entryMenu.current ? !entryMenu.current.mixedPosition && (entryMenu.value.position || "center") === "center" : false
                    onClicked: section.patchStrokeAt(entryMenu.entryIndex, {
                        position: "center"
                    })
                }

                SegmentedOption {
                    label: qsTr("Inside")
                    active: entryMenu.current ? !entryMenu.current.mixedPosition && entryMenu.value.position === "inside" : false
                    onClicked: section.patchStrokeAt(entryMenu.entryIndex, {
                        position: "inside"
                    })
                }

                SegmentedOption {
                    label: qsTr("Outside")
                    active: entryMenu.current ? !entryMenu.current.mixedPosition && entryMenu.value.position === "outside" : false
                    onClicked: section.patchStrokeAt(entryMenu.entryIndex, {
                        position: "outside"
                    })
                }
            }

            Text {
                visible: !entryMenu.isText && !entryMenu.isImage
                Layout.fillWidth: true
                text: qsTr("Dash style")
                font.pixelSize: 11
                color: AppTheme.muted
            }

            RowLayout {
                visible: !entryMenu.isText && !entryMenu.isImage
                Layout.fillWidth: true
                spacing: 8

                SegmentedOption {
                    label: qsTr("Solid")
                    active: entryMenu.current ? !entryMenu.current.mixedDash && !entryMenu.isDashed : false
                    onClicked: section.patchStrokeAt(entryMenu.entryIndex, {
                        dash: []
                    })
                }

                SegmentedOption {
                    label: qsTr("Dashed")
                    active: entryMenu.current ? !entryMenu.current.mixedDash && entryMenu.isDashed && entryMenu.dashLen > 1 : false
                    onClicked: section.setStrokeDashStyleAt(entryMenu.entryIndex, "dashed")
                }

                SegmentedOption {
                    label: qsTr("Dotted")
                    active: entryMenu.current ? !entryMenu.current.mixedDash && entryMenu.isDashed && entryMenu.dashLen <= 1 : false
                    onClicked: section.setStrokeDashStyleAt(entryMenu.entryIndex, "dotted")
                }
            }

            RowLayout {
                visible: !entryMenu.isText && !entryMenu.isImage && entryMenu.current && !entryMenu.current.mixedDash && entryMenu.isDashed
                Layout.fillWidth: true
                spacing: 8

                NumberField {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    prefix: qsTr("D")
                    minimum: 0
                    scrubStep: 0.5
                    value: entryMenu.dashLen
                    onCommitted: v => section.setStrokeDashLenAt(entryMenu.entryIndex, v)
                    onScrubStarted: section.snapshot.beginScrub()
                    onScrubFinished: section.snapshot.endScrub()
                }

                NumberField {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    prefix: qsTr("G")
                    minimum: 0
                    scrubStep: 0.5
                    value: entryMenu.dashGap
                    onCommitted: v => section.setStrokeDashGapAt(entryMenu.entryIndex, v)
                    onScrubStarted: section.snapshot.beginScrub()
                    onScrubFinished: section.snapshot.endScrub()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Order")
                    font.pixelSize: 11
                    color: AppTheme.muted
                }

                PanelIconButton {
                    iconKind: "caret"
                    filled: false
                    iconSize: 14
                    rotation: 180
                    enabled: entryMenu.entryIndex > 0
                    onClicked: {
                        section.moveStrokeAt(entryMenu.entryIndex, -1);
                        entryMenu.entryIndex = Math.max(0, entryMenu.entryIndex - 1);
                    }
                }

                PanelIconButton {
                    iconKind: "caret"
                    filled: false
                    iconSize: 14
                    enabled: entryMenu.entryIndex < section.strokeCount - 1
                    onClicked: {
                        section.moveStrokeAt(entryMenu.entryIndex, 1);
                        entryMenu.entryIndex = Math.min(section.strokeCount - 1, entryMenu.entryIndex + 1);
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Delete")
                    font.pixelSize: 11
                    color: AppTheme.muted
                }

                PanelIconButton {
                    iconKind: "close"
                    filled: false
                    iconSize: 12
                    onClicked: {
                        section.removeStrokeAt(entryMenu.entryIndex);
                        entryMenu.close();
                    }
                }
            }
        }

        function openFor(at, anchor, ax, ay) {
            entryMenu.entryIndex = at;
            entryMenu.placeNear(anchor, ax, ay);
            entryMenu.open();
        }

        // Anchor-relative placement in overlay coords: below the
        // button when it fits, above otherwise, clamped on both axes
        // with an 8px margin (same rule as the color picker).
        function placeNear(anchor, ax, ay) {
            var ov = entryMenu.parent;
            var w = entryMenu.width;
            var h = entryMenu.implicitHeight > 0 ? entryMenu.implicitHeight : 320;
            if (!anchor || !ov) {
                entryMenu.x = 8;
                entryMenu.y = 8;
                return;
            }
            var p = anchor.mapToItem(ov, ax, ay);
            entryMenu.x = Math.min(Math.max(8, Math.round(p.x - w / 2)), Math.max(8, ov.width - w - 8));
            var maxY = Math.max(8, ov.height - h - 8);
            var below = Math.round(p.y + 12);
            if (below + h <= ov.height - 8)
                entryMenu.y = below;
            else
                entryMenu.y = Math.max(8, Math.min(Math.round(p.y - 12 - h), maxY));
        }
    }

    function gradStop(g, i) {
        var s = (g ?? {}).stops ?? [];
        if (i < s.length)
            return String(s[i].color);
        return i === 0 ? "#000000" : "#ffffff";
    }

    function dashOf(entry) {
        var d = (entry ?? {}).dash;
        var norm = {
            dash: 0,
            gap: 0
        };
        if (d && typeof d.length === "number") {
            if (d.length > 0)
                norm.dash = Math.max(0, Number(d[0]) || 0);
            if (d.length > 1)
                norm.gap = Math.max(0, Number(d[1]) || 0);
        }
        return norm;
    }

    // Per-index common stroke (maps never === by ref). Leaves missing
    // the index are skipped: edits apply where the entry exists.
    function collectStrokeAt(at) {
        var leaves = section.snapshot.selLeaves;
        var base = {
            enabled: true,
            color: "#000000",
            type: "solid",
            gradient: {
                angle: 90,
                stops: [
                    {
                        color: "#000000",
                        pos: 0
                    },
                    {
                        color: "#ffffff",
                        pos: 1
                    }
                ]
            },
            width: 1,
            dash: [],
            position: "center",
            opacity: 1
        };
        var first = null;
        for (var i = 0; i < leaves.length; i++) {
            var list = leaves[i].strokes || [];
            if (at < list.length) {
                first = list[at];
                break;
            }
        }
        if (!first) {
            return {
                value: base,
                mixedColor: true,
                mixedType: true,
                mixedOpacity: true,
                mixedWidth: true,
                mixedPosition: true,
                mixedDash: true,
                mixedEnabled: true,
                mixedAngle: true
            };
        }
        var mc = false, mt = false, mo = false, mw = false, mp = false, md = false, me = false, ma = false;
        var fd = section.dashOf(first);
        for (var j = 0; j < leaves.length; j++) {
            var cur = (leaves[j].strokes || [])[at];
            if (!cur)
                continue;
            if (String(cur.color) !== String(first.color))
                mc = true;
            if (String(cur.type ?? "solid") !== String(first.type ?? "solid"))
                mt = true;
            if (Number(cur.opacity ?? 1) !== Number(first.opacity ?? 1))
                mo = true;
            if (Number(cur.width ?? 0) !== Number(first.width ?? 0))
                mw = true;
            if (String(cur.position ?? "center") !== String(first.position ?? "center"))
                mp = true;
            var cd = section.dashOf(cur);
            if (cd.dash !== fd.dash || cd.gap !== fd.gap)
                md = true;
            if ((cur.enabled !== false) !== (first.enabled !== false))
                me = true;
            if (Number((cur.gradient ?? {}).angle ?? 90) !== Number((first.gradient ?? {}).angle ?? 90))
                ma = true;
        }
        return {
            value: {
                enabled: first.enabled !== false,
                color: String(first.color ?? "#000000"),
                type: (first.type ?? "solid") === "linear" ? "linear" : "solid",
                gradient: {
                    angle: Number((first.gradient ?? {}).angle) || 0,
                    stops: [
                        {
                            color: section.gradStop(first.gradient, 0),
                            pos: 0
                        },
                        {
                            color: section.gradStop(first.gradient, 1),
                            pos: 1
                        }
                    ]
                },
                width: Math.max(0, Number(first.width) || 0),
                dash: (first.dash || []).slice(),
                position: (first.position === "inside" || first.position === "outside") ? first.position : "center",
                opacity: Math.min(1, Math.max(0, Number(first.opacity ?? 1)))
            },
            mixedColor: mc,
            mixedType: mt,
            mixedOpacity: mo,
            mixedWidth: mw,
            mixedPosition: mp,
            mixedDash: md,
            mixedEnabled: me,
            mixedAngle: ma
        };
    }

    // New entries prepend (index 0, topmost) on every selected leaf.
    function addStroke() {
        if (section.doc)
            section.doc.addStrokeToSelected();
    }

    function removeStrokeAt(at) {
        if (section.doc)
            section.doc.removeStrokeAtSelected(at);
    }

    function moveStrokeAt(at, delta) {
        if (section.doc)
            section.doc.moveStrokeAtSelected(at, delta);
    }

    function toggleStrokeAt(at) {
        if (section.doc)
            section.doc.toggleStrokeAtSelected(at);
    }

    function patchStrokeAt(at, patch) {
        if (section.doc)
            section.doc.patchStrokeAtSelected(at, patch);
    }

    function setStrokeTypeAt(at, type) {
        if (section.doc)
            section.doc.patchStrokeAtSelected(at, {
                type: type === "linear" ? "linear" : "solid"
            });
    }

    function setStrokeAngleAt(at, v) {
        if (!section.doc)
            return;
        var cur = section.collectStrokeAt(at).value.gradient ?? {};
        section.doc.patchStrokeAtSelected(at, {
            gradient: {
                angle: Math.min(360, Math.max(0, Number(v) || 0)),
                stops: [
                    {
                        color: section.gradStop(cur, 0),
                        pos: 0
                    },
                    {
                        color: section.gradStop(cur, 1),
                        pos: 1
                    }
                ]
            }
        });
    }

    // Dash presets keep the current gap when it is positive; dashed
    // keeps a current dash above one line-width, otherwise both fall
    // back to the canonical pairs. A dash at or below one line-width
    // reads as dots with round caps/joins.
    function setStrokeDashStyleAt(at, style) {
        if (!section.doc)
            return;
        if (style === "solid") {
            section.doc.patchStrokeAtSelected(at, {
                dash: []
            });
            return;
        }
        var cur = section.collectStrokeAt(at).value;
        var dd = section.dashOf(cur);
        var gap = dd.gap > 0 ? dd.gap : 2;
        var dash = 4;
        if (style === "dotted")
            dash = 1;
        else if (dd.dash > 1)
            dash = dd.dash;
        section.doc.patchStrokeAtSelected(at, {
            dash: [dash, gap]
        });
    }

    function setStrokeDashLenAt(at, v) {
        if (!section.doc)
            return;
        var dd = section.dashOf(section.collectStrokeAt(at).value);
        section.doc.patchStrokeAtSelected(at, {
            dash: [Math.max(0, Number(v) || 0), dd.gap]
        });
    }

    function setStrokeDashGapAt(at, v) {
        if (!section.doc)
            return;
        var dd = section.dashOf(section.collectStrokeAt(at).value);
        section.doc.patchStrokeAtSelected(at, {
            dash: [dd.dash, Math.max(0, Number(v) || 0)]
        });
    }
}
