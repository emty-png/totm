import QtQuick
import QtQuick.Layouts
import Totm

// One stacked stroke entry as a single compact row: eye, swatch,
// width, opacity and a ... menu holding everything else (color hex,
// type, angle, position, dash style, order, delete). Wired by the
// owner like EffectShadowCard delegates; every commit goes through
// section.patchStrokeAt so multi-selection stays in one undo entry.
// Index 0 paints topmost, above all fills.
RowLayout {
    id: card

    // Plain props with defaults (never required): Repeater delegates
    // evaluate required bindings before model context attaches.
    property var section: null
    property int entryIndex: -1

    property var common: card.section && card.entryIndex >= 0 ? card.section.collectStrokeAt(card.entryIndex) : null
    readonly property var current: card.common ?? ({
            value: {
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
            },
            mixedColor: true,
            mixedType: true,
            mixedOpacity: true,
            mixedWidth: true,
            mixedPosition: true,
            mixedDash: true,
            mixedEnabled: true,
            mixedAngle: true
        })
    readonly property bool isLinear: !card.current.mixedType && card.current.value.type === "linear"
    readonly property bool isText: card.section ? card.section.snapshot.allOfType("text") : false

    spacing: 8

    PanelIconButton {
        iconKind: card.current.value.enabled !== false ? "eye" : "eyeOff"
        filled: false
        iconSize: 14
        onClicked: {
            if (card.section)
                card.section.toggleStrokeAt(card.entryIndex);
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
                        card.section.openStrokeGradientPickerAt(card.entryIndex, swatch, mouse.x, mouse.y);
                    else
                        card.section.openStrokePickerAt(card.entryIndex, String(card.current.value.color), swatch, mouse.x, mouse.y);
                }
            }
        }
    }

    // Text uses the native 1px outline, so the width value is
    // meaningless there. Hidden for all-text selections.
    NumberField {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        visible: !card.isText
        prefix: "S"
        suffix: qsTr("px")
        minimum: 0
        scrubStep: 0.5
        value: Number(card.current.value.width) || 0
        mixed: card.current.mixedWidth
        onCommitted: v => {
            if (card.section)
                card.section.patchStrokeAt(card.entryIndex, {
                    width: v
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

    Text {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        visible: card.isText
        text: qsTr("Outline")
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
                card.section.patchStrokeAt(card.entryIndex, {
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
                card.section.openStrokeMenuAt(card.entryIndex, dotsBtn, dotsBtn.width / 2, dotsBtn.height / 2);
        }
    }
}
