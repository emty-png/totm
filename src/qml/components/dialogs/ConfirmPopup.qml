import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Generic destructive-action confirm: title plus message with Cancel
// and a foreground confirm action, in the export/template modal
// language. Callers set the copy through ask() (which opens) and run
// the action on confirmed; dismissals do nothing.
Popup {
    id: confirm

    property string title: ""
    property string message: ""
    property string confirmLabel: ""

    signal confirmed

    function ask(askTitle, askMessage, askConfirmLabel) {
        confirm.title = askTitle;
        confirm.message = askMessage;
        confirm.confirmLabel = askConfirmLabel;
        confirm.open();
    }

    anchors.centerIn: parent
    implicitWidth: 300
    padding: 12
    modal: true
    dim: true
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
        radius: AppTheme.radiusLarge
        color: AppTheme.surface
        border.width: 1
        border.color: AppTheme.border
    }

    contentItem: ColumnLayout {
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: confirm.title
            font.pixelSize: 13
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            color: AppTheme.foreground
        }

        Text {
            Layout.fillWidth: true
            text: confirm.message
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            color: AppTheme.muted
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: AppTheme.radiusSmall
                border.width: 1
                border.color: AppTheme.fieldBorder
                color: cancelMouse.containsMouse || cancelMouse.pressed ? AppTheme.hover : AppTheme.surface

                Behavior on color {
                    ColorAnimation {
                        duration: 100
                        easing.type: Easing.OutCubic
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: qsTr("Cancel")
                    font.pixelSize: 12
                    color: cancelMouse.containsMouse || cancelMouse.pressed ? AppTheme.foreground : AppTheme.muted
                }

                MouseArea {
                    id: cancelMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: confirm.close()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: AppTheme.radiusSmall
                border.width: 1
                border.color: AppTheme.foreground
                color: AppTheme.foreground

                Text {
                    anchors.centerIn: parent
                    text: confirm.confirmLabel
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: AppTheme.background
                }

                MouseArea {
                    id: confirmMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        confirm.close();
                        confirm.confirmed();
                    }
                }
            }
        }
    }
}
