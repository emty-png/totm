import QtQuick
import QtQuick.Layouts
import Totm

// One workspace row in the home sidebar. Click selects, double-click
// renames, hover reveals delete (never for Default). Accepts design
// card drops to move designs in.
Item {
    id: rowRoot

    // Plain props with defaults (never required): Repeater delegates
    // evaluate required bindings before the model context attaches,
    // which breaks modelData reads. Same rule as LayersRow/TitleBarTab.
    property string workspaceId: ""
    property string workspaceName: ""
    property bool isDefault: false
    property bool selected: false
    property bool editing: false

    property var selectPolicy: null
    property var beginRenamePolicy: null
    property var commitPolicy: null
    property var cancelPolicy: null
    property var deletePolicy: null
    property var movePolicy: null

    readonly property bool hovered: rowMouse.containsMouse || deleteMouse.containsMouse

    Layout.fillWidth: true
    Layout.preferredHeight: 32

    LayerHighlight {
        selected: rowRoot.selected || dropArea.containsDrag
        hovered: rowRoot.hovered
        lifted: false
    }

    DropArea {
        id: dropArea

        anchors.fill: parent
        keys: ["application/x-totm-designs"]
        onDropped: drop => {
            var ids = drop.mimeData["application/x-totm-designs"];
            if (ids && rowRoot.movePolicy)
                rowRoot.movePolicy(ids, rowRoot.workspaceId);
        }
    }

    MouseArea {
        id: rowMouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onClicked: {
            if (rowRoot.selectPolicy)
                rowRoot.selectPolicy(rowRoot.workspaceId);
        }
        onDoubleClicked: {
            if (rowRoot.beginRenamePolicy)
                rowRoot.beginRenamePolicy(rowRoot.workspaceId);
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 8
        spacing: 8

        Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            visible: !rowRoot.editing
            text: rowRoot.workspaceName
            font.pixelSize: 12
            elide: Text.ElideRight
            color: rowRoot.selected ? AppTheme.foreground : rowRoot.hovered ? AppTheme.foreground : AppTheme.muted

            Behavior on color {
                ColorAnimation {
                    duration: 100
                    easing.type: Easing.OutCubic
                }
            }
        }

        // Inline rename editor, same language as the layers list.
        RenameField {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            visible: rowRoot.editing
            initialText: rowRoot.workspaceName
            onCommitted: text => {
                if (rowRoot.commitPolicy)
                    rowRoot.commitPolicy(rowRoot.workspaceId, text);
            }
            onCancelled: {
                if (rowRoot.cancelPolicy)
                    rowRoot.cancelPolicy(rowRoot.workspaceId);
            }
        }

        Item {
            Layout.preferredWidth: 22
            Layout.preferredHeight: 22
            Layout.alignment: Qt.AlignVCenter
            visible: !rowRoot.isDefault && (rowRoot.hovered || rowRoot.selected) && !rowRoot.editing

            AppIcon {
                anchors.centerIn: parent
                width: 14
                height: 14
                kind: "close"
                iconColor: deleteMouse.containsMouse ? AppTheme.foreground : AppTheme.muted
            }

            MouseArea {
                id: deleteMouse

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                onClicked: {
                    if (rowRoot.deletePolicy)
                        rowRoot.deletePolicy(rowRoot.workspaceId);
                }
            }
        }
    }
}
