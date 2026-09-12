import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Effect picker: anchored popup listing the effects a shape can take.
// The list grows without changing callers. Window-clamped like the
// color picker so short windows never push it off-screen.
Popup {
    id: popup

    parent: Overlay.overlay

    signal outerShadowClicked
    signal innerShadowClicked
    signal layerBlurClicked
    signal backgroundBlurClicked
    signal outerGlowClicked
    signal innerGlowClicked
    signal grainClicked

    // True while the selection holds text: background blur samples no
    // backdrop for glyphs, so its row goes inert instead of no-op.
    property bool textSelected: false

    width: 220
    padding: 6
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
        radius: 10
        color: AppTheme.surface
        border.width: 1
        border.color: AppTheme.border
    }

    contentItem: ColumnLayout {
        width: parent.width
        spacing: 2

        EffectRow {
            label: qsTr("Outer Shadow")
            iconKind: "shadeOuter"
            onChosen: {
                popup.close();
                popup.outerShadowClicked();
            }
        }

        EffectRow {
            label: qsTr("Inner Shadow")
            iconKind: "shadeInner"
            onChosen: {
                popup.close();
                popup.innerShadowClicked();
            }
        }

        EffectRow {
            label: qsTr("Layer Blur")
            iconKind: "blur"
            onChosen: {
                popup.close();
                popup.layerBlurClicked();
            }
        }

        EffectRow {
            label: qsTr("Background Blur")
            iconKind: "backdrop"
            rowEnabled: !popup.textSelected
            onChosen: {
                popup.close();
                popup.backgroundBlurClicked();
            }
        }

        EffectRow {
            label: qsTr("Outer Glow")
            iconKind: "sparkle"
            onChosen: {
                popup.close();
                popup.outerGlowClicked();
            }
        }

        EffectRow {
            label: qsTr("Inner Glow")
            iconKind: "glowInner"
            onChosen: {
                popup.close();
                popup.innerGlowClicked();
            }
        }

        EffectRow {
            label: qsTr("Grain")
            iconKind: "grain"
            onChosen: {
                popup.close();
                popup.grainClicked();
            }
        }
    }

    // One picker row: hover fill, glyph plus label, click chooses.
    component EffectRow: Rectangle {
        id: row

        required property string label
        required property string iconKind
        property bool rowEnabled: true

        signal chosen

        Layout.fillWidth: true
        Layout.preferredHeight: 34
        radius: 6
        opacity: row.rowEnabled ? 1 : 0.35
        color: row.rowEnabled && (rowMouse.containsMouse || rowMouse.pressed) ? AppTheme.hover : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: 100
                easing.type: Easing.OutCubic
            }
        }

        RowLayout {
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 10
                rightMargin: 10
            }
            spacing: 8

            AppIcon {
                Layout.preferredWidth: 14
                Layout.preferredHeight: 14
                kind: row.iconKind
                iconColor: AppTheme.foreground
            }

            Text {
                Layout.fillWidth: true
                text: row.label
                font.pixelSize: 12
                elide: Text.ElideRight
                color: AppTheme.foreground
            }
        }

        MouseArea {
            id: rowMouse

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: row.rowEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (row.rowEnabled)
                    row.chosen();
            }
        }
    }

    // Section entry: opens below the section's top-right corner (where
    // the + sits), above when it does not fit, clamped with margin.
    function openAt(anchor) {
        popup.placeNear(anchor);
        popup.open();
    }

    function placeNear(anchor) {
        var ov = popup.parent;
        var w = popup.width;
        var h = popup.implicitHeight > 0 ? popup.implicitHeight : 48;
        if (!anchor || !ov) {
            popup.x = 8;
            popup.y = 8;
            return;
        }
        var p = anchor.mapToItem(ov, anchor.width - 40, 10);
        popup.x = Math.min(Math.max(8, Math.round(p.x - w / 2)), Math.max(8, ov.width - w - 8));
        var maxY = Math.max(8, ov.height - h - 8);
        var below = Math.round(p.y + 12);
        if (below + h <= ov.height - 8)
            popup.y = below;
        else
            popup.y = Math.max(8, Math.min(Math.round(p.y - 12 - h), maxY));
    }
}
