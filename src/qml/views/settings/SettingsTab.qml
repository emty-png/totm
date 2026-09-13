import QtQuick
import QtQuick.Layouts
import Totm

// Settings tab: same language as the titlebar document tabs (fixed
// 184px, background fill when active, hover/pressed otherwise, right
// divider). No drag, no close: settings tabs switch views only.
Rectangle {
    id: tab

    property string tabId: ""
    property string title: ""
    property bool active: false
    property var clickPolicy: null

    signal clicked

    Layout.preferredWidth: 184
    Layout.fillHeight: true
    color: tab.active ? AppTheme.background : tabMouse.pressed ? AppTheme.pressed : tabMouse.containsMouse ? AppTheme.hover : "transparent"

    Behavior on color {
        ColorAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }

    Text {
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 12
            rightMargin: 12
        }
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: tab.title
        font.pixelSize: 12
        color: tab.active || tabMouse.containsMouse || tabMouse.pressed ? AppTheme.foreground : AppTheme.muted

        Behavior on color {
            ColorAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }
    }

    // Right divider.
    Rectangle {
        anchors {
            right: parent.right
            top: parent.top
            bottom: parent.bottom
        }
        width: 1
        color: AppTheme.border
    }

    MouseArea {
        id: tabMouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (tab.clickPolicy)
                tab.clickPolicy(tab.tabId);
            else
                tab.clicked();
        }
    }
}
