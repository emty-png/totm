import QtQuick
import QtQuick.Layouts
import Totm

// Colors card: edits one theme at a time (defaults to the live theme).
// Rows arrive via onItemAdded so delegates never reach for outer ids
// (same rule as LayersView/Shortcut rows).
Rectangle {
    id: colorsCard

    property bool editingDark: AppTheme.isDark

    readonly property var colorKeys: ["background", "foreground", "surface", "border", "muted", "hover", "pressed", "closeHover", "closePressed", "canvas", "sceneFrame", "fieldBorder", "selection", "snapGuide", "layerSelected"]
    readonly property bool hasCustom: {
        var map = colorsCard.editingDark ? SettingsStore.darkColors : SettingsStore.lightColors;
        return Object.keys(map).length > 0;
    }
    property string pickerKey: ""

    Layout.fillWidth: true
    implicitHeight: colorsBody.implicitHeight + 24
    radius: AppTheme.radiusLarge
    border.width: 1
    border.color: AppTheme.border
    color: AppTheme.surface

    ColumnLayout {
        id: colorsBody

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
                text: qsTr("Colors")
                font.pixelSize: 12
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                color: AppTheme.foreground
            }

            Text {
                text: qsTr("Reset")
                font.pixelSize: 12
                color: colorsCard.hasCustom ? AppTheme.foreground : AppTheme.muted
                opacity: colorsCard.hasCustom ? 1 : 0.4

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: colorsCard.hasCustom ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (colorsCard.hasCustom)
                            SettingsStore.resetAllAppearanceColors(colorsCard.editingDark);
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            SegmentedOption {
                label: qsTr("Light")
                active: !colorsCard.editingDark
                onClicked: colorsCard.editingDark = false
            }

            SegmentedOption {
                label: qsTr("Dark")
                active: colorsCard.editingDark
                onClicked: colorsCard.editingDark = true
            }
        }

        Repeater {
            model: colorsCard.colorKeys

            onItemAdded: (idx, item) => {
                item.colorKey = colorsCard.colorKeys[idx];
                item.editingDark = Qt.binding(() => colorsCard.editingDark);
                item.openPolicy = (key, anchor, ax, ay) => colorsCard.openPickerFor(key, anchor, ax, ay);
            }

            delegate: AppearanceColorRow {
                Layout.fillWidth: true
            }
        }
    }

    ColorPickerPopup {
        id: picker

        allowGradient: false
        onCommitted: c => {
            if (colorsCard.pickerKey !== "")
                SettingsStore.setAppearanceColor(colorsCard.pickerKey, colorsCard.editingDark, String(c));
        }
    }

    function openPickerFor(key, anchor, ax, ay) {
        colorsCard.pickerKey = key;
        var map = colorsCard.editingDark ? SettingsStore.darkColors : SettingsStore.lightColors;
        var current = map[key] || AppTheme.defaultColor(key, colorsCard.editingDark);
        picker.openFor(current, anchor, ax, ay);
    }
}
