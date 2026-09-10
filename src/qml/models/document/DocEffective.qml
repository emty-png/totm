import QtQuick

// Inherited visibility/lock checks over ancestor chains. Operates on the
// owner via `doc`.
QtObject {
    id: docEffective
    required property var doc

    function isEffectivelyVisible(node) {
        // Hidden when self or any ancestor is hidden.
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
