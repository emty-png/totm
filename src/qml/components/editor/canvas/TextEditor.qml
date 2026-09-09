import QtQuick
import Totm

// Inline text editing (Figma): double-click or fresh creation opens
// a TextInput over the shape. Keystrokes stream into one undo
// transaction; Enter or focus loss commits, Esc restores + cancels.
// Owns the editing session (uid/start/doc) so tab switches end the
// gesture on the old doc, never the new one.
Item {
    id: textEditor

    anchors.fill: parent

    required property var canvas

    property int editingUid: -1
    property string editStart: ""
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

    // Inline text editor, floating over the shape in screen coords.
    // Rotation rides along (same angle about the same center) so it
    // tracks rotated text; the box itself stays axis-aligned math.
    TextInput {
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
        color: editor.node ? editor.node.fill : AppTheme.foreground
        selectionColor: AppTheme.selection
        font.family: editor.node ? editor.node.fontFamily : "Inter"
        font.pixelSize: Math.max(1, (editor.node ? editor.node.fontSize : 16) * textEditor.canvas.zoom)
        font.weight: editor.node ? editor.node.fontWeight : 400
        font.letterSpacing: editor.node ? editor.node.fontSize * editor.node.letterSpacing / 100 * textEditor.canvas.zoom : 0
        horizontalAlignment: textEditor.editAlignH()
        verticalAlignment: textEditor.editAlignV()
        wrapMode: editor.node && !editor.node.autoSize ? TextInput.WordWrap : TextInput.NoWrap

        onTextChanged: {
            if (textEditor.editingUid < 0 || !textEditor.editDoc)
                return;
            var cur = textEditor.editNode();
            // Seeding assignment (beginTextEdit copies node text in)
            // echoes back here with identical content: skip it so merely
            // opening the editor never dirties the document.
            if (cur && editor.text === cur.textContent)
                return;
            textEditor.editDoc.setShapeProp(textEditor.editingUid, "textContent", editor.text);
            var n = textEditor.editNode();
            if (n && n.autoSize) {
                var m = textEditor.measureText(editor.text, n.fontFamily, n.fontWeight, n.fontSize, n.letterSpacing);
                textEditor.applyMeasured(textEditor.editingUid, m.w, m.h);
            }
        }
        onEditingFinished: textEditor.commitTextEdit()
        Keys.onEscapePressed: event => {
            textEditor.cancelTextEdit();
            event.accepted = true;
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
            return TextInput.AlignLeft;
        switch (n.hAlign) {
        case "center":
            return TextInput.AlignHCenter;
        case "right":
            return TextInput.AlignRight;
        case "justify":
            return TextInput.AlignJustify;
        default:
            return TextInput.AlignLeft;
        }
    }
    function editAlignV() {
        var n = textEditor.editNode();
        if (!n)
            return TextInput.AlignTop;
        switch (n.vAlign) {
        case "middle":
            return TextInput.AlignVCenter;
        case "bottom":
            return TextInput.AlignBottom;
        default:
            return TextInput.AlignTop;
        }
    }
    // Render-free box measure for content at a font. Empty content
    // measures one line ("Ag") with a 40px floor so fresh texts stay a
    // visible click target; letter spacing adds per glyph.
    function measureText(content, family, weight, size, spacingPct) {
        textMeasure.font.family = family;
        textMeasure.font.weight = weight;
        textMeasure.font.pixelSize = Math.max(1, size);
        textMeasure.font.letterSpacing = 0;
        var t = content === "" ? "Ag" : content;
        textMeasure.text = t;
        var r = textMeasure.boundingRect;
        var extra = t.length * size * (spacingPct || 0) / 100;
        return {
            w: content === "" ? Math.max(40, r.width + extra) : Math.max(1, r.width + extra),
            h: Math.max(size * 1.2, r.height)
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
        editor.text = n.textContent;
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
        textEditor.editingUid = -1;
        try {
            if (textEditor.editDoc) {
                var n = textEditor.editDoc.findNode(uid);
                if (n && n.textContent !== back) {
                    textEditor.editDoc.setShapeProp(uid, "textContent", back);
                    var m = textEditor.measureText(back, n.fontFamily, n.fontWeight, n.fontSize, n.letterSpacing);
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
