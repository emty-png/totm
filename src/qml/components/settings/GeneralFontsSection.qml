import QtQuick
import QtQuick.Layouts
import Totm

// Fonts card: install curated open-licensed web families into the same
// store as manual imports, so they appear in the editor picker right
// away. Removal lives on the Appearance tab's import list.
Rectangle {
    id: fontsCard

    Layout.fillWidth: true
    implicitHeight: fontsBody.implicitHeight + 24
    radius: AppTheme.radiusLarge
    border.width: 1
    border.color: AppTheme.border
    color: AppTheme.surface

    ColumnLayout {
        id: fontsBody

        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Fonts")
            font.pixelSize: 12
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            color: AppTheme.foreground
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("Install open-licensed fonts from the web. Installed faces appear in the editor font picker.")
            font.pixelSize: 12
            color: AppTheme.muted
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            radius: AppTheme.radiusSmall
            border.width: 1
            border.color: browseMouse.containsMouse ? AppTheme.foreground : AppTheme.fieldBorder
            color: browseMouse.pressed ? AppTheme.pressed : browseMouse.containsMouse ? AppTheme.hover : AppTheme.surface

            Behavior on color {
                ColorAnimation {
                    duration: 100
                    easing.type: Easing.OutCubic
                }
            }

            Text {
                anchors.centerIn: parent
                text: qsTr("Browse fonts")
                font.pixelSize: 12
                color: AppTheme.foreground
            }

            MouseArea {
                id: browseMouse

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: fontPopup.show()
            }
        }
    }

    FontInstallerPopup {
        id: fontPopup
    }
}
