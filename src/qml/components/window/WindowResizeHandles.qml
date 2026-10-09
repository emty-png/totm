import QtQuick

// Frameless resize handles (all edges + corners).
// Hidden while maximized/fullscreen: the frame owns the geometry
// there and startSystemResize would no-op or fight the compositor.
Item {
    id: handles

    required property Window window

    anchors.fill: parent
    z: 100
    visible: window.visibility !== Window.Maximized && window.visibility !== Window.FullScreen

    // Right edge (below the titlebar drag area).
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
    // Left edge.
    MouseArea {
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
            topMargin: 45
        }
        width: 5
        cursorShape: Qt.SizeHorCursor
        acceptedButtons: Qt.LeftButton
        onPressed: mouse => handles.window.startSystemResize(Qt.LeftEdge)
    }
    // Bottom edge.
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
    // Top edge (below the titlebar): thin strip for completeness.
    MouseArea {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            topMargin: 45
        }
        height: 3
        cursorShape: Qt.SizeVerCursor
        acceptedButtons: Qt.LeftButton
        onPressed: mouse => handles.window.startSystemResize(Qt.TopEdge)
    }
    // Corners.
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
    MouseArea {
        anchors {
            left: parent.left
            bottom: parent.bottom
        }
        width: 12
        height: 12
        cursorShape: Qt.SizeBDiagCursor
        acceptedButtons: Qt.LeftButton
        onPressed: mouse => handles.window.startSystemResize(Qt.LeftEdge | Qt.BottomEdge)
    }
    MouseArea {
        anchors {
            left: parent.left
            top: parent.top
            topMargin: 45
        }
        width: 12
        height: 12
        cursorShape: Qt.SizeFDiagCursor
        acceptedButtons: Qt.LeftButton
        onPressed: mouse => handles.window.startSystemResize(Qt.LeftEdge | Qt.TopEdge)
    }
    MouseArea {
        anchors {
            right: parent.right
            top: parent.top
            topMargin: 45
        }
        width: 12
        height: 12
        cursorShape: Qt.SizeBDiagCursor
        acceptedButtons: Qt.LeftButton
        onPressed: mouse => handles.window.startSystemResize(Qt.RightEdge | Qt.TopEdge)
    }
}
