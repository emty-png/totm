import QtQuick
import QtQuick.Layouts
import Totm

// Rotation, opacity and corner radius. Rotation hides while grouped;
// radius shows for rectangles only.
ColumnLayout {
    id: section

    required property var snapshot

    spacing: 10

    RowLayout {
        visible: section.snapshot.sel.length > 0 && !section.snapshot.hasGroup
        enabled: !section.snapshot.allLocked
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        spacing: 8

        Text {
            Layout.preferredWidth: 52
            text: qsTr("Rotation")
            font.pixelSize: 12
            color: AppTheme.muted
        }
        NumberField {
            Layout.fillWidth: true
            value: section.snapshot.commonOf("rotation").value
            mixed: section.snapshot.commonOf("rotation").mixed
            onCommitted: v => section.snapshot.setAll("rotation", v)
        }
    }

    RowLayout {
        visible: section.snapshot.sel.length > 0 && !section.snapshot.hasGroup
        enabled: !section.snapshot.allLocked
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        spacing: 8

        Text {
            Layout.preferredWidth: 52
            text: qsTr("Opacity")
            font.pixelSize: 12
            color: AppTheme.muted
        }
        NumberField {
            Layout.fillWidth: true
            value: Math.round(section.snapshot.commonOf("opacity").value * 100)
            mixed: section.snapshot.commonOf("opacity").mixed
            minimum: 0
            maximum: 100
            onCommitted: v => section.snapshot.setAll("opacity", v / 100)
        }
    }

    RowLayout {
        visible: section.snapshot.sel.length > 0 && section.snapshot.allOfType("rectangle")
        enabled: !section.snapshot.allLocked
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        spacing: 8

        Text {
            Layout.preferredWidth: 52
            text: qsTr("Radius")
            font.pixelSize: 12
            color: AppTheme.muted
        }
        NumberField {
            Layout.fillWidth: true
            value: section.snapshot.commonOf("radius").value
            mixed: section.snapshot.commonOf("radius").mixed
            minimum: 0
            onCommitted: v => section.snapshot.setAll("radius", v)
        }
    }
}
