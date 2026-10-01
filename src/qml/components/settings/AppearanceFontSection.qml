import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Font card: bundled Inter by default, the OS font on explicit choice,
// or import .ttf/.otf files (copied to <AppData>/totm/fonts/ and
// registered via QFontDatabase), then pick from the list.
// No typing: the user selects one of the rows.
// A stored family that is gone next session falls back to the Inter
// default and shows a "Font not found" error until re-picked or reset.
Rectangle {
    id: fontCard

    readonly property bool isSystem: SettingsStore.fontFamily.toLowerCase() === "system"
    readonly property bool hasCustom: SettingsStore.fontFamily !== "" && !fontCard.isSystem
    // Last family we already prompted a restart for: a fresh pick
    // re-prompts, repeated appearanceChanged signals for the same
    // family do not.
    property string seenFamily: "__none__"

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
            text: qsTr("Font not found: %1. Using Inter instead.").arg(SettingsStore.fontFamily)
            font.pixelSize: 12
            color: AppTheme.snapGuide
        }

        RowLayout {
            Layout.fillWidth: true
            visible: SettingsStore.fontRestartNeeded
            spacing: 8

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("New font applies after a restart.")
                font.pixelSize: 11
                color: AppTheme.muted
            }

            Rectangle {
                Layout.preferredWidth: restartLabel.implicitWidth + 20
                Layout.preferredHeight: 28
                radius: AppTheme.radiusSmall
                border.width: 1
                border.color: restartMouse.containsMouse ? AppTheme.foreground : AppTheme.fieldBorder
                color: restartMouse.pressed ? AppTheme.pressed : restartMouse.containsMouse ? AppTheme.hover : AppTheme.surface

                Behavior on color {
                    ColorAnimation {
                        duration: 100
                        easing.type: Easing.OutCubic
                    }
                }

                Text {
                    id: restartLabel
                    anchors.centerIn: parent
                    text: qsTr("Restart")
                    font.pixelSize: 12
                    color: AppTheme.foreground
                }

                MouseArea {
                    id: restartMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: SettingsStore.restartApp()
                }
            }
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
            familyName: qsTr("Inter (default)")
            selected: SettingsStore.fontFamily === "" && !SettingsStore.fontMissing
            selectPolicy: () => SettingsStore.fontFamily = ""
        }

        AppearanceFontRow {
            Layout.fillWidth: true
            fileName: ""
            familyName: qsTr("System default")
            selected: fontCard.isSystem && !SettingsStore.fontMissing
            selectPolicy: () => SettingsStore.fontFamily = "system"
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

    // Restart offer right after a font pick: Restart relaunches at once,
    // Cancel leaves the inline Restart button above for later.
    ConfirmPopup {
        id: restartPopup
        parent: Overlay.overlay
        onConfirmed: SettingsStore.restartApp()
    }

    Connections {
        target: SettingsStore
        function onAppearanceChanged() {
            if (SettingsStore.fontRestartNeeded && fontCard.seenFamily !== SettingsStore.fontFamily) {
                fontCard.seenFamily = SettingsStore.fontFamily;
                restartPopup.ask(qsTr("Restart to apply the new font?"), qsTr("The app font applies after a restart. Restart now?"), qsTr("Restart"));
            }
        }
    }
}
