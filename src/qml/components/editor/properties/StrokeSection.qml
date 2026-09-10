import QtQuick
import QtQuick.Layouts
import Totm

// Single stroke per shape; width 0 counts as missing. The header swaps
// between + (no stroke) and - (has stroke) so shapes can carry no
// stroke. On text the stroke outlines the glyphs. Shapes only.
PanelSection {
    id: section

    required property var snapshot

    property var widthCommon: section.snapshot.commonOf("strokeWidth")
    property bool hasStroke: section.widthCommon.mixed || section.widthCommon.value > 0

    title: qsTr("Stroke")
    visible: section.snapshot.sel.length > 0 && !section.snapshot.hasGroup && !section.snapshot.allOfType("image")
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
            id: swatch

            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: 6
            color: section.snapshot.commonOf("stroke").value
            border.width: 1
            border.color: AppTheme.border

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => picker.openFor(String(section.snapshot.commonOf("stroke").value), swatch, mouse.x, mouse.y)
            }
        }

        HexField {
            Layout.fillWidth: true
            value: String(section.snapshot.commonOf("stroke").value)
            mixed: section.snapshot.commonOf("stroke").mixed
            onCommitted: c => section.snapshot.setAll("stroke", c)
        }

        NumberField {
            Layout.preferredWidth: 76
            // Text uses the native 1px outline, so the width value is
            // meaningless there: the +/- header already toggles it via
            // 0/1. Hidden for all-text selections, shown otherwise.
            visible: !section.snapshot.allOfType("text")
            prefix: "S"
            value: section.widthCommon.value
            mixed: section.widthCommon.mixed
            minimum: 0
            onCommitted: v => section.snapshot.setAll("strokeWidth", v)
            onScrubStarted: section.snapshot.beginScrub()
            onScrubFinished: section.snapshot.endScrub()
        }
    }

    // Picker flow mirrors FillSection: drags stream through one scrub
    // transaction, typed hex commits discretely on its own.
    ColorPickerPopup {
        id: picker

        onScrubStarted: section.snapshot.beginScrub()
        onCommitted: c => section.snapshot.setAll("stroke", c)
        onScrubFinished: section.snapshot.endScrub()
    }
}
