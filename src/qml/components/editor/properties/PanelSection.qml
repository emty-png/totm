import QtQuick
import QtQuick.Layouts
import Totm

// One design-panel section: top hairline, bold title row with optional
// add/remove actions, then caller body. Next section's top line doubles
// as this section's bottom line, so no trailing divider. Actions are
// direct children (never injected) so they always render.
ColumnLayout {
    id: section

    property string title: ""
    property bool showAdd: false
    property bool showRemove: false
    // Compact (empty body): title centers itself with 10px above/below
    // instead of the roomy 12/8/12 content rhythm.
    property bool compact: false

    signal addClicked
    signal removeClicked

    default property alias content: body.data

    spacing: 0

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: AppTheme.border
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: 8
        Layout.topMargin: section.compact ? 10 : 12
        Layout.bottomMargin: section.compact ? 10 : 8
        spacing: 4

        Text {
            Layout.fillWidth: true
            text: section.title
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: AppTheme.foreground
            elide: Text.ElideRight
        }

        Row {
            spacing: 4

            PanelIconButton {
                iconKind: "plus"
                filled: false
                strong: true
                iconSize: 16
                visible: section.showAdd
                onClicked: section.addClicked()
            }

            PanelIconButton {
                iconKind: "minimize"
                filled: false
                strong: true
                iconSize: 16
                visible: section.showRemove
                onClicked: section.removeClicked()
            }
        }
    }

    ColumnLayout {
        id: body

        visible: !section.compact
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        Layout.bottomMargin: 12
        spacing: 8
    }
}
