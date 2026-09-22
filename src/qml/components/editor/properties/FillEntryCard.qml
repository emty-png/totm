import QtQuick
import QtQuick.Layouts
import Totm

// One stacked fill entry as a single compact row: eye, swatch, hex,
// opacity and a ... menu holding everything else (type, angle,
// order, delete). Wired by the owner like EffectShadowCard
// delegates; every commit goes through section.patchFillAt so
// multi-selection stays in one undo entry. Index 0 paints topmost.
RowLayout {
    id: card

    // Plain props with defaults (never required): Repeater delegates
    // evaluate required bindings before model context attaches.
    property var section: null
    property int entryIndex: -1

    property var common: card.section && card.entryIndex >= 0 ? card.section.collectFillAt(card.entryIndex) : null
    readonly property var current: card.common ?? ({
            value: {
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
            },
            mixedColor: true,
            mixedType: true,
            mixedOpacity: true,
            mixedEnabled: true,
            mixedAngle: true
        })
    readonly property bool isLinear: !card.current.mixedType && card.current.value.type === "linear"

    spacing: 8

    PanelIconButton {
        iconKind: card.current.value.enabled !== false ? "eye" : "eyeOff"
        filled: false
        iconSize: 14
        onClicked: {
            if (card.section)
                card.section.toggleFillAt(card.entryIndex);
        }
    }

    Rectangle {
        id: swatch

        Layout.preferredWidth: 28
        Layout.preferredHeight: 28
        Layout.alignment: Qt.AlignVCenter
        radius: AppTheme.radiusSmall
        border.width: 1
        border.color: AppTheme.border
        color: card.isLinear ? "transparent" : card.current.value.color

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            visible: card.isLinear
            radius: Math.max(0, AppTheme.radiusSmall - 1)
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: card.section ? card.section.gradStop(card.current.value.gradient, 0) : "#000000"
                }
                GradientStop {
                    position: 1
                    color: card.section ? card.section.gradStop(card.current.value.gradient, 1) : "#ffffff"
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (card.section) {
                    if (card.isLinear)
                        card.section.openFillGradientPickerAt(card.entryIndex, swatch, mouse.x, mouse.y);
                    else
                        card.section.openFillPickerAt(card.entryIndex, String(card.current.value.color), swatch, mouse.x, mouse.y);
                }
            }
        }
    }

    HexField {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        visible: !card.isLinear
        value: String(card.current.value.color)
        mixed: card.current.mixedColor
        onCommitted: c => {
            if (card.section)
                card.section.patchFillAt(card.entryIndex, {
                    color: c,
                    type: "solid"
                });
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        visible: card.isLinear
        text: qsTr("Gradient")
        font.pixelSize: 11
        color: AppTheme.muted
        elide: Text.ElideRight
    }

    NumberField {
        Layout.preferredWidth: 70
        suffix: "%"
        minimum: 0
        maximum: 100
        scrubStep: 1
        value: Math.round(Number(card.current.value.opacity ?? 1) * 100)
        mixed: card.current.mixedOpacity
        onCommitted: v => {
            if (card.section)
                card.section.patchFillAt(card.entryIndex, {
                    opacity: v / 100
                });
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

    PanelIconButton {
        id: dotsBtn

        iconKind: "dots"
        filled: true
        iconSize: 16
        onClicked: {
            if (card.section)
                card.section.openFillMenuAt(card.entryIndex, dotsBtn, dotsBtn.width / 2, dotsBtn.height / 2);
        }
    }
}
