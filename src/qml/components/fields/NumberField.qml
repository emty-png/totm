import QtQuick
import QtQuick.Controls
import Totm

// Numeric property field. Shows `mixed` as "Mixed" placeholder when the
// selection disagrees; commits live (clamped) via committed().
// The adornment zones (prefix/suffix) are scrub handles: drag sideways
// to adjust (Shift for tenth steps, Ctrl for tenfold leaps), click to
// focus for typing.
TextField {
    id: field

    property real value: 0
    property real minimum: -1000000
    property real maximum: 1000000
    property bool mixed: false
    property string prefix: ""
    property string suffix: ""
    // Glyph adornment (TitleBarIcon kind) used instead of prefix text.
    property string prefixIcon: ""
    // Value change per dragged pixel.
    property real scrubStep: 1

    signal committed(real newValue)
    signal scrubStarted
    signal scrubFinished

    implicitHeight: 28
    leftPadding: field.prefixIcon !== "" ? 30 : field.prefix !== "" ? 24 : 8
    rightPadding: field.suffix !== "" ? 26 : 8
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
        color: field.activeFocus ? AppTheme.hover : field.hovered ? AppTheme.hover : AppTheme.surface
        border.width: 1
        border.color: field.activeFocus ? AppTheme.selection : AppTheme.fieldBorder

        Text {
            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
                leftMargin: 8
            }
            visible: field.prefix !== "" && field.prefixIcon === ""
            text: field.prefix
            font.pixelSize: 11
            color: scrubLeft.containsMouse || scrubLeft.pressed ? AppTheme.foreground : AppTheme.muted
        }

        TitleBarIcon {
            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
                leftMargin: 8
            }
            visible: field.prefixIcon !== ""
            kind: field.prefixIcon
            width: 14
            height: 14
            iconColor: scrubLeft.containsMouse || scrubLeft.pressed ? AppTheme.foreground : AppTheme.muted
        }

        Text {
            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
                rightMargin: 8
            }
            visible: field.suffix !== ""
            text: field.suffix
            font.pixelSize: 11
            color: scrubRight.containsMouse || scrubRight.pressed ? AppTheme.foreground : AppTheme.muted
        }
    }

    // Scrub handles over the adornment zones. They float above the text
    // input (z) so presses here never reach it: selecting text and
    // scrubbing never conflict. preventStealing keeps the panel scroll
    // from grabbing mid-drag.
    MouseArea {
        id: scrubLeft

        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
        }
        width: 30
        z: 10
        visible: field.prefix !== "" || field.prefixIcon !== ""
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.SizeHorCursor
        preventStealing: true

        property real pressX: 0
        property real pressValue: 0
        property bool moved: false

        onPressed: mouse => field.scrubPress(mouse, scrubLeft)
        onPositionChanged: mouse => field.scrubMove(mouse, scrubLeft)
        onReleased: field.scrubRelease(scrubLeft)
    }

    MouseArea {
        id: scrubRight

        anchors {
            right: parent.right
            top: parent.top
            bottom: parent.bottom
        }
        width: 28
        z: 10
        visible: field.suffix !== ""
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.SizeHorCursor
        preventStealing: true

        property real pressX: 0
        property real pressValue: 0
        property bool moved: false

        onPressed: mouse => field.scrubPress(mouse, scrubRight)
        onPositionChanged: mouse => field.scrubMove(mouse, scrubRight)
        onReleased: field.scrubRelease(scrubRight)
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

    // Scrub handling shared by both adornment zones. Commits live so the
    // canvas follows the drag; a press without drag focuses for typing.
    // Scrub bounds form one undo entry: started fires before the first
    // live commit, finished once on release.
    function scrubPress(mouse, area) {
        area.pressX = mouse.x;
        var v = parseFloat(field.text);
        area.pressValue = isNaN(v) ? field.value : v;
        area.moved = false;
    }

    function scrubMove(mouse, area) {
        if (!area.pressed)
            return;
        var dx = mouse.x - area.pressX;
        if (!area.moved && Math.abs(dx) >= 3) {
            area.moved = true;
            field.scrubStarted();
        }
        var step = field.scrubStep;
        if (mouse.modifiers & Qt.ShiftModifier)
            step *= 0.1;
        else if (mouse.modifiers & Qt.ControlModifier)
            step *= 10;
        var v = Math.min(field.maximum, Math.max(field.minimum, area.pressValue + dx * step));
        field.text = field.formatValue(v);
        field.committed(v);
    }

    function scrubRelease(area) {
        if (!area.moved) {
            field.forceActiveFocus();
            field.selectAll();
        } else {
            field.scrubFinished();
        }
    }
}
