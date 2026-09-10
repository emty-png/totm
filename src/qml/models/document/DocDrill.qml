import QtQuick

// Drill path plus press resolving inside groups. -1 is the root
// container. Operates on the owner via `doc`.
QtObject {
    id: docDrill
    required property var doc

    function _activeContainerUid() {
        if (doc.drillPath.length === 0)
            return -1;
        return doc.drillPath[doc.drillPath.length - 1];
    }

    function activeContainerNode() {
        var uid = _activeContainerUid();
        return uid < 0 ? null : doc.findNode(uid);
    }

    function resolvePress(uid) {
        var hit = doc._find(uid);
        if (!hit)
            return uid;
        var chain = hit.ancestors.concat([hit.node]);
        var start = 0;
        if (doc.drillPath.length > 0) {
            // Chain must pass through the drilled groups; find the active
            // container in the chain and resolve below it.
            var active = _activeContainerUid();
            var ai = -1;
            for (var i = 0; i < chain.length; i++) {
                if (chain[i].uid === active) {
                    ai = i;
                    break;
                }
            }
            if (ai < 0)
                return uid;
            start = ai + 1;
        }
        if (start >= chain.length)
            return uid;
        return chain[start].uid;
    }

    function drillInto(uid) {
        var n = doc.findNode(uid);
        if (!n || n.kind !== "group")
            return;
        // Only one level deeper from the active container (root = -1).
        if (!doc._isDirectChildOf(uid, _activeContainerUid()))
            return;
        var path = doc.drillPath.slice();
        if (path.indexOf(uid) < 0)
            path.push(uid);
        doc.drillPath = path;
        doc.touch();
    }

    function drillOut() {
        if (doc.drillPath.length === 0)
            return false;
        doc.drillPath = doc.drillPath.slice(0, doc.drillPath.length - 1);
        doc.touch();
        return true;
    }

    function drillTo(uid) {
        // Breadcrumb jump: truncate the path to uid (root = -1 clears).
        if (uid < 0) {
            doc.drillPath = [];
            doc.touch();
            return;
        }
        var i = doc.drillPath.indexOf(uid);
        if (i >= 0) {
            doc.drillPath = doc.drillPath.slice(0, i + 1);
            doc.touch();
        }
    }

    // Drop path entries whose groups no longer exist (ungroup/delete).
    // Without this, creates and pastes land in a dead container and leak.
    function pruneDrillPath() {
        var path = [];
        for (var k = 0; k < doc.drillPath.length; k++) {
            if (doc.findNode(doc.drillPath[k]))
                path.push(doc.drillPath[k]);
            else
                break;
        }
        if (path.length !== doc.drillPath.length) {
            doc.drillPath = path;
            doc.touch();
        }
    }
}
