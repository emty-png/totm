import QtQuick
import QtQuick.Layouts
import Totm

// Radius + opacity rows for one blur branch (grain reuses it for size
// + amount via sizePrefix/sizeMaximum). Pure over explicit props: the
// owner collects common values and patches a single role per commit.
ColumnLayout {
    id: fields

    required property real radiusValue
    required property bool radiusMixed
    required property real opacityValue
    required property bool opacityMixed
    property string sizePrefix: "R"
    property real sizeMaximum: 100

    signal radiusCommitted(real value)
    signal opacityCommitted(real value)
    signal scrubStarted
    signal scrubFinished

    spacing: 8

    NumberField {
        Layout.fillWidth: true
        prefix: fields.sizePrefix
        suffix: qsTr("px")
        minimum: 0
        maximum: fields.sizeMaximum
        value: fields.radiusValue
        mixed: fields.radiusMixed
        onCommitted: v => fields.radiusCommitted(v)
        onScrubStarted: fields.scrubStarted()
        onScrubFinished: fields.scrubFinished()
    }

    NumberField {
        Layout.fillWidth: true
        suffix: "%"
        minimum: 0
        maximum: 100
        value: Math.round(fields.opacityValue * 100)
        mixed: fields.opacityMixed
        onCommitted: v => fields.opacityCommitted(v / 100)
        onScrubStarted: fields.scrubStarted()
        onScrubFinished: fields.scrubFinished()
    }
}
