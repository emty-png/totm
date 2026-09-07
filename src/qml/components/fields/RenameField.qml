import QtQuick
import QtQuick.Controls
import Totm

// Inline rename text field. Opens with initialText selected, commits on
// Enter or focus loss, cancels on Escape. Unchanged text cancels.
TextField {
    id: field

    required property string initialText

    signal committed(string text)
    signal cancelled

    property string editOrig: ""

    font.pixelSize: 12
    color: AppTheme.foreground
    selectionColor: AppTheme.selection
    selectedTextColor: "#ffffff"
    selectByMouse: true
    topPadding: 0
    bottomPadding: 0
    leftPadding: 8
    rightPadding: 8
    verticalAlignment: TextInput.AlignVCenter

    background: Rectangle {
        radius: 6
        color: AppTheme.background
        border.width: 1
        border.color: field.activeFocus ? AppTheme.selection : AppTheme.fieldBorder
    }

    onVisibleChanged: {
        if (visible) {
            field.editOrig = field.initialText;
            field.text = field.initialText;
            field.selectAll();
            field.forceActiveFocus();
        }
    }
    onAccepted: field.settle()
    onActiveFocusChanged: {
        if (!field.activeFocus)
            field.settle();
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            field.cancelled();
            event.accepted = true;
        }
    }

    function settle() {
        field.focus = false;
        if (field.text === field.editOrig)
            field.cancelled();
        else
            field.committed(field.text);
    }
}
