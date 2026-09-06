import QtQuick

// Frameless resize handles (right / bottom / corner).
Item {
    id: handles

    required property Window window

    anchors.fill: parent
    z: 100

    MouseArea {
        anchors {
            right: parent.right
            top: parent.top
            bottom: parent.bottom
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
