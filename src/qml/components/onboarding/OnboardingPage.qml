import QtQuick
import QtQuick.Layouts
import Totm

// Single welcome-tour page: centered icon tile, title and short body.
// Colors/radii resolve from AppTheme only so light/dark and
// sharp/rounded/pill presets apply with no per-page work.
ColumnLayout {
    id: page

    property string iconKind: "sparkle"
    property string title: ""
    property string body: ""

    spacing: 12

    Rectangle {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: 56
        Layout.preferredHeight: 56
        radius: AppTheme.radiusMedium
        border.width: 1
        border.color: AppTheme.fieldBorder
        color: AppTheme.background

        AppIcon {
            anchors.centerIn: parent
            width: 24
            height: 24
            kind: page.iconKind
            iconColor: AppTheme.foreground
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.topMargin: 4
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: page.title
        font.pixelSize: 18
        font.weight: Font.DemiBold
        color: AppTheme.foreground
    }

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: page.body
        font.pixelSize: 13
        lineHeight: 1.35
        color: AppTheme.muted
    }
}
