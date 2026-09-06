import QtQuick
import QtQuick.Controls
import Totm

// Numeric property field. Shows `mixed` as "Mixed" placeholder when the
// selection disagrees; commits live (clamped) via committed().
TextField {
    id: field

    property real value: 0
    property real minimum: -1000000
    property real maximum: 1000000
    property bool mixed: false

    signal committed(real newValue)

    implicitHeight: 28
    leftPadding: 8
    rightPadding: 8
    font.pixelSize: 12
    color: AppTheme.foreground
    placeholderText: field.mixed ? qsTr("Mixed") : ""
    placeholderTextColor: AppTheme.muted
    selectByMouse: true
    validator: DoubleValidator {
        bottom: field.minimum
        top: field.maximum
        decimals: 2
        notation: DoubleValidator.StandardNotation
    }

    background: Rectangle {
        radius: 6
        color: field.activeFocus ? AppTheme.hover : "transparent"
        border.width: 1
        border.color: field.activeFocus ? AppTheme.border : "transparent"
    }

    Component.onCompleted: field.text = field.formatValue(field.value)
    onValueChanged: {
        if (!field.activeFocus)
            field.text = field.mixed ? "" : field.formatValue(field.value);
    }
    onMixedChanged: {
        if (!field.activeFocus)
            field.text = field.mixed ? "" : field.formatValue(field.value);
    }
    onAccepted: field.commit()
    onActiveFocusChanged: {
        if (!field.activeFocus)
            field.commit();
    }

    function formatValue(v) {
        return String(Math.round(v * 100) / 100);
    }

    function commit() {
        var v = parseFloat(field.text);
        if (isNaN(v)) {
            field.text = field.mixed ? "" : field.formatValue(field.value);
            return;
        }
        v = Math.min(field.maximum, Math.max(field.minimum, v));
        field.text = field.formatValue(v);
        if (!field.mixed && v === field.value)
            return;
        field.committed(v);
    }
}
