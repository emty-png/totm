import QtQuick
import QtQuick.Layouts
import Totm

// Fill editors. Single fill edits directly; multiple distinct fills list
// every fill with per-fill recolor. Shapes only, hidden while grouped.
ColumnLayout {
    id: section

    required property var snapshot
    required property var doc

    spacing: 6

    visible: section.snapshot.sel.length > 0 && !section.snapshot.hasGroup
    enabled: !section.snapshot.allLocked
    Layout.fillWidth: true
    Layout.leftMargin: 12
    Layout.rightMargin: 12

    Text {
        text: section.snapshot.distinctFills().length > 1 ? qsTr("Fills") : qsTr("Fill")
        font.pixelSize: 12
        color: AppTheme.muted
    }

    RowLayout {
        visible: section.snapshot.distinctFills().length <= 1
        Layout.fillWidth: true
        spacing: 8

        Rectangle {
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            Layout.alignment: Qt.AlignVCenter
            radius: 5
            color: section.snapshot.commonOf("fill").value
            border.width: 1
            border.color: AppTheme.border
        }
        HexField {
            Layout.fillWidth: true
            value: String(section.snapshot.commonOf("fill").value)
            mixed: section.snapshot.commonOf("fill").mixed
            onCommitted: c => section.snapshot.setAll("fill", c)
        }
    }

    Repeater {
        model: section.snapshot.distinctFills().length > 1 ? section.snapshot.distinctFills() : []

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                Layout.alignment: Qt.AlignVCenter
                radius: 5
                color: modelData
                border.width: 1
                border.color: AppTheme.border
            }
            HexField {
                Layout.fillWidth: true
                value: modelData
                onCommitted: c => section.doc.recolorFill(modelData, c)
            }
        }
    }
}
