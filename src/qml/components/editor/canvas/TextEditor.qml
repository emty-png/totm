import QtQuick
import Totm

// Inline text editing: double-click or fresh creation opens
// a rich TextEdit over the shape (multiline; per-span styling
// round-trips through TextRuns). Keystrokes stream
// into one undo transaction; focus loss commits, Esc restores +
// cancels. Owns the editing session (uid/start/doc) so tab switches
// end the gesture on the old doc, never the new one. Runs round-trip
// through TextRuns (canonical HTML subset); foreign pastes normalize
// to it on commit.
Item {
    id: textEditor

    anchors.fill: parent

    required property var canvas

    property int editingUid: -1
    property string editStart: ""
    property var editStartRuns: []
    // Document owning the open edit transaction. Tracked separately so
    // tab switches end the gesture on the old doc, never the new one.
    property var editDoc: null

    // Render-free measurer for text boxes (creation sizing and edit
    // growth). Bindings re-evaluate on read, so setting font/text then
    // reading boundingRect in one call always measures fresh values.
    TextMetrics {
        id: textMeasure

        elide: Text.ElideNone
    }

    // First enabled fill color of the edited node (run default + editor
    // base color).
    function editBaseColor() {
        var n = textEditor.editNode();
        if (n && n.fills && n.fills.length > 0) {
            for (var i = 0; i < n.fills.length; i++) {
                var f = n.fills[i];
                if (f && f.enabled !== false && f.color !== undefined)
                    return String(f.color);
            }
            if (n.fills[0] && n.fills[0].color !== undefined)
                return String(n.fills[0].color);
        }
        return AppTheme.foreground;
    }

    // Inline text editor, floating over the shape in screen coords.
    // Rotation rides along (same angle about the same center) so it
    // tracks rotated text; the box itself stays axis-aligned math.
    TextEdit {
        id: editor

        property var node: textEditor.editNode()

        visible: textEditor.editingUid >= 0 && !!editor.node
        x: textEditor.canvas.offsetX + (editor.node ? editor.node.x * textEditor.canvas.zoom : 0)
        y: textEditor.canvas.offsetY + (editor.node ? editor.node.y * textEditor.canvas.zoom : 0)
        width: Math.max(24, (editor.node ? editor.node.w * textEditor.canvas.zoom : 0) + 8)
        height: Math.max(16, (editor.node ? editor.node.h * textEditor.canvas.zoom : 0) + 8)
        rotation: editor.node ? editor.node.rotation : 0
        transformOrigin: Item.Center
        z: 50
        focus: visible
        selectByMouse: true
        clip: true
        wrapMode: editor.node && !editor.node.autoSize ? TextEdit.WordWrap : TextEdit.NoWrap
        textFormat: TextEdit.RichText
        color: textEditor.editBaseColor()
        selectionColor: AppTheme.selection
        font: TextRuns.textFont(editor.node ? editor.node.fontFamily : "Inter", editor.node ? editor.node.fontWeight : 400, Math.max(1, (editor.node ? editor.node.fontSize : 16) * textEditor.canvas.zoom), editor.node ? editor.node.fontItalic === true : false, editor.node ? editor.node.fontUnderline === true : false, editor.node ? editor.node.fontStrike === true : false, editor.node ? editor.node.fontCaps : "none", editor.node ? editor.node.fontSize * editor.node.letterSpacing / 100 * textEditor.canvas.zoom : 0)
        horizontalAlignment: textEditor.editAlignH()
        verticalAlignment: textEditor.editAlignV()

        onTextChanged: {
            if (textEditor.editingUid < 0 || !textEditor.editDoc)
                return;
            var cur = textEditor.editNode();
            if (!cur)
                return;
            var parsed = TextRuns.runsFromHtml(editor.text, textEditor.editBaseColor());
            var nextText = String(parsed.text).split("\r\n").join("\n").split("\r").join("\n");
            // Seeding assignment (beginTextEdit copies node content in)
            // parses back identically: skip it so merely opening the
            // editor never dirties the document.
            if (nextText === cur.textContent && textEditor.runsEqual(parsed.runs, cur.textRuns))
                return;
            textEditor.editDoc.setShapeProp(textEditor.editingUid, "textContent", nextText);
            textEditor.editDoc.setShapeProp(textEditor.editingUid, "textRuns",
                TextRuns.normalizeRuns(nextText, parsed.runs));
            var n = textEditor.editNode();
            if (n && n.autoSize) {
                var m = textEditor.measureText(nextText, n.fontFamily, n.fontWeight, n.fontSize, n.letterSpacing, n.fontItalic === true);
                textEditor.applyMeasured(textEditor.editingUid, m.w, m.h);
            }
        }
        onActiveFocusChanged: {
            if (!editor.activeFocus && textEditor.editingUid >= 0)
                textEditor.commitTextEdit();
        }
        Keys.onEscapePressed: event => {
            textEditor.cancelTextEdit();
            event.accepted = true;
        }
        Keys.onPressed: event => {
            // Ctrl/Cmd+Enter commits multiline edits without leaving the box.
            if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                textEditor.commitTextEdit();
                event.accepted = true;
            }
        }
    }

    // Node under the inline editor (null when closed or deleted).
    function editNode() {
        if (!textEditor.canvas.doc || textEditor.editingUid < 0)
            return null;
        return textEditor.canvas.doc.findNode(textEditor.editingUid);
    }
    function editAlignH() {
        var n = textEditor.editNode();
        if (!n)
            return TextEdit.AlignLeft;
        switch (n.hAlign) {
        case "center":
            return TextEdit.AlignHCenter;
        case "right":
            return TextEdit.AlignRight;
        case "justify":
            return TextEdit.AlignJustify;
        default:
            return TextEdit.AlignLeft;
        }
    }
    function editAlignV() {
        var n = textEditor.editNode();
        if (!n)
            return TextEdit.AlignTop;
        switch (n.vAlign) {
        case "middle":
            return TextEdit.AlignVCenter;
        case "bottom":
            return TextEdit.AlignBottom;
        default:
            return TextEdit.AlignTop;
        }
    }
    // Run-list equality (order + style): guards the seeding echo and
    // Esc-restore so identical runs never dirty the document.
    function runsEqual(a, b) {
        var x = a ?? [], y = b ?? [];
        if (x.length !== y.length)
            return false;
        for (var i = 0; i < x.length; i++) {
            var r = x[i] ?? {}, s = y[i] ?? {};
            if (Number(r.start) !== Number(s.start) || Number(r.len) !== Number(s.len))
                return false;
            if ((r.bold === true) !== (s.bold === true) || (r.italic === true) !== (s.italic === true))
                return false;
            if ((r.underline === true) !== (s.underline === true) || (r.strike === true) !== (s.strike === true))
                return false;
            if (String(r.color ?? "") !== String(s.color ?? ""))
                return false;
        }
        return true;
    }
    // Render-free box measure for content at a font. Empty content
    // measures one line ("Ag") with a 40px floor so fresh texts stay a
    // visible click target; letter spacing adds per glyph. Multiline
    // content measures the widest line (TextMetrics wraps only with an
    // explicit width, so split on newlines like the document layout).
    function measureText(content, family, weight, size, spacingPct, italic) {
        textMeasure.font = TextRuns.textFont(family, weight, size, italic, false, false, "none", 0);
        var t = content === "" ? "Ag" : content;
        var lines = String(t).split("\n");
        var bestW = 1, bestH = 0;
        for (var i = 0; i < lines.length; i++) {
            var lt = lines[i] === "" ? " " : lines[i];
            textMeasure.text = lt;
            var r = textMeasure.boundingRect;
            var extra = lt.length * size * (spacingPct || 0) / 100;
            bestW = Math.max(bestW, r.width + extra);
            bestH += Math.max(size * 1.2, r.height);
        }
        return {
            w: content === "" ? Math.max(40, bestW) : Math.max(1, bestW),
            h: Math.max(size * 1.2, bestH)
        };
    }
    // Text creation: auto boxes size from the (empty) content, fixed
    // boxes keep the drag rect. Both land selected and editing.
    function createText(cx, cy, w, h, auto) {
        if (!textEditor.canvas.doc)
            return;
        var bw = w, bh = h;
        if (auto) {
            var m = textEditor.measureText("", "Inter", 400, 16, 0);
            bw = m.w;
            bh = m.h;
        }
        var uid = textEditor.canvas.doc.addText(cx, cy, Math.max(1, bw), Math.max(1, bh), auto);
        textEditor.beginTextEdit(uid);
    }
    function beginTextEdit(uid) {
        var d = textEditor.canvas.doc;
        if (!d || textEditor.editingUid === uid)
            return;
        textEditor.commitTextEdit();
        var n = d.findNode(uid);
        if (!n || n.kind !== "shape" || n.shapeType !== "text")
            return;
        if (d.isEffectivelyLocked(n) || !d.isEffectivelyVisible(n))
            return;
        textEditor.editingUid = uid;
        textEditor.editDoc = d;
        textEditor.editStart = n.textContent;
        textEditor.editStartRuns = (n.textRuns || []).slice();
        editor.text = TextRuns.htmlFromRuns(n.textContent, n.textRuns ?? []);
        d.beginTransaction();
        editor.forceActiveFocus();
        editor.selectAll();
    }
    function commitTextEdit() {
        if (textEditor.editingUid < 0)
            return;
        textEditor.editingUid = -1;
        // editDoc may belong to a closed tab (destroyed): ending there
        // must never throw, the edit is simply already gone.
        try {
            if (textEditor.editDoc)
                textEditor.editDoc.endTransaction();
        } catch (e) {}
        textEditor.editDoc = null;
        textEditor.canvas.forceActiveFocus();
    }
    function cancelTextEdit() {
        if (textEditor.editingUid < 0)
            return;
        var uid = textEditor.editingUid;
        var back = textEditor.editStart;
        var backRuns = textEditor.editStartRuns;
        textEditor.editingUid = -1;
        try {
            if (textEditor.editDoc) {
                var n = textEditor.editDoc.findNode(uid);
                if (n && (n.textContent !== back || !textEditor.runsEqual(n.textRuns, backRuns))) {
                    textEditor.editDoc.setShapeProp(uid, "textContent", back);
                    textEditor.editDoc.setShapeProp(uid, "textRuns", backRuns);
                    var m = textEditor.measureText(back, n.fontFamily, n.fontWeight, n.fontSize, n.letterSpacing, n.fontItalic === true);
                    textEditor.applyMeasuredOn(textEditor.editDoc, uid, m.w, m.h);
                }
                textEditor.editDoc.endTransaction();
            }
        } catch (e) {}
        textEditor.editDoc = null;
        textEditor.canvas.forceActiveFocus();
    }
    // Measured writeback for auto-size boxes. Joins the ambient gesture
    // when one is open (typing, font edits), else commits a single entry
    // via begin/end. The 1px deadband keeps renders convergent.
    function applyMeasured(uid, w, h) {
        if (textEditor.canvas.doc)
            textEditor.applyMeasuredOn(textEditor.canvas.doc, uid, w, h);
    }
    function applyMeasuredOn(d, uid, w, h) {
        // Preview frames never resize boxes: grow/shrink playback would
        // otherwise checkpoint every tick into undo and autosave.
        if (d.anim && d.anim.playBase)
            return;
        var n = d.findNode(uid);
        if (!n || n.shapeType !== "text" || !n.autoSize)
            return;
        if (d.isEffectivelyLocked(n))
            return;
        var nw = Math.max(20, Math.round(w));
        var nh = Math.max(1, Math.round(Math.max(n.fontSize * 1.2, h)));
        if (Math.abs(nw - n.w) < 1 && Math.abs(nh - n.h) < 1)
            return;
        d.beginTransaction();
        d.setShapeProp(uid, "w", nw);
        d.setShapeProp(uid, "h", nh);
        d.endTransaction();
    }
    // Static-text writeback from ShapeItem paint. Editing items report
    // nothing (hidden glyphs paint zero); the editor measures instead.
    function textMeasured(uid, w, h) {
        textEditor.applyMeasured(uid, w, h);
    }
}
