import QtQuick

// Batteries-included marquee overlay: fills its parent, shows the
// selection rect, forwards logic signals. For custom placement (mouse
// below content, rect above), use DragSelection directly instead.
Item {
    id: box
    anchors.fill: parent

    property bool selectionEnabled: true
    property real threshold: 4
    property color fillColor: "#140d99ff"
    property color borderColor: "#0d99ff"
    readonly property bool selecting: logic.selecting
    readonly property rect selection: logic.selection

    signal started
    signal changed(rect area)
    signal finished(rect area, bool additive)
    signal tapped

    DragSelection {
        id: logic
        threshold: box.threshold
        onStarted: box.started()
        onChanged: area => box.changed(area)
        onFinished: (area, additive) => box.finished(area, additive)
        onTapped: box.tapped()
    }

    Rectangle {
        visible: logic.selecting
        x: logic.selection.x
        y: logic.selection.y
        width: logic.selection.width
        height: logic.selection.height
        color: box.fillColor
        border.width: 1
        border.color: box.borderColor
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        enabled: box.selectionEnabled
        onPressed: mouse => logic.pressAt(mouse.x, mouse.y)
        onPositionChanged: mouse => logic.moveTo(mouse.x, mouse.y)
        onReleased: mouse => logic.release(!!(mouse.modifiers & Qt.ShiftModifier))
    }
}
