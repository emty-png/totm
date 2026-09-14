import QtQuick
import QtQuick.Layouts
import Totm

// One font option row: system default (fileName "") or an imported
// file. Family resolves live from the imported map so picked fonts
// preview in their own face. Selection/removal ride policy callbacks
// wired in onItemAdded (same rule as LayersView/Shortcut rows).
// Plain props with defaults (never required): Repeater delegates
// evaluate required bindings before model context attaches.
Rectangle {
    id: fontRow

    property string fileName: ""
    property string familyName: ""
    property bool selected: false
    property var selectPolicy: null
    property var removePolicy: null

    readonly property string resolvedFamily: {
        if (fontRow.fileName === "")
            return "";
        var fam = SettingsStore.importedFontFamilyMap[fontRow.fileName];
        return fam !== undefined ? String(fam) : "";
    }
    readonly property string displayName: {
        if (fontRow.fileName === "")
            return fontRow.familyName !== "" ? fontRow.familyName : qsTr("System default");
        return fontRow.resolvedFamily !== "" ? fontRow.resolvedFamily : fontRow.fileName;
    }
    readonly property bool isActive: {
        if (fontRow.fileName === "")
            return fontRow.selected;
        return SettingsStore.fontFamily === fontRow.resolvedFamily && fontRow.resolvedFamily !== "" && !SettingsStore.fontMissing;
    }

    Layout.fillWidth: true
    implicitHeight: 36
    radius: AppTheme.radiusSmall
    color: fontRow.isActive ? AppTheme.layerSelected : hoverMouse.containsMouse ? AppTheme.hover : "transparent"

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
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (fontRow.fileName === "") {
                if (fontRow.selectPolicy)
                    fontRow.selectPolicy();
            } else if (fontRow.selectPolicy) {
                fontRow.selectPolicy(fontRow.fileName);
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 8

        Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: fontRow.displayName
            font.pixelSize: 12
            font.family: fontRow.resolvedFamily !== "" ? fontRow.resolvedFamily : ""
            color: AppTheme.foreground
            elide: Text.ElideRight
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            visible: fontRow.isActive
            text: qsTr("Selected")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            visible: fontRow.fileName !== ""
            text: qsTr("Remove")
            font.pixelSize: 12
            color: AppTheme.muted

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    mouse.accepted = true;
                    if (fontRow.removePolicy)
                        fontRow.removePolicy(fontRow.fileName);
                }
            }
        }
    }
}
