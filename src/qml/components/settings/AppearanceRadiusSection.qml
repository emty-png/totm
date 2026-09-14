import QtQuick
import QtQuick.Layouts
import Totm

// Corners card: Sharp / Rounded / Pill presets plus Custom per-size
// values (0..28px). Effective radii live in AppTheme; custom fields
// write straight to SettingsStore.
Rectangle {
    id: radiusCard

    readonly property bool isCustom: SettingsStore.radiusPreset === "custom"

    Layout.fillWidth: true
    implicitHeight: radiusBody.implicitHeight + 24
    radius: AppTheme.radiusLarge
    border.width: 1
    border.color: AppTheme.border
    color: AppTheme.surface

    ColumnLayout {
        id: radiusBody

        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                Layout.fillWidth: true
                text: qsTr("Corners")
                font.pixelSize: 12
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                color: AppTheme.foreground
            }

            PanelIconButton {
                iconKind: "gear"
                filled: false
                active: radiusCard.isCustom
                strong: true
                iconSize: 16
                onClicked: SettingsStore.radiusPreset = radiusCard.isCustom ? "rounded" : "custom"
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: 8
            rowSpacing: 8

            SegmentedOption {
                label: qsTr("Sharp")
                active: SettingsStore.radiusPreset === "sharp"
                onClicked: SettingsStore.radiusPreset = "sharp"
            }

            SegmentedOption {
                label: qsTr("Rounded")
                active: SettingsStore.radiusPreset === "rounded"
                onClicked: SettingsStore.radiusPreset = "rounded"
            }

            SegmentedOption {
                label: qsTr("Pill")
                active: SettingsStore.radiusPreset === "pill"
                onClicked: SettingsStore.radiusPreset = "pill"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: radiusCard.isCustom
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: qsTr("Small")
                    font.pixelSize: 11
                    color: AppTheme.muted
                }

                NumberField {
                    Layout.fillWidth: true
                    value: SettingsStore.customRadiusSmall
                    minimum: 0
                    maximum: 28
                    onCommitted: v => SettingsStore.customRadiusSmall = Math.round(v)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: qsTr("Medium")
                    font.pixelSize: 11
                    color: AppTheme.muted
                }

                NumberField {
                    Layout.fillWidth: true
                    value: SettingsStore.customRadiusMedium
                    minimum: 0
                    maximum: 28
                    onCommitted: v => SettingsStore.customRadiusMedium = Math.round(v)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: qsTr("Large")
                    font.pixelSize: 11
                    color: AppTheme.muted
                }

                NumberField {
                    Layout.fillWidth: true
                    value: SettingsStore.customRadiusLarge
                    minimum: 0
                    maximum: 28
                    onCommitted: v => SettingsStore.customRadiusLarge = Math.round(v)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: qsTr("XLarge")
                    font.pixelSize: 11
                    color: AppTheme.muted
                }

                NumberField {
                    Layout.fillWidth: true
                    value: SettingsStore.customRadiusXLarge
                    minimum: 0
                    maximum: 28
                    onCommitted: v => SettingsStore.customRadiusXLarge = Math.round(v)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: 6
                color: AppTheme.background
                border.width: 1
                border.color: AppTheme.fieldBorder
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: 8
                color: AppTheme.background
                border.width: 1
                border.color: AppTheme.fieldBorder
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: 10
                color: AppTheme.background
                border.width: 1
                border.color: AppTheme.fieldBorder
            }
        }
    }
}
