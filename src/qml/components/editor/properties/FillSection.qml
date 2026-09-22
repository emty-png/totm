import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Stacked fills per shape (Figma-style, index 0 paints topmost).
// Each entry carries its own color/gradient, opacity %, eye toggle
// and order; strokes paint above all fills. Per-index values collect
// across the selection with mixed flags (see EffectShadowCard);
// edits apply where the index exists, adds apply to every leaf.
PanelSection {
    id: section

    required property var snapshot
    required property var doc

    // Picker entry being live-recolored. Drags stream committed()
    // between scrubStarted/scrubFinished so each gesture stays one
    // undo entry; typed hex commits discretely on its own.
    property int pickerFillIndex: -1

    // Widest stack in the selection; cards past a leaf's own length
    // show defaults with everything mixed and skip it on commit.
    readonly property int fillCount: {
        var m = 0;
        var leaves = section.snapshot.selLeaves;
        for (var i = 0; i < leaves.length; i++) {
            var n = (leaves[i].fills || []).length;
            if (n > m)
                m = n;
        }
        return m;
    }

    title: qsTr("Fill")
    visible: section.snapshot.sel.length > 0 && !section.snapshot.hasGroup && !section.snapshot.allOfType("image")
    enabled: !section.snapshot.allLocked
    compact: section.fillCount === 0
    showAdd: true
    showRemove: false
    onAddClicked: section.addFill()

    Repeater {
        model: section.fillCount

        onItemAdded: (at, item) => {
            item.section = section;
            item.entryIndex = at;
        }

        FillEntryCard {
            Layout.fillWidth: true
        }
    }

    // Picker flow: swatch seeds the popup, drags stream through one
    // scrub transaction, typed hex commits discretely on its own.
    // Solid picks land as solid (converting linear entries back);
    // gradient picks land as linear. Gradient tabs only for vector
    // shapes (text glyphs stay solid).
    ColorPickerPopup {
        id: picker

        allowGradient: !section.snapshot.allOfType("text") && !section.snapshot.allOfType("image")
        onScrubStarted: section.snapshot.beginScrub()
        onCommitted: c => {
            if (section.pickerFillIndex >= 0)
                section.patchFillAt(section.pickerFillIndex, {
                    color: String(c),
                    type: "solid"
                });
        }
        onGradientCommitted: g => {
            if (section.pickerFillIndex >= 0)
                section.patchFillAt(section.pickerFillIndex, {
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

    // Centered entry menu: type, angle, order and delete for one
    // fill. Opens from the row's ... button via openFillMenuAt.
    Popup {
        id: entryMenu

        parent: Overlay.overlay

        property int entryIndex: -1

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
                text: qsTr("Fill %1").arg(entryMenu.entryIndex + 1)
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: AppTheme.foreground
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
                        section.moveFillAt(entryMenu.entryIndex, -1);
                        entryMenu.entryIndex = Math.max(0, entryMenu.entryIndex - 1);
                    }
                }

                PanelIconButton {
                    iconKind: "caret"
                    filled: false
                    iconSize: 14
                    enabled: entryMenu.entryIndex < section.fillCount - 1
                    onClicked: {
                        section.moveFillAt(entryMenu.entryIndex, 1);
                        entryMenu.entryIndex = Math.min(section.fillCount - 1, entryMenu.entryIndex + 1);
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
                        section.removeFillAt(entryMenu.entryIndex);
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
            var h = entryMenu.implicitHeight > 0 ? entryMenu.implicitHeight : 160;
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

    function openFillPickerAt(at, color, anchor, ax, ay) {
        section.pickerFillIndex = at;
        picker.openFor(color, anchor, ax, ay);
    }

    function openFillGradientPickerAt(at, anchor, ax, ay) {
        section.pickerFillIndex = at;
        var cur = section.collectFillAt(at).value.gradient ?? {};
        picker.openForGradient(cur, anchor, ax, ay);
    }

    // Advanced per-entry settings live in a popup behind the row's
    // ... button (Figma-style): order and delete. It opens below the
    // button when it fits, above otherwise, like the color picker.
    // The popup follows the entry across reorders and closes on delete.
    function openFillMenuAt(at, anchor, ax, ay) {
        entryMenu.openFor(at, anchor, ax, ay);
    }

    function gradStop(g, i) {
        var s = (g ?? {}).stops ?? [];
        if (i < s.length)
            return String(s[i].color);
        return i === 0 ? "#000000" : "#ffffff";
    }

    // Per-index common fill (maps never === by ref). Leaves missing
    // the index are skipped: edits apply where the entry exists.
    function collectFillAt(at) {
        var leaves = section.snapshot.selLeaves;
        var base = {
            enabled: true,
            color: "#d9d9d9",
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
            opacity: 1
        };
        var first = null;
        for (var i = 0; i < leaves.length; i++) {
            var list = leaves[i].fills || [];
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
                mixedEnabled: true,
                mixedAngle: true
            };
        }
        var mc = false, mt = false, mo = false, me = false, ma = false;
        for (var j = 0; j < leaves.length; j++) {
            var cur = (leaves[j].fills || [])[at];
            if (!cur)
                continue;
            if (String(cur.color) !== String(first.color))
                mc = true;
            if (String(cur.type ?? "solid") !== String(first.type ?? "solid"))
                mt = true;
            if (Number(cur.opacity ?? 1) !== Number(first.opacity ?? 1))
                mo = true;
            if ((cur.enabled !== false) !== (first.enabled !== false))
                me = true;
            if (Number((cur.gradient ?? {}).angle ?? 90) !== Number((first.gradient ?? {}).angle ?? 90))
                ma = true;
        }
        return {
            value: {
                enabled: first.enabled !== false,
                color: String(first.color ?? "#d9d9d9"),
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
                opacity: Math.min(1, Math.max(0, Number(first.opacity ?? 1)))
            },
            mixedColor: mc,
            mixedType: mt,
            mixedOpacity: mo,
            mixedEnabled: me,
            mixedAngle: ma
        };
    }

    // New entries prepend (index 0, topmost) on every selected leaf.
    function addFill() {
        if (section.doc)
            section.doc.addFillToSelected();
    }

    function removeFillAt(at) {
        if (section.doc)
            section.doc.removeFillAtSelected(at);
    }

    function moveFillAt(at, delta) {
        if (section.doc)
            section.doc.moveFillAtSelected(at, delta);
    }

    function toggleFillAt(at) {
        if (section.doc)
            section.doc.toggleFillAtSelected(at);
    }

    function patchFillAt(at, patch) {
        if (section.doc)
            section.doc.patchFillAtSelected(at, patch);
    }
}
