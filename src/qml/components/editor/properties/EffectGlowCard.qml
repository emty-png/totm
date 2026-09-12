import QtQuick
import QtQuick.Layouts
import Totm

// One stacked glow entry: header (eye, reorder, delete) plus outer/
// inner switch and the shared glow fields. Wired in onItemAdded by the
// owner like LayersView delegates. Text forces outer: the switch
// disables inner when the selection holds text.
ColumnLayout {
    id: card

    // Plain props with defaults (never required): Repeater delegates
    // evaluate required bindings before model context attaches.
    property var section: null
    property int entryIndex: -1

    property var common: card.section && card.entryIndex >= 0 ? card.section.collectGlowAt(card.entryIndex) : null
    readonly property var current: card.common ?? ({
            value: {
                enabled: true,
                inner: false,
                color: "#cc00ffff",
                blur: 16,
                spread: 4
            },
            mixedColor: true,
            mixedBlur: true,
            mixedSpread: true
        })
    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        spacing: 4

        Text {
            Layout.fillWidth: true
            text: qsTr("Glow %1").arg(card.entryIndex + 1)
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
                    card.section.toggleGlowAt(card.entryIndex);
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
                    card.section.moveGlowAt(card.entryIndex, -1);
            }
        }

        PanelIconButton {
            iconKind: "caret"
            filled: false
            iconSize: 14
            enabled: card.section && card.entryIndex < card.section.glowCount - 1
            onClicked: {
                if (card.section)
                    card.section.moveGlowAt(card.entryIndex, 1);
            }
        }

        PanelIconButton {
            iconKind: "close"
            filled: false
            iconSize: 12
            onClicked: {
                if (card.section)
                    card.section.removeGlowAt(card.entryIndex);
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
                    card.section.setGlowInnerAt(card.entryIndex, false);
            }
        }

        SegmentedOption {
            label: qsTr("Inner")
            active: card.current.value.inner === true
            onClicked: {
                if (card.section)
                    card.section.setGlowInnerAt(card.entryIndex, true);
            }
        }
    }

    EffectGlowFields {
        Layout.fillWidth: true
        glowRgb: card.section ? card.section.hexOf(card.current.value.color) : "#00ffff"
        colorMixed: card.current.mixedColor
        colorAlpha: card.section ? card.section.alphaOf(card.current.value.color) : 100
        blurValue: card.current.value.blur
        blurMixed: card.current.mixedBlur
        spreadValue: card.current.value.spread
        spreadMixed: card.current.mixedSpread
        onRgbCommitted: c => {
            if (card.section)
                card.section.patchGlowAt(card.entryIndex, "color", card.section.withAlpha(c, card.section.alphaOf(card.current.value.color)));
        }
        onAlphaCommitted: v => {
            if (card.section)
                card.section.patchGlowAt(card.entryIndex, "color", card.section.withAlpha(card.section.hexOf(card.current.value.color), v));
        }
        onBlurCommitted: v => {
            if (card.section)
                card.section.patchGlowAt(card.entryIndex, "blur", v);
        }
        onSpreadCommitted: v => {
            if (card.section)
                card.section.patchGlowAt(card.entryIndex, "spread", v);
        }
        onSwatchClicked: (anchor, mx, my) => {
            if (card.section)
                card.section.openGlowPickerAt(card.entryIndex, String(card.section.hexOf(card.current.value.color)), anchor, mx, my);
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
