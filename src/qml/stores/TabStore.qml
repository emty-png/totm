pragma Singleton
import QtQuick
import Totm

// Tab state: pinned home tab first, then document tabs.
// Model index 0 is always home; doc tabs start at index 1.
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

    function addUntitled() {
        var uid = tabStore.nextUid++;
        var doc = tabStore.documentFactory.createObject(tabStore, {
            uid: uid
        });
        tabStore.documents[uid] = doc;
        tabStore.tabs.append({
            kind: "doc",
            title: "Untitled",
            uid: uid
        });
        tabStore.currentIndex = tabStore.tabs.count - 1;
    }

    function select(modelIndex) {
        tabStore.currentIndex = modelIndex;
    }

    // Close a document tab (home at index 0 can never close).
    // Closing the active tab selects the nearest neighbor (prefer left);
    // closing a tab left of the selection shifts the index along.
    function closeTab(modelIndex) {
        if (modelIndex < 1 || modelIndex >= tabStore.tabs.count)
            return;
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
