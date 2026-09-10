import QtQuick

// Inline rename state (single renaming node). Blank commits keep the old
// name. Operates on the owner via `doc`.
QtObject {
    id: docRename
    required property var doc

    function beginRename(uid) {
        var hit = doc._find(uid);
        if (!hit)
            return;
        var all = doc._allNodes();
        for (var i = 0; i < all.length; i++)
            all[i].renaming = all[i].uid === uid;
        doc.touch();
    }

    function commitRename(uid, name) {
        var n = doc.findNode(uid);
        if (!n)
            return;
        var t = String(name).trim();
        if (t !== "")
            n.name = t;
        n.renaming = false;
        doc.touch();
    }

    function cancelRename(uid) {
        var n = doc.findNode(uid);
        if (n)
            n.renaming = false;
        doc.touch();
    }
}
