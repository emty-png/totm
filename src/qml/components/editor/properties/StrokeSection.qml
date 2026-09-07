import QtQuick
import QtQuick.Layouts
import Totm

// Single stroke per shape; width 0 counts as missing. The header swaps
// between + (no stroke) and - (has stroke) so shapes can carry no
// stroke. Shapes only.
PanelSection {
    id: section

    required property var snapshot

    property var widthCommon: section.snapshot.commonOf("strokeWidth")
    property bool hasStroke: section.widthCommon.mixed || section.widthCommon.value > 0

    title: qsTr("Stroke")
    visible: section.snapshot.sel.length > 0 && !section.snapshot.hasGroup
    enabled: !section.snapshot.allLocked
    compact: !section.hasStroke
    showAdd: !section.hasStroke
    showRemove: section.hasStroke
    onAddClicked: section.snapshot.setAll("strokeWidth", 1)
    onRemoveClicked: section.snapshot.setAll("strokeWidth", 0)

    RowLayout {
        visible: section.hasStroke
        Layout.fillWidth: true
        spacing: 8

        Rectangle {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: 6
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
            Layout.preferredWidth: 76
            prefix: "S"
            value: section.widthCommon.value
            mixed: section.widthCommon.mixed
            minimum: 0
            onCommitted: v => section.snapshot.setAll("strokeWidth", v)
            onScrubStarted: section.snapshot.beginScrub()
            onScrubFinished: section.snapshot.endScrub()
        }
    }
}
