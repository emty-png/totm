import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// General settings panel: new-design defaults, video-export defaults
// and storage. Same centered 640px card rhythm as the other tabs.
ColumnLayout {
    id: generalPanel

    spacing: 0

    property real centerMargin: Math.max(16, (generalPanel.width - 640) / 2)

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: generalPanel.centerMargin
        Layout.rightMargin: generalPanel.centerMargin
        Layout.topMargin: 12
        Layout.bottomMargin: 8
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("General")
            font.pixelSize: 16
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            color: AppTheme.foreground
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: resetText.implicitWidth + 20
            implicitHeight: 28
            radius: AppTheme.radiusSmall
            border.width: 1
            border.color: resetMouse.containsMouse ? AppTheme.foreground : AppTheme.fieldBorder
            color: resetMouse.pressed ? AppTheme.pressed : resetMouse.containsMouse ? AppTheme.hover : AppTheme.surface

            Behavior on color {
                ColorAnimation {
                    duration: 100
                    easing.type: Easing.OutCubic
                }
            }

            Text {
                id: resetText

                anchors.centerIn: parent
                text: qsTr("Reset all")
                font.pixelSize: 12
                color: AppTheme.foreground
            }

            MouseArea {
                id: resetMouse

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: SettingsStore.resetGeneral()
            }
        }
    }

    ScrollView {
        id: generalScroll

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: Math.min(640, generalScroll.availableWidth - 32)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12

            GeneralNewDesignSection {}

            GeneralExportSection {}

            GeneralStorageSection {}

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 16
            }
        }
    }
}
