import QtQuick

// Camera for one canvas. Reads and writes `canvas` viewport and `canvas.doc`.
QtObject {
    id: camera
    required property var canvas

    function clampZoom(v) {
        return Math.min(canvas.maxZoom, Math.max(canvas.minZoom, v));
    }

    function zoomAt(mx, my, dy) {
        // NOTE: sign is flipped vs the web formula: Qt wheel deltas are
        // positive on scroll-up while browser deltaY is positive on
        // scroll-down. Scroll-up zooms in (Figma/Chrome/VS Code feel).
        var next = canvas.clampZoom(canvas.zoom * Math.exp(dy * 0.0018));
        if (next === canvas.zoom)
            return;
        var ratio = next / canvas.zoom;
        canvas.offsetX = mx - (mx - canvas.offsetX) * ratio;
        canvas.offsetY = my - (my - canvas.offsetY) * ratio;
        canvas.zoom = next;
    }

    function tryCenter() {
        if (!canvas.doc || canvas.doc.centered)
            return false;
        if (canvas.width < 10 || canvas.height < 10)
            return false;
        var fit = Math.min(canvas.width / canvas.doc.sceneWidth, canvas.height / canvas.doc.sceneHeight) * 0.95;
        var next = canvas.clampZoom(fit);
        canvas.zoom = next;
        canvas.offsetX = (canvas.width - canvas.doc.sceneWidth * next) / 2;
        canvas.offsetY = (canvas.height - canvas.doc.sceneHeight * next) / 2;
        canvas.doc.centered = true;
        return true;
    }

    function saveCamera(d) {
        d.camZoom = canvas.zoom;
        d.camX = canvas.offsetX;
        d.camY = canvas.offsetY;
    }

    function loadCamera(d) {
        canvas.zoom = d.camZoom;
        canvas.offsetX = d.camX;
        canvas.offsetY = d.camY;
    }

    function showDocument(d) {
        if (d === canvas.shownDoc) {
            if (d && !d.centered && canvas.tryCenter())
                canvas.saveCamera(d);
            return;
        }
        if (canvas.shownDoc)
            canvas.saveCamera(canvas.shownDoc);
        canvas.shownDoc = d;
        if (!d)
            return;
        if (!d.centered) {
            if (canvas.tryCenter())
                canvas.saveCamera(d);
        } else {
            canvas.loadCamera(d);
        }
    }
}
