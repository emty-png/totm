import QtQuick
import QtQuick.Layouts
import Totm

// Document tab: 4x the 46px home tab = 184px. Same hover behavior as
// the window-control buttons; no hover feedback while active.
Rectangle {
    id: docTab

    property string title: "Untitled"
    property bool active: false

    signal clicked
    signal closeRequested

    Layout.preferredWidth: 184
    Layout.fillHeight: true
    color: docTab.active ? AppTheme.background : mouse.pressed || closeBtn.hovered ? AppTheme.pressed : mouse.containsMouse || closeBtn.hovered ? AppTheme.hover : "transparent"

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
            rightMargin: 52
        }
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: docTab.title
        font.pixelSize: 12
        color: docTab.active || mouse.containsMouse || mouse.pressed || closeBtn.hovered ? AppTheme.foreground : AppTheme.muted

        Behavior on color {
            ColorAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }
    }

    // Right divider, like web `.titlebar-tab { border-right: ... }`
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
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: event => {
            if (event.button === Qt.MiddleButton)
                docTab.closeRequested();
            else
                docTab.clicked();
        }
    }

    // Close zone: a real window-control button (same hover language as the
    // rest of the bar), revealed when active or hovered, like web
    // `.titlebar-tab:not(.active) .titlebar-tab-close`.
    // Declared after the tab MouseArea so it stays on top of it.
    Item {
        anchors {
            right: parent.right
            top: parent.top
            bottom: parent.bottom
        }
        width: 46
        visible: opacity > 0
        // closeBtn keeps the zone visible once hovered (hover doesn't
        // propagate to the tab MouseArea underneath).
        opacity: (docTab.active || mouse.containsMouse || closeBtn.hovered) ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }

        TitleBarButton {
            id: closeBtn
            anchors.fill: parent
            iconKind: "close"
            onClicked: docTab.closeRequested()
        }
    }
}
