import QtQuick
import QtQuick.Layouts
import Totm

// One permission row in the approval popup: checkbox plus title and the
// maker's reason. Self-contained for Repeater use; the popup wires
// togglePolicy in onItemAdded so delegates never reach for outer ids.
Rectangle {
    id: row

    property var entry: null
    property bool checked: true
    property var togglePolicy: null

    radius: 6
    color: rowMouse.containsMouse ? AppTheme.hover : "transparent"

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 8

        Rectangle {
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            Layout.alignment: Qt.AlignVCenter
            radius: 6
            border.width: 1
            border.color: AppTheme.fieldBorder
            color: row.checked ? AppTheme.foreground : AppTheme.surface

            AppIcon {
                anchors.centerIn: parent
                kind: "plus"
                rotation: 45
                width: 12
                height: 12
                visible: row.checked
                iconColor: AppTheme.background
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: row.entry ? (row.entry.title || row.entry.id) : ""
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: AppTheme.foreground
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: row.entry ? (row.entry.reason || "") : ""
                font.pixelSize: 11
                color: AppTheme.muted
                elide: Text.ElideRight
            }
        }
    }

    MouseArea {
        id: rowMouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (row.togglePolicy)
                row.togglePolicy(row.entry ? row.entry.id : "");
        }
    }
}
