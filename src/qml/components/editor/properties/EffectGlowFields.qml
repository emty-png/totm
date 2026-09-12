import QtQuick
import QtQuick.Layouts
import Totm

// Opaque color + alpha + blur + spread rows for one glow branch (no
// offsets: glow is centered by design). Hex speaks opaque rgb like the
// shadow rows; the alpha field owns opacity. Pure over explicit props:
// the owner collects common values and patches a single role per commit.
ColumnLayout {
    id: fields

    required property string glowRgb
    required property bool colorMixed
    required property real colorAlpha
    required property real blurValue
    required property bool blurMixed
    required property real spreadValue
    required property bool spreadMixed

    signal rgbCommitted(string value)
    signal alphaCommitted(real value)
    signal blurCommitted(real value)
    signal spreadCommitted(real value)
    signal swatchClicked(var anchor, real mouseX, real mouseY)
    signal scrubStarted
    signal scrubFinished

    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Rectangle {
            id: swatch

            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: 6
            color: fields.glowRgb
            border.width: 1
            border.color: AppTheme.border

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => fields.swatchClicked(swatch, mouse.x, mouse.y)
            }
        }

        HexField {
            Layout.fillWidth: true
            value: fields.glowRgb
            mixed: fields.colorMixed
            onCommitted: c => fields.rgbCommitted(c)
        }

        NumberField {
            Layout.preferredWidth: 76
            suffix: "%"
            minimum: 0
            maximum: 100
            value: fields.colorAlpha
            mixed: fields.colorMixed
            onCommitted: v => fields.alphaCommitted(v)
            onScrubStarted: fields.scrubStarted()
            onScrubFinished: fields.scrubFinished()
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "B"
            suffix: qsTr("px")
            minimum: 0
            maximum: 100
            value: fields.blurValue
            mixed: fields.blurMixed
            onCommitted: v => fields.blurCommitted(v)
            onScrubStarted: fields.scrubStarted()
            onScrubFinished: fields.scrubFinished()
        }

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "S"
            suffix: qsTr("px")
            minimum: 0
            maximum: 50
            value: fields.spreadValue
            mixed: fields.spreadMixed
            onCommitted: v => fields.spreadCommitted(v)
            onScrubStarted: fields.scrubStarted()
            onScrubFinished: fields.scrubFinished()
        }
    }
}
