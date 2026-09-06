import QtQuick

// Inherited visibility and lock checks. Walks ancestors. Operates on the owning Document via `doc`.
QtObject {
    id: docEffective
    required property var doc

    function isEffectivelyVisible(node) {
        // Hidden if self or any ancestor hidden. Nodes store visible=true
        // as "shown", so check the negation.
        var hit = doc._find(node.uid);
        var chain = hit ? hit.ancestors.concat([node]) : [node];
        for (var i = 0; i < chain.length; i++) {
            if (!chain[i].visible)
                return false;
        }
        return true;
    }

    function isEffectivelyLocked(node) {
        var hit = doc._find(node.uid);
        var chain = hit ? hit.ancestors.concat([node]) : [node];
        for (var i = 0; i < chain.length; i++) {
            if (chain[i].locked)
                return true;
        }
        return false;
    }
}
