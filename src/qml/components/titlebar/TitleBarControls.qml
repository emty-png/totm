import QtQuick
import QtQuick.Layouts
import Totm

// Our custom window controls: minimize / maximize-restore / close.
RowLayout {
    id: controls

    required property Window window

    spacing: 0

    TitleBarButton {
        iconKind: "minimize"
        onClicked: controls.window.showMinimized()
    }
    TitleBarButton {
        iconKind: controls.window.visibility === Window.Maximized ? "restore" : "maximize"
        onClicked: controls.toggleMaximize()
    }
    TitleBarButton {
        iconKind: "close"
        hoverColor: AppTheme.closeHover
        pressedColor: AppTheme.closePressed
        hoverTextColor: "#ffffff"
        onClicked: controls.window.close()
    }

    function toggleMaximize() {
        if (controls.window.visibility === Window.Maximized)
            controls.window.showNormal();
        else
            controls.window.showMaximized();
    }
}
