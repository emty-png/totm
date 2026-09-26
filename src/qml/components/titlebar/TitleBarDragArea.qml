import QtQuick
import QtQuick.Layouts

// Empty draggable region (no title text). Handles system-move + double-click.
// Disabled via dragEnabled (Appearance window settings): the area then
// ignores presses so the compositor owns window moves.
Item {
    id: dragArea

    required property Window window
    property var toggleMaximize: () => {}
    property bool dragEnabled: true

    Layout.fillWidth: true
    Layout.fillHeight: true

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        enabled: dragArea.dragEnabled
        onPressed: mouse => {
            // Windows-style drag-to-restore: dragging a maximized window
            // unmaximizes it first so startSystemMove() can grab it.
            if (dragArea.window.visibility === Window.Maximized || dragArea.window.visibility === Window.FullScreen) {
                dragArea.window.showNormal();
            }
            dragArea.window.startSystemMove();
        }
        onDoubleClicked: dragArea.toggleMaximize()
    }
}
