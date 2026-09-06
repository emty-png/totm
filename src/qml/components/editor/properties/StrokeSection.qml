import QtQuick
import QtQuick.Layouts
import Totm

// Stroke color and width. Shapes only, hidden while grouped.
ColumnLayout {
    id: section

    required property var snapshot

    spacing: 6

    visible: section.snapshot.sel.length > 0 && !section.snapshot.hasGroup
    enabled: !section.snapshot.allLocked
    Layout.fillWidth: true
    Layout.leftMargin: 12
    Layout.rightMargin: 12

    Text {
        text: qsTr("Stroke")
        font.pixelSize: 12
        color: AppTheme.muted
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Rectangle {
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            Layout.alignment: Qt.AlignVCenter
            radius: 5
            color: section.snapshot.commonOf("stroke").value
            border.width: 1
            border.color: AppTheme.border
        }
        HexField {
            Layout.fillWidth: true
            value: String(section.snapshot.commonOf("stroke").value)
            mixed: section.snapshot.commonOf("stroke").mixed
            onCommitted: c => section.snapshot.setAll("stroke", c)
        }
        NumberField {
            Layout.preferredWidth: 64
            value: section.snapshot.commonOf("strokeWidth").value
            mixed: section.snapshot.commonOf("strokeWidth").mixed
            minimum: 0
            onCommitted: v => section.snapshot.setAll("strokeWidth", v)
        }
    }
}
