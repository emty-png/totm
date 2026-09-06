import QtQuick
import QtQuick.Layouts
import Totm

// Position and size editors. Group selections edit the bbox (scales the
// subtree); shape selections edit leaves directly via snapshot.setAll.
ColumnLayout {
    id: section

    required property var snapshot

    spacing: 10

    RowLayout {
        visible: section.snapshot.sel.length > 0
        enabled: !section.snapshot.allLocked
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        spacing: 8

        Text {
            Layout.preferredWidth: 52
            text: qsTr("Position")
            font.pixelSize: 12
            color: AppTheme.muted
        }
        NumberField {
            Layout.fillWidth: true
            value: section.snapshot.commonOf("x").value
            mixed: section.snapshot.commonOf("x").mixed
            onCommitted: v => section.snapshot.setAll("x", v)
        }
        NumberField {
            Layout.fillWidth: true
            value: section.snapshot.commonOf("y").value
            mixed: section.snapshot.commonOf("y").mixed
            onCommitted: v => section.snapshot.setAll("y", v)
        }
    }

    RowLayout {
        visible: section.snapshot.sel.length > 0
        enabled: !section.snapshot.allLocked
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        spacing: 8

        Text {
            Layout.preferredWidth: 52
            text: qsTr("Size")
            font.pixelSize: 12
            color: AppTheme.muted
        }
        NumberField {
            Layout.fillWidth: true
            value: section.snapshot.commonOf("w").value
            mixed: section.snapshot.commonOf("w").mixed
            minimum: 1
            onCommitted: v => section.snapshot.setAll("w", v)
        }
        NumberField {
            Layout.fillWidth: true
            value: section.snapshot.commonOf("h").value
            mixed: section.snapshot.commonOf("h").mixed
            minimum: 1
            onCommitted: v => section.snapshot.setAll("h", v)
        }
    }
}
