import QtQuick
import QtQuick.Controls
import Totm

// Hex color field (#rrggbb, accepts rgb shorthand and bare hex).
// Shows `mixed` as "Mixed"; invalid text gets a red border and reverts.
TextField {
    id: field

    property string value: "#000000"
    property bool mixed: false

    signal committed(string newColor)

    implicitHeight: 28
    leftPadding: 8
    rightPadding: 8
    font.pixelSize: 12
    color: AppTheme.foreground
    placeholderText: field.mixed ? qsTr("Mixed") : ""
    placeholderTextColor: AppTheme.muted
    selectByMouse: true

    readonly property bool valid: field.normalize(field.text) !== ""

    background: Rectangle {
        radius: 6
        color: field.activeFocus ? AppTheme.hover : field.hovered ? AppTheme.hover : AppTheme.surface
        border.width: 1
        border.color: !field.valid ? "#e81123" : field.activeFocus ? AppTheme.selection : AppTheme.fieldBorder
    }

    Component.onCompleted: field.text = field.mixed ? "" : field.value
    onValueChanged: {
        if (!field.activeFocus)
            field.text = field.mixed ? "" : field.value;
    }
    onMixedChanged: {
        if (!field.activeFocus)
            field.text = field.mixed ? "" : field.value;
    }
    onAccepted: field.commit()
    onActiveFocusChanged: {
        if (!field.activeFocus)
            field.commit();
    }

    function normalize(raw) {
        var t = raw.trim().toLowerCase();
        if (t.charAt(0) === "#")
            t = t.slice(1);
        if (/^[0-9a-f]{3}$/.test(t))
            t = t.charAt(0) + t.charAt(0) + t.charAt(1) + t.charAt(1) + t.charAt(2) + t.charAt(2);
        if (/^[0-9a-f]{6}$/.test(t))
            return "#" + t;
        return "";
    }

    function commit() {
        // Enter always finishes editing: blur even when nothing changed.
        field.focus = false;
        var c = field.normalize(field.text);
        if (c === "") {
            field.text = field.mixed ? "" : field.value;
            return;
        }
        field.text = c;
        if (!field.mixed && c === field.value.toLowerCase())
            return;
        field.committed(c);
    }
}
