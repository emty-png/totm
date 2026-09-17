import QtCore
import QtQuick
import QtQuick.Layouts
import Totm

// Font card: import .ttf/.otf files (copied to <AppData>/totm/fonts/
// and registered via QFontDatabase), then pick from the list.
// No typing: the user selects System default or an imported font.
// A stored family that is gone next session falls back to the system
// font and shows a "Font not found" error until re-picked or reset.
Rectangle {
    id: fontCard

    readonly property bool hasCustom: SettingsStore.fontFamily !== ""

    Layout.fillWidth: true
    implicitHeight: fontBody.implicitHeight + 24
    radius: AppTheme.radiusLarge
    border.width: 1
    border.color: AppTheme.border
    color: AppTheme.surface

    ColumnLayout {
        id: fontBody

        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: qsTr("Font")
                font.pixelSize: 12
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                color: AppTheme.foreground
            }

            Text {
                visible: fontCard.hasCustom
                text: qsTr("Reset")
                font.pixelSize: 12
                color: AppTheme.foreground

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: SettingsStore.fontFamily = ""
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: SettingsStore.fontMissing
            wrapMode: Text.WordWrap
            text: qsTr("Font not found: %1. Using system default instead.").arg(SettingsStore.fontFamily)
            font.pixelSize: 12
            color: AppTheme.snapGuide
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            radius: AppTheme.radiusSmall
            border.width: 1
            border.color: importMouse.containsMouse ? AppTheme.foreground : AppTheme.fieldBorder
            color: importMouse.pressed ? AppTheme.pressed : importMouse.containsMouse ? AppTheme.hover : AppTheme.surface

            Behavior on color {
                ColorAnimation {
                    duration: 100
                    easing.type: Easing.OutCubic
                }
            }

            Text {
                anchors.centerIn: parent
                text: qsTr("Import")
                font.pixelSize: 12
                color: AppTheme.foreground
            }

            MouseArea {
                id: importMouse

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: fontPicker.open()
            }
        }

        AppearanceFontRow {
            Layout.fillWidth: true
            fileName: ""
            familyName: qsTr("System default")
            selected: !fontCard.hasCustom && !SettingsStore.fontMissing
            selectPolicy: () => SettingsStore.fontFamily = ""
        }

        Repeater {
            model: SettingsStore.importedFonts

            onItemAdded: (idx, item) => {
                item.fileName = SettingsStore.importedFonts[idx];
            }

            delegate: AppearanceFontRow {
                Layout.fillWidth: true
                removePolicy: file => SettingsStore.removeImportedFont(file)
                selectPolicy: file => SettingsStore.selectImportedFont(file)
            }
        }
    }

    FilePicker {
        id: fontPicker

        suffixes: ["ttf", "otf", "ttc", "woff", "woff2"]
        currentFolder: StandardPaths.writableLocation(StandardPaths.DownloadLocation)
        onAccepted: {
            var family = SettingsStore.importFont(fontPicker.selectedFile);
            if (family !== "")
                SettingsStore.fontFamily = family;
        }
    }
}
