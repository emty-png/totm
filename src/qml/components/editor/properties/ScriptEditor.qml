import QtQuick
import QtQuick.Controls
import Totm

// Mono code box for one dev script tab, with syntax highlighting and
// line numbers. A rich-text backdrop renders ScriptHighlight output
// behind a transparent TextArea (identical font/padding/geometry, so
// glyphs align); the gutter syncs to the shared scroll offset. code
// syncs both ways with !== guards so programmatic sets (design load)
// never fight typing.
Rectangle {
    id: editor

    property string code: ""
    property string language: "plain"

    onCodeChanged: {
        if (area.text !== editor.code)
            area.text = editor.code;
    }

    function gutterText() {
        var count = String(editor.code ?? "").split("\n").length;
        var out = "";
        for (var i = 1; i <= count; i++) {
            if (i > 1)
                out += "\n";
            out += i;
        }
        return out;
    }

    radius: AppTheme.radiusSmall
    color: AppTheme.background
    border.width: 1
    border.color: area.activeFocus ? AppTheme.foreground : AppTheme.fieldBorder
    clip: true

    ScriptHighlight {
        id: syntax
    }

    readonly property var pal: ({
            plain: AppTheme.foreground,
            keyword: AppTheme.selection,
            string: AppTheme.isDark ? "#9ece6a" : "#2e7d32",
            number: AppTheme.isDark ? "#ff9e64" : "#b26a00",
            comment: AppTheme.muted
        })

    Row {
        anchors.fill: parent
        anchors.margins: 1
        spacing: 0

        // Fixed line-number gutter, synced to the shared scroll.
        Item {
            width: 34
            height: parent.height
            clip: true

            Text {
                y: 8 - flick.contentY
                width: parent.width - 6
                horizontalAlignment: Text.AlignRight
                font.family: "monospace"
                font.pixelSize: 12
                color: AppTheme.muted
                text: editor.gutterText()
            }
        }

        Flickable {
            id: flick

            width: parent.width - 34
            height: parent.height
            clip: true
            contentWidth: area.contentWidth + 20
            contentHeight: area.contentHeight + 16
            ScrollBar.vertical: ScrollBar {}
            ScrollBar.horizontal: ScrollBar {}

            Text {
                id: backdrop

                x: 10
                y: 8
                width: area.contentWidth
                font.family: "monospace"
                font.pixelSize: 12
                wrapMode: Text.NoWrap
                textFormat: Text.RichText
                color: editor.pal.plain
                // Rich text collapses raw newlines as whitespace: break
                // lines explicitly (the highlighter itself stays plain
                // text, so its output still round-trips losslessly).
                text: syntax.highlight(area.text, editor.language, editor.pal).replace(/\n/g, "<br/>")
            }

            TextArea {
                id: area

                width: Math.max(flick.width, flick.contentWidth)
                height: Math.max(flick.height, flick.contentHeight)
                background: null
                color: "transparent"
                selectionColor: AppTheme.selection
                selectedTextColor: "#ffffff"
                font.family: "monospace"
                font.pixelSize: 12
                leftPadding: 10
                rightPadding: 10
                topPadding: 8
                bottomPadding: 8
                wrapMode: TextArea.NoWrap
                selectByMouse: true
                cursorDelegate: Rectangle {
                    width: 2
                    color: AppTheme.foreground
                }
                onTextChanged: {
                    if (text !== editor.code)
                        editor.code = text;
                }
            }
        }
    }
}
