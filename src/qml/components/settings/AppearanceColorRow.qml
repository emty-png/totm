import QtQuick
import QtQuick.Layouts
import Totm

// One appearance color row: label left, swatch + hex + reset right.
// Plain props with defaults (never required): Repeater delegates
// evaluate required bindings before model context attaches.
Rectangle {
    id: row

    property string colorKey: ""
    property bool editingDark: true
    property var openPolicy: null

    readonly property string defaultValue: AppTheme.defaultColor(row.colorKey, row.editingDark)
    readonly property string currentValue: {
        var map = row.editingDark ? SettingsStore.darkColors : SettingsStore.lightColors;
        var v = map[row.colorKey];
        return v !== undefined ? String(v) : row.defaultValue;
    }
    readonly property bool custom: {
        var m = row.editingDark ? SettingsStore.darkColors : SettingsStore.lightColors;
        return m[row.colorKey] !== undefined;
    }

    function labelFor(key) {
        switch (key) {
        case "background":
            return qsTr("Background");
        case "foreground":
            return qsTr("Foreground");
        case "surface":
            return qsTr("Surface");
        case "border":
            return qsTr("Border");
        case "muted":
            return qsTr("Muted");
        case "hover":
            return qsTr("Hover");
        case "pressed":
            return qsTr("Pressed");
        case "closeHover":
            return qsTr("Close hover");
        case "closePressed":
            return qsTr("Close pressed");
        case "canvas":
            return qsTr("Canvas");
        case "sceneFrame":
            return qsTr("Scene frame");
        case "fieldBorder":
            return qsTr("Field border");
        case "selection":
            return qsTr("Selection accent");
        case "snapGuide":
            return qsTr("Snap guide");
        case "layerSelected":
            return qsTr("Layer selected");
        default:
            return key;
        }
    }

    implicitHeight: 36
    radius: AppTheme.radiusSmall
    color: hoverMouse.containsMouse ? AppTheme.hover : "transparent"

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
            text: row.labelFor(row.colorKey)
            font.pixelSize: 12
            color: AppTheme.foreground
            elide: Text.ElideRight
        }

        Item {
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            Layout.alignment: Qt.AlignVCenter
            visible: row.custom

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
                onClicked: SettingsStore.resetAppearanceColor(row.colorKey, row.editingDark)
            }
        }

        Rectangle {
            Layout.preferredWidth: 44
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: AppTheme.radiusSmall
            color: row.currentValue
            border.width: 1
            border.color: AppTheme.fieldBorder

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    if (row.openPolicy)
                        row.openPolicy(row.colorKey, row, mouse.x, mouse.y);
                }
            }
        }

        HexField {
            Layout.preferredWidth: 96
            Layout.alignment: Qt.AlignVCenter
            value: row.currentValue
            onCommitted: c => SettingsStore.setAppearanceColor(row.colorKey, row.editingDark, c)
        }
    }
}
