pragma Singleton
import QtQuick
import Totm

// Tab state: pinned home tab first, then document tabs. Model index 0 is
// always home; doc tabs start at 1. Each doc tab is backed by a design in
// the library: new tabs create their design in the Default workspace,
// closing a tab saves its scene first, and opening a design focuses its
// tab or restores the saved scene.
QtObject {
    id: tabState

    property int currentIndex: 0

    // Documents keyed by tab uid. The uid travels with the model row, so
    // add/remove cannot desync scenes from tabs. Documents are owned here
    // and destroyed on drop.
    property int nextUid: 1
    property var documents: ({})
    // Shape clipboard (plain snapshots, app-wide so paste works across
    // tabs). Reassigned wholesale so bindings update.
    property var clipboard: []
    readonly property Component documentFactory: Component {
        Document {}
    }

    readonly property ListModel tabs: ListModel {
        ListElement {
            kind: "home"
            title: "Home"
        }
    }

    readonly property bool isHomeSelected: tabState.currentIndex === 0
    readonly property int docCount: tabState.tabs.count - 1

    function titleAt(modelIndex) {
        return tabState.tabs.get(modelIndex).title;
    }

    function designIdAt(modelIndex) {
        if (modelIndex < 0 || modelIndex >= tabState.tabs.count)
            return "";
        return tabState.tabs.get(modelIndex).designId || "";
    }

    function modelIndexForDesign(designId) {
        if (!designId)
            return -1;
        for (var i = 1; i < tabState.tabs.count; i++) {
            if (tabState.tabs.get(i).designId === designId)
                return i;
        }
        return -1;
    }

    function addUntitled() {
        var designId = LibraryStore.createDesign(LibraryStore.defaultWorkspaceId, "Untitled");
        if (!designId)
            return;
        tabState.openDesign(designId);
    }

    // Opens a design's tab, restoring its saved scene on first open.
    // Already-open designs only refocus.
    function openDesign(designId) {
        if (!designId || !LibraryStore.hasDesign(designId))
            return;
        var existing = tabState.modelIndexForDesign(designId);
        if (existing >= 0) {
            tabState.currentIndex = existing;
            return;
        }
        var info = LibraryStore.design(designId);
        var uid = tabState.nextUid++;
        var doc = tabState.documentFactory.createObject(tabState, {
            uid: uid
        });
        doc.restoreScene(LibraryStore.loadScene(designId));
        tabState.documents[uid] = doc;
        tabState.tabs.append({
            kind: "doc",
            title: info["name"] || "Untitled",
            uid: uid,
            designId: designId
        });
        tabState.currentIndex = tabState.tabs.count - 1;
    }

    function select(modelIndex) {
        tabState.currentIndex = modelIndex;
    }

    // Reorders document tabs (home at 0 never moves). Selection follows
    // its document by uid so dragging never deselects.
    function moveTab(fromModelIndex, toModelIndex) {
        if (fromModelIndex < 1 || toModelIndex < 1)
            return;
        if (fromModelIndex >= tabState.tabs.count || toModelIndex >= tabState.tabs.count)
            return;
        if (fromModelIndex === toModelIndex)
            return;
        var selUid = -1;
        if (tabState.currentIndex > 0)
            selUid = tabState.tabs.get(tabState.currentIndex).uid;
        tabState.tabs.move(fromModelIndex, toModelIndex, 1);
        if (selUid < 0) {
            tabState.currentIndex = 0;
            return;
        }
        for (var i = 1; i < tabState.tabs.count; i++) {
            if (tabState.tabs.get(i).uid === selUid) {
                tabState.currentIndex = i;
                return;
            }
        }
        tabState.currentIndex = 0;
    }

    function saveOpenDesign(designId) {
        var modelIndex = tabState.modelIndexForDesign(designId);
        if (modelIndex < 0)
            return;
        var uid = tabState.tabs.get(modelIndex).uid;
        var doc = tabState.documents[uid];
        if (doc)
            LibraryStore.saveScene(designId, doc.snapshotScene());
    }

    function saveAllOpen() {
        for (var i = 1; i < tabState.tabs.count; i++)
            tabState.saveOpenDesign(tabState.tabs.get(i).designId);
    }

    function renameTabByDesign(designId, name) {
        var modelIndex = tabState.modelIndexForDesign(designId);
        if (modelIndex >= 0)
            tabState.tabs.setProperty(modelIndex, "title", name);
    }

    // Closes a document tab (home never closes), saving its scene first.
    // The active tab falls back to the nearest neighbor (prefer left);
    // a close left of the selection shifts the index along.
    function closeTab(modelIndex) {
        if (modelIndex < 1 || modelIndex >= tabState.tabs.count)
            return;
        tabState.saveOpenDesign(tabState.tabs.get(modelIndex).designId);
        tabState.dropTab(modelIndex);
    }

    // Closes without saving. Deleting a design discards it, so its tab
    // must go away without writing the scene back first.
    function closeTabByDesign(designId) {
        var modelIndex = tabState.modelIndexForDesign(designId);
        if (modelIndex >= 0)
            tabState.dropTab(modelIndex);
    }

    function dropTab(modelIndex) {
        var uid = tabState.tabs.get(modelIndex).uid;
        var doc = tabState.documents[uid];
        if (doc)
            doc.destroy();
        delete tabState.documents[uid];
        tabState.tabs.remove(modelIndex);
        if (tabState.currentIndex === modelIndex)
            tabState.currentIndex = Math.min(modelIndex, tabState.tabs.count - 1);
        else if (tabState.currentIndex > modelIndex)
            tabState.currentIndex--;
    }

    // Document owning a model index's scene (null for home/out of range).
    // Touches tabs.count so bindings re-evaluate on add/remove.
    function documentFor(modelIndex) {
        tabState.tabs.count;
        if (modelIndex < 0 || modelIndex >= tabState.tabs.count)
            return null;
        var row = tabState.tabs.get(modelIndex);
        if (row.kind === "home" || row.uid === undefined)
            return null;
        return tabState.documents[row.uid] ?? null;
    }
}
