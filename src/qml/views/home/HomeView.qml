import QtQuick
import QtQuick.Layouts
import Totm

// Home tab: workspace sidebar on the left, design cards on the right.
// Cards show a live miniature of the stored scene; click opens,
// drag onto a sidebar workspace moves. Empty-area drags marquee-select
// (same DragSelection core as canvas and timeline); Delete removes the
// card selection, right-click opens the card menu.
RowLayout {
    id: homeView

    spacing: 0
    focus: true

    property string selectedWorkspaceId: ""
    property string editingDesignId: ""

    // Card selection state + set ops + marquee hit-testing.
    property var selection: HomeSelection {}

    // Designs of the selected workspace, cached as a stable array:
    // GridView tears down delegates mid-layout if the model array
    // identity changes on every read, so refresh wholesale on change.
    property var filteredDesigns: []

    function refreshFiltered() {
        var out = [];
        var all = LibraryStore.designList;
        for (var i = 0; i < all.length; i++) {
            if (all[i].workspaceId === homeView.selectedWorkspaceId)
                out.push(all[i]);
        }
        homeView.filteredDesigns = out;
    }

    onSelectedWorkspaceIdChanged: homeView.refreshFiltered()

    function openCardMenu(item, designId, x, y) {
        var info = LibraryStore.design(designId);
        var count = homeView.selection.isSelected(designId) ? homeView.selection.selectedIds.length : 1;
        var p = item.mapToItem(gridArea, x, y);
        cardMenu.openFor(designId, !!info.starred, count, p.x, p.y);
    }

    Keys.onDeletePressed: event => {
        if (homeView.editingDesignId !== "")
            return;
        homeView.selection.deleteSelected();
        event.accepted = true;
    }
    Keys.onEscapePressed: event => {
        homeView.selection.clearSelection();
        event.accepted = true;
    }

    Component.onCompleted: {
        homeView.selectedWorkspaceId = LibraryStore.defaultWorkspaceId;
        homeView.refreshFiltered();
    }

    WorkspacePanel {
        Layout.preferredWidth: 230
        Layout.fillHeight: true
        selectedWorkspaceId: homeView.selectedWorkspaceId
        selectPolicy: id => {
            homeView.selectedWorkspaceId = id;
        }
        movePolicy: (idsJson, workspaceId) => {
            var ids = homeView.parseIds(idsJson);
            for (var i = 0; i < ids.length; i++)
                LibraryStore.moveDesign(ids[i], workspaceId);
        }
        openPolicy: id => TabStore.openDesign(id)
    }

    function parseIds(idsJson) {
        try {
            var parsed = JSON.parse(idsJson);
            return Array.isArray(parsed) ? parsed : [];
        } catch (e) {
            return [];
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.topMargin: 12
            Layout.bottomMargin: 8
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: LibraryStore.workspaceName(homeView.selectedWorkspaceId) || qsTr("Workspace")
                font.pixelSize: 16
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                color: AppTheme.foreground
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            visible: homeView.filteredDesigns.length === 0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            text: qsTr("Nothing to see here...")
            font.pixelSize: 13
            color: AppTheme.muted
        }

        Item {
            id: gridArea

            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: homeView.filteredDesigns.length > 0
            clip: true

            // Flow + Repeater (not GridView): delegates instantiate
            // synchronously with stable geometry, which the marquee
            // hit-testing relies on.
            Flickable {
                id: flick

                anchors.fill: parent
                contentWidth: width
                contentHeight: flow.implicitHeight
                clip: true

                Flow {
                    id: flow

                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        leftMargin: 16
                        rightMargin: 16
                        topMargin: 4
                    }
                    spacing: 12

                    Repeater {
                        model: homeView.filteredDesigns

                        DesignCard {
                            designId: modelData.designId
                            designName: modelData.name
                            updatedAt: modelData.updatedAt
                            scene: modelData.scene
                            starred: !!modelData.starred
                            selected: homeView.selection.isSelected(modelData.designId)
                            selectedIds: homeView.selection.selectedIds
                            editing: modelData.designId === homeView.editingDesignId
                            selectOnlyPolicy: id => homeView.selection.selectOnly(id)
                            togglePolicy: id => homeView.selection.toggleSelect(id)
                            openPolicy: id => TabStore.openDesign(id)
                            contextPolicy: (item, x, y) => homeView.openCardMenu(item, modelData.designId, x, y)
                            starPolicy: id => LibraryStore.toggleStarred(id)
                            beginRenamePolicy: id => {
                                homeView.editingDesignId = id;
                            }
                            commitPolicy: (id, text) => {
                                LibraryStore.renameDesign(id, text);
                                TabStore.renameTabByDesign(id, LibraryStore.design(id).name);
                                homeView.editingDesignId = "";
                            }
                            cancelPolicy: () => {
                                homeView.editingDesignId = "";
                            }
                        }
                    }
                }
            }

            // Marquee rect visual, above the cards.
            Rectangle {
                visible: marquee.selecting
                x: marquee.selection.x
                y: marquee.selection.y
                width: marquee.selection.width
                height: marquee.selection.height
                color: "#140d99ff"
                border.width: 1
                border.color: AppTheme.selection
            }

            DragSelection {
                id: marquee

                onFinished: (area, additive) => homeView.selection.applyMarquee(flow.children, marqueeMouse, area, additive)
                onTapped: homeView.selection.clearSelection()
            }

            // Empty-area press starts the marquee; presses on cards fall
            // through (accepted = false) so cards keep clicks and drags.
            MouseArea {
                id: marqueeMouse

                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onPressed: mouse => {
                    if (homeView.selection.cardAt(flow.children, marqueeMouse, mouse.x, mouse.y) !== null) {
                        mouse.accepted = false;
                        return;
                    }
                    homeView.forceActiveFocus();
                    marquee.pressAt(mouse.x, mouse.y);
                }
                onPositionChanged: mouse => {
                    if (pressed)
                        marquee.moveTo(mouse.x, mouse.y);
                }
                onReleased: mouse => {
                    marquee.release(!!(mouse.modifiers & (Qt.ShiftModifier | Qt.ControlModifier | Qt.MetaModifier)));
                }
            }

            DesignContextMenu {
                id: cardMenu

                renamePolicy: id => {
                    homeView.editingDesignId = id;
                }
                starPolicy: id => LibraryStore.toggleStarred(id)
                deletePolicy: id => {
                    homeView.selection.deleteDesignOrSelected(id);
                }
            }
        }
    }

    // If the selected workspace disappears (deleted elsewhere), fall
    // back to Default so the grid never points at nothing.
    Connections {
        target: LibraryStore
        function onLibraryChanged() {
            if (LibraryStore.workspaceName(homeView.selectedWorkspaceId) === "")
                homeView.selectedWorkspaceId = LibraryStore.defaultWorkspaceId;
            homeView.refreshFiltered();
        }
    }
}
