import QtQuick
import QtQuick.Layouts
import Totm

// Home tab content area: empty sidebar on the left, main area on the right.
RowLayout {
    id: homeView

    spacing: 0

    HomeSideBar {
        Layout.preferredWidth: 230
        Layout.fillHeight: true
    }

    // Main area placeholder
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: AppTheme.background
    }
}
