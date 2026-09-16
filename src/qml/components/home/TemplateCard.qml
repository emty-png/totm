import QtQuick
import QtQuick.Layouts
import Totm

// Starter-template card: name plus blurb, click builds a new design.
// Plain props with defaults (never required): Repeater delegates
// evaluate required bindings before model context attaches, like
// DesignCard and LayersRow.
Item {
    id: card

    property string templateId: ""
    property string templateName: ""
    property string blurb: ""
    property var usePolicy: null

    width: 220
    height: 92

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
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 12
                rightMargin: 12
            }
            spacing: 4

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
