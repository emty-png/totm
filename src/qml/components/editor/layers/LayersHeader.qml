import QtQuick
import QtQuick.Layouts
import Totm

// Layers list header and empty state.
ColumnLayout {
    id: header

    required property var doc

    spacing: 0

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: 8
        Layout.topMargin: 10
        Layout.bottomMargin: 6
        text: qsTr("Layer")
        font.pixelSize: 13
        font.weight: Font.DemiBold
        color: AppTheme.foreground
    }

    Text {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: 16
        Layout.rightMargin: 16
        visible: !header.doc || header.doc.totalCount() === 0
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: qsTr("Nothing to see here...")
        font.pixelSize: 13
        wrapMode: Text.WordWrap
        color: AppTheme.muted
    }
}
