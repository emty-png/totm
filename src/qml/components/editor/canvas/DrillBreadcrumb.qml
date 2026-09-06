import QtQuick
import Totm

// Active-group breadcrumb. Shows the drilled group name with Up/Root exits.
Rectangle {
    id: crumb

    required property var doc

    visible: crumb.doc !== null && crumb.doc.drillPath.length > 0
    implicitWidth: crumbRow.implicitWidth + 20
    implicitHeight: 32
    radius: 8
    color: AppTheme.surface
    border.width: 1
    border.color: AppTheme.border

    Row {
        id: crumbRow

        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 10
            rightMargin: 10
        }
        spacing: 8

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: {
                if (!crumb.doc || crumb.doc.drillPath.length === 0)
                    return "";
                var top = crumb.doc.findNode(crumb.doc.drillPath[crumb.doc.drillPath.length - 1]);
                return top ? top.name : qsTr("Group");
            }
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: AppTheme.foreground
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Up")
            font.pixelSize: 12
            color: upMouse.containsMouse ? AppTheme.foreground : AppTheme.muted

            MouseArea {
                id: upMouse

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                onClicked: {
                    if (crumb.doc)
                        crumb.doc.drillOut();
                }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Root")
            font.pixelSize: 12
            color: rootMouse.containsMouse ? AppTheme.foreground : AppTheme.muted

            MouseArea {
                id: rootMouse

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                onClicked: {
                    if (crumb.doc)
                        crumb.doc.drillTo(-1);
                }
            }
        }
    }
}
