import QtQuick
import Totm

// Home tab sidebar. Empty for now.
// Matches web `.home-sidebar`: 230px, background fill, 1px right border.
Item {
    id: sideBar

    implicitWidth: 230
    implicitHeight: 200

    Rectangle {
        anchors.fill: parent
        color: AppTheme.background
    }

    Rectangle {
        anchors {
            right: parent.right
            top: parent.top
            bottom: parent.bottom
        }
        width: 1
        color: AppTheme.border
    }
}
