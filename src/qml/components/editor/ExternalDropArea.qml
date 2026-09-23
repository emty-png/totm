import QtQuick
import Totm

// OS-level image intake for the editor: file drops anywhere over the
// window plus system-clipboard paste (copied files and raw pixel data
// like screenshots or browser copies). Drops stamp centered on the
// drop point, pastes land at the viewport center; multi-file gestures
// cascade and commit as one undo entry. SVGs vectorize through the
// same path as the image-tool picker (image-blob fallback when
// unconvertible); anything else is skipped. Inbound only: app content
// never reaches the OS clipboard.
DropArea {
    id: intake

    property var canvas: null
    property var doc: null
    property bool windowActive: false

    enabled: intake.windowActive && !!intake.canvas && !!intake.doc

    // Scene-px cascade offset per file in one gesture.
    readonly property real cascadeStep: 24

    onDropped: drop => {
        if (!intake.enabled)
            return;
        var urls = [];
        for (var i = 0; i < drop.urls.length; i++)
            urls.push(drop.urls[i]);
        var p = intake.mapToItem(intake.canvas, drop.x, drop.y);
        intake.importUrls(urls, (p.x - intake.canvas.offsetX) / intake.canvas.zoom, (p.y - intake.canvas.offsetY) / intake.canvas.zoom);
    }

    function viewportCenter() {
        var c = intake.canvas;
        return {
            x: (c.width / 2 - c.offsetX) / c.zoom,
            y: (c.height / 2 - c.offsetY) / c.zoom
        };
    }

    function mediaUrls(urls) {
        var out = [];
        var list = urls || [];
        for (var i = 0; i < list.length; i++) {
            var s = String(list[i]).split("?")[0];
            // Local files only: remote URLs have no local path to import.
            if (/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(s) && !/^file:\/\//i.test(s))
                continue;
            if (/\.svg$/i.test(s) || /\.(png|jpe?g|webp|gif)$/i.test(s))
                out.push(list[i]);
        }
        return out;
    }

    function asFileUrl(u) {
        var s = String(u);
        if (s.indexOf("://") < 0)
            s = "file://" + s;
        return s;
    }

    // One gesture, one undo entry: failures land per file, the rest
    // still commit. Returns the placed count.
    function importUrls(urls, sceneX, sceneY) {
        var files = intake.mediaUrls(urls);
        if (files.length === 0 || !intake.doc)
            return 0;
        var placed = 0;
        var d = intake.doc;
        d.beginTransaction();
        for (var i = 0; i < files.length; i++) {
            if (intake.placeFile(intake.asFileUrl(files[i]), sceneX + i * intake.cascadeStep, sceneY + i * intake.cascadeStep))
                placed++;
        }
        d.endTransaction();
        return placed;
    }

    // Mirrors the image-tool picker accept: SVGs vectorize at natural
    // size (blob fallback when unconvertible), rasters stamp clamped
    // so a 4k drop never covers the scene. Centered on (x, y).
    function placeFile(u, x, y) {
        var flat = String(u).split("?")[0];
        if (/\.svg$/i.test(flat)) {
            var vec = LibraryStore.importSvgVectors(u);
            if (vec && vec.ok && vec.paths && vec.paths.length > 0) {
                var vw = Math.max(1, Number(vec.width) || 0);
                var vh = Math.max(1, Number(vec.height) || 0);
                var base = String(flat.split("/").pop() || "SVG").replace(/\.svg$/i, "");
                intake.doc.importSvgPaths(vec.paths, base, Math.round(x - vw / 2), Math.round(y - vh / 2), 1, 1);
                return true;
            }
        }
        if (!/\.(png|jpe?g|webp|gif|svg)$/i.test(flat))
            return false;
        var name = LibraryStore.importImage(u);
        if (!name)
            return false;
        var info = LibraryStore.imageInfo(name);
        var w = Number(info.width) || 400;
        var h = Number(info.height) || 300;
        if (w > 800 || h > 800) {
            var k = Math.min(800 / w, 800 / h);
            w = Math.max(1, Math.round(w * k));
            h = Math.max(1, Math.round(h * k));
        }
        intake.doc.addImage(name, Math.round(x - w / 2), Math.round(y - h / 2), w, h);
        return true;
    }

    function canPasteFromSystem() {
        return LibraryStore.clipboardFileUrls().length > 0 || LibraryStore.clipboardHasImage();
    }

    // File URLs first (same handling as drops), raw pixels second.
    // Returns true when anything landed.
    function pasteFromSystem() {
        if (!intake.doc)
            return false;
        var c = intake.viewportCenter();
        var urls = LibraryStore.clipboardFileUrls();
        if (urls.length > 0)
            return intake.importUrls(urls, c.x, c.y) > 0;
        if (LibraryStore.clipboardHasImage()) {
            var name = LibraryStore.pasteClipboardImage();
            if (!name)
                return false;
            var info = LibraryStore.imageInfo(name);
            var w = Number(info.width) || 400;
            var h = Number(info.height) || 300;
            if (w > 800 || h > 800) {
                var k = Math.min(800 / w, 800 / h);
                w = Math.max(1, Math.round(w * k));
                h = Math.max(1, Math.round(h * k));
            }
            intake.doc.addImage(name, Math.round(c.x - w / 2), Math.round(c.y - h / 2), w, h);
            return true;
        }
        return false;
    }
}
