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
                options: section.weights
                currentId: String(section.snapshot.commonOf("fontWeight").value)
                onPicked: id => section.commit("fontWeight", parseInt(id, 10))
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
            text: qsTr("Line height")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        RowLayout {
            spacing: 8

            SegOption {
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

            AlignButton {
                mode: "hLeft"
                active: section.alignIs("hAlign", "left")
                onClicked: section.commit("hAlign", "left")
            }

            AlignButton {
                mode: "hCenter"
                active: section.alignIs("hAlign", "center")
                onClicked: section.commit("hAlign", "center")
            }

            AlignButton {
                mode: "hRight"
                active: section.alignIs("hAlign", "right")
                onClicked: section.commit("hAlign", "right")
            }

            AlignButton {
                mode: "justify"
                active: section.alignIs("hAlign", "justify")
                onClicked: section.commit("hAlign", "justify")
            }
        }

        RowLayout {
            spacing: 8

            AlignButton {
                mode: "vTop"
                active: section.alignIs("vAlign", "top")
                onClicked: section.commit("vAlign", "top")
            }

            AlignButton {
                mode: "vMiddle"
                active: section.alignIs("vAlign", "middle")
                onClicked: section.commit("vAlign", "middle")
            }

            AlignButton {
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

    function isAutoHeight() {
        return section.snapshot.commonOf("lineHeightAuto").value === true;
    }

    // Mixed selections read as nothing-active, never as off.
    function alignIs(role, want) {
        var c = section.snapshot.commonOf(role);
        return !c.mixed && c.value === want;
    }
}
