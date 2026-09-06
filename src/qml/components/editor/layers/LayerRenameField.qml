import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Name slot of a layers row: static text plus inline rename editor.
Item {
    id: namer

    required property string rowName
    required property bool editing
    required property bool selected
    required property bool hovered
    required property bool rowVisible
    property var commitPolicy: null
    property var cancelPolicy: null

    property string editOrig: ""

    implicitWidth: 40
    implicitHeight: 26
    Layout.fillWidth: true

    Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        visible: !namer.editing
        text: namer.rowName
        font.pixelSize: 12
        elide: Text.ElideRight
        opacity: namer.rowVisible ? 1 : 0.45
        color: namer.selected ? AppTheme.foreground : namer.hovered ? AppTheme.foreground : AppTheme.muted

        Behavior on opacity {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }
        Behavior on color {
            ColorAnimation {
                duration: 100
                easing.type: Easing.OutCubic
            }
        }
    }

    TextField {
        id: nameField

        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 26
        visible: namer.editing
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
            border.color: nameField.activeFocus ? AppTheme.selection : "transparent"
        }

        onVisibleChanged: {
            if (visible) {
                namer.editOrig = namer.rowName;
                nameField.text = namer.rowName;
                nameField.selectAll();
                nameField.forceActiveFocus();
            }
        }
        onAccepted: namer.settleRename()
        onActiveFocusChanged: {
            if (!nameField.activeFocus && nameField.visible)
                namer.settleRename();
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                if (namer.cancelPolicy)
                    namer.cancelPolicy();
                event.accepted = true;
            }
        }
    }

    function settleRename() {
        if (!namer.editing)
            return;
        if (nameField.text === namer.editOrig) {
            if (namer.cancelPolicy)
                namer.cancelPolicy();
        } else if (namer.commitPolicy) {
            namer.commitPolicy(nameField.text);
        }
    }
}
