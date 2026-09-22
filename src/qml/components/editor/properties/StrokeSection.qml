import QtQuick
import QtQuick.Layouts
import Totm

// Single stroke per shape; width 0 counts as missing. The header swaps
// between + (no stroke) and - (has stroke) so shapes can carry no
// stroke. On text the stroke outlines the glyphs. Shapes only.
PanelSection {
    id: section

    required property var snapshot

    property var widthCommon: section.snapshot.commonOf("strokeWidth")
    property bool hasStroke: section.widthCommon.mixed || section.widthCommon.value > 0
    // Gradient strokes ride strokeGradient; maps compare by deep key so
    // multi-selections agree only on identical gradients.
    property var typeCommon: section.snapshot.commonOf("strokeType")
    property bool isLinear: !section.typeCommon.mixed && section.typeCommon.value === "linear"
    property var gradCommon: section.collectGrad()
    property var dashCommon: section.collectDash()

    title: qsTr("Stroke")
    visible: section.snapshot.sel.length > 0 && !section.snapshot.hasGroup && !section.snapshot.allOfType("image")
    enabled: !section.snapshot.allLocked
    compact: !section.hasStroke
    showAdd: !section.hasStroke
    showRemove: section.hasStroke
    onAddClicked: section.snapshot.setAll("strokeWidth", 1)
    onRemoveClicked: section.snapshot.setAll("strokeWidth", 0)

    RowLayout {
        visible: section.hasStroke && !section.isLinear
        Layout.fillWidth: true
        spacing: 8

        Rectangle {
            id: swatch

            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: AppTheme.radiusSmall
            color: section.snapshot.commonOf("stroke").value
            border.width: 1
            border.color: AppTheme.border

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => picker.openFor(String(section.snapshot.commonOf("stroke").value), swatch, mouse.x, mouse.y)
            }
        }

        HexField {
            Layout.fillWidth: true
            value: String(section.snapshot.commonOf("stroke").value)
            mixed: section.snapshot.commonOf("stroke").mixed
            onCommitted: c => section.snapshot.setAll("stroke", c)
        }

        NumberField {
            Layout.preferredWidth: 76
            // Text uses the native 1px outline, so the width value is
            // meaningless there: the +/- header already toggles it via
            // 0/1. Hidden for all-text selections, shown otherwise.
            visible: !section.snapshot.allOfType("text")
            prefix: "S"
            value: section.widthCommon.value
            mixed: section.widthCommon.mixed
            minimum: 0
            onCommitted: v => section.snapshot.setAll("strokeWidth", v)
            onScrubStarted: section.snapshot.beginScrub()
            onScrubFinished: section.snapshot.endScrub()
        }
    }

    // Picker flow mirrors FillSection: drags stream through one scrub
    // transaction, typed hex commits discretely on its own. Gradient
    // tabs only for vector shapes (glyph outlines stay solid).
    ColorPickerPopup {
        id: picker

        allowGradient: !section.snapshot.allOfType("text") && !section.snapshot.allOfType("image")
        onScrubStarted: section.snapshot.beginScrub()
        onCommitted: c => section.snapshot.setAll("stroke", c)
        onGradientCommitted: g => section.regradientLive(g)
        onScrubFinished: section.snapshot.endScrub()
    }

    // Linear stroke row: gradient swatch plus angle and width fields.
    // Colors edit through the picker's Gradient tab.
    RowLayout {
        visible: section.hasStroke && section.isLinear
        Layout.fillWidth: true
        spacing: 8

        Rectangle {
            id: gradSwatch

            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: AppTheme.radiusSmall
            border.width: 1
            border.color: AppTheme.border
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: section.gradStop(section.gradCommon.value, 0)
                }
                GradientStop {
                    position: 1
                    color: section.gradStop(section.gradCommon.value, 1)
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => picker.openForGradient(section.gradCommon.value, gradSwatch, mouse.x, mouse.y)
            }
        }

        NumberField {
            Layout.fillWidth: true
            prefix: qsTr("A")
            suffix: qsTr("°")
            minimum: 0
            maximum: 360
            scrubStep: 1
            value: Number(section.gradCommon.value.angle) || 0
            onCommitted: v => section.setGradAngle(v)
            onScrubStarted: section.snapshot.beginScrub()
            onScrubFinished: section.snapshot.endScrub()
        }

        NumberField {
            Layout.preferredWidth: 76
            // Same width control as the solid row: without it gradient
            // strokes could only change the angle.
            visible: !section.snapshot.allOfType("text")
            prefix: "S"
            value: section.widthCommon.value
            mixed: section.widthCommon.mixed
            minimum: 0
            onCommitted: v => section.snapshot.setAll("strokeWidth", v)
            onScrubStarted: section.snapshot.beginScrub()
            onScrubFinished: section.snapshot.endScrub()
        }

        PanelIconButton {
            iconKind: "minimize"
            filled: false
            strong: true
            iconSize: 16
            onClicked: section.snapshot.setAll("strokeType", "solid")
        }
    }

    // Dash style: solid/dashed/dotted presets plus dash/gap lengths in
    // stroke-width units (both must be positive, else solid). Applies
    // to solid and gradient strokes alike; native text outlines stay
    // solid so the rows hide for text.
    Text {
        visible: section.hasStroke && !section.snapshot.allOfType("text")
        Layout.fillWidth: true
        text: qsTr("Dash style")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        visible: section.hasStroke && !section.snapshot.allOfType("text")
        Layout.fillWidth: true
        spacing: 8

        SegmentedOption {
            label: qsTr("Solid")
            active: !section.dashCommon.mixed && section.dashCommon.dash <= 0 && section.dashCommon.gap <= 0
            onClicked: section.setDashStyle("solid")
        }

        SegmentedOption {
            label: qsTr("Dashed")
            active: !section.dashCommon.mixed && (section.dashCommon.dash > 0 || section.dashCommon.gap > 0) && section.dashCommon.dash > 1
            onClicked: section.setDashStyle("dashed")
        }

        SegmentedOption {
            label: qsTr("Dotted")
            active: !section.dashCommon.mixed && (section.dashCommon.dash > 0 || section.dashCommon.gap > 0) && section.dashCommon.dash <= 1
            onClicked: section.setDashStyle("dotted")
        }
    }

    RowLayout {
        visible: section.hasStroke && !section.snapshot.allOfType("text") && !section.dashCommon.mixed && (section.dashCommon.dash > 0 || section.dashCommon.gap > 0)
        Layout.fillWidth: true
        spacing: 8

        NumberField {
            Layout.fillWidth: true
            prefix: qsTr("D")
            minimum: 0
            scrubStep: 0.5
            value: section.dashCommon.dash
            mixed: section.dashCommon.mixed
            onCommitted: v => section.setDashLen(v)
            onScrubStarted: section.snapshot.beginScrub()
            onScrubFinished: section.snapshot.endScrub()
        }

        NumberField {
            Layout.fillWidth: true
            prefix: qsTr("G")
            minimum: 0
            scrubStep: 0.5
            value: section.dashCommon.gap
            mixed: section.dashCommon.mixed
            onCommitted: v => section.setDashGap(v)
            onScrubStarted: section.snapshot.beginScrub()
            onScrubFinished: section.snapshot.endScrub()
        }
    }

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

    // Common gradient by deep key; mixed unless every leaf agrees.
    function collectGrad() {
        var leaves = section.snapshot.selLeaves;
        if (leaves.length === 0)
            return {
                mixed: true,
                value: {
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
                }
            };
        var first = section.gradKey(leaves[0].strokeGradient);
        for (var i = 1; i < leaves.length; i++) {
            if (section.gradKey(leaves[i].strokeGradient) !== first)
                return {
                    mixed: true,
                    value: leaves[0].strokeGradient
                };
        }
        return {
            mixed: false,
            value: leaves[0].strokeGradient ?? {
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
            }
        };
    }

    // Streamed gradient drags: replace whole maps, coalesced by the
    // picker's scrub signals; type flips to linear alongside.
    function regradientLive(g) {
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
        section.snapshot.setAll("strokeGradient", next);
        section.snapshot.setAll("strokeType", "linear");
    }

    function setGradAngle(v) {
        var cur = section.gradCommon.value ?? {};
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
        section.snapshot.setAll("strokeGradient", next);
    }

    // Common dash pair by value; mixed unless every leaf agrees. A dash
    // at or below one line-width reads as dots with round caps/joins,
    // which is how the Dotted preset (dash 1, gap 2) is defined.
    function collectDash() {
        var leaves = section.snapshot.selLeaves;
        if (leaves.length === 0)
            return {
                mixed: true,
                dash: 0,
                gap: 0
            };
        var norm = d => {
            var a = (d && typeof d.length === "number") ? d : [];
            return {
                dash: a.length > 0 ? Math.max(0, Number(a[0]) || 0) : 0,
                gap: a.length > 1 ? Math.max(0, Number(a[1]) || 0) : 0
            };
        };
        var first = norm(leaves[0].strokeDash);
        for (var i = 1; i < leaves.length; i++) {
            var cur = norm(leaves[i].strokeDash);
            if (cur.dash !== first.dash || cur.gap !== first.gap)
                return {
                    mixed: true,
                    dash: first.dash,
                    gap: first.gap
                };
        }
        return {
            mixed: false,
            dash: first.dash,
            gap: first.gap
        };
    }

    // Presets keep the current gap when it is positive; dashed keeps a
    // current dash above one line-width, otherwise both fall back to
    // the canonical pairs.
    function setDashStyle(style) {
        if (style === "solid") {
            section.snapshot.setAll("strokeDash", []);
            return;
        }
        var cur = section.dashCommon;
        var gap = !cur.mixed && Number(cur.gap) > 0 ? Number(cur.gap) : 2;
        var dash = 4;
        if (style === "dotted")
            dash = 1;
        else if (!cur.mixed && Number(cur.dash) > 1)
            dash = Number(cur.dash);
        section.snapshot.setAll("strokeDash", [dash, gap]);
    }

    function setDashLen(v) {
        var cur = section.dashCommon;
        var gap = cur.mixed ? 2 : Math.max(0, Number(cur.gap) || 0);
        section.snapshot.setAll("strokeDash", [Math.max(0, Number(v) || 0), gap]);
    }

    function setDashGap(v) {
        var cur = section.dashCommon;
        var dash = cur.mixed ? 4 : Math.max(0, Number(cur.dash) || 0);
        section.snapshot.setAll("strokeDash", [dash, Math.max(0, Number(v) || 0)]);
    }
}
