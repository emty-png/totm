import QtQuick
import QtQuick.Layouts
import Totm

// Opacity and corner radius with glyph adornments like the other
// sections (contrast/corner icons plus % unit). Shapes only; radius
// shows for every pointed shape except the ellipse, points for stars.
PanelSection {
    id: section

    required property var snapshot

    title: qsTr("Appearance")
    visible: section.snapshot.sel.length > 0 && !section.snapshot.hasGroup
    enabled: !section.snapshot.allLocked

    RowLayout {
        spacing: 8

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            spacing: 4

            Text {
                text: qsTr("Opacity")
                font.pixelSize: 11
                color: AppTheme.muted
            }

            NumberField {
                Layout.fillWidth: true
                prefixIcon: "contrast"
                suffix: "%"
                value: Math.round(section.snapshot.commonOf("opacity").value * 100)
                mixed: section.snapshot.commonOf("opacity").mixed
                minimum: 0
                maximum: 100
                onCommitted: v => section.snapshot.setAll("opacity", v / 100)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            visible: section.snapshot.supportsRadius()
            spacing: 4

            Text {
                text: qsTr("Corner radius")
                font.pixelSize: 11
                color: AppTheme.muted
            }

            NumberField {
                Layout.fillWidth: true
                prefixIcon: "corner"
                value: section.snapshot.commonOf("radius").value
                mixed: section.snapshot.commonOf("radius").mixed
                minimum: 0
                onCommitted: v => section.snapshot.setAll("radius", v)
            }
        }
    }

    ColumnLayout {
        visible: section.snapshot.allOfType("star")
        spacing: 4

        Text {
            text: qsTr("Points")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        RowLayout {
            spacing: 8

            NumberField {
                Layout.fillWidth: true
                Layout.maximumWidth: Math.max(0, (section.width - 32) / 2)
                prefixIcon: "starFill"
                value: section.snapshot.commonOf("points").value
                mixed: section.snapshot.commonOf("points").mixed
                minimum: 3
                maximum: 12
                onCommitted: v => section.snapshot.setAll("points", v)
            }

            Item {
                Layout.fillWidth: true
            }
        }
    }
}
