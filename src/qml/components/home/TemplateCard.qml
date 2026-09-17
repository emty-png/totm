import QtQuick
import QtQuick.Layouts
import Totm

// Starter-template card: rendered scene preview plus name and blurb,
// click builds a new design. The scene is optional (null keeps the old
// text-only tile); the picker fills it from one-undo-entry builder
// snapshots so tiles match what a new design opens with.
// Plain props with defaults (never required): Repeater delegates
// evaluate required bindings before model context attaches, like
// DesignCard and LayersRow.
Item {
    id: card

    property string templateId: ""
    property string templateName: ""
    property string blurb: ""
    property var scene: null
    property var usePolicy: null

    readonly property bool hasPreview: card.scene !== null && card.scene !== undefined

    width: 220
    height: card.hasPreview ? 208 : 92
    // Layout-friendly mirror of the explicit size, so grid/column
    // parents size rows without delegate-side props (ignored in Rows).
    Layout.fillWidth: true
    Layout.preferredHeight: card.height

    Rectangle {
        anchors.fill: parent
        radius: AppTheme.radiusMedium
        color: cardMouse.containsMouse || cardMouse.pressed ? AppTheme.hover : AppTheme.surface
        border.width: 1
        border.color: AppTheme.fieldBorder

        Behavior on color {
            ColorAnimation {
                duration: 100
                easing.type: Easing.OutCubic
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            // Preview tile in the home-card language: canvas wash with
            // a hairline overlay (children paint over the base border).
            // Content-box fit zooms to the shapes, not the empty scene.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 104
                visible: card.hasPreview
                radius: AppTheme.radiusSmall
                color: AppTheme.canvas

                Item {
                    anchors.fill: parent
                    anchors.margins: 1
                    clip: true

                    DesignCardPreview {
                        anchors.fill: parent
                        scene: card.scene
                        fitContent: true
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: AppTheme.radiusSmall
                    color: "transparent"
                    border.width: 1
                    border.color: AppTheme.border
                }
            }

            Text {
                Layout.fillWidth: true
                text: card.templateName
                font.pixelSize: 12
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                color: AppTheme.foreground
            }

            Text {
                Layout.fillWidth: true
                text: card.blurb
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: AppTheme.muted
            }

            // Absorbs layout slack so rows read top-down in both modes.
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        MouseArea {
            id: cardMouse

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (card.usePolicy)
                    card.usePolicy(card.templateId);
            }
        }
    }
}
