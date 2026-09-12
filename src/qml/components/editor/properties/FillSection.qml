import QtQuick
import QtQuick.Layouts
import Totm

// Single fill per shape. Transparent counts as missing: header + paints
// it black, header - clears the selection back to transparent, so shapes
// can carry no fill. Multi-selections list each distinct opaque fill;
// per-variant - shows only then. All edits stay selection-scoped.
PanelSection {
    id: section

    required property var snapshot
    required property var doc

    title: qsTr("Fill")
    visible: section.snapshot.sel.length > 0 && !section.snapshot.hasGroup && !section.snapshot.allOfType("image")
    enabled: !section.snapshot.allLocked
    compact: section.opaqueFills().length === 0
    showAdd: section.hasNoFill()
    showRemove: section.opaqueFills().length > 0
    onAddClicked: section.addFill()
    onRemoveClicked: section.removeFills()

    // Variant being live-recolored by the picker. Chained string-to-
    // string so each drag move finds the previous one (recolor matches
    // on exact strings, scoped to the selection like everything else).
    // Gradients chain the same way by deep key (angle + stops).
    property string liveFill: "#000000"
    property string liveGradKey: ""

    Repeater {
        model: section.opaqueFills()

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                id: swatch

                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                Layout.alignment: Qt.AlignVCenter
                radius: 6
                color: modelData
                border.width: 1
                border.color: AppTheme.border

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => section.openPicker(modelData, swatch, mouse.x, mouse.y)
                }
            }

            HexField {
                Layout.fillWidth: true
                value: modelData
                onCommitted: c => section.doc.recolorSelected(modelData, c)
            }

            PanelIconButton {
                iconKind: "minimize"
                filled: false
                strong: true
                iconSize: 16
                visible: section.opaqueFills().length > 1
                onClicked: section.removeVariant(modelData)
            }
        }
    }

    // One row per distinct linear gradient: gradient swatch (Rectangle
    // gradients preview fine; only borders lack them) plus angle field.
    // Colors edit through the picker's Gradient tab.
    Repeater {
        model: section.linearGrads()

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                id: gradSwatch

                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                Layout.alignment: Qt.AlignVCenter
                radius: 6
                border.width: 1
                border.color: AppTheme.border
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: section.gradStop(modelData, 0)
                    }
                    GradientStop {
                        position: 1
                        color: section.gradStop(modelData, 1)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => section.openGradientPicker(modelData, gradSwatch, mouse.x, mouse.y)
                }
            }

            NumberField {
                Layout.fillWidth: true
                prefix: qsTr("A")
                suffix: qsTr("°")
                minimum: 0
                maximum: 360
                scrubStep: 1
                // Release-committed: this row lives in a rev-driven
                // Repeater, so live commits would rebuild the delegate
                // mid-drag. Text previews during the drag instead.
                commitOnRelease: true
                value: Number(modelData.angle) || 0
                onCommitted: v => section.setGradAngle(modelData, v)
                onScrubStarted: section.snapshot.beginScrub()
                onScrubFinished: section.snapshot.endScrub()
            }

            PanelIconButton {
                iconKind: "minimize"
                filled: false
                strong: true
                iconSize: 16
                visible: section.linearGrads().length > 1
                onClicked: section.dropGradient(modelData)
            }
        }
    }

    function isNoFill(f) {
        var s = String(f).toLowerCase();
        if (s === "transparent" || s === "")
            return true;
        // Opaque serializes as #rrggbb, translucent as #aarrggbb.
        if (s.charAt(0) === "#" && s.length === 9)
            return s.slice(1, 3) === "00";
        return false;
    }

    function opaqueFills() {
        var out = [];
        var fills = section.snapshot.distinctFills();
        for (var i = 0; i < fills.length; i++) {
            if (!section.isNoFill(fills[i]))
                out.push(fills[i]);
        }
        return out;
    }

    // Deep key so gradient variants match by value (maps never ===).
    function gradKey(g) {
        var d = g ?? {};
        var s = d.stops ?? [];
        var c0 = s.length > 0 ? String(s[0].color) : "#000000";
        var c1 = s.length > 1 ? String(s[1].color) : "#ffffff";
        return String(Number(d.angle) || 0) + "|" + c0 + "|" + c1;
    }

    function gradStop(g, i) {
        var s = (g ?? {}).stops ?? [];
        if (i < s.length)
            return String(s[i].color);
        return i === 0 ? "#000000" : "#ffffff";
    }

    function linearGrads() {
        var out = [];
        var seen = {};
        var leaves = section.snapshot.selLeaves;
        for (var i = 0; i < leaves.length; i++) {
            if (leaves[i].fillType !== "linear")
                continue;
            var k = section.gradKey(leaves[i].fillGradient);
            if (!seen[k]) {
                seen[k] = true;
                out.push({
                    angle: Number((leaves[i].fillGradient ?? {}).angle) || 0,
                    stops: [
                        {
                            color: section.gradStop(leaves[i].fillGradient, 0),
                            pos: 0
                        },
                        {
                            color: section.gradStop(leaves[i].fillGradient, 1),
                            pos: 1
                        }
                    ]
                });
            }
        }
        return out;
    }

    function hasNoFill() {
        var fills = section.snapshot.distinctFills();
        for (var i = 0; i < fills.length; i++) {
            if (section.isNoFill(fills[i]))
                return true;
        }
        return false;
    }

    // Paint only the missing shapes black; opaque fills keep their color.
    // Loops wrap in one transaction so each action is one undo entry.
    function addFill() {
        section.snapshot.beginScrub();
        var leaves = section.snapshot.selLeaves;
        for (var i = 0; i < leaves.length; i++) {
            if (section.isNoFill(leaves[i].fill))
                section.doc.setShapeProp(leaves[i].uid, "fill", "#000000");
        }
        section.snapshot.endScrub();
    }

    // Clear the selection's fills (selection-scoped, lock-aware).
    function removeFills() {
        section.snapshot.beginScrub();
        var leaves = section.snapshot.selLeaves;
        for (var i = 0; i < leaves.length; i++)
            section.doc.setShapeProp(leaves[i].uid, "fill", "transparent");
        section.snapshot.endScrub();
    }

    // Clear one distinct fill variant within the selection only.
    function removeVariant(fillValue) {
        section.snapshot.beginScrub();
        var leaves = section.snapshot.selLeaves;
        for (var i = 0; i < leaves.length; i++) {
            if (String(leaves[i].fill) === String(fillValue))
                section.doc.setShapeProp(leaves[i].uid, "fill", "transparent");
        }
        section.snapshot.endScrub();
    }

    // Picker flow: swatch seeds the popup, drags stream through one
    // scrub transaction, typed hex commits discretely on its own.
    // Gradient tabs only for vector shapes (text glyphs stay solid).
    ColorPickerPopup {
        id: picker

        allowGradient: !section.snapshot.allOfType("text") && !section.snapshot.allOfType("image")
        onScrubStarted: section.snapshot.beginScrub()
        onCommitted: c => section.recolorLive(c)
        onGradientCommitted: g => section.regradientLive(g)
        onScrubFinished: section.snapshot.endScrub()
    }

    function openPicker(variant, anchor, ax, ay) {
        section.liveFill = String(variant);
        section.liveGradKey = "";
        picker.openFor(variant, anchor, ax, ay);
    }

    function openGradientPicker(variant, anchor, ax, ay) {
        section.liveGradKey = section.gradKey(variant);
        picker.openForGradient(variant, anchor, ax, ay);
    }

    function recolorLive(c) {
        var next = String(c);
        section.doc.recolorSelected(section.liveFill, next);
        section.liveFill = next;
    }

    // Gradient drags stream whole maps: replace the matching variant by
    // key and chain the key so the next move finds this one. Scrub
    // coalescing rides the picker's scrub signals like solid recolor.
    // Converting from the Solid tab (liveGradKey empty) flips the picked
    // solid variant to linear instead of matching a gradient variant.
    function regradientLive(g) {
        var leaves = section.snapshot.selLeaves;
        var next = {
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
        };
        if (section.liveGradKey === "") {
            for (var i = 0; i < leaves.length; i++) {
                if (String(leaves[i].fill) === section.liveFill) {
                    section.doc.setShapeProp(leaves[i].uid, "fillGradient", next);
                    section.doc.setShapeProp(leaves[i].uid, "fillType", "linear");
                }
            }
        } else {
            for (var j = 0; j < leaves.length; j++) {
                if (leaves[j].fillType === "linear" && section.gradKey(leaves[j].fillGradient) === section.liveGradKey) {
                    section.doc.setShapeProp(leaves[j].uid, "fillGradient", next);
                    section.doc.setShapeProp(leaves[j].uid, "fillType", "linear");
                }
            }
        }
        section.liveGradKey = section.gradKey(next);
    }

    // Discrete angle commit (typing, or one release-committed scrub):
    // key-chained replace with one undo entry via setShapeProp.
    function setGradAngle(variant, v) {
        var leaves = section.snapshot.selLeaves;
        var key = section.gradKey(variant);
        for (var i = 0; i < leaves.length; i++) {
            if (leaves[i].fillType === "linear" && section.gradKey(leaves[i].fillGradient) === key) {
                var cur = leaves[i].fillGradient ?? {};
                var next = {
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
                };
                section.doc.setShapeProp(leaves[i].uid, "fillGradient", next);
            }
        }
    }

    // Drop a gradient variant back to its solid fallback fill.
    function dropGradient(variant) {
        var leaves = section.snapshot.selLeaves;
        var key = section.gradKey(variant);
        for (var i = 0; i < leaves.length; i++) {
            if (leaves[i].fillType === "linear" && section.gradKey(leaves[i].fillGradient) === key)
                section.doc.setShapeProp(leaves[i].uid, "fillType", "solid");
        }
    }
}
