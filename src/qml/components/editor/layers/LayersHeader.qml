import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Layers list header: title, search field, and empty state. The field
// owns its text (like the home search); matches flow up through
// filterPolicy so the view owns the filter state.
ColumnLayout {
    id: header

    required property var doc
    property var filterPolicy: null
    property bool ready: false

    Component.onCompleted: header.ready = true
    onDocChanged: {
        if (header.ready)
            searchField.text = "";
    }

    spacing: 0

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: 8
        Layout.topMargin: 10
        Layout.bottomMargin: 6
        text: qsTr("Layers")
        font.pixelSize: 13
        font.weight: Font.DemiBold
        color: AppTheme.foreground
    }

    TextField {
        id: searchField

        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        Layout.bottomMargin: 8
        implicitHeight: 32
        visible: !!(header.doc && header.doc.totalCount() > 0)
        placeholderText: qsTr("Search layers...")
        placeholderTextColor: AppTheme.muted
        leftPadding: 12
        rightPadding: 12
        font.pixelSize: 12
        color: AppTheme.foreground
        selectByMouse: true
        onTextChanged: {
            if (header.filterPolicy)
                header.filterPolicy(text);
        }

        background: Rectangle {
            radius: AppTheme.radiusLarge
            color: AppTheme.surface
            border.width: 1
            border.color: searchField.activeFocus ? AppTheme.selection : AppTheme.fieldBorder
        }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                searchField.text = "";
                header.forceActiveFocus();
                event.accepted = true;
            }
        }
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
