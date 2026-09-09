import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Totm

// Layers context menu (sidebar only): Undo / Redo / Copy / Paste /
// Duplicate / Group / Ungroup / Arrange (side submenu) / Rename /
// Delete. Custom popups in the shapes-dropdown style so the theme
// carries over; text rows like Figma (no icons). Actions run straight
// against the document.
Item {
    id: menu

    property var doc: null
    // Row the menu was opened from (-1 for empty-area opens).
    property int contextUid: -1

    readonly property bool hasSelection: menu.computeHasSelection()
    readonly property bool canPaste: !!menu.doc && TabStore.clipboard.length > 0
    readonly property bool contextValid: menu.computeContextValid()
    readonly property bool canGroup: !!menu.doc && menu.doc.canGroup()
    readonly property bool canUngroup: !!menu.doc && menu.doc.canUngroup()
    readonly property bool canUndo: !!menu.doc && menu.doc.canUndo
    readonly property bool canRedo: !!menu.doc && menu.doc.canRedo

    function computeHasSelection() {
        var d = menu.doc;
        if (!d)
            return false;
        d.rev;
        return d.selectedTops().length > 0;
    }

    function computeContextValid() {
        var d = menu.doc;
        if (!d || menu.contextUid < 0)
            return false;
        d.rev;
        return !!d.findNode(menu.contextUid);
    }

    function doCopy() {
        if (menu.doc && menu.hasSelection)
            TabStore.clipboard = menu.doc.copySelected();
    }

    // Copy / Paste / Duplicate / Group / Ungroup / Rename / Delete all
    // land here; Esc and outside presses dismiss via closePolicy.
    function openFor(uid, px, py) {
        menu.contextUid = uid;
        sub.close();
        var w = 170, h = 370;
        main.x = Math.min(Math.max(0, px), Math.max(0, menu.parent.width - w));
        main.y = Math.min(Math.max(0, py), Math.max(0, menu.parent.height - h));
        main.open();
    }

    function closeAll() {
        sub.close();
        main.close();
    }

    // Shared popup backdrop: surface card floating over a soft shadow so
    // menus lift off the canvas instead of reading flat. The card sits
    // 10px inside the popup bounds, leaving bleed room for the shadow;
    // popups below pad 16 so content keeps its 6px gutter to the card.
    component MenuBackground: Item {
        Rectangle {
            id: card
            anchors.fill: parent
            anchors.margins: 10
            radius: 10
            color: AppTheme.surface
            border.width: 1
            border.color: AppTheme.fieldBorder
        }
        MultiEffect {
            source: card
            anchors.fill: card
            shadowEnabled: true
            shadowColor: "#4d000000"
            shadowBlur: 0.45
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 4
        }
    }

    Popup {
        id: main
        implicitWidth: 170
        padding: 16
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        transformOrigin: Item.TopLeft

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

        background: MenuBackground {}

        contentItem: ColumnLayout {
            spacing: 2

            MenuItem {
                label: qsTr("Undo")
                hint: qsTr("Ctrl+Z")
                enabled: menu.canUndo
                onClicked: {
                    menu.doc.undo();
                    menu.closeAll();
                }
            }
            MenuItem {
                label: qsTr("Redo")
                hint: qsTr("Ctrl+Y")
                enabled: menu.canRedo
                onClicked: {
                    menu.doc.redo();
                    menu.closeAll();
                }
            }
            MenuItem {
                label: qsTr("Copy")
                enabled: menu.hasSelection
                onClicked: {
                    menu.doCopy();
                    menu.closeAll();
                }
            }
            MenuItem {
                label: qsTr("Paste")
                enabled: menu.canPaste
                onClicked: {
                    menu.doc.insertCopies(TabStore.clipboard);
                    menu.closeAll();
                }
            }
            MenuItem {
                label: qsTr("Duplicate")
                enabled: menu.hasSelection
                onClicked: {
                    menu.doc.duplicateSelected();
                    menu.closeAll();
                }
            }
            MenuItem {
                label: qsTr("Group")
                enabled: menu.canGroup
                onClicked: {
                    menu.doc.groupSelected();
                    menu.closeAll();
                }
            }
            MenuItem {
                label: qsTr("Ungroup")
                enabled: menu.canUngroup
                onClicked: {
                    menu.doc.ungroupSelected();
                    menu.closeAll();
                }
            }
            MenuItem {
                id: arrangeItem
                label: qsTr("Arrange")
                hint: qsTr("›")
                enabled: menu.hasSelection
                onClicked: {
                    if (sub.opened)
                        sub.close();
                    else
                        sub.open();
                }

                Popup {
                    id: sub
                    // Tucked 2px over the main card so the pair reads as
                    // one connected surface instead of two floating boxes.
                    x: arrangeItem.width - 6
                    y: -6
                    implicitWidth: 190
                    padding: 16
                    closePolicy: Popup.CloseOnEscape
                    transformOrigin: Item.TopLeft

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

                    background: MenuBackground {}

                    contentItem: ColumnLayout {
                        spacing: 2

                        MenuItem {
                            label: qsTr("Bring to the front")
                            onClicked: {
                                menu.doc.bringToFront();
                                menu.closeAll();
                            }
                        }
                        MenuItem {
                            label: qsTr("Move to the back")
                            onClicked: {
                                menu.doc.sendToBack();
                                menu.closeAll();
                            }
                        }
                        MenuItem {
                            label: qsTr("Move forward")
                            onClicked: {
                                menu.doc.moveForward();
                                menu.closeAll();
                            }
                        }
                        MenuItem {
                            label: qsTr("Move backward")
                            onClicked: {
                                menu.doc.moveBackward();
                                menu.closeAll();
                            }
                        }
                    }
                }
            }
            MenuItem {
                label: qsTr("Rename")
                enabled: menu.contextValid
                onClicked: {
                    menu.doc.beginRename(menu.contextUid);
                    menu.closeAll();
                }
            }
            MenuItem {
                label: qsTr("Delete")
                enabled: menu.hasSelection
                onClicked: {
                    menu.doc.deleteSelected();
                    menu.closeAll();
                }
            }
        }
    }
}
