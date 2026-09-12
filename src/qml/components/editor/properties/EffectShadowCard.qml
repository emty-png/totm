import QtQuick
import QtQuick.Layouts
import Totm

// One stacked shadow entry: header (eye, reorder, delete) plus outer/
// inner switch and color/offset/blur/spread rows. Wired in onItemAdded
// by the owner like LayersView delegates; every commit goes through
// section.patchShadowAt so multi-selection stays in one undo entry.
ColumnLayout {
    id: card

    // Plain props with defaults (never required): Repeater delegates
    // evaluate required bindings before model context attaches.
    property var section: null
    property int entryIndex: -1

    property var common: card.section && card.entryIndex >= 0 ? card.section.collectShadowAt(card.entryIndex) : null
    readonly property var current: card.common ?? ({
            value: {
                enabled: true,
                inner: false,
                color: "#80000000",
                x: 0,
                y: 4,
                blur: 8,
                spread: 0
            },
            mixedColor: true,
            mixedX: true,
            mixedY: true,
            mixedBlur: true,
            mixedSpread: true
        })

    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        spacing: 4

        Text {
            Layout.fillWidth: true
            text: qsTr("Shadow %1").arg(card.entryIndex + 1)
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: AppTheme.foreground
            elide: Text.ElideRight
        }

        PanelIconButton {
            iconKind: card.current.value.enabled !== false ? "eye" : "eyeOff"
            filled: false
            iconSize: 14
            onClicked: {
                if (card.section)
                    card.section.toggleShadowAt(card.entryIndex);
            }
        }

        PanelIconButton {
            iconKind: "caret"
            filled: false
            iconSize: 14
            enabled: card.entryIndex > 0
            rotation: 180
            onClicked: {
                if (card.section)
                    card.section.moveShadowAt(card.entryIndex, -1);
            }
        }

        PanelIconButton {
            iconKind: "caret"
            filled: false
            iconSize: 14
            enabled: card.section && card.entryIndex < card.section.shadowCount - 1
            onClicked: {
                if (card.section)
                    card.section.moveShadowAt(card.entryIndex, 1);
            }
        }

        PanelIconButton {
            iconKind: "close"
            filled: false
            iconSize: 12
            onClicked: {
                if (card.section)
                    card.section.removeShadowAt(card.entryIndex);
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        SegmentedOption {
            label: qsTr("Outer")
            active: card.current.value.inner !== true
            onClicked: {
                if (card.section)
                    card.section.setShadowInnerAt(card.entryIndex, false);
            }
        }

        SegmentedOption {
            label: qsTr("Inner")
            active: card.current.value.inner === true
            onClicked: {
                if (card.section)
                    card.section.setShadowInnerAt(card.entryIndex, true);
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Rectangle {
            id: swatch

            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: 6
            color: card.current.value.color
            border.width: 1
            border.color: AppTheme.border

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    if (card.section)
                        card.section.openShadowPickerAt(card.entryIndex, String(card.current.value.color), swatch, mouse.x, mouse.y);
                }
            }
        }

        HexField {
            Layout.fillWidth: true
            value: card.section ? card.section.hexOf(card.current.value.color) : "#000000"
            mixed: card.current.mixedColor
            onCommitted: c => {
                if (card.section)
                    card.section.patchShadowAt(card.entryIndex, "color", card.section.withAlpha(c, card.section.alphaOf(card.current.value.color)));
            }
        }

        NumberField {
            Layout.preferredWidth: 76
            suffix: "%"
            minimum: 0
            maximum: 100
            value: card.section ? card.section.alphaOf(card.current.value.color) : 100
            mixed: card.current.mixedColor
            onCommitted: v => {
                if (card.section)
                    card.section.patchShadowAt(card.entryIndex, "color", card.section.withAlpha(card.section.hexOf(card.current.value.color), v));
            }
            onScrubStarted: {
                if (card.section)
                    card.section.snapshot.beginScrub();
            }
            onScrubFinished: {
                if (card.section)
                    card.section.snapshot.endScrub();
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "X"
            suffix: qsTr("px")
            minimum: -500
            maximum: 500
            value: card.current.value.x
            mixed: card.current.mixedX
            onCommitted: v => {
                if (card.section)
                    card.section.patchShadowAt(card.entryIndex, "x", v);
            }
            onScrubStarted: {
                if (card.section)
                    card.section.snapshot.beginScrub();
            }
            onScrubFinished: {
                if (card.section)
                    card.section.snapshot.endScrub();
            }
        }

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "Y"
            suffix: qsTr("px")
            minimum: -500
            maximum: 500
            value: card.current.value.y
            mixed: card.current.mixedY
            onCommitted: v => {
                if (card.section)
                    card.section.patchShadowAt(card.entryIndex, "y", v);
            }
            onScrubStarted: {
                if (card.section)
                    card.section.snapshot.beginScrub();
            }
            onScrubFinished: {
                if (card.section)
                    card.section.snapshot.endScrub();
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "B"
            suffix: qsTr("px")
            minimum: 0
            maximum: 100
            value: card.current.value.blur
            mixed: card.current.mixedBlur
            onCommitted: v => {
                if (card.section)
                    card.section.patchShadowAt(card.entryIndex, "blur", v);
            }
            onScrubStarted: {
                if (card.section)
                    card.section.snapshot.beginScrub();
            }
            onScrubFinished: {
                if (card.section)
                    card.section.snapshot.endScrub();
            }
        }

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "S"
            suffix: qsTr("px")
            minimum: 0
            maximum: 50
            value: card.current.value.spread
            mixed: card.current.mixedSpread
            onCommitted: v => {
                if (card.section)
                    card.section.patchShadowAt(card.entryIndex, "spread", v);
            }
            onScrubStarted: {
                if (card.section)
                    card.section.snapshot.beginScrub();
            }
            onScrubFinished: {
                if (card.section)
                    card.section.snapshot.endScrub();
            }
        }
    }
}
