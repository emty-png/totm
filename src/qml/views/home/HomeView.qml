import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Home screen: workspace sidebar + design grid for the selection.
// Cards show a live miniature of the stored scene; click selects one,
// double-click opens, drag onto a sidebar workspace moves. Empty-area
// drag marquee-selects via the shared DragSelection core; Delete removes
// the selection, right-click opens the card menu.
RowLayout {
    id: homeView

    spacing: 0
    focus: true

    property string selectedWorkspaceId: ""
    property string editingDesignId: ""
    // Pending design for the .totm export save dialog.
    property string exportDesignId: ""
    // Destination held while the overwrite confirm is up.
    property url pendingExportUrl
    // Placeholder settings view; true while the sidebar Settings entry
    // owns the content area instead of a workspace grid.
    property bool settingsSelected: false
    // Grid toolbar state: live search query + sort mode
    // ("recent" | "name" | "oldest"). Part of refreshFiltered so
    // library writes, typing and mode cycles share one path.
    property string searchText: ""
    property string sortMode: "recent"
    // Pending workspace for the delete-choice popup.
    property string pendingDeleteWorkspaceId: ""
    property string pendingDeleteWorkspaceName: ""
    property int pendingDeleteCount: 0

    // Card selection state (components/home/HomeSelection). One instance
    // per HomeView; ids reassign wholesale so card bindings update.
    property var selection: HomeSelection {}

    // Starter templates (components/home/TemplateLibrary). One instance
    // per HomeView, like the card selection above.
    property var templateLib: TemplateLibrary {}

    // Designs of the selected workspace. Refreshed wholesale on change so
    // the model array identity stays stable for delegates (see Flow below).
    // Search filters by name (case-insensitive); sort applies per mode.
    property var filteredDesigns: []

    function refreshFiltered() {
        var out = [];
        var all = LibraryStore.designList;
        var q = String(homeView.searchText || "").trim().toLowerCase();
        for (var i = 0; i < all.length; i++) {
            if (all[i].workspaceId !== homeView.selectedWorkspaceId)
                continue;
            if (q !== "" && String(all[i].name || "").toLowerCase().indexOf(q) < 0)
                continue;
            out.push(all[i]);
        }
        if (homeView.sortMode === "name") {
            out.sort((a, b) => String(a.name || "").localeCompare(String(b.name || "")));
        } else {
            out.sort((a, b) => {
                var ta = Date.parse(a.updatedAt);
                var tb = Date.parse(b.updatedAt);
                if (isNaN(ta))
                    ta = 0;
                if (isNaN(tb))
                    tb = 0;
                return homeView.sortMode === "oldest" ? ta - tb : tb - ta;
            });
        }
        homeView.filteredDesigns = out;
    }

    function sortLabel() {
        if (homeView.sortMode === "name")
            return qsTr("Name");
        if (homeView.sortMode === "oldest")
            return qsTr("Oldest");
        return qsTr("Recent");
    }

    function cycleSort() {
        if (homeView.sortMode === "recent")
            homeView.sortMode = "name";
        else if (homeView.sortMode === "name")
            homeView.sortMode = "oldest";
        else
            homeView.sortMode = "recent";
    }

    onSearchTextChanged: homeView.refreshFiltered()
    onSortModeChanged: homeView.refreshFiltered()

    onSelectedWorkspaceIdChanged: {
        // The grid rebuilds for the new workspace, which would strand
        // any open editor in a dead delegate: drop edits on switch.
        homeView.editingDesignId = "";
        workspacePanel.editingWorkspaceId = "";
        homeView.refreshFiltered();
    }

    function openCardMenu(item, designId, x, y) {
        var info = LibraryStore.design(designId);
        var count = homeView.selection.isSelected(designId) ? homeView.selection.selectedIds.length : 1;
        var p = item.mapToItem(gridArea, x, y);
        cardMenu.openFor(designId, !!info.starred, count, p.x, p.y, info.workspaceId || "");
    }

    // Moves the card-menu target (whole selection when the target is
    // inside it, else the single card) into the chosen workspace.
    function moveCardSelectionTo(workspaceId) {
        var target = cardMenu.contextId;
        var ids = [];
        if (homeView.selection.isSelected(target) && homeView.selection.selectedIds.length > 0)
            ids = homeView.selection.selectedIds.slice();
        else if (target !== "")
            ids = [target];
        for (var i = 0; i < ids.length; i++)
            LibraryStore.moveDesign(ids[i], workspaceId);
        homeView.refreshFiltered();
    }

    // Creates a workspace, selects it and opens inline rename so the
    // Creates a workspace with a unique default name, selects it and
    // clears the card selection. No inline editor: rename later with
    // double-click or F2-style menu when needed.
    function uniqueWorkspaceName() {
        var base = qsTr("Untitled workspace");
        var taken = {};
        var all = LibraryStore.workspaceList;
        for (var i = 0; i < all.length; i++)
            taken[all[i].name] = true;
        if (!taken[base])
            return base;
        var n = 2;
        while (taken[base + " " + n])
            n++;
        return base + " " + n;
    }

    function homeNewWorkspace() {
        var id = LibraryStore.createWorkspace(homeView.uniqueWorkspaceName());
        if (!id)
            return;
        homeView.selection.clearSelection();
        homeView.selectedWorkspaceId = id;
        homeView.settingsSelected = false;
    }

    // Delete choice: non-default workspaces ask whether designs move
    // to Default or are deleted too. Default never reaches here (its
    // row hides delete and the backend rejects it regardless).
    function askDeleteWorkspace(workspaceId) {
        if (workspaceId === "" || LibraryStore.isDefaultWorkspace(workspaceId))
            return;
        homeView.pendingDeleteWorkspaceId = workspaceId;
        homeView.pendingDeleteWorkspaceName = LibraryStore.workspaceName(workspaceId);
        homeView.pendingDeleteCount = LibraryStore.designCount(workspaceId);
        workspaceDeletePopup.open();
    }

    function designsInWorkspace(workspaceId) {
        var out = [];
        var all = LibraryStore.designList;
        for (var i = 0; i < all.length; i++) {
            if (all[i].workspaceId === workspaceId)
                out.push(all[i].designId);
        }
        return out;
    }

    function commitDeleteMoveToDefault() {
        var id = homeView.pendingDeleteWorkspaceId;
        homeView.pendingDeleteWorkspaceId = "";
        if (id === "")
            return;
        if (id === homeView.selectedWorkspaceId)
            homeView.selectedWorkspaceId = LibraryStore.defaultWorkspaceId;
        LibraryStore.deleteWorkspace(id);
    }

    function commitDeleteWithDesigns() {
        var id = homeView.pendingDeleteWorkspaceId;
        homeView.pendingDeleteWorkspaceId = "";
        if (id === "")
            return;
        var doomed = homeView.designsInWorkspace(id);
        for (var i = 0; i < doomed.length; i++)
            TabState.closeTabByDesign(doomed[i]);
        var kept = [];
        var sel = homeView.selection.selectedIds.slice();
        for (var j = 0; j < sel.length; j++) {
            if (doomed.indexOf(sel[j]) < 0)
                kept.push(sel[j]);
        }
        homeView.selection.selectedIds = kept;
        if (id === homeView.selectedWorkspaceId)
            homeView.selectedWorkspaceId = LibraryStore.defaultWorkspaceId;
        LibraryStore.deleteWorkspaceAndDesigns(id);
    }

    // Home shortcuts (single source: ShortcutState, editable in Settings).
    // Text inputs and open rename editors swallow keys first, like the
    // editor guards. Suspended while capturing a new sequence.
    function focusInTextInput() {
        var w = homeView.Window.window;
        var f = w ? w.activeFocusItem : null;
        return !!f && typeof f.text !== "undefined" && typeof f.undo === "function" && typeof f.selectAll === "function";
    }

    function homeEditing() {
        return homeView.editingDesignId !== "" || workspacePanel.editingWorkspaceId !== "" || homeView.focusInTextInput();
    }

    function homeNewDesign() {
        var ws = homeView.selectedWorkspaceId || LibraryStore.defaultWorkspaceId;
        var id = LibraryStore.createDesign(ws, "Untitled");
        if (id)
            TabState.openDesign(id);
    }

    // Starts a design from a starter template: creates the design in
    // the current workspace, opens it, then builds the template scene
    // (one undo entry) and saves, so the card preview is alive at once.
    function homeNewFromTemplate(templateId) {
        var ws = homeView.selectedWorkspaceId || LibraryStore.defaultWorkspaceId;
        var id = LibraryStore.createDesign(ws, homeView.templateLib.templateName(templateId));
        if (!id)
            return;
        TabState.openDesign(id);
        var doc = TabState.documentFor(TabState.modelIndexForDesign(id));
        if (doc && homeView.templateLib.build(doc, templateId))
            TabState.saveOpenDesign(id);
        homeView.refreshFiltered();
    }

    function homeOpenSelected() {
        if (homeView.selection.selectedIds.length !== 1)
            return;
        TabState.openDesign(homeView.selection.selectedIds[0]);
    }

    function homeDuplicateSelected() {
        var ids = homeView.selection.selectedIds.slice();
        if (ids.length === 0)
            return;
        var made = [];
        for (var i = 0; i < ids.length; i++) {
            var info = LibraryStore.design(ids[i]);
            if (!info || !info.id)
                continue;
            var name = (info.name || "Untitled") + qsTr(" copy");
            var ws = info.workspaceId || homeView.selectedWorkspaceId || LibraryStore.defaultWorkspaceId;
            var fresh = LibraryStore.createDesign(ws, name);
            if (!fresh)
                continue;
            LibraryStore.saveScene(fresh, LibraryStore.loadScene(ids[i]));
            made.push(fresh);
        }
        if (made.length > 0)
            homeView.selection.selectedIds = made;
        homeView.refreshFiltered();
    }

    // .totm share: export writes name + scene + blobs via the store
    // (errors surface in the global bar); import remaps blobs under
    // fresh names and selects the new card.
    function homeExportDesign(designId) {
        if (!designId)
            return;
        LibraryStore.clearError();
        homeView.exportDesignId = designId;
        var info = LibraryStore.design(designId);
        var base = (info && info.name) || "design";
        exportPicker.currentFolder = StandardPaths.writableLocation(StandardPaths.DocumentsLocation);
        exportPicker.fileName = base + ".totm";
        exportPicker.open();
    }

    // Overwrite path: existing destinations confirm through the shared
    // popup before exportDesign runs with overwrite set.
    function commitExport(dest, overwrite) {
        if (homeView.exportDesignId !== "")
            LibraryStore.exportDesign(homeView.exportDesignId, dest, overwrite);
        homeView.exportDesignId = "";
    }

    function fileName(url) {
        return String(url).split("/").pop();
    }

    function homeToggleStarSelected() {
        var ids = homeView.selection.selectedIds.slice();
        for (var i = 0; i < ids.length; i++)
            LibraryStore.toggleStarred(ids[i]);
    }

    Keys.onDeletePressed: event => {
        if (homeView.editingDesignId !== "" || workspacePanel.editingWorkspaceId !== "")
            return;
        homeView.selection.deleteSelected();
        event.accepted = true;
    }
    Keys.onEscapePressed: event => {
        if (homeView.editingDesignId !== "" || workspacePanel.editingWorkspaceId !== "")
            return;
        homeView.selection.clearSelection();
        event.accepted = true;
    }

    Shortcut {
        sequences: [ShortcutState.homeNew]
        enabled: TabState.isHomeSelected && !ShortcutState.capturing && !homeView.homeEditing()
        onActivated: {
            if (homeView.homeEditing())
                return;
            homeView.homeNewDesign();
        }
    }

    Shortcut {
        sequences: [ShortcutState.homeOpen, "Enter"]
        enabled: TabState.isHomeSelected && !ShortcutState.capturing && !homeView.settingsSelected && homeView.selection.selectedIds.length === 1 && !homeView.homeEditing()
        onActivated: {
            if (homeView.homeEditing())
                return;
            homeView.homeOpenSelected();
        }
    }

    Shortcut {
        sequences: [ShortcutState.homeRename]
        enabled: TabState.isHomeSelected && !ShortcutState.capturing && !homeView.settingsSelected && homeView.selection.selectedIds.length === 1 && !homeView.homeEditing()
        onActivated: {
            if (homeView.homeEditing())
                return;
            homeView.editingDesignId = homeView.selection.selectedIds[0];
        }
    }

    Shortcut {
        sequences: [ShortcutState.homeDelete, "Backspace"]
        enabled: TabState.isHomeSelected && !ShortcutState.capturing && !homeView.settingsSelected && homeView.selection.selectedIds.length > 0 && !homeView.homeEditing()
        onActivated: {
            if (homeView.homeEditing())
                return;
            homeView.selection.deleteSelected();
        }
    }

    Shortcut {
        sequences: [ShortcutState.homeDuplicate]
        enabled: TabState.isHomeSelected && !ShortcutState.capturing && !homeView.settingsSelected && homeView.selection.selectedIds.length > 0 && !homeView.homeEditing()
        onActivated: {
            if (homeView.homeEditing())
                return;
            homeView.homeDuplicateSelected();
        }
    }

    Shortcut {
        sequences: [ShortcutState.homeStar]
        enabled: TabState.isHomeSelected && !ShortcutState.capturing && !homeView.settingsSelected && homeView.selection.selectedIds.length > 0 && !homeView.homeEditing()
        onActivated: {
            if (homeView.homeEditing())
                return;
            homeView.homeToggleStarSelected();
        }
    }

    Component.onCompleted: {
        homeView.selectedWorkspaceId = LibraryStore.defaultWorkspaceId;
        homeView.refreshFiltered();
    }

    WorkspacePanel {
        id: workspacePanel

        Layout.preferredWidth: 230
        Layout.fillHeight: true
        selectedWorkspaceId: homeView.selectedWorkspaceId
        settingsSelected: homeView.settingsSelected
        selectPolicy: id => {
            homeView.selectedWorkspaceId = id;
            homeView.settingsSelected = false;
        }
        movePolicy: (idsJson, workspaceId) => {
            var ids = homeView.parseIds(idsJson);
            for (var i = 0; i < ids.length; i++)
                LibraryStore.moveDesign(ids[i], workspaceId);
        }
        openPolicy: id => TabState.openDesign(id)
        newWorkspacePolicy: () => homeView.homeNewWorkspace()
        deleteRequestPolicy: id => homeView.askDeleteWorkspace(id)
        settingsPolicy: () => {
            homeView.editingDesignId = "";
            homeView.settingsSelected = true;
        }
        creditsPolicy: () => SettingsStore.openCredits()
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
            visible: !homeView.settingsSelected

            Text {
                Layout.fillWidth: true
                text: LibraryStore.workspaceName(homeView.selectedWorkspaceId) || qsTr("Workspace")
                font.pixelSize: 16
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                color: AppTheme.foreground
            }

            Rectangle {
                Layout.preferredWidth: templateLabel.implicitWidth + 20
                Layout.preferredHeight: 28
                radius: AppTheme.radiusSmall
                border.width: 1
                border.color: AppTheme.fieldBorder
                color: templateMouse.containsMouse || templateMouse.pressed ? AppTheme.hover : AppTheme.surface

                Behavior on color {
                    ColorAnimation {
                        duration: 100
                        easing.type: Easing.OutCubic
                    }
                }

                Text {
                    id: templateLabel
                    anchors.centerIn: parent
                    text: qsTr("Template")
                    font.pixelSize: 12
                    color: templateMouse.containsMouse || templateMouse.pressed ? AppTheme.foreground : AppTheme.muted
                }

                MouseArea {
                    id: templateMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: templateMenu.openPicker()
                }
            }

            Rectangle {
                Layout.preferredWidth: importLabel.implicitWidth + 20
                Layout.preferredHeight: 28
                radius: AppTheme.radiusSmall
                border.width: 1
                border.color: AppTheme.fieldBorder
                color: importMouse.containsMouse || importMouse.pressed ? AppTheme.hover : AppTheme.surface

                Behavior on color {
                    ColorAnimation {
                        duration: 100
                        easing.type: Easing.OutCubic
                    }
                }

                Text {
                    id: importLabel
                    anchors.centerIn: parent
                    text: qsTr("Import")
                    font.pixelSize: 12
                    color: importMouse.containsMouse || importMouse.pressed ? AppTheme.foreground : AppTheme.muted
                }

                MouseArea {
                    id: importMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        importPicker.currentFolder = StandardPaths.writableLocation(StandardPaths.DocumentsLocation);
                        importPicker.open();
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.bottomMargin: 8
            spacing: 8
            visible: !homeView.settingsSelected

            TextField {
                id: searchField

                Layout.fillWidth: true
                implicitHeight: 28
                placeholderText: qsTr("Search designs")
                placeholderTextColor: AppTheme.muted
                font.pixelSize: 12
                color: AppTheme.foreground
                selectByMouse: true
                onTextChanged: {
                    if (homeView.searchText !== text)
                        homeView.searchText = text;
                }

                background: Rectangle {
                    radius: AppTheme.radiusSmall
                    color: AppTheme.surface
                    border.width: 1
                    border.color: searchField.activeFocus ? AppTheme.selection : AppTheme.fieldBorder
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        searchField.text = "";
                        homeView.forceActiveFocus();
                        event.accepted = true;
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: 80
                Layout.preferredHeight: 28
                radius: AppTheme.radiusSmall
                border.width: 1
                border.color: AppTheme.fieldBorder
                color: sortMouse.containsMouse || sortMouse.pressed ? AppTheme.hover : AppTheme.surface

                Behavior on color {
                    ColorAnimation {
                        duration: 100
                        easing.type: Easing.OutCubic
                    }
                }

                Text {
                    id: sortText
                    anchors.centerIn: parent
                    text: homeView.sortLabel()
                    font.pixelSize: 12
                    color: sortMouse.containsMouse || sortMouse.pressed ? AppTheme.foreground : AppTheme.muted
                }

                MouseArea {
                    id: sortMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: homeView.cycleSort()
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            visible: !homeView.settingsSelected && homeView.filteredDesigns.length === 0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            text: String(homeView.searchText || "").trim() !== "" ? qsTr("No designs match your search...") : qsTr("Nothing to see here...")
            font.pixelSize: 13
            color: AppTheme.muted
        }

        SettingsView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: homeView.settingsSelected
        }

        Item {
            id: gridArea

            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !homeView.settingsSelected && homeView.filteredDesigns.length > 0
            clip: true

            // Flow + Repeater (not GridView): synchronous delegates with
            // stable geometry for marquee hit-testing.
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
                            openPolicy: id => TabState.openDesign(id)
                            contextPolicy: (item, x, y) => homeView.openCardMenu(item, modelData.designId, x, y)
                            starPolicy: id => LibraryStore.toggleStarred(id)
                            commitPolicy: (id, text) => {
                                // Stale settles (e.g. the previous card's
                                // focus-loss commit landing after a fast
                                // re-target) never clobber the live edit.
                                if (homeView.editingDesignId !== id)
                                    return;
                                LibraryStore.renameDesign(id, text);
                                TabState.renameTabByDesign(id, LibraryStore.design(id).name);
                                homeView.editingDesignId = "";
                                homeView.refreshFiltered();
                            }
                            cancelPolicy: id => {
                                if (homeView.editingDesignId !== id)
                                    return;
                                homeView.editingDesignId = "";
                                homeView.refreshFiltered();
                            }
                        }
                    }
                }
            }

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

            // Presses on cards fall through (accepted = false) so cards
            // keep clicks and drags; empty-area presses start the marquee.
            // preventStealing keeps the Flickable from hijacking the
            // gesture mid-drag once this area owns the press.
            MouseArea {
                id: marqueeMouse

                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                preventStealing: true
                onPressed: mouse => {
                    if (homeView.selection.cardAt(flow.children, marqueeMouse, mouse.x, mouse.y) !== null) {
                        mouse.accepted = false;
                        return;
                    }
                    mouse.accepted = true;
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
                movePolicy: wsId => homeView.moveCardSelectionTo(wsId)
                exportPolicy: id => homeView.homeExportDesign(id)
                deletePolicy: id => {
                    homeView.selection.deleteDesignOrSelected(id);
                }
            }
        }
    }

    FilePicker {
        id: exportPicker
        saveMode: true
        suffixes: ["totm"]
        onAccepted: {
            var dest = exportPicker.selectedFile;
            if (homeView.exportDesignId !== "" && LibraryStore.exportDestinationExists(dest)) {
                homeView.pendingExportUrl = dest;
                overwritePopup.ask(qsTr("Overwrite design?"), qsTr("“%1” already exists. Overwriting replaces it.").arg(homeView.fileName(dest)), qsTr("Overwrite"));
            } else {
                homeView.commitExport(dest, false);
            }
        }
        onRejected: homeView.exportDesignId = ""
    }

    FilePicker {
        id: importPicker
        suffixes: ["totm"]
        currentFolder: StandardPaths.writableLocation(StandardPaths.DocumentsLocation)
        onAccepted: {
            LibraryStore.clearError();
            var ws = homeView.selectedWorkspaceId || LibraryStore.defaultWorkspaceId;
            var id = LibraryStore.importDesign(ws, importPicker.selectedFile);
            if (id) {
                homeView.refreshFiltered();
                homeView.selection.selectOnly(id);
            }
        }
    }

    // Starter-template picker for the header Template button. Same
    // templates as the strip below, modal so a pick or outside press
    // resolves it.
    TemplateMenu {
        id: templateMenu
        templateLib: homeView.templateLib
        usePolicy: id => homeView.homeNewFromTemplate(id)
    }

    // Overwrite guard for .totm exports: existing destinations resolve
    // here before commitExport runs with overwrite set.
    ConfirmPopup {
        id: overwritePopup
        onConfirmed: homeView.commitExport(homeView.pendingExportUrl, true)
    }

    // Workspace delete choice: re-home designs to Default (safe) or
    // delete them with the workspace (closes their tabs first).
    // Default never reaches here; empty workspaces delete directly.
    Popup {
        id: workspaceDeletePopup
        anchors.centerIn: parent
        implicitWidth: 320
        padding: 12
        modal: true
        dim: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

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
            radius: AppTheme.radiusLarge
            color: AppTheme.surface
            border.width: 1
            border.color: AppTheme.border
        }

        contentItem: ColumnLayout {
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: homeView.pendingDeleteCount === 0 ? qsTr("Delete “%1”?").arg(homeView.pendingDeleteWorkspaceName) : homeView.pendingDeleteCount === 1 ? qsTr("“%1” has 1 design. Move it to Default, or delete it with the workspace?").arg(homeView.pendingDeleteWorkspaceName) : qsTr("“%1” has %2 designs. Move them to Default, or delete them with the workspace?").arg(homeView.pendingDeleteWorkspaceName).arg(homeView.pendingDeleteCount)
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                color: AppTheme.muted
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: AppTheme.radiusSmall
                border.width: 1
                border.color: AppTheme.foreground
                color: AppTheme.foreground
                visible: homeView.pendingDeleteCount > 0

                Text {
                    anchors.centerIn: parent
                    text: homeView.pendingDeleteCount === 1 ? qsTr("Move to Default") : qsTr("Move %1 to Default").arg(homeView.pendingDeleteCount)
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: AppTheme.background
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        workspaceDeletePopup.close();
                        homeView.commitDeleteMoveToDefault();
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: AppTheme.radiusSmall
                border.width: 1
                border.color: AppTheme.fieldBorder
                color: deleteWsMouse.containsMouse || deleteWsMouse.pressed ? AppTheme.hover : AppTheme.surface

                Behavior on color {
                    ColorAnimation {
                        duration: 100
                        easing.type: Easing.OutCubic
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: homeView.pendingDeleteCount === 0 ? qsTr("Delete workspace") : homeView.pendingDeleteCount === 1 ? qsTr("Delete design too") : qsTr("Delete %1 designs").arg(homeView.pendingDeleteCount)
                    font.pixelSize: 12
                    color: deleteWsMouse.containsMouse || deleteWsMouse.pressed ? AppTheme.foreground : AppTheme.muted
                }

                MouseArea {
                    id: deleteWsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        workspaceDeletePopup.close();
                        if (homeView.pendingDeleteCount === 0)
                            homeView.commitDeleteMoveToDefault();
                        else
                            homeView.commitDeleteWithDesigns();
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: AppTheme.radiusSmall
                border.width: 1
                border.color: AppTheme.fieldBorder
                color: cancelWsMouse.containsMouse || cancelWsMouse.pressed ? AppTheme.hover : AppTheme.surface

                Behavior on color {
                    ColorAnimation {
                        duration: 100
                        easing.type: Easing.OutCubic
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: qsTr("Cancel")
                    font.pixelSize: 12
                    color: cancelWsMouse.containsMouse || cancelWsMouse.pressed ? AppTheme.foreground : AppTheme.muted
                }

                MouseArea {
                    id: cancelWsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        homeView.pendingDeleteWorkspaceId = "";
                        workspaceDeletePopup.close();
                    }
                }
            }
        }

        onClosed: {
            if (homeView.pendingDeleteWorkspaceId !== "" && !workspaceDeletePopup.opened)
                homeView.pendingDeleteWorkspaceId = "";
        }
    }

    // The selected workspace can disappear (deleted elsewhere); fall back
    // to Default so the grid never points at nothing.
    Connections {
        target: LibraryStore
        function onLibraryChanged() {
            if (LibraryStore.workspaceName(homeView.selectedWorkspaceId) === "")
                homeView.selectedWorkspaceId = LibraryStore.defaultWorkspaceId;
            // Rebuilding the grid mid-edit destroys the open editor and
            // eats typed text; commits/cancels refresh explicitly after.
            if (homeView.editingDesignId === "" && workspacePanel.editingWorkspaceId === "")
                homeView.refreshFiltered();
        }
    }
}
