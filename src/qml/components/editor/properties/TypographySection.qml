import QtQuick
import QtQuick.Layouts
import Totm

// Typography editors for text shapes: family, weight, size, line
// height (Auto or factor), letter spacing (percent of size) and full
// alignment (horizontal + vertical). Hidden unless every selected leaf
// is text; mixed selections keep the shared sections only.
PanelSection {
    id: section

    required property var snapshot

    // Curated cross-platform families (plain names so fallback stays
    // sane where one is missing). Weights map to QML Font weights.
    property var families: [
        {
            id: "Inter",
            name: "Inter"
        },
        {
            id: "Arial",
            name: "Arial"
        },
        {
            id: "Helvetica",
            name: "Helvetica"
        },
        {
            id: "Georgia",
            name: "Georgia"
        },
        {
            id: "Times New Roman",
            name: "Times New Roman"
        },
        {
            id: "Courier New",
            name: "Courier New"
        },
        {
            id: "Verdana",
            name: "Verdana"
        },
        {
            id: "Trebuchet MS",
            name: "Trebuchet MS"
        }
    ]
    property var weights: [
        {
            id: "400",
            name: qsTr("Regular")
        },
        {
            id: "500",
            name: qsTr("Medium")
        },
        {
            id: "600",
            name: qsTr("SemiBold")
        },
        {
            id: "700",
            name: qsTr("Bold")
        }
    ]

    // Weight presets plus a dynamic entry for values outside them, so
    // the dropdown names the live weight instead of falling back to
    // the first preset (PanelDropdown shows options[0] on no match).
    readonly property var weightOptions: {
        var cur = section.snapshot.commonOf("fontWeight");
        var base = section.weights.slice();
        if (!cur.mixed) {
            var id = String(Math.min(1000, Math.max(1, Math.round(Number(cur.value) || 400))));
            var known = false;
            for (var i = 0; i < base.length; i++) {
                if (String(base[i].id) === id) {
                    known = true;
                    break;
                }
            }
            if (!known)
                base.push({
                    id: id,
                    name: qsTr("Custom %1").arg(id)
                });
        }
        return base;
    }

    title: qsTr("Typography")
    visible: section.snapshot.sel.length > 0 && section.snapshot.allOfType("text")
    enabled: !section.snapshot.allLocked

    ColumnLayout {
        spacing: 4

        Text {
            text: qsTr("Font")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        PanelDropdown {
            options: section.families
            currentId: String(section.snapshot.commonOf("fontFamily").value)
            onPicked: id => section.commit("fontFamily", id)
        }
    }

    ColumnLayout {
        spacing: 4

        RowLayout {
            spacing: 8

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 0
                text: qsTr("Font weight")
                font.pixelSize: 11
                color: AppTheme.muted
            }

            Text {
                Layout.preferredWidth: 76
                text: qsTr("Font size")
                font.pixelSize: 11
                color: AppTheme.muted
            }
        }

        RowLayout {
            spacing: 8

            PanelDropdown {
                options: section.weightOptions
                currentId: {
                    var c = section.snapshot.commonOf("fontWeight");
                    return c.mixed ? "" : String(Math.min(1000, Math.max(1, Math.round(Number(c.value) || 400))));
                }
                onPicked: id => section.commitWeight(parseInt(id, 10))
            }

            NumberField {
                Layout.preferredWidth: 76
                suffix: "px"
                value: section.snapshot.commonOf("fontSize").value
                mixed: section.snapshot.commonOf("fontSize").mixed
                minimum: 1
                maximum: 1000
                onCommitted: v => section.commit("fontSize", v)
                onScrubStarted: section.snapshot.beginScrub()
                onScrubFinished: section.snapshot.endScrub()
            }
        }
    }

    ColumnLayout {
        spacing: 4

        Text {
            text: qsTr("Custom weight")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        NumberField {
            Layout.fillWidth: true
            minimum: 1
            maximum: 1000
            value: section.snapshot.commonOf("fontWeight").value
            mixed: section.snapshot.commonOf("fontWeight").mixed
            onCommitted: v => section.commitWeight(v)
            onScrubStarted: section.snapshot.beginScrub()
            onScrubFinished: section.snapshot.endScrub()
        }
    }

    ColumnLayout {
        spacing: 4

        Text {
            text: qsTr("Line height")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        RowLayout {
            spacing: 8

            SegmentedOption {
                label: qsTr("Auto")
                active: section.snapshot.commonOf("lineHeightAuto").value === true
                onClicked: section.commit("lineHeightAuto", !section.isAutoHeight())
            }

            NumberField {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 0
                enabled: !section.isAutoHeight()
                suffix: "×"
                value: section.snapshot.commonOf("lineHeight").value
                mixed: section.snapshot.commonOf("lineHeight").mixed
                minimum: 0.5
                maximum: 10
                onCommitted: v => section.commit("lineHeight", v)
                onScrubStarted: section.snapshot.beginScrub()
                onScrubFinished: section.snapshot.endScrub()
            }
        }
    }

    ColumnLayout {
        spacing: 4

        Text {
            text: qsTr("Letter spacing")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        NumberField {
            Layout.fillWidth: true
            suffix: "%"
            value: section.snapshot.commonOf("letterSpacing").value
            mixed: section.snapshot.commonOf("letterSpacing").mixed
            minimum: -100
            maximum: 200
            onCommitted: v => section.commit("letterSpacing", v)
            onScrubStarted: section.snapshot.beginScrub()
            onScrubFinished: section.snapshot.endScrub()
        }
    }

    ColumnLayout {
        spacing: 4

        Text {
            text: qsTr("Alignment")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        RowLayout {
            spacing: 8

            AlignOption {
                mode: "hLeft"
                active: section.alignIs("hAlign", "left")
                onClicked: section.commit("hAlign", "left")
            }

            AlignOption {
                mode: "hCenter"
                active: section.alignIs("hAlign", "center")
                onClicked: section.commit("hAlign", "center")
            }

            AlignOption {
                mode: "hRight"
                active: section.alignIs("hAlign", "right")
                onClicked: section.commit("hAlign", "right")
            }

            AlignOption {
                mode: "justify"
                active: section.alignIs("hAlign", "justify")
                onClicked: section.commit("hAlign", "justify")
            }
        }

        RowLayout {
            spacing: 8

            AlignOption {
                mode: "vTop"
                active: section.alignIs("vAlign", "top")
                onClicked: section.commit("vAlign", "top")
            }

            AlignOption {
                mode: "vMiddle"
                active: section.alignIs("vAlign", "middle")
                onClicked: section.commit("vAlign", "middle")
            }

            AlignOption {
                mode: "vBottom"
                active: section.alignIs("vAlign", "bottom")
                onClicked: section.commit("vAlign", "bottom")
            }

            Item {
                Layout.fillWidth: true
            }
        }
    }

    // Single-undo commits: the begin/end pair also absorbs the canvas
    // auto-size writeback (font edits resize the box), so one gesture
    // never splits into two history entries. Nests inside scrubs.
    function commit(role, value) {
        section.snapshot.beginScrub();
        section.snapshot.setAll(role, value);
        section.snapshot.endScrub();
    }

    // Custom weight commit: clamp to the Qt 1..1000 scale, then snap to
    // the closest weight the current family actually ships (enumerated
    // from QFontDatabase styles). Mixed families and unknown families
    // keep the exact value and let Qt approximate the glyphs.
    function nearestWeight(v) {
        var want = Math.min(1000, Math.max(1, Math.round(Number(v) || 400)));
        var fam = section.snapshot.commonOf("fontFamily");
        if (fam.mixed)
            return want;
        var list = [];
        try {
            list = SettingsStore.fontWeights(String(fam.value || "")) || [];
        } catch (e) {
            list = [];
        }
        var avail = [];
        if (list && typeof list.length === "number") {
            for (var i = 0; i < list.length; i++) {
                var w = Math.round(Number(list[i]));
                if (!isNaN(w))
                    avail.push(Math.min(1000, Math.max(1, w)));
            }
        }
        if (avail.length === 0)
            return want;
        var best = avail[0], bd = Math.abs(avail[0] - want);
        for (var j = 1; j < avail.length; j++) {
            var d = Math.abs(avail[j] - want);
            if (d < bd) {
                bd = d;
                best = avail[j];
            }
        }
        return best;
    }

    function commitWeight(v) {
        section.commit("fontWeight", section.nearestWeight(v));
    }

    function isAutoHeight() {
        return section.snapshot.commonOf("lineHeightAuto").value === true;
    }

    // Mixed selections read as nothing-active, never as off.
    function alignIs(role, want) {
        var c = section.snapshot.commonOf(role);
        return !c.mixed && c.value === want;
    }
}
