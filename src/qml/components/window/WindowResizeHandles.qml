import QtQuick

// Frameless resize handles (right / bottom / corner).
// Hidden while maximized/fullscreen: the frame owns the geometry
// there and startSystemResize would no-op or fight the compositor.
Item {
    id: handles

    required property Window window

    anchors.fill: parent
    z: 100
    visible: window.visibility !== Window.Maximized && window.visibility !== Window.FullScreen

    MouseArea {
        anchors {
            right: parent.right
            top: parent.top
            bottom: parent.bottom
            // Titlebar height: the drag area above owns presses there.
            topMargin: 45
        }
        width: 5
        cursorShape: Qt.SizeHorCursor
        acceptedButtons: Qt.LeftButton
        onPressed: mouse => handles.window.startSystemResize(Qt.RightEdge)
    }
    MouseArea {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: 5
        cursorShape: Qt.SizeVerCursor
        acceptedButtons: Qt.LeftButton
        onPressed: mouse => handles.window.startSystemResize(Qt.BottomEdge)
    }
    MouseArea {
        anchors {
            right: parent.right
            bottom: parent.bottom
        }
        width: 12
        height: 12
        cursorShape: Qt.SizeFDiagCursor
        acceptedButtons: Qt.LeftButton
        onPressed: mouse => handles.window.startSystemResize(Qt.RightEdge | Qt.BottomEdge)
    }
}
