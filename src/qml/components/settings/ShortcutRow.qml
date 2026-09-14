import QtQuick
import QtQuick.Layouts
import Totm

// One editable shortcut row: label left, per-row reset when customized,
// capture badge right. Reads singletons directly (data-only props in),
// the settings panel passes actionId/label/sequence per delegate.
Rectangle {
    id: row

    // Stable action id, assigned by the panel in onItemAdded (the index
    // arrives as a plain argument, immune to nested-Repeater context).
    // Label/sequence derive from singletons so remaps flow live.
    property string actionId: ""
    property string label: ShortcutState.labelFor(actionId)
    property string sequence: ShortcutState.sequenceFor(actionId)
    property bool custom: ShortcutState.isCustom(actionId)
    property bool capturing: ShortcutState.capturing && ShortcutState.capturingId === actionId
    property var capturePolicy: null
    property var resetPolicy: null

    implicitHeight: 36
    radius: AppTheme.radiusSmall
    color: row.capturing ? AppTheme.hover : hoverMouse.containsMouse ? AppTheme.hover : "transparent"

    Behavior on color {
        ColorAnimation {
            duration: 100
            easing.type: Easing.OutCubic
        }
    }

    MouseArea {
        id: hoverMouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 8

        Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: row.label
            font.pixelSize: 12
            color: AppTheme.foreground
            elide: Text.ElideRight
        }

        Item {
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            Layout.alignment: Qt.AlignVCenter
            visible: row.custom && !row.capturing

            AppIcon {
                anchors.centerIn: parent
                kind: "undo"
                width: 14
                height: 14
                iconColor: resetMouse.containsMouse ? AppTheme.foreground : AppTheme.muted
            }

            MouseArea {
                id: resetMouse

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (row.resetPolicy)
                        row.resetPolicy(row.actionId);
                }
            }
        }

        Rectangle {
            id: badge

            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Math.max(64, badgeText.implicitWidth + 20)
            implicitHeight: 28
            radius: AppTheme.radiusSmall
            border.width: row.capturing ? 2 : 1
            border.color: row.capturing ? AppTheme.selection : badgeMouse.containsMouse ? AppTheme.foreground : AppTheme.fieldBorder
            color: AppTheme.background

            Behavior on border.color {
                ColorAnimation {
                    duration: 100
                    easing.type: Easing.OutCubic
                }
            }

            Text {
                id: badgeText

                anchors.centerIn: parent
                text: row.capturing ? qsTr("Press keys…") : row.sequence
                font.pixelSize: 12
                color: row.capturing ? AppTheme.selection : AppTheme.foreground
            }

            MouseArea {
                id: badgeMouse

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (row.capturePolicy)
                        row.capturePolicy(row.actionId);
                }
            }
        }
    }
}
