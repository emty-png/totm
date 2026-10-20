import QtQuick
import Totm

// Pure syntax highlighters for dev script editors (no UI): each
// function takes plain source plus a palette and returns escaped
// rich text with <span> coloring. Kept UI-free so the logic stays
// headlessly testable; ScriptEditor renders the output behind a
// transparent TextArea. Scripts are KBs, so every function rescans
// the full text per keystroke with cross-line state for block
// comments and template literals.
QtObject {
    id: highlighter

    // Editor palette keyed off the app theme (which carries no syntax
    // colors, so they live here): {plain, keyword, string, number,
    // comment}. Tags/selectors/keywords share `keyword`; attribute
    // and property names ride `plain`.
    function palette() {
        var dark = true;
        try {
            dark = AppTheme.isDark;
        } catch (e) {}
        return {
            plain: dark ? "#e8e6df" : "#2b2620",
            keyword: "#0d99ff",
            string: dark ? "#9ece6a" : "#2e7d32",
            number: dark ? "#ff9e64" : "#b26a00",
            comment: dark ? "#8a8a8a" : "#9a938a"
        };
    }

    function esc(s) {
        return String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function span(text, color) {
        return "<span style=\"color:" + color + "\">" + highlighter.esc(text) + "</span>";
    }

    function highlight(code, language, pal) {
        var p = pal ?? highlighter.palette();
        var src = String(code ?? "");
        if (language === "html")
            return highlighter.highlightHtml(src, p);
        if (language === "css")
            return highlighter.highlightCss(src, p);
        if (language === "js")
            return highlighter.highlightJs(src, p);
        return highlighter.esc(src);
    }

    // HTML: <!-- --> comments, <tag attr="str">/text. Tag internals
    // parse quote-aware so > inside strings never ends the tag.
    function highlightHtml(code, pal) {
        var out = "";
        var i = 0;
        var n = code.length;
        while (i < n) {
            if (code.startsWith("<!--", i)) {
                var end = code.indexOf("-->", i + 4);
                end = end < 0 ? n : end + 3;
                out += highlighter.span(code.slice(i, end), pal.comment);
                i = end;
                continue;
            }
            if (code[i] === "<" && i + 1 < n && /[a-zA-Z\/!?]/.test(code[i + 1])) {
                var j = i + 1;
                var quote = null;
                while (j < n) {
                    var ch = code[j];
                    if (quote) {
                        if (ch === quote)
                            quote = null;
                    } else if (ch === '"' || ch === "'") {
                        quote = ch;
                    } else if (ch === ">") {
                        break;
                    }
                    j++;
                }
                var tag = code.slice(i, Math.min(j + 1, n));
                out += highlighter.highlightTag(tag, pal);
                i = Math.min(j + 1, n);
                continue;
            }
            var next = code.indexOf("<", i);
            if (next < 0)
                next = n;
            out += highlighter.esc(code.slice(i, next));
            i = next;
        }
        return out;
    }

    function highlightTag(tag, pal) {
        // </name attrs...>: name rides keyword, attr names plain,
        // quoted values string, punctuation plain.
        var m = /^(<\/?)([a-zA-Z][a-zA-Z0-9]*)?/.exec(tag);
        if (!m)
            return highlighter.esc(tag);
        var out = highlighter.esc(m[1]);
        var rest = tag.slice(m[1].length);
        if (m[2]) {
            out += highlighter.span(m[2], pal.keyword);
            rest = rest.slice(m[2].length);
        }
        var attrRe = /(\s+)([a-zA-Z][a-zA-Z0-9-]*)(=)("[^"]*"|'[^']*')?/g;
        var last = 0;
        var a = null;
        while ((a = attrRe.exec(rest)) !== null) {
            out += highlighter.esc(rest.slice(last, a.index));
            out += highlighter.esc(a[1]) + a[2];
            if (a[3])
                out += highlighter.esc(a[3]);
            if (a[4])
                out += highlighter.span(a[4], pal.string);
            last = a.index + a[0].length;
        }
        out += highlighter.esc(rest.slice(last));
        return out;
    }

    // CSS: selectors, {prop: value;} with strings/numbers/functions,
    // /* */ comments (multiline). Per-rule recovery mirrors the
    // compiler: one bad rule never kills the sheet's coloring.
    function highlightCss(code, pal) {
        var out = "";
        var i = 0;
        var n = code.length;
        var skipWs = () => {
            var s = "";
            while (i < n && /\s/.test(code[i])) {
                s += code[i];
                i++;
            }
            return s;
        };
        while (true) {
            out += highlighter.esc(skipWs());
            if (i >= n)
                break;
            if (code.startsWith("/*", i)) {
                var end = code.indexOf("*/", i + 2);
                end = end < 0 ? n : end + 2;
                out += highlighter.span(code.slice(i, end), pal.comment);
                i = end;
                continue;
            }
            var brace = code.indexOf("{", i);
            if (brace < 0) {
                out += highlighter.esc(code.slice(i));
                break;
            }
            out += highlighter.span(code.slice(i, brace), pal.keyword);
            i = brace + 1;
            var depth = 1;
            var j = i;
            while (j < n && depth > 0) {
                if (code[j] === "{")
                    depth++;
                else if (code[j] === "}")
                    depth--;
                j++;
            }
            var body = code.slice(i, depth > 0 ? n : j - 1);
            i = depth > 0 ? n : j;
            out += highlighter.esc("{") + highlighter.highlightCssBody(body, pal) + highlighter.esc(depth > 0 ? "" : "}");
        }
        return out;
    }

    function highlightCssBody(body, pal) {
        var out = "";
        var parts = [];
        var cur = "";
        var pd = 0;
        var quote = null;
        for (var c = 0; c < body.length; c++) {
            var ch = body[c];
            if (quote) {
                cur += ch;
                if (ch === quote)
                    quote = null;
                continue;
            }
            if (ch === '"' || ch === "'") {
                quote = ch;
                cur += ch;
                continue;
            }
            if (ch === "(")
                pd++;
            else if (ch === ")")
                pd = Math.max(0, pd - 1);
            if (ch === ";" && pd === 0) {
                parts.push(cur + ";");
                cur = "";
                continue;
            }
            cur += ch;
        }
        parts.push(cur);
        for (var p = 0; p < parts.length; p++) {
            var part = parts[p];
            var m = /^(\s*)([a-zA-Z-]+)(\s*:\s*)([\s\S]*?)(\s*;?\s*)$/.exec(part);
            if (!m || m[2] === "") {
                out += highlighter.esc(part);
                continue;
            }
            out += highlighter.esc(m[1]) + m[2] + highlighter.esc(m[3]) + highlighter.highlightCssValue(m[4], pal) + highlighter.esc(m[5]);
        }
        return out;
    }

    function highlightCssValue(value, pal) {
        var out = "";
        var re = /("[^"]*"|'[^']*'|#[0-9a-fA-F]{3,8}|-?[0-9]*\.?[0-9]+(?:deg|px|%|s|ms)?|[a-zA-Z-]+\()/g;
        var last = 0;
        var m = null;
        while ((m = re.exec(value)) !== null) {
            out += highlighter.esc(value.slice(last, m.index));
            var tok = m[0];
            if (tok[0] === '"' || tok[0] === "'" || tok[0] === "#")
                out += highlighter.span(tok, pal.string);
            else if (/^-?[0-9]/.test(tok))
                out += highlighter.span(tok, pal.number);
            else
                out += highlighter.span(tok, pal.keyword);
            last = m.index + tok.length;
        }
        out += highlighter.esc(value.slice(last));
        return out;
    }

    // JS: // and /* */ comments, ' " ` strings (escapes; backticks
    // span lines), numbers, keywords, totm.
    function highlightJs(code, pal) {
        var keywords = {
            "var": 1,
            "let": 1,
            "const": 1,
            "function": 1,
            "return": 1,
            "if": 1,
            "else": 1,
            "for": 1,
            "while": 1,
            "do": 1,
            "break": 1,
            "continue": 1,
            "new": 1,
            "delete": 1,
            "typeof": 1,
            "instanceof": 1,
            "in": 1,
            "of": 1,
            "switch": 1,
            "case": 1,
            "default": 1,
            "try": 1,
            "catch": 1,
            "finally": 1,
            "throw": 1,
            "true": 1,
            "false": 1,
            "null": 1,
            "undefined": 1,
            "this": 1,
            "class": 1,
            "extends": 1,
            "super": 1,
            "import": 1,
            "from": 1,
            "export": 1,
            "async": 1,
            "await": 1,
            "totm": 1
        };
        var out = "";
        var i = 0;
        var n = code.length;
        while (i < n) {
            var ch = code[i];
            if (ch === "/" && code[i + 1] === "/") {
                var nl = code.indexOf("\n", i);
                nl = nl < 0 ? n : nl;
                out += highlighter.span(code.slice(i, nl), pal.comment);
                i = nl;
                continue;
            }
            if (ch === "/" && code[i + 1] === "*") {
                var end = code.indexOf("*/", i + 2);
                end = end < 0 ? n : end + 2;
                out += highlighter.span(code.slice(i, end), pal.comment);
                i = end;
                continue;
            }
            if (ch === '"' || ch === "'" || ch === "`") {
                var q = ch;
                var j = i + 1;
                var str = ch;
                while (j < n) {
                    var c2 = code[j];
                    str += c2;
                    if (c2 === "\\" && j + 1 < n) {
                        str += code[j + 1];
                        j += 2;
                        continue;
                    }
                    j++;
                    if (c2 === q)
                        break;
                    // ' and " never span raw newlines (recovery).
                    if ((q === '"' || q === "'") && c2 === "\n")
                        break;
                }
                out += highlighter.span(str, pal.string);
                i = j;
                continue;
            }
            if (/[0-9]/.test(ch) || (ch === "." && i + 1 < n && /[0-9]/.test(code[i + 1]))) {
                var num = /^(0[xX][0-9a-fA-F]+|0[bB][01]+|0[oO][0-7]+|-?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?)/.exec(code.slice(i));
                out += highlighter.span(num[0], pal.number);
                i += num[0].length;
                continue;
            }
            if (/[a-zA-Z_$]/.test(ch)) {
                var id = /^[a-zA-Z_$][a-zA-Z0-9_$]*/.exec(code.slice(i))[0];
                out += keywords[id] ? highlighter.span(id, pal.keyword) : highlighter.esc(id);
                i += id.length;
                continue;
            }
            out += highlighter.esc(ch);
            i++;
        }
        return out;
    }
}
