import QtQuick
import QtQuick.Layouts
import Totm

// New-design defaults card: canvas size (with aspect presets), scene
// background and timeline length for Untitled designs. Reads
// SettingsStore directly like the appearance cards (data-only).
Rectangle {
    id: newDesignCard

    Layout.fillWidth: true
    implicitHeight: newDesignBody.implicitHeight + 24
    radius: AppTheme.radiusLarge
    border.width: 1
    border.color: AppTheme.border
    color: AppTheme.surface

    ColumnLayout {
        id: newDesignBody

        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("New designs")
            font.pixelSize: 12
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            color: AppTheme.foreground
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("Canvas size")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            NumberField {
                Layout.fillWidth: true
                suffix: qsTr("px")
                scrubStep: 10
                minimum: 16
                maximum: 7680
                value: SettingsStore.defaultSceneWidth
                onCommitted: v => SettingsStore.defaultSceneWidth = Math.round(v)
            }

            Text {
                text: "×"
                font.pixelSize: 12
                color: AppTheme.muted
            }

            NumberField {
                Layout.fillWidth: true
                suffix: qsTr("px")
                scrubStep: 10
                minimum: 16
                maximum: 7680
                value: SettingsStore.defaultSceneHeight
                onCommitted: v => SettingsStore.defaultSceneHeight = Math.round(v)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            SegmentedOption {
                label: qsTr("16:9")
                active: SettingsStore.defaultSceneWidth === 1920 && SettingsStore.defaultSceneHeight === 1080
                onClicked: SettingsStore.applyScenePreset("16:9")
            }

            SegmentedOption {
                label: qsTr("9:16")
                active: SettingsStore.defaultSceneWidth === 1080 && SettingsStore.defaultSceneHeight === 1920
                onClicked: SettingsStore.applyScenePreset("9:16")
            }

            SegmentedOption {
                label: qsTr("1:1")
                active: SettingsStore.defaultSceneWidth === 1080 && SettingsStore.defaultSceneHeight === 1080
                onClicked: SettingsStore.applyScenePreset("1:1")
            }

            SegmentedOption {
                label: qsTr("4:3")
                active: SettingsStore.defaultSceneWidth === 1600 && SettingsStore.defaultSceneHeight === 1200
                onClicked: SettingsStore.applyScenePreset("4:3")
            }
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("Background")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: AppTheme.radiusSmall
                border.width: 1
                border.color: AppTheme.fieldBorder
                color: SettingsStore.defaultSceneColor
            }

            HexField {
                Layout.fillWidth: true
                value: SettingsStore.defaultSceneColor
                onCommitted: c => SettingsStore.defaultSceneColor = c
            }
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("Timeline length")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        NumberField {
            Layout.fillWidth: true
            suffix: qsTr("s")
            scrubStep: 0.1
            minimum: 0.5
            maximum: 60
            value: SettingsStore.defaultDuration
            onCommitted: v => SettingsStore.defaultDuration = v
        }
    }
}
