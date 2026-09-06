import QtQuick
import QtQuick.Layouts
import Totm

// One layers-list row. Inset highlight, leading icon, editable name,
// hover-revealed toggles. Data arrives as explicit props; clicks leave
// through policies wired by the view.
Item {
    id: rowRoot

    property bool selected: false
    property string rowName: ""
    property string rowType: "rectangle"
    property int rowUid: -1
    property bool rowVisible: true
    property bool rowLocked: false
    property bool editing: false
    property bool isGroup: false
    property bool nodeExpanded: true
    property int indent: 0
    property var togglePolicy: null
    property string editOrig: ""
    property var clickPolicy: null
    property var eyePolicy: null
    property var lockPolicy: null
    property var contextPolicy: null
    property var renamePolicy: null
    property var commitPolicy: null
    property var cancelPolicy: null
    property var dragPressPolicy: null
    property var dragMovePolicy: null
    property var dragReleasePolicy: null

    property real dragLift: 0
    Behavior on dragLift {
        NumberAnimation {
            duration: 80
            easing.type: Easing.OutCubic
        }
    }
    transform: Translate {
        y: rowRoot.dragLift
    }
    z: rowRoot.dragLift !== 0 ? 10 : 0

    readonly property bool hovered: rowMouse.containsMouse || toggles.hovered || leading.hovered

    Layout.fillWidth: true
    Layout.preferredHeight: 32

    LayerHighlight {
        selected: rowRoot.selected
        hovered: rowRoot.hovered
        lifted: rowRoot.dragLift !== 0
    }

    MouseArea {
        id: rowMouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: event => {
            if (event.button === Qt.RightButton && rowRoot.contextPolicy)
                rowRoot.contextPolicy(rowRoot.rowUid, event.x, event.y);
            else if (event.button === Qt.LeftButton && rowRoot.dragPressPolicy)
                rowRoot.dragPressPolicy(rowRoot.rowUid, event.x, event.y, event.modifiers);
        }
        onPositionChanged: event => {
            if (pressed && rowRoot.dragMovePolicy)
                rowRoot.dragMovePolicy(rowRoot.rowUid, event.x, event.y);
        }
        onReleased: {
            if (rowRoot.dragReleasePolicy)
                rowRoot.dragReleasePolicy();
        }
        onCanceled: {
            if (rowRoot.dragReleasePolicy)
                rowRoot.dragReleasePolicy();
        }
        onClicked: event => {
            if (event.button === Qt.LeftButton && rowRoot.clickPolicy)
                rowRoot.clickPolicy(rowRoot.rowUid, event.modifiers);
        }
        onDoubleClicked: event => {
            if (event.button === Qt.LeftButton && rowRoot.renamePolicy)
                rowRoot.renamePolicy(rowRoot.rowUid);
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16 + rowRoot.indent * 16
        anchors.rightMargin: 8
        spacing: 8

        LayerLeading {
            id: leading

            Layout.alignment: Qt.AlignVCenter
            isGroup: rowRoot.isGroup
            nodeExpanded: rowRoot.nodeExpanded
            rowType: rowRoot.rowType
            selected: rowRoot.selected
            rowVisible: rowRoot.rowVisible
            togglePolicy: () => {
                if (rowRoot.togglePolicy)
                    rowRoot.togglePolicy(rowRoot.rowUid);
            }
        }

        LayerRenameField {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            rowName: rowRoot.rowName
            editing: rowRoot.editing
            selected: rowRoot.selected
            hovered: rowRoot.hovered
            rowVisible: rowRoot.rowVisible
            commitPolicy: text => {
                if (rowRoot.commitPolicy)
                    rowRoot.commitPolicy(rowRoot.rowUid, text);
            }
            cancelPolicy: () => {
                if (rowRoot.cancelPolicy)
                    rowRoot.cancelPolicy(rowRoot.rowUid);
            }
        }

        LayerToggles {
            id: toggles

            Layout.alignment: Qt.AlignVCenter
            rowVisible: rowRoot.rowVisible
            rowLocked: rowRoot.rowLocked
            editing: rowRoot.editing
            rowHovered: rowMouse.containsMouse || leading.hovered
            eyePolicy: () => {
                if (rowRoot.eyePolicy)
                    rowRoot.eyePolicy(rowRoot.rowUid);
            }
            lockPolicy: () => {
                if (rowRoot.lockPolicy)
                    rowRoot.lockPolicy(rowRoot.rowUid);
            }
        }
    }
}
