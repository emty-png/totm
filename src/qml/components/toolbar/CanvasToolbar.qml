import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Floating canvas toolbar: undo/redo, select, shapes (with subtype
// dropdown), pen, text, image.
Rectangle {
    id: toolbar

    property var doc: null

    // Whether the shapes menu is open (used by the canvas outside-click
    // catcher below the toolbar).
    readonly property alias menuOpen: shapesMenu.opened

    function closeMenu() {
        shapesMenu.close();
    }

    // Map the active shape subtype to its toolbar icon.
    function shapeIcon() {
        return ToolState.shapeIconFor(ToolState.activeShapeType);
    }

    implicitWidth: barRow.implicitWidth + 16
    implicitHeight: 44
    radius: 12
    color: AppTheme.surface
    border.width: 1
    border.color: AppTheme.border

    // Swallow clicks in the pill gaps so they never reach the canvas.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    }

    RowLayout {
        id: barRow
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 8
            rightMargin: 8
        }
        spacing: 4

        ToolbarButton {
            iconKind: "undo"
            enabled: !!toolbar.doc && toolbar.doc.canUndo
            onClicked: {
                if (toolbar.doc)
                    toolbar.doc.undo();
            }
        }

        ToolbarButton {
            iconKind: "redo"
            enabled: !!toolbar.doc && toolbar.doc.canRedo
            onClicked: {
                if (toolbar.doc)
                    toolbar.doc.redo();
            }
        }

        // Hairline between history and tools.
        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: 20
            Layout.alignment: Qt.AlignVCenter
            color: AppTheme.border
        }

        ToolbarButton {
            iconKind: "cursor"
            active: ToolState.activeTool === "select"
            onClicked: ToolState.setActiveTool("select")
        }

        // Shapes button + subtype dropdown.
        Item {
            id: shapesWrap
            Layout.preferredWidth: 56
            Layout.preferredHeight: 32

            RowLayout {
                anchors.fill: parent
                spacing: 2

                ToolbarButton {
                    iconKind: toolbar.shapeIcon()
                    active: ToolState.activeTool === "shapes"
                    onClicked: {
                        ToolState.setActiveTool("shapes");
                        shapesMenu.close();
                    }
                }

                // Slim chevron trigger for the subtype menu.
                Rectangle {
                    Layout.preferredWidth: 18
                    Layout.fillHeight: true
                    radius: 6
                    color: chevronMouse.containsMouse || chevronMouse.pressed ? AppTheme.hover : shapesMenu.opened ? AppTheme.hover : "transparent"

                    AppIcon {
                        anchors.centerIn: parent
                        kind: "caret"
                        scale: 0.65
                        rotation: shapesMenu.opened ? 180 : 0
                        transformOrigin: Item.Center
                        iconColor: AppTheme.muted

                        Behavior on rotation {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    MouseArea {
                        id: chevronMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        // Plain toggle: outside presses never reach the menu
                        // policy (the canvas catcher below the toolbar owns
                        // them), so press and click always agree on state.
                        onClicked: {
                            if (shapesMenu.opened)
                                shapesMenu.close();
                            else
                                shapesMenu.open();
                        }
                    }
                }
            }

            Popup {
                id: shapesMenu
                x: Math.round((shapesWrap.width - width) / 2)
                y: -(implicitHeight + 10)
                implicitWidth: 180
                padding: 6
                closePolicy: Popup.CloseOnEscape
                transformOrigin: Item.Bottom

                enter: Transition {
                    NumberAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: 120
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        property: "scale"
                        from: 0.97
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

                contentItem: ColumnLayout {
                    spacing: 2

                    ToolbarMenuItem {
                        iconKind: "square"
                        label: qsTr("Rectangle")
                        active: ToolState.activeShapeType === "rectangle"
                        onClicked: {
                            ToolState.setActiveShapeType("rectangle");
                            shapesMenu.close();
                        }
                    }
                    ToolbarMenuItem {
                        iconKind: "circle"
                        label: qsTr("Ellipse")
                        active: ToolState.activeShapeType === "ellipse"
                        onClicked: {
                            ToolState.setActiveShapeType("ellipse");
                            shapesMenu.close();
                        }
                    }
                    ToolbarMenuItem {
                        iconKind: "triangle"
                        label: qsTr("Triangle")
                        active: ToolState.activeShapeType === "triangle"
                        onClicked: {
                            ToolState.setActiveShapeType("triangle");
                            shapesMenu.close();
                        }
                    }
                    ToolbarMenuItem {
                        iconKind: "star"
                        label: qsTr("Star")
                        active: ToolState.activeShapeType === "star"
                        onClicked: {
                            ToolState.setActiveShapeType("star");
                            shapesMenu.close();
                        }
                    }
                }
            }
        }

        ToolbarButton {
            iconKind: "pen"
            active: ToolState.activeTool === "pen"
            onClicked: ToolState.setActiveTool("pen")
        }

        ToolbarButton {
            iconKind: "text"
            active: ToolState.activeTool === "text"
            onClicked: ToolState.setActiveTool("text")
        }

        ToolbarButton {
            iconKind: "image"
            active: ToolState.activeTool === "image"
            onClicked: ToolState.setActiveTool("image")
        }
    }
}
