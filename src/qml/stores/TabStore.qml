pragma Singleton
import QtQuick
import Totm

// Tab state: pinned home tab first, then document tabs.
// Model index 0 is always home; doc tabs start at index 1.
// Every doc tab is backed by a design in the on-disk library: new tabs
// create their design in the Default workspace, closing a tab saves its
// scene first, and opening a design focuses its tab or restores it.
QtObject {
    id: tabStore

    property int currentIndex: 0

    // Documents keyed by tab uid (uid travels with the model row, so
    // add/remove can never desync scenes from tabs).
    property int nextUid: 1
    property var documents: ({})
    // Shape clipboard for copy/paste (plain snapshots, app-wide so paste
    // works across tabs). Always reassigned wholesale so bindings update.
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

    readonly property bool isHomeSelected: tabStore.currentIndex === 0
    readonly property int docCount: tabStore.tabs.count - 1

    function titleAt(modelIndex) {
        return tabStore.tabs.get(modelIndex).title;
    }

    function designIdAt(modelIndex) {
        if (modelIndex < 0 || modelIndex >= tabStore.tabs.count)
            return "";
        return tabStore.tabs.get(modelIndex).designId || "";
    }

    function modelIndexForDesign(designId) {
        if (!designId)
            return -1;
        for (var i = 1; i < tabStore.tabs.count; i++) {
            if (tabStore.tabs.get(i).designId === designId)
                return i;
        }
        return -1;
    }

    function addUntitled() {
        var designId = LibraryStore.createDesign(LibraryStore.defaultWorkspaceId, "Untitled");
        if (!designId)
            return;
        tabStore.openDesign(designId);
    }

    // Open a design's tab, restoring its saved scene on first open.
    // Already-open designs just focus.
    function openDesign(designId) {
        if (!designId || !LibraryStore.hasDesign(designId))
            return;
        var existing = tabStore.modelIndexForDesign(designId);
        if (existing >= 0) {
            tabStore.currentIndex = existing;
            return;
        }
        var info = LibraryStore.design(designId);
        var uid = tabStore.nextUid++;
        var doc = tabStore.documentFactory.createObject(tabStore, {
            uid: uid
        });
        doc.restoreScene(LibraryStore.loadScene(designId));
        tabStore.documents[uid] = doc;
        tabStore.tabs.append({
            kind: "doc",
            title: info["name"] || "Untitled",
            uid: uid,
            designId: designId
        });
        tabStore.currentIndex = tabStore.tabs.count - 1;
    }

    function select(modelIndex) {
        tabStore.currentIndex = modelIndex;
    }

    function saveOpenDesign(designId) {
        var modelIndex = tabStore.modelIndexForDesign(designId);
        if (modelIndex < 0)
            return;
        var uid = tabStore.tabs.get(modelIndex).uid;
        var doc = tabStore.documents[uid];
        if (doc)
            LibraryStore.saveScene(designId, doc.snapshotScene());
    }

    function saveAllOpen() {
        for (var i = 1; i < tabStore.tabs.count; i++)
            tabStore.saveOpenDesign(tabStore.tabs.get(i).designId);
    }

    function renameTabByDesign(designId, name) {
        var modelIndex = tabStore.modelIndexForDesign(designId);
        if (modelIndex >= 0)
            tabStore.tabs.setProperty(modelIndex, "title", name);
    }

    // Close a document tab (home at index 0 can never close), saving its
    // scene to the library first. Closing the active tab selects the
    // nearest neighbor (prefer left); closing a tab left of the selection
    // shifts the index along.
    function closeTab(modelIndex) {
        if (modelIndex < 1 || modelIndex >= tabStore.tabs.count)
            return;
        tabStore.saveOpenDesign(tabStore.tabs.get(modelIndex).designId);
        tabStore.dropTab(modelIndex);
    }

    // Close without saving: deleting a design discards it, so its tab
    // must go away without writing the scene back first.
    function closeTabByDesign(designId) {
        var modelIndex = tabStore.modelIndexForDesign(designId);
        if (modelIndex >= 0)
            tabStore.dropTab(modelIndex);
    }

    function dropTab(modelIndex) {
        var uid = tabStore.tabs.get(modelIndex).uid;
        var doc = tabStore.documents[uid];
        if (doc)
            doc.destroy();
        delete tabStore.documents[uid];
        tabStore.tabs.remove(modelIndex);
        if (tabStore.currentIndex === modelIndex)
            tabStore.currentIndex = Math.min(modelIndex, tabStore.tabs.count - 1);
        else if (tabStore.currentIndex > modelIndex)
            tabStore.currentIndex--;
    }

    // Document owning modelIndex's scene (null for home/out of range).
    // Reads tabs.count so bindings re-evaluate on add/remove.
    function documentFor(modelIndex) {
        tabStore.tabs.count;
        if (modelIndex < 0 || modelIndex >= tabStore.tabs.count)
            return null;
        var row = tabStore.tabs.get(modelIndex);
        if (row.kind === "home" || row.uid === undefined)
            return null;
        return tabStore.documents[row.uid] ?? null;
    }
}
