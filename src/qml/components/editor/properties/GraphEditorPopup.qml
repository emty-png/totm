import QtQuick
import QtQuick.Controls
import Totm

// Easing graph editor: an animation-type dropdown (presets plus Custom)
// above a draggable cubic-bezier canvas with live curve. Picking a
// preset commits once; touching a handle after that flips the clip to
// Custom. Handle drags stream through one doc transaction (single undo
// entry). Bezier handles mirror the sampler's frozen math.
Popup {
    id: graph

    required property var doc
    required property int clipId

    property string curId: "easeOut"
    property real hx1: 0
    property real hy1: 0
    property real hx2: 0.58
    property real hy2: 1

    readonly property var watchedClip: graph.doc ? graph.doc.animClip(graph.clipId) : null

    width: 264
    padding: 12
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    x: Math.round((parent.width - width) / 2)
    y: 40

    onOpened: graph.reloadFromClip()
    onWatchedClipChanged: {
        if (!graph.watchedClip && graph.opened)
            graph.close();
    }

    background: Rectangle {
        radius: 10
        color: AppTheme.surface
        border.width: 1
        border.color: AppTheme.border
    }

    contentItem: Column {
        width: parent.width
        spacing: 10

        // Header: back plus static title.
        Row {
            width: parent.width
            height: 28
            spacing: 4

            Item {
                width: 28
                height: 28

                AppIcon {
                    anchors.centerIn: parent
                    kind: "caret"
                    rotation: 90
                    width: 14
                    height: 14
                    iconColor: backMouse.containsMouse || backMouse.pressed ? AppTheme.foreground : AppTheme.muted
                }

                MouseArea {
                    id: backMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: graph.close()
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 32
                text: qsTr("Animation type")
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                color: AppTheme.foreground
            }
        }

        // Animation-type dropdown: presets plus a Custom free mode.
        Rectangle {
            id: dropBox

            width: parent.width
            height: 32
            radius: 6
            color: typeMenu.opened || dropMouse.containsMouse || dropMouse.pressed ? AppTheme.hover : AppTheme.surface
            border.width: 1
            border.color: AppTheme.fieldBorder

            Text {
                anchors {
                    left: parent.left
                    right: caretIcon.left
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                    rightMargin: 8
                }
                text: graph.easingTitle()
                font.pixelSize: 12
                elide: Text.ElideRight
                color: AppTheme.foreground
            }

            AppIcon {
                id: caretIcon

                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    rightMargin: 10
                }
                kind: "caret"
                rotation: typeMenu.opened ? 180 : 0
                width: 12
                height: 12
                iconColor: AppTheme.muted

                Behavior on rotation {
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.OutCubic
                    }
                }
            }

            MouseArea {
                id: dropMouse

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (typeMenu.opened)
                        typeMenu.close();
                    else
                        typeMenu.open();
                }
            }

            Popup {
                id: typeMenu

                x: 0
                y: dropBox.height + 4
                width: dropBox.width
                padding: 6
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                transformOrigin: Item.Top

                enter: Transition {
                    NumberAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: 120
                        easing.type: Easing.OutCubic
                    }
                }
                exit: Transition {
                    NumberAnimation {
                        property: "opacity"
                        from: 1
                        to: 0
                        duration: 100
                        easing.type: Easing.InCubic
                    }
                }

                background: Rectangle {
                    radius: 10
                    color: AppTheme.surface
                    border.width: 1
                    border.color: AppTheme.border
                }

                contentItem: Column {
                    spacing: 2

                    Repeater {
                        model: graph.menuOptions()

                        Rectangle {
                            // availableWidth: explicit popup width minus
                            // padding (binding contentWidth here would loop).
                            width: typeMenu.availableWidth
                            height: 30
                            radius: 6
                            color: modelData.id === graph.curId ? AppTheme.hover : optMouse.containsMouse || optMouse.pressed ? AppTheme.hover : "transparent"

                            Text {
                                anchors {
                                    left: parent.left
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: 10
                                }
                                text: modelData.name
                                font.pixelSize: 12
                                font.weight: modelData.id === graph.curId ? Font.DemiBold : Font.Normal
                                color: modelData.id === graph.curId ? AppTheme.foreground : AppTheme.muted
                            }

                            MouseArea {
                                id: optMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: graph.pickOption(modelData.id)
                            }
                        }
                    }
                }
            }
        }

        BezierCanvas {
            width: parent.width
            height: 170
            bezier: [graph.hx1, graph.hy1, graph.hx2, graph.hy2]
            easeId: graph.curId
            beginPolicy: () => graph.beginHandle()
            movePolicy: b => graph.moveHandle(b)
            endPolicy: () => graph.endHandle()
        }
    }

    function menuOptions() {
        if (!graph.doc)
            return [];
        var opts = graph.doc.anim.presets.easingPresets().slice();
        opts.push({
            id: "custom",
            name: qsTr("Custom"),
            bezier: null
        });
        return opts;
    }

    function easingTitle() {
        if (!graph.doc)
            return "";
        return graph.doc.anim.presets.easingName(graph.curId);
    }

    function reloadFromClip() {
        var c = graph.doc ? graph.doc.animClip(graph.clipId) : null;
        if (!c)
            return;
        var ez = c.easing || {};
        graph.curId = typeof ez.id === "string" && ez.id !== "" ? ez.id : "easeOut";
        var b = null;
        if (graph.curId === "custom" && ez.bezier)
            b = ez.bezier;
        else if (graph.doc)
            b = graph.doc.anim.presets.easingBezier(graph.curId);
        b = b || [0.25, 0.1, 0.25, 1];
        graph.hx1 = b[0];
        graph.hy1 = b[1];
        graph.hx2 = b[2];
        graph.hy2 = b[3];
    }

    // Dropdown pick: presets commit once, Custom keeps the handles as
    // they stand (already custom means nothing to do).
    function pickOption(id) {
        typeMenu.close();
        if (id === "custom") {
            graph.makeCustom();
            return;
        }
        graph.pickEasing(id);
    }

    function makeCustom() {
        if (graph.curId === "custom" || !graph.doc)
            return;
        graph.curId = "custom";
        graph.doc.setClipEasing(graph.clipId, {
            id: "custom",
            bezier: [graph.hx1, graph.hy1, graph.hx2, graph.hy2]
        });
    }

    function pickEasing(id) {
        if (!graph.doc)
            return;
        graph.curId = id;
        var b = graph.doc.anim.presets.easingBezier(id);
        graph.hx1 = b[0];
        graph.hy1 = b[1];
        graph.hx2 = b[2];
        graph.hy2 = b[3];
        graph.doc.setClipEasing(graph.clipId, {
            id: id
        });
    }

    function beginHandle() {
        if (graph.doc)
            graph.doc.beginTransaction();
    }

    function moveHandle(b) {
        graph.hx1 = b[0];
        graph.hy1 = b[1];
        graph.hx2 = b[2];
        graph.hy2 = b[3];
        graph.curId = "custom";
        if (graph.doc)
            graph.doc.setClipEasing(graph.clipId, {
                id: "custom",
                bezier: [graph.hx1, graph.hy1, graph.hx2, graph.hy2]
            });
    }

    function endHandle() {
        if (graph.doc)
            graph.doc.endTransaction();
    }
}
