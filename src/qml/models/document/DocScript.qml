import QtQuick
import Totm

// Live-linked dev script for one Document. Compiles the totm-flavored
// HTML/CSS/JS source in doc.script into native nodes + clips, so canvas
// preview and video export work untouched (export renders plain scene
// data and cannot run code). Generated nodes carry ownedTag in
// scriptId; re-runs replace same-tag nodes, hand-owned nodes are never
// touched. HTML supports rect/ellipse/triangle/star/text/img/video/
// pen/audio plus nested <g> groups; CSS cascades type/.class/#name
// rules (geometry, paint, typography, effects, shaders) over HTML
// presentation attributes; the JS tab evaluates in the sandboxed
// ScriptRunner (ops only: creates, groups, find, set/remove, presets
// incl. custom from-to via options, mediated picks, audio, duration)
// and applies in the same undo entry. JS runs async (hang-safe);
// HTML/CSS-only runs stay sync.
QtObject {
    id: devScript
    required property var doc

    // Ownership tag written onto generated nodes (DocNode.scriptId).
    readonly property string ownedTag: "script"
    // Find-handle bit: handles >= this from totm.find() index the
    // op-list finds array (mirrors ScriptBridge::kFindBit in C++).
    readonly property int jsFindBit: 1073741824
    // Resource caps (mirror ScriptBridge in C++): a tight JS loop must
    // fail with a readable error, never OOM the app. The worker enforces
    // the same numbers; these guards run first so oversize input never
    // spawns a helper or opens a giant undo transaction.
    readonly property int maxSourceChars: 262144
    readonly property int maxHtmlElements: 2000
    readonly property int maxCssRules: 500
    readonly property int maxGroupDepth: 64
    readonly property int maxJsCreates: 2000
    readonly property int maxJsGroups: 500
    readonly property int maxJsAnimates: 2000
    readonly property int maxJsSets: 5000
    readonly property int maxJsRemoves: 2000
    readonly property int maxJsFinds: 1000
    readonly property int maxJsPicks: 32
    readonly property int maxJsAudio: 128
    readonly property int maxJsPenPoints: 4096
    readonly property int maxTotalNodes: 3000
    readonly property int maxDiags: 200

    // Last Run report: {ok, diagnostics: [{tab, line, message,
    // kind ("error"|"warning")}], created: [uids]}.
    property var lastRun: ({
            ok: true,
            diagnostics: [],
            created: []
        })

    // Async JS state: parsed HTML/CSS wait while the worker evaluates.
    // A fresh Run aborts the previous worker first.
    property bool jsRunning: false
    property int pendingRunId: -1
    property var pending: null

    // Two-phase pick flow: phase 1 collects file requests (no scene
    // mutation); the panel drives mediated picks; phase 2 replays with
    // chosen blobs (replaying) and applies. Cancel leaves no trace.
    property bool jsPickFlow: false
    property var pickDefs: []
    property var pickBlobs: ({})
    property bool replaying: false
    property var pendingPick: null

    // Audio duration probe (imperative children: QtObject nests none).
    // Narrow compositions clamp in addClip; undecodable files error out.
    property var probePlayer: null
    property var probeTimer: null
    property var probeQueue: []
    property var probeCont: null
    property int probeTries: 0

    // QtObject has no default property, so Connections cannot nest
    // here: hook the runner signal imperatively instead. The probe
    // player/timer are built the same way for the same reason; either
    // failing degrades to skip (audio ops error at apply).
    Component.onCompleted: {
        ScriptRunner.finished.connect(devScript._onJsFinished);
        try {
            devScript.probePlayer = Qt.createQmlObject("import QtMultimedia; MediaPlayer {}", devScript);
            devScript.probeTimer = Qt.createQmlObject("import QtQuick; Timer { interval: 100; repeat: true }", devScript);
        } catch (e) {
            devScript.probePlayer = null;
            devScript.probeTimer = null;
        }
        if (devScript.probeTimer)
            devScript.probeTimer.triggered.connect(devScript._onProbeTick);
    }

    function _num(raw, fallback) {
        var v = Number(raw);
        return isNaN(v) ? fallback : v;
    }

    // HTML subset, one element per line, with <g> grouping:
    //   <rect x=".." y=".." w=".." h=".." fill=".."/>
    //   <ellipse|triangle|star ...same... />
    //   <text x=".." y=".." w=".." h=".." fill="..">content</text>
    //   <img src="blob" x=".." y=".." w=".." h=".."/>
    //   <video src="blob" x=".." y=".." w=".." h=".."/>
    //   <pen points="x1,y1 x2,y2 ..." closed="true|false" fill=".."/>
    //   <audio src="blob" t0=".." duration=".."/>
    //   <g name=".." class=".."> ... children ... </g>
    // <g> nests (one per line); <g .../> is an empty group. src names
    // a library blob (hard error when missing). Unknown tags and
    // malformed lines become errors (with line numbers); valid lines
    // still run (partial output).
    function parseHtml(src) {
        var elements = [];
        var errors = [];
        var kinds = {
            rect: "rectangle",
            ellipse: "ellipse",
            triangle: "triangle",
            star: "star",
            text: "text",
            img: "image",
            video: "video",
            pen: "pen",
            audio: "audio"
        };
        // Group stack: each frame {name, classes, line, attrStyle,
        // children}. Top-level shapes attach to `elements`.
        var stack = [];
        var topList = () => stack.length > 0 ? stack[stack.length - 1].children : elements;
        var lines = String(src ?? "").split("\n");
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (line === "" || line.startsWith("<!--"))
                continue;
            var closeM = /^<\/([a-zA-Z]+)\s*>\s*(<!--.*)?$/.exec(line);
            if (closeM) {
                var closeTag = closeM[1].toLowerCase();
                if (closeTag === "g") {
                    if (stack.length === 0) {
                        errors.push({
                            line: i + 1,
                            message: qsTr("Unmatched </g>")
                        });
                        continue;
                    }
                    var frame = stack.pop();
                    var gEl = {
                        tag: "g",
                        kind: "group",
                        line: frame.line,
                        name: frame.name,
                        classes: frame.classes,
                        attrStyle: frame.attrStyle,
                        children: frame.children
                    };
                    topList().push(gEl);
                    continue;
                }
                errors.push({
                    line: i + 1,
                    message: qsTr("Unexpected closing tag </%1>").arg(closeM[1])
                });
                continue;
            }
            if (line.startsWith("</")) {
                errors.push({
                    line: i + 1,
                    message: qsTr("Unexpected closing tag")
                });
                continue;
            }
            var m = /^<([a-zA-Z]+)((?:\s+[a-zA-Z][a-zA-Z0-9-]*\s*=\s*(?:"[^"]*"|'[^']*'))*)\s*\/?>\s*(.*)$/.exec(line);
            if (!m) {
                errors.push({
                    line: i + 1,
                    message: qsTr("Could not parse line")
                });
                continue;
            }
            var tag = m[1].toLowerCase();
            var attrs = {};
            var attrRe = /([a-zA-Z][a-zA-Z0-9-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')/g;
            var a = null;
            while ((a = attrRe.exec(m[2])) !== null)
                attrs[a[1].toLowerCase()] = a[2] ?? a[3] ?? "";
            // Group open: <g name class> pushes a frame; <g .../>
            // is an empty group. Children attach to topList().
            if (tag === "g") {
                var gAttrStyle = {};
                var gPresent = ["opacity", "radius"];
                for (var gi = 0; gi < gPresent.length; gi++) {
                    if (attrs[gPresent[gi]] !== undefined) {
                        gAttrStyle[gPresent[gi]] = {
                            value: attrs[gPresent[gi]],
                            line: i + 1
                        };
                    }
                }
                var gClasses = String(attrs.class ?? "").split(/\s+/).filter(s => s !== "");
                var gName = attrs.name ?? "";
                var selfClose = /\/>\s*(<!--.*)?$/.test(line);
                var trail = (m[3] || "").trim();
                if (trail !== "" && !trail.startsWith("<!--")) {
                    errors.push({
                        line: i + 1,
                        message: qsTr("Unexpected content after tag")
                    });
                    continue;
                }
                if (selfClose) {
                    topList().push({
                        tag: "g",
                        kind: "group",
                        line: i + 1,
                        name: gName,
                        classes: gClasses,
                        attrStyle: gAttrStyle,
                        children: []
                    });
                } else if (stack.length >= devScript.maxGroupDepth) {
                    errors.push({
                        line: i + 1,
                        message: qsTr("Too many nested groups (max %1)").arg(devScript.maxGroupDepth)
                    });
                } else {
                    stack.push({
                        name: gName,
                        classes: gClasses,
                        line: i + 1,
                        attrStyle: gAttrStyle,
                        children: []
                    });
                }
                continue;
            }
            if (!(tag in kinds)) {
                errors.push({
                    line: i + 1,
                    message: qsTr("Unknown tag <%1>").arg(m[1])
                });
                continue;
            }
            // Presentation attributes: style props written inline ride
            // as the lowest-priority style layer (CSS rules override
            // them in _applyHtmlElement). Fill/x/y/w/h/rotation/name/
            // class/src stay on the element itself.
            var attrStyle = {};
            var presentProps = ["opacity", "radius", "fill-opacity", "stroke", "stroke-width", "stroke-position", "stroke-opacity", "layer-blur", "background-blur", "grain", "shadow", "glow", "shader", "shader-mode", "font-family", "font-size", "font-weight", "font-style", "text-decoration", "text-transform", "text-align"];
            for (var pi = 0; pi < presentProps.length; pi++) {
                var pp = presentProps[pi];
                if (attrs[pp] !== undefined) {
                    attrStyle[pp] = {
                        value: attrs[pp],
                        line: i + 1
                    };
                }
            }
            var el = {
                tag: tag,
                kind: kinds[tag],
                line: i + 1,
                x: devScript._num(attrs.x, 0),
                y: devScript._num(attrs.y, 0),
                w: Math.max(1, Math.round(devScript._num(attrs.w, 100))),
                h: Math.max(1, Math.round(devScript._num(attrs.h, 100))),
                rotation: devScript._num(attrs.rotation ?? attrs.rotate ?? 0, 0),
                fill: attrs.fill ?? (tag === "text" ? "#000000" : "#d9d9d9"),
                name: attrs.name ?? "",
                classes: String(attrs.class ?? "").split(/\s+/).filter(s => s !== ""),
                blob: attrs.src ?? "",
                attrStyle: attrStyle
            };
            if (el.kind === "image" || el.kind === "video" || el.kind === "audio") {
                if (el.blob === "") {
                    errors.push({
                        line: i + 1,
                        message: qsTr("<%1> needs a src blob name").arg(m[1])
                    });
                    continue;
                }
            }
            if (tag === "audio") {
                // Timeline clip, not a node: explicit duration keeps
                // the HTML path sync (JS probes async instead).
                el.t0 = Math.max(0, Number(attrs.t0 ?? 0) || 0);
                el.duration = Number(attrs.duration ?? attrs.dur ?? 0);
                if (!(el.duration > 0)) {
                    errors.push({
                        line: i + 1,
                        message: qsTr("<audio> needs a duration in seconds")
                    });
                    continue;
                }
            }
            if (tag === "pen") {
                // Polyline points "x1,y1 x2,y2 ...", absolute content
                // coords; closed="true" joins the loop. Needs 2+ pts.
                var ptsRaw = String(attrs.points ?? "").trim().split(/\s+/).filter(s => s !== "");
                var pts = [];
                var badPt = false;
                for (var qi = 0; qi < ptsRaw.length; qi++) {
                    var xy = ptsRaw[qi].split(",");
                    if (xy.length !== 2) {
                        badPt = true;
                        break;
                    }
                    var px = Number(xy[0]);
                    var py = Number(xy[1]);
                    if (isNaN(px) || isNaN(py)) {
                        badPt = true;
                        break;
                    }
                    pts.push({
                        x: px,
                        y: py,
                        smooth: false,
                        inX: px,
                        inY: py,
                        outX: px,
                        outY: py
                    });
                }
                if (badPt || pts.length < 2) {
                    errors.push({
                        line: i + 1,
                        message: qsTr("<pen> needs points=\"x1,y1 x2,y2 ...\" (2+ points)")
                    });
                    continue;
                }
                var closedRaw = String(attrs.closed ?? "false").trim().toLowerCase();
                el.pathData = [
                    {
                        closed: closedRaw === "true" || closedRaw === "1" || closedRaw === "yes",
                        pts: pts
                    }
                ];
            }
            if (el.fill === "" && el.kind !== "image" && el.kind !== "video" && el.kind !== "audio" && el.kind !== "pen") {
                errors.push({
                    line: i + 1,
                    message: qsTr("Empty fill color")
                });
                continue;
            }
            if (tag === "text") {
                var rest = m[3] || "";
                var close = rest.lastIndexOf("</text>");
                el.content = (close >= 0 ? rest.slice(0, close) : rest).trim();
                if (close < 0) {
                    errors.push({
                        line: i + 1,
                        message: qsTr("<text> is missing </text>")
                    });
                    continue;
                }
            } else if ((m[3] || "").trim() !== "") {
                errors.push({
                    line: i + 1,
                    message: qsTr("Unexpected content after tag")
                });
                continue;
            }
            topList().push(el);
        }
        while (stack.length > 0) {
            var open = stack.pop();
            errors.push({
                line: open.line,
                message: qsTr("Missing </g> for <g> opened here")
            });
            // Keep partial children: attach what was collected.
            topList().push({
                tag: "g",
                kind: "group",
                line: open.line,
                name: open.name,
                classes: open.classes,
                attrStyle: open.attrStyle,
                children: open.children
            });
        }
        return {
            elements: elements,
            errors: errors
        };
    }

    // Destroy a node subtree (children are doc-parented, so groups
    // need an explicit walk or orphaned leaves leak).
    function _burn(node) {
        if (node.kind === "group") {
            var kids = node.children || [];
            for (var i = 0; i < kids.length; i++)
                devScript._burn(kids[i]);
        }
        node.destroy();
    }

    // Delete every script-owned node (any depth), keeping hand-owned
    // content. Runs inside the caller's transaction.
    function _deleteOwned() {
        var d = devScript.doc;
        var prune = list => {
            var out = [];
            for (var j = 0; j < list.length; j++) {
                var n = list[j];
                if (String(n.scriptId ?? "") === devScript.ownedTag) {
                    devScript._burn(n);
                    continue;
                }
                if (n.kind === "group")
                    n.children = prune(n.children);
                out.push(n);
            }
            return out;
        };
        d.rootChildren = prune(d.rootChildren);
        d.pruneDrillPath();
        d.anchorUid = -1;
        d._refreshStructural();
    }

    // ---- CSS subset -------------------------------------------------
    // Rules: `rect { fill: #ff0000; }`, `.cls { ... }`, `#name { ... }`,
    // comma lists. Selectors: type (rect/ellipse/triangle/star/text/
    // img/video/pen/audio/g), .class (matches the class attribute
    // word list) or
    // #name (matches the name attribute). Anything else warns as
    // unsupported. Properties: x, y, w, h, rotation, fill (color or
    // linear-gradient()), fill-opacity, stroke, stroke-width,
    // stroke-position, stroke-opacity, opacity, radius, font-family,
    // font-size, font-weight, font-style, text-decoration,
    // text-transform, text-align. Unknown properties warn; malformed
    // rules error and are skipped. Recovery is per rule, so one bad
    // rule never kills the sheet.
    readonly property var cssProps: ["x", "y", "w", "h", "rotation", "fill", "fill-opacity", "stroke", "stroke-width", "stroke-position", "stroke-opacity", "opacity", "radius", "layer-blur", "background-blur", "grain", "shadow", "glow", "shader", "shader-mode", "font-family", "font-size", "font-weight", "font-style", "text-decoration", "text-transform", "text-align"]

    function _cssLineOf(text, upTo) {
        var line = 1;
        for (var i = 0; i < upTo && i < text.length; i++) {
            if (text[i] === "\n")
                line++;
        }
        return line;
    }

    function parseCss(src) {
        var rules = [];
        var diags = [];
        // Strip /* */ comments but keep newlines so line numbers hold.
        var text = String(src ?? "").replace(/\/\*[\s\S]*?\*\//g, function (m) {
            return m.replace(/[^\n]/g, "");
        });
        var n = text.length;
        var i = 0;
        var skipWs = () => {
            while (i < n && /\s/.test(text[i]))
                i++;
        };
        while (true) {
            skipWs();
            if (i >= n)
                break;
            var selLine = devScript._cssLineOf(text, i);
            var brace = text.indexOf("{", i);
            if (brace < 0) {
                if (text.slice(i).trim() !== "") {
                    diags.push({
                        line: selLine,
                        message: qsTr("Expected '{' after selector"),
                        kind: "error"
                    });
                }
                break;
            }
            var selText = text.slice(i, brace);
            i = brace + 1;
            // Pasted sources smuggle invisible characters (zero-width
            // spaces, BOM) that trim() keeps and that would otherwise
            // surface as mystery "unsupported selector" reports.
            selText = selText.replace(/[\u200B\u200C\u200D\uFEFF]/g, "");
            var depth = 1;
            var j = i;
            while (j < n && depth > 0) {
                if (text[j] === "{")
                    depth++;
                else if (text[j] === "}")
                    depth--;
                j++;
            }
            if (depth > 0) {
                diags.push({
                    line: selLine,
                    message: qsTr("Missing '}'"),
                    kind: "error"
                });
                break;
            }
            var body = text.slice(i, j - 1);
            i = j;
            var selectors = [];
            var raws = selText.split(",");
            for (var s = 0; s < raws.length; s++) {
                var sel = raws[s].trim();
                if (sel === "")
                    continue;
                if (sel.startsWith("#") && sel.length > 1)
                    selectors.push({
                        type: "id",
                        value: sel.slice(1),
                        score: 3
                    });
                else if (sel.startsWith(".") && sel.length > 1 && /^\.[A-Za-z0-9_-]+$/.test(sel))
                    selectors.push({
                        type: "class",
                        value: sel.slice(1),
                        score: 2
                    });
                else if (/^(rect|ellipse|triangle|star|text|img|video|pen|audio|g)$/.test(sel))
                    selectors.push({
                        type: "tag",
                        value: sel,
                        score: 1
                    });
                else {
                    diags.push({
                        line: selLine,
                        message: qsTr("Unsupported selector '%1' — use a type (rect, ellipse, triangle, star, text, img, video, pen, audio, g), .class or #name").arg(sel),
                        kind: "warning"
                    });
                }
            }
            if (selectors.length === 0) {
                diags.push({
                    line: selLine,
                    message: qsTr("Rule has no usable selector — use a type (rect, ellipse, triangle, star, text, img, video, pen, audio, g), .class or #name"),
                    kind: "error"
                });
                continue;
            }
            // Split declarations on ';' outside parens (gradients
            // carry commas, never semicolons, but stay general).
            var parts = [];
            var cur = "";
            var pd = 0;
            for (var c = 0; c < body.length; c++) {
                var ch = body[c];
                if (ch === "(")
                    pd++;
                else if (ch === ")")
                    pd = Math.max(0, pd - 1);
                if (ch === ";" && pd === 0) {
                    parts.push(cur);
                    cur = "";
                } else {
                    cur += ch;
                }
            }
            if (cur.trim() !== "")
                parts.push(cur);
            var decls = {};
            var offset = 0;
            for (var p = 0; p < parts.length; p++) {
                var part = parts[p];
                var at = body.indexOf(part, offset);
                offset = (at < 0 ? offset : at) + part.length;
                // The chunk carries leading whitespace (often the
                // newline ending the previous line), so count those
                // newlines too or errors point a line too high.
                var leadNl = (part.match(/^\s*/) || [""])[0].split("\n").length - 1;
                var declLine = selLine + devScript._cssLineOf(body, at < 0 ? 0 : at) - 1 + leadNl;
                var trimmed = part.trim();
                if (trimmed === "")
                    continue;
                var colon = trimmed.indexOf(":");
                if (colon < 0) {
                    diags.push({
                        line: declLine,
                        message: qsTr("Expected ':' in declaration"),
                        kind: "error"
                    });
                    continue;
                }
                var prop = trimmed.slice(0, colon).trim().toLowerCase();
                var value = trimmed.slice(colon + 1).trim();
                if (value === "") {
                    diags.push({
                        line: declLine,
                        message: qsTr("Empty value for '%1'").arg(prop),
                        kind: "error"
                    });
                    continue;
                }
                if (devScript.cssProps.indexOf(prop) < 0) {
                    diags.push({
                        line: declLine,
                        message: qsTr("Unknown property '%1'").arg(prop),
                        kind: "warning"
                    });
                    continue;
                }
                decls[prop] = {
                    value: value,
                    line: declLine
                };
            }
            rules.push({
                selectors: selectors,
                decls: decls,
                line: selLine,
                matched: false
            });
        }
        return {
            rules: rules,
            diags: diags
        };
    }

    // linear-gradient(90deg, #ff0000 0%, #0000ff): angle defaults to
    // 90; stop positions are optional (missing ones space evenly at
    // paint time, like native gradients). The inner match spans
    // newlines so pressing Enter mid-gradient never breaks it.
    // Returns {angle, stops} or {error}.
    function parseGradientFill(value) {
        var m = /^linear-gradient\s*\(([\s\S]*)\)\s*$/.exec(String(value).trim());
        if (!m)
            return {
                error: true
            };
        var inner = m[1].split(",");
        var angle = 90;
        var from = 0;
        var first = (inner.length > 0 ? inner[0] : "").trim();
        var am = /^([0-9.]+)deg$/.exec(first);
        if (am) {
            angle = Number(am[1]);
            from = 1;
        }
        var stops = [];
        for (var k = from; k < inner.length; k++) {
            var tok = inner[k].trim();
            if (tok === "")
                continue;
            var bits = tok.split(/\s+/);
            var pos = -1;
            var last = bits[bits.length - 1];
            if (bits.length > 1 && last.endsWith("%")) {
                pos = Math.min(1, Math.max(0, Number(last.slice(0, -1)) / 100));
                if (isNaN(pos))
                    pos = -1;
                bits = bits.slice(0, -1);
            }
            var color = bits.join(" ");
            if (color === "")
                return {
                    error: true
                };
            stops.push({
                color: color,
                pos: pos
            });
        }
        if (stops.length < 2)
            return {
                error: true
            };
        return {
            angle: angle,
            stops: stops
        };
    }

    // Known animated shader presets (mirrors ShaderEngine presets).
    readonly property var shaderPresets: ["plasma", "aurora", "clouds", "kaleidoscope", "scanlines", "fire", "nebula", "vortex", "matrix"]

    // Effect value helpers: each accepts a CSS string or a JS value
    // (number / {…} map from the bridge) and returns a native snap
    // fragment or {error}. Warnings are raised by the caller.
    function _parseBlurVal(v, defRadius, defOpacity) {
        if (v !== null && typeof v === "object") {
            var r = Number(v.radius ?? defRadius);
            var o = Number(v.opacity ?? defOpacity);
            if (isNaN(r) || isNaN(o))
                return {
                    error: true
                };
            return {
                radius: Math.max(0, r),
                opacity: Math.min(1, Math.max(0, o))
            };
        }
        var n = Number(String(v ?? "").replace(/px$/, "").trim());
        if (isNaN(n))
            return {
                error: true
            };
        return {
            radius: Math.max(0, n),
            opacity: defOpacity
        };
    }

    function _parseGrainVal(v) {
        if (v !== null && typeof v === "object") {
            var a = Number(v.amount ?? 0.5);
            var s = Number(v.size ?? 2);
            if (isNaN(a) || isNaN(s))
                return {
                    error: true
                };
            return {
                amount: Math.min(1, Math.max(0, a)),
                size: Math.min(10, Math.max(1, Math.round(s)))
            };
        }
        var toks = String(v ?? "").trim().split(/\s+/).filter(t => t !== "");
        if (toks.length === 0 || toks.length > 2)
            return {
                error: true
            };
        var amt = Number(toks[0]);
        var sz = toks.length > 1 ? Number(toks[1]) : 2;
        if (isNaN(amt) || isNaN(sz))
            return {
                error: true
            };
        return {
            amount: Math.min(1, Math.max(0, amt)),
            size: Math.min(10, Math.max(1, Math.round(sz)))
        };
    }

    // "color [x y blur spread] [inner]": bare color uses defaults
    // (0, 4, 8, 0). JS may pass {color,x,y,blur,spread,inner}.
    function _parseShadowVal(v) {
        if (v !== null && typeof v === "object" && !Array.isArray(v)) {
            var c = String(v.color ?? "");
            if (c === "")
                return {
                    error: true
                };
            return {
                color: c,
                x: Number(v.x ?? 0) || 0,
                y: v.y !== undefined ? (Number(v.y) || 0) : 4,
                blur: Math.max(0, Number(v.blur ?? 8) || 0),
                spread: Math.max(0, Number(v.spread ?? 0) || 0),
                inner: v.inner === true || v.inset === true
            };
        }
        var toks = String(v ?? "").trim().split(/\s+/).filter(t => t !== "");
        if (toks.length === 0)
            return {
                error: true
            };
        var inner = false;
        toks = toks.filter(t => {
            var low = t.toLowerCase();
            if (low === "inner" || low === "inset") {
                inner = true;
                return false;
            }
            return true;
        });
        var nums = toks.slice(1).map(Number);
        if (nums.some(n => isNaN(n)) || nums.length > 4)
            return {
                error: true
            };
        return {
            color: toks[0],
            x: nums.length > 0 ? nums[0] : 0,
            y: nums.length > 1 ? nums[1] : 4,
            blur: nums.length > 2 ? Math.max(0, nums[2]) : 8,
            spread: nums.length > 3 ? Math.max(0, nums[3]) : 0,
            inner: inner
        };
    }

    // "color [blur spread] [inner]": bare color uses defaults
    // (16, 4). JS may pass {color,blur,spread,inner}.
    function _parseGlowVal(v) {
        if (v !== null && typeof v === "object" && !Array.isArray(v)) {
            var c = String(v.color ?? "");
            if (c === "")
                return {
                    error: true
                };
            return {
                color: c,
                blur: Math.max(0, Number(v.blur ?? 16) || 0),
                spread: Math.max(0, Number(v.spread ?? 4) || 0),
                inner: v.inner === true || v.inset === true
            };
        }
        var toks = String(v ?? "").trim().split(/\s+/).filter(t => t !== "");
        if (toks.length === 0)
            return {
                error: true
            };
        var inner = false;
        toks = toks.filter(t => {
            var low = t.toLowerCase();
            if (low === "inner" || low === "inset") {
                inner = true;
                return false;
            }
            return true;
        });
        var nums = toks.slice(1).map(Number);
        if (nums.some(n => isNaN(n)) || nums.length > 2)
            return {
                error: true
            };
        return {
            color: toks[0],
            blur: nums.length > 0 ? Math.max(0, nums[0]) : 16,
            spread: nums.length > 1 ? Math.max(0, nums[1]) : 4,
            inner: inner
        };
    }

    // "preset:plasma" or bare "plasma"; "" / "none" clears.
    function _parseShaderVal(v) {
        var s = String(v ?? "").trim();
        if (s === "" || s.toLowerCase() === "none")
            return {
                clear: true
            };
        if (s.startsWith("preset:"))
            s = s.slice(7);
        if (devScript.shaderPresets.indexOf(s) < 0)
            return {
                error: true
            };
        return {
            id: "preset:" + s
        };
    }

    // Cascade matching rules over one element. #name (score 3) beats
    // .class (score 2) beats type (score 1); ties go to the later rule.
    // Returns style mapping prop -> {value, line}.
    function cascadeFor(el, rules) {
        var style = {};
        var best = {};
        for (var ri = 0; ri < rules.length; ri++) {
            var r = rules[ri];
            var score = -1;
            for (var s = 0; s < r.selectors.length; s++) {
                var sel = r.selectors[s];
                if (sel.type === "id" && el.name !== "" && el.name === sel.value)
                    score = Math.max(score, sel.score);
                else if (sel.type === "class" && (el.classes ?? []).indexOf(sel.value) >= 0)
                    score = Math.max(score, sel.score);
                else if (sel.type === "tag" && el.tag === sel.value)
                    score = Math.max(score, sel.score);
            }
            if (score < 0)
                continue;
            r.matched = true;
            for (var prop in r.decls) {
                var cur = best[prop];
                if (!cur || score >= cur.score) {
                    style[prop] = r.decls[prop];
                    best[prop] = {
                        score: score
                    };
                }
            }
        }
        return style;
    }

    function _styleNum(entry, fallback) {
        var v = Number(String(entry.value).replace(/px$/, ""));
        return isNaN(v) ? fallback : v;
    }

    // Insert one parsed element as a script-owned node in the active
    // container, with the cascaded CSS style applied over the HTML
    // attributes. Runs inside the caller's transaction. Value problems
    // append warnings to diags instead of failing the element.
    function _createElement(el, style, diags) {
        var d = devScript.doc;
        var container = d._activeContainerUid();
        // Diagnostics from value fallbacks belong to the element's
        // source tab (HTML attribute defaults report as CSS-side
        // notes; JS-built elements carry tab "js").
        var elTab = el.tab ?? "css";
        var warn = (prop, message) => {
            diags.push({
                tab: elTab,
                line: (style[prop] || {}).line ?? el.line ?? 0,
                message: message,
                kind: "warning"
            });
        };
        // Fill: CSS wins over the attribute; gradients compile to a
        // native linear entry (normalized by the factory).
        var fillColor = el.fill;
        var fillOpacity = 1;
        var fillGradient = null;
        if (style["fill"]) {
            var raw = String(style["fill"].value).trim();
            if (/^linear-gradient\s*\(/.test(raw)) {
                var g = devScript.parseGradientFill(raw);
                if (g.error) {
                    warn("fill", qsTr("Bad linear-gradient(), using attribute fill"));
                } else {
                    fillGradient = d.factory._copyGradient({
                        angle: g.angle,
                        stops: g.stops
                    });
                }
            } else if (raw === "") {
                warn("fill", qsTr("Empty fill color, using attribute fill"));
            } else {
                fillColor = raw;
            }
        } else if (/^linear-gradient\s*\(/.test(String(fillColor ?? "").trim())) {
            // Attribute/JS fills may carry a gradient directly (no CSS
            // rule): compile it here so HTML and JS share the CSS path.
            var ag = devScript.parseGradientFill(String(fillColor).trim());
            if (ag.error) {
                diags.push({
                    tab: elTab,
                    line: el.line ?? 0,
                    message: qsTr("Bad linear-gradient(), using solid fill"),
                    kind: "warning"
                });
                fillColor = "#d9d9d9";
            } else {
                fillGradient = d.factory._copyGradient({
                    angle: ag.angle,
                    stops: ag.stops
                });
            }
        }
        if (style["fill-opacity"]) {
            var fo = Number(style["fill-opacity"].value);
            if (isNaN(fo))
                warn("fill-opacity", qsTr("Bad fill-opacity, using 1"));
            else
                fillOpacity = Math.min(1, Math.max(0, fo));
        }
        var fillEntry = {
            enabled: true,
            color: fillColor,
            type: fillGradient ? "linear" : "solid",
            opacity: fillOpacity
        };
        if (fillGradient)
            fillEntry.gradient = fillGradient;
        // Stroke: only when the sheet asks for one (new shapes stay
        // stroke-free like hand-drawn ones).
        var strokes = [];
        if (style["stroke"]) {
            var sc = String(style["stroke"].value).trim();
            if (sc === "") {
                warn("stroke", qsTr("Empty stroke color, skipping stroke"));
            } else {
                var sw = style["stroke-width"] ? devScript._styleNum(style["stroke-width"], NaN) : 1;
                if (isNaN(sw) || sw < 0) {
                    warn("stroke-width", qsTr("Bad stroke-width, using 1"));
                    sw = 1;
                }
                var sp = style["stroke-position"] ? String(style["stroke-position"].value).trim().toLowerCase() : "center";
                if (sp !== "inside" && sp !== "outside" && sp !== "center") {
                    warn("stroke-position", qsTr("Bad stroke-position, using center"));
                    sp = "center";
                }
                var so = 1;
                if (style["stroke-opacity"]) {
                    var son = Number(style["stroke-opacity"].value);
                    if (isNaN(son))
                        warn("stroke-opacity", qsTr("Bad stroke-opacity, using 1"));
                    else
                        so = Math.min(1, Math.max(0, son));
                }
                strokes.push({
                    enabled: true,
                    color: sc,
                    type: "solid",
                    width: sw,
                    position: sp,
                    opacity: so
                });
            }
        }
        var snap = {
            x: Math.round(el.x),
            y: Math.round(el.y),
            w: el.w,
            h: el.h,
            rotation: Number(el.rotation) || 0,
            fills: [fillEntry],
            strokes: strokes,
            scriptId: devScript.ownedTag
        };
        // Geometry: CSS wins over attributes. Bad numbers warn and
        // keep the attribute value; w/h clamp at 1px like the parser.
        if (style["x"]) {
            var gx = devScript._styleNum(style["x"], NaN);
            if (isNaN(gx))
                warn("x", qsTr("Bad x, using attribute value"));
            else
                snap.x = Math.round(gx);
        }
        if (style["y"]) {
            var gy = devScript._styleNum(style["y"], NaN);
            if (isNaN(gy))
                warn("y", qsTr("Bad y, using attribute value"));
            else
                snap.y = Math.round(gy);
        }
        if (style["w"]) {
            var gw = devScript._styleNum(style["w"], NaN);
            if (isNaN(gw) || gw <= 0)
                warn("w", qsTr("Bad w, using attribute value"));
            else
                snap.w = Math.max(1, Math.round(gw));
        }
        if (style["h"]) {
            var gh = devScript._styleNum(style["h"], NaN);
            if (isNaN(gh) || gh <= 0)
                warn("h", qsTr("Bad h, using attribute value"));
            else
                snap.h = Math.max(1, Math.round(gh));
        }
        if (style["rotation"]) {
            var gr = Number(String(style["rotation"].value).replace(/deg$/, ""));
            if (isNaN(gr))
                warn("rotation", qsTr("Bad rotation, using 0"));
            else
                snap.rotation = gr;
        }
        if (style["opacity"]) {
            var op = Number(style["opacity"].value);
            if (isNaN(op))
                warn("opacity", qsTr("Bad opacity, using 1"));
            else
                snap.opacity = Math.min(1, Math.max(0, op));
        }
        if (style["radius"]) {
            var rad = devScript._styleNum(style["radius"], NaN);
            if (isNaN(rad) || rad < 0)
                warn("radius", qsTr("Bad radius, using 0"));
            else
                snap.radius = rad;
        }
        // Effects: single-entry stacks from one declaration; bad
        // values warn and leave the default (disabled / empty).
        if (style["layer-blur"]) {
            var lb = devScript._parseBlurVal(style["layer-blur"].value, 8, 1);
            if (lb.error)
                warn("layer-blur", qsTr("Bad layer-blur, expected e.g. 8px"));
            else
                snap.layerBlur = {
                    enabled: true,
                    radius: lb.radius,
                    opacity: lb.opacity
                };
        }
        if (style["background-blur"]) {
            var bb = devScript._parseBlurVal(style["background-blur"].value, 16, 0.7);
            if (bb.error)
                warn("background-blur", qsTr("Bad background-blur, expected e.g. 16px"));
            else
                snap.backgroundBlur = {
                    enabled: true,
                    radius: bb.radius,
                    opacity: bb.opacity
                };
        }
        if (style["grain"]) {
            var gr2 = devScript._parseGrainVal(style["grain"].value);
            if (gr2.error)
                warn("grain", qsTr("Bad grain, expected e.g. 0.5"));
            else
                snap.grain = {
                    enabled: true,
                    amount: gr2.amount,
                    size: gr2.size
                };
        }
        if (style["shadow"]) {
            var sh = devScript._parseShadowVal(style["shadow"].value);
            if (sh.error)
                warn("shadow", qsTr("Bad shadow, expected e.g. #80000000 0 4 8 0"));
            else
                snap.shadows = [
                    {
                        enabled: true,
                        inner: sh.inner,
                        color: sh.color,
                        x: sh.x,
                        y: sh.y,
                        blur: sh.blur,
                        spread: sh.spread
                    }
                ];
        }
        if (style["glow"]) {
            var gl = devScript._parseGlowVal(style["glow"].value);
            if (gl.error)
                warn("glow", qsTr("Bad glow, expected e.g. #cc00ffff 16 4"));
            else
                snap.glows = [
                    {
                        enabled: true,
                        inner: gl.inner,
                        color: gl.color,
                        blur: gl.blur,
                        spread: gl.spread
                    }
                ];
        }
        if (style["shader"]) {
            var sv = devScript._parseShaderVal(style["shader"].value);
            if (sv.error)
                warn("shader", qsTr("Bad shader, expected e.g. preset:plasma"));
            else if (sv.clear)
                snap.shaderId = "";
            else {
                snap.shaderId = sv.id;
                var smode = style["shader-mode"] ? String(style["shader-mode"].value).trim().toLowerCase() : "fill";
                snap.shaderMode = smode === "overlay" ? "overlay" : "fill";
                if (style["shader-mode"] && smode !== "overlay" && smode !== "fill")
                    warn("shader-mode", qsTr("Bad shader-mode, using fill"));
            }
        }
        // Typography (text leaves; box props below ride _makeShapeNode
        // defaults for other kinds).
        if (el.kind === "text") {
            snap.textContent = el.content;
            if (style["font-family"])
                snap.fontFamily = String(style["font-family"].value);
            if (style["font-weight"]) {
                var fw = String(style["font-weight"].value).trim().toLowerCase();
                if (fw === "bold")
                    snap.fontWeight = 700;
                else if (fw === "normal")
                    snap.fontWeight = 400;
                else {
                    var fwn = Number(fw);
                    if (isNaN(fwn))
                        warn("font-weight", qsTr("Bad font-weight, using 400"));
                    else
                        snap.fontWeight = Math.round(fwn);
                }
            }
            if (style["font-size"]) {
                var fs = devScript._styleNum(style["font-size"], NaN);
                if (isNaN(fs) || fs <= 0)
                    warn("font-size", qsTr("Bad font-size, using 16"));
                else
                    snap.fontSize = fs;
            }
            if (style["font-style"]) {
                var fi = String(style["font-style"].value).trim().toLowerCase();
                if (fi === "italic")
                    snap.fontItalic = true;
                else if (fi !== "normal")
                    warn("font-style", qsTr("Bad font-style, using normal"));
            }
            if (style["text-decoration"]) {
                var td = String(style["text-decoration"].value).trim().toLowerCase();
                if (td === "underline")
                    snap.fontUnderline = true;
                else if (td === "line-through")
                    snap.fontStrike = true;
                else if (td !== "none")
                    warn("text-decoration", qsTr("Bad text-decoration, using none"));
            }
            if (style["text-transform"]) {
                var tt = String(style["text-transform"].value).trim().toLowerCase();
                if (tt === "uppercase")
                    snap.fontCaps = "upper";
                else if (tt === "lowercase")
                    snap.fontCaps = "lower";
                else if (tt !== "none")
                    warn("text-transform", qsTr("Bad text-transform, using none"));
            }
            if (style["text-align"]) {
                var ta = String(style["text-align"].value).trim().toLowerCase();
                if (ta === "left" || ta === "center" || ta === "right")
                    snap.hAlign = ta;
                else
                    warn("text-align", qsTr("Bad text-align, using left"));
            }
        }
        if (el.name !== "")
            snap.name = el.name;
        // Media kinds go through their factories (blob-backed) and get
        // tagged afterwards; fills/strokes don't apply to footage.
        // Unknown blobs are hard errors (the run continues partial).
        if (el.kind === "image" || el.kind === "video") {
            var known = el.kind === "image" ? LibraryStore.hasImage(el.blob) : LibraryStore.hasVideo(el.blob);
            if (!known) {
                diags.push({
                    tab: elTab,
                    line: el.line ?? 0,
                    message: qsTr("Unknown %1 blob '%2'").arg(el.kind).arg(el.blob),
                    kind: "error"
                });
                return -1;
            }
            var mediaUid = -1;
            if (el.kind === "image")
                mediaUid = d.factory.addImage(el.blob ?? "", snap.x, snap.y, snap.w, snap.h);
            else
                mediaUid = d.factory.addVideo(el.blob ?? "", snap.x, snap.y, snap.w, snap.h, 0);
            if (mediaUid < 0) {
                diags.push({
                    tab: elTab,
                    line: el.line ?? 0,
                    message: qsTr("Could not create media node"),
                    kind: "warning"
                });
                return -1;
            }
            var mediaNode = d.findNode(mediaUid);
            if (mediaNode) {
                mediaNode.scriptId = devScript.ownedTag;
                if (el.name !== "")
                    mediaNode.name = el.name;
                mediaNode.rotation = snap.rotation;
                if (style["opacity"]) {
                    var mop = Number(style["opacity"].value);
                    if (!isNaN(mop))
                        mediaNode.opacity = Math.min(1, Math.max(0, mop));
                }
                if (style["radius"]) {
                    var mrad = devScript._styleNum(style["radius"], NaN);
                    if (!isNaN(mrad) && mrad >= 0)
                        mediaNode.radius = mrad;
                }
                // Effects ride the snap (same parse as shapes).
                if (snap.layerBlur !== undefined)
                    mediaNode.layerBlur = snap.layerBlur;
                if (snap.backgroundBlur !== undefined)
                    mediaNode.backgroundBlur = snap.backgroundBlur;
                if (snap.grain !== undefined)
                    mediaNode.grain = snap.grain;
                if (snap.shadows !== undefined)
                    mediaNode.shadows = snap.shadows;
                if (snap.glows !== undefined)
                    mediaNode.glows = snap.glows;
                if (snap.shaderId !== undefined) {
                    mediaNode.shaderId = snap.shaderId;
                    mediaNode.shaderMode = snap.shaderMode ?? "fill";
                }
            }
            return mediaUid;
        }
        // Pen paths go through addPen (bbox-derived box), then take
        // the script tag + style over the defaults.
        if (el.kind === "pen") {
            var penUid = d.factory.addPen(el.pathData ?? []);
            if (penUid < 0) {
                diags.push({
                    tab: elTab,
                    line: el.line ?? 0,
                    message: qsTr("Could not create pen node"),
                    kind: "warning"
                });
                return -1;
            }
            var penNode = d.findNode(penUid);
            if (penNode) {
                penNode.scriptId = devScript.ownedTag;
                if (el.name !== "")
                    penNode.name = el.name;
                // addPen derives x/y/w/h from the path bbox; an
                // explicit rotation attr still applies afterwards.
                if (snap.rotation)
                    penNode.rotation = snap.rotation;
                if (snap.fills && snap.fills.length > 0)
                    penNode.fills = snap.fills;
                if (strokes.length > 0)
                    penNode.strokes = strokes;
                if (snap.opacity !== undefined)
                    penNode.opacity = snap.opacity;
                if (snap.radius !== undefined)
                    penNode.radius = snap.radius;
                if (snap.layerBlur !== undefined)
                    penNode.layerBlur = snap.layerBlur;
                if (snap.backgroundBlur !== undefined)
                    penNode.backgroundBlur = snap.backgroundBlur;
                if (snap.grain !== undefined)
                    penNode.grain = snap.grain;
                if (snap.shadows !== undefined)
                    penNode.shadows = snap.shadows;
                if (snap.glows !== undefined)
                    penNode.glows = snap.glows;
                if (snap.shaderId !== undefined) {
                    penNode.shaderId = snap.shaderId;
                    penNode.shaderMode = snap.shaderMode ?? "fill";
                }
            }
            return penUid;
        }
        var n = d._makeShapeNode(el.kind, snap);
        var list = d._childrenOf(container).slice();
        list.unshift(n);
        d._setChildren(container, list);
        d.anchorUid = n.uid;
        d._refreshStructural();
        return n.uid;
    }

    // First top-first uid whose node name matches (groups included).
    function _findUidByName(d, name) {
        var walk = list => {
            for (var i = 0; i < list.length; i++) {
                var n = list[i];
                if (String(n.name ?? "") === name)
                    return n.uid;
                if (n.kind === "group") {
                    var hit = walk(n.children || []);
                    if (hit >= 0)
                        return hit;
                }
            }
            return -1;
        };
        return walk(d.rootChildren || []);
    }

    // Shared report finalizer: unmatched-rule notes, tab tagging for
    // creation-time notes, errors-first ordering.
    function _finishReport(d, diags, made, sheet) {
        for (var u = 0; u < sheet.rules.length; u++) {
            if (!sheet.rules[u].matched) {
                diags.push({
                    tab: "css",
                    line: sheet.rules[u].line,
                    message: qsTr("Selector matched nothing"),
                    kind: "warning"
                });
            }
        }
        for (var t = 0; t < diags.length; t++) {
            if (!diags[t].tab) {
                diags[t].tab = "css";
                diags[t].kind = diags[t].kind ?? "warning";
            }
        }
        // Errors first, then warnings; stable within each class.
        diags.sort((a, b) => {
            var ka = a.kind === "error" ? 0 : 1;
            var kb = b.kind === "error" ? 0 : 1;
            return ka - kb;
        });
        // The console renders one item per diagnostic: cap it so a
        // pathological run cannot OOM the panel's Repeater.
        if (diags.length > devScript.maxDiags) {
            var dropped = diags.length - devScript.maxDiags;
            diags = diags.slice(0, devScript.maxDiags);
            diags.push({
                tab: "css",
                line: 0,
                message: qsTr("… and %n more issue(s)", "", dropped),
                kind: "warning"
            });
        }
        var report = {
            ok: diags.every(e => e.kind !== "error"),
            diagnostics: diags,
            created: made
        };
        devScript.lastRun = report;
        return report;
    }

    // Parse HTML/CSS synchronously (cheap) into a plan the apply step
    // consumes. Diagnostics are decorated here; creation notes append
    // during apply.
    function _plan(d) {
        var parsed = devScript.parseHtml((d.script ?? {}).html);
        var sheet = devScript.parseCss((d.script ?? {}).css);
        var diags = [];
        for (var h = 0; h < parsed.errors.length; h++) {
            diags.push({
                tab: "html",
                line: parsed.errors[h].line,
                message: parsed.errors[h].message,
                kind: "error"
            });
        }
        for (var c = 0; c < sheet.diags.length; c++) {
            diags.push({
                tab: "css",
                line: sheet.diags[c].line,
                message: sheet.diags[c].message,
                kind: sheet.diags[c].kind
            });
        }
        // Bound the apply that follows: thousands of nodes in one
        // transaction would freeze then OOM the app. Truncated runs stay
        // partial (like any other error) and report what happened.
        if (parsed.elements.length > devScript.maxHtmlElements) {
            diags.push({
                tab: "html",
                line: 0,
                message: qsTr("Too many elements (max %1) — only the first %1 will run").arg(devScript.maxHtmlElements),
                kind: "error"
            });
            parsed.elements = devScript._trimHtmlTree(parsed.elements, devScript.maxHtmlElements);
        }
        if (sheet.rules.length > devScript.maxCssRules) {
            diags.push({
                tab: "css",
                line: 0,
                message: qsTr("Too many CSS rules (max %1) — only the first %1 will run").arg(devScript.maxCssRules),
                kind: "error"
            });
            sheet.rules = sheet.rules.slice(0, devScript.maxCssRules);
        }
        return {
            elements: parsed.elements,
            sheet: sheet,
            diags: diags
        };
    }

    // Top-first trim of an HTML tree to a node budget (groups count as
    // one plus their kept children). Keeps _plan bounded even when one
    // giant <g> holds more than the budget on its own.
    function _trimHtmlTree(nodes, budget) {
        var kept = [];
        var n = 0;
        var take = list => {
            var out = [];
            for (var i = 0; i < (list ?? []).length && n < budget; i++) {
                var el = list[i] || {};
                n++;
                if (el.kind === "group") {
                    var kids = take(el.children ?? []);
                    var copy = Object.assign({}, el, {
                        children: kids
                    });
                    out.push(copy);
                } else {
                    out.push(el);
                }
            }
            return out;
        };
        return take(nodes ?? []);
    }

    // Total node count of an HTML tree (groups included), short-circuit
    // past the combined budget so counting itself stays cheap.
    function _countHtmlNodes(nodes) {
        var n = 0;
        var walk = list => {
            for (var i = 0; i < (list ?? []).length; i++) {
                n++;
                if (n > devScript.maxTotalNodes)
                    return;
                var el = list[i] || {};
                if (el.kind === "group")
                    walk(el.children ?? []);
                if (n > devScript.maxTotalNodes)
                    return;
            }
        };
        walk(nodes);
        return n;
    }

    // Apply one HTML element (sync path). Inline presentation
    // attributes (el.attrStyle) lose to real CSS rules. Returns uid.
    function _applyHtmlElement(el, sheet, diags, made) {
        var cssStyle = devScript.cascadeFor(el, sheet.rules);
        var style = {};
        var base = el.attrStyle ?? {};
        for (var k in base)
            style[k] = base[k];
        for (var k2 in cssStyle)
            style[k2] = cssStyle[k2];
        var uid = devScript._createElement(el, style, diags);
        if (uid >= 0)
            made.push(uid);
        return uid;
    }

    // HTML timeline clip (not a node): validated in parseHtml, so a
    // missing blob is the only hard error left here.
    function _applyHtmlAudio(el, diags) {
        var d = devScript.doc;
        if (!LibraryStore.hasAudio(el.blob)) {
            diags.push({
                tab: "html",
                line: el.line ?? 0,
                message: qsTr("Unknown audio blob '%1'").arg(el.blob),
                kind: "error"
            });
            return;
        }
        var t0 = Math.max(0, Number(el.t0) || 0);
        var id = d.audio.addClip(el.blob, t0, Number(el.duration));
        if (id < 0) {
            diags.push({
                tab: "html",
                line: el.line ?? 0,
                message: qsTr("Audio '%1' fits nowhere (past composition end?)").arg(el.blob),
                kind: "warning"
            });
        }
    }

    // Recursive tree apply: groups collect their children as tops
    // first (same detach-then-group pattern as JS groups), then
    // reparent under one owned group node. Returns uids created for
    // this subtree (leaves + nested groups).
    function _applyHtmlTree(nodes, sheet, diags, made) {
        var d = devScript.doc;
        for (var i = 0; i < (nodes ?? []).length; i++) {
            var el = nodes[i] || {};
            if (el.kind === "group") {
                // Mark group-targeted rules matched (no visual style
                // on the container itself beyond opacity below).
                devScript.cascadeFor(el, sheet.rules);
                var before = made.length;
                devScript._applyHtmlTree(el.children ?? [], sheet, diags, made);
                var childUids = made.slice(before);
                if (childUids.length === 0) {
                    var empty = d._makeGroupNode(el.name !== "" ? el.name : "Group", [], {
                        scriptId: devScript.ownedTag
                    });
                    var list0 = d._childrenOf(d._activeContainerUid()).slice();
                    list0.unshift(empty);
                    d._setChildren(d._activeContainerUid(), list0);
                    d.anchorUid = empty.uid;
                    d._refreshStructural();
                    made.push(empty.uid);
                    continue;
                }
                var kids = [];
                var ok = true;
                for (var ci = 0; ci < childUids.length; ci++) {
                    var node = d.findNode(childUids[ci]);
                    if (!node) {
                        ok = false;
                        break;
                    }
                    kids.push(node);
                }
                if (!ok || kids.length === 0)
                    continue;
                for (var k = 0; k < kids.length; k++) {
                    var hit = d._find(kids[k].uid);
                    if (!hit)
                        continue;
                    var sibs = d._childrenOf(hit.parentUid).slice();
                    sibs.splice(hit.index, 1);
                    d._setChildren(hit.parentUid, sibs);
                    kids[k].selected = false;
                }
                var group = d._makeGroupNode(el.name !== "" ? el.name : "Group", kids, {
                    scriptId: devScript.ownedTag
                });
                // Group-level presentation attrs that exist: opacity.
                var gStyle = devScript.cascadeFor(el, sheet.rules);
                var gBase = el.attrStyle ?? {};
                var gMerged = {};
                for (var gk in gBase)
                    gMerged[gk] = gBase[gk];
                for (var gk2 in gStyle)
                    gMerged[gk2] = gStyle[gk2];
                if (gMerged["opacity"]) {
                    var gop = Number(gMerged["opacity"].value);
                    if (!isNaN(gop))
                        group.opacity = Math.min(1, Math.max(0, gop));
                }
                var container = d._activeContainerUid();
                var list = d._childrenOf(container).slice();
                list.unshift(group);
                d._setChildren(container, list);
                d.anchorUid = group.uid;
                d._refreshStructural();
                made.push(group.uid);
                continue;
            }
            if (el.kind === "audio") {
                devScript._applyHtmlAudio(el, diags);
                continue;
            }
            devScript._applyHtmlElement(el, sheet, diags, made);
        }
    }

    // Apply validated JS ops inside the caller's transaction. Creates
    // share the HTML element path (same ownership + reconcile); groups
    // reparent created tops; removes/sets mutate by handle; animates
    // resolve to uids and compile to native clips. JS keeps its own
    // style (the CSS sheet stays HTML-only); classes ride along for
    // forward-compat. Returns created uids.
    function _applyJsOps(d, ops, diags) {
        var made = [];
        // Defensive second line (the worker and _onJsFinished enforce
        // the same caps first): never apply unbounded op lists, even if
        // a future caller passes hand-built ops straight here.
        var capOps = (key, arr, max) => {
            var list = Array.isArray(arr) ? arr : [];
            if (list.length > max) {
                diags.push({
                    tab: "js",
                    line: 0,
                    message: qsTr("Too many %1 (max %2) — only the first %2 will run").arg(key).arg(max),
                    kind: "error"
                });
                return list.slice(0, max);
            }
            return list;
        };
        var creates = capOps("shapes", (ops ?? {}).creates, devScript.maxJsCreates);
        ops = Object.assign({}, ops, {
            groups: capOps("groups", (ops ?? {}).groups, devScript.maxJsGroups),
            animates: capOps("animations", (ops ?? {}).animates, devScript.maxJsAnimates),
            sets: capOps("set calls", (ops ?? {}).sets, devScript.maxJsSets),
            removes: capOps("remove calls", (ops ?? {}).removes, devScript.maxJsRemoves),
            finds: capOps("finds", (ops ?? {}).finds, devScript.maxJsFinds),
            picks: capOps("file picks", (ops ?? {}).picks, devScript.maxJsPicks),
            audio: capOps("audio clips", (ops ?? {}).audio, devScript.maxJsAudio)
        });
        var jsMade = [];
        for (var i = 0; i < creates.length; i++) {
            var c = creates[i] || {};
            var el = {
                tab: "js",
                kind: String(c.kind ?? "rectangle"),
                x: Number(c.x) || 0,
                y: Number(c.y) || 0,
                w: Math.max(1, Math.round(Number(c.w) || 100)),
                h: Math.max(1, Math.round(Number(c.h) || 100)),
                rotation: Number(c.rotation ?? c.rotate ?? 0) || 0,
                fill: String(c.fill ?? "#d9d9d9"),
                name: String(c.name ?? ""),
                classes: Array.isArray(c.classes) ? c.classes.map(s => String(s)) : String(c.classes ?? c.class ?? c.className ?? "").split(/\s+/).filter(s => s !== ""),
                content: String(c.content ?? ""),
                blob: String(c.blob ?? "")
            };
            // JS style parity with CSS: camelCase opts ride the same
            // cascade entry shape ({value, line}) so _createElement
            // validates + warns identically. Absent stays absent.
            var jsStyle = {};
            var putStyle = (prop, v) => {
                if (v !== undefined && v !== null)
                    jsStyle[prop] = {
                        value: v,
                        line: 0
                    };
            };
            if (c.opacity !== undefined)
                putStyle("opacity", c.opacity);
            if (c.radius !== undefined)
                putStyle("radius", c.radius);
            if (c.fillOpacity !== undefined)
                putStyle("fill-opacity", c.fillOpacity);
            if (c.stroke !== undefined)
                putStyle("stroke", c.stroke);
            if (c.strokeWidth !== undefined)
                putStyle("stroke-width", c.strokeWidth);
            if (c.strokePosition !== undefined)
                putStyle("stroke-position", c.strokePosition);
            if (c.strokeOpacity !== undefined)
                putStyle("stroke-opacity", c.strokeOpacity);
            if (c.layerBlur !== undefined)
                putStyle("layer-blur", c.layerBlur);
            if (c.backgroundBlur !== undefined)
                putStyle("background-blur", c.backgroundBlur);
            if (c.grain !== undefined)
                putStyle("grain", c.grain);
            if (c.shadow !== undefined)
                putStyle("shadow", c.shadow);
            if (c.glow !== undefined)
                putStyle("glow", c.glow);
            if (c.shader !== undefined)
                putStyle("shader", c.shader);
            if (c.shaderMode !== undefined)
                putStyle("shader-mode", c.shaderMode);
            if (c.fontFamily !== undefined)
                putStyle("font-family", c.fontFamily);
            if (c.fontWeight !== undefined)
                putStyle("font-weight", c.fontWeight);
            if (c.fontSize !== undefined)
                putStyle("font-size", c.fontSize);
            if (c.fontStyle !== undefined)
                putStyle("font-style", c.fontStyle);
            if (c.textDecoration !== undefined)
                putStyle("text-decoration", c.textDecoration);
            if (c.textTransform !== undefined)
                putStyle("text-transform", c.textTransform);
            if (c.textAlign !== undefined)
                putStyle("text-align", c.textAlign);
            if (el.kind === "image" || el.kind === "video") {
                if (el.blob === "") {
                    diags.push({
                        tab: "js",
                        line: 0,
                        message: qsTr("Media node is missing its blob name"),
                        kind: "warning"
                    });
                    jsMade.push(-1);
                    continue;
                }
            } else if (["rectangle", "ellipse", "triangle", "star", "text", "pen"].indexOf(el.kind) < 0) {
                diags.push({
                    tab: "js",
                    line: 0,
                    message: qsTr("Unknown shape kind '%1'").arg(el.kind),
                    kind: "warning"
                });
                jsMade.push(-1);
                continue;
            }
            if (el.kind === "pen") {
                // Bridge normalizes points to [{x,y}]; build the
                // single-subpath pathData _createElement expects.
                var rawPts = Array.isArray(c.points) ? c.points : [];
                if (rawPts.length > devScript.maxJsPenPoints) {
                    diags.push({
                        tab: "js",
                        line: 0,
                        message: qsTr("Too many pen points (max %1)").arg(devScript.maxJsPenPoints),
                        kind: "warning"
                    });
                    jsMade.push(-1);
                    continue;
                }
                var penPts = [];
                for (var qi = 0; qi < rawPts.length; qi++) {
                    var qp = rawPts[qi] || {};
                    penPts.push({
                        x: Number(qp.x) || 0,
                        y: Number(qp.y) || 0,
                        smooth: false,
                        inX: Number(qp.x) || 0,
                        inY: Number(qp.y) || 0,
                        outX: Number(qp.x) || 0,
                        outY: Number(qp.y) || 0
                    });
                }
                if (penPts.length < 2) {
                    diags.push({
                        tab: "js",
                        line: 0,
                        message: qsTr("Pen needs at least 2 points"),
                        kind: "warning"
                    });
                    jsMade.push(-1);
                    continue;
                }
                el.pathData = [
                    {
                        closed: c.closed === true,
                        pts: penPts
                    }
                ];
            }
            var uid = devScript._createElement(el, jsStyle, diags);
            jsMade.push(uid);
            if (uid >= 0)
                made.push(uid);
        }
        // Groups reparent created tops under one owned group.
        var groups = (ops ?? {}).groups ?? [];
        for (var gi = 0; gi < groups.length; gi++) {
            var gop = groups[gi] || {};
            var members = gop.members ?? [];
            var kids = [];
            var ok = true;
            for (var mi = 0; mi < members.length; mi++) {
                var idx = members[mi];
                if (typeof idx !== "number" || idx < 0 || idx >= jsMade.length || jsMade[idx] < 0) {
                    diags.push({
                        tab: "js",
                        line: 0,
                        message: qsTr("Group references an unknown shape handle"),
                        kind: "warning"
                    });
                    ok = false;
                    break;
                }
                var node = d.findNode(jsMade[idx]);
                if (!node) {
                    ok = false;
                    break;
                }
                kids.push(node);
            }
            if (!ok || kids.length === 0)
                continue;
            for (var k = 0; k < kids.length; k++) {
                var hit = d._find(kids[k].uid);
                if (!hit)
                    continue;
                var sibs = d._childrenOf(hit.parentUid).slice();
                sibs.splice(hit.index, 1);
                d._setChildren(hit.parentUid, sibs);
                kids[k].selected = false;
            }
            var gname = String(gop.name ?? "Group");
            var group = d._makeGroupNode(gname === "" ? "Group" : gname, kids, {
                scriptId: devScript.ownedTag
            });
            var container = d._activeContainerUid();
            var list = d._childrenOf(container).slice();
            list.unshift(group);
            d._setChildren(container, list);
            d.anchorUid = group.uid;
            d._refreshStructural();
            made.push(group.uid);
        }
        // Removals run before sets/animates so later ops warn
        // instead of orphaning clips on deleted nodes.
        var finds = (ops ?? {}).finds ?? [];
        var resolveTarget = th => {
            if (typeof th === "number" && th >= 0 && th < devScript.jsFindBit && th < jsMade.length)
                return jsMade[th];
            if (typeof th === "number" && th >= devScript.jsFindBit && th - devScript.jsFindBit < finds.length)
                return devScript._findUidByName(d, String(finds[th - devScript.jsFindBit] ?? ""));
            return -1;
        };
        var removes = (ops ?? {}).removes ?? [];
        var removedUids = {};
        for (var ri = 0; ri < removes.length; ri++) {
            var rTarget = resolveTarget(removes[ri]);
            var rNode = rTarget >= 0 ? d.findNode(rTarget) : null;
            if (!rNode) {
                diags.push({
                    tab: "js",
                    line: 0,
                    message: qsTr("Remove target not found"),
                    kind: "warning"
                });
                continue;
            }
            var rHit = d._find(rTarget);
            if (rHit) {
                var rSibs = d._childrenOf(rHit.parentUid).slice();
                rSibs.splice(rHit.index, 1);
                d._setChildren(rHit.parentUid, rSibs);
            }
            removedUids[rTarget] = true;
            // Invalidate create handles pointing at this uid so
            // later groups/sets/animates warn instead of reusing it.
            for (var ji = 0; ji < jsMade.length; ji++) {
                if (jsMade[ji] === rTarget)
                    jsMade[ji] = -1;
            }
            devScript._burn(rNode);
            d._refreshStructural();
        }
        // Scalar sets (fill color, opacity, geometry, name). Stacks
        // stay structural: edit them by hand or recreate the node.
        var sets = (ops ?? {}).sets ?? [];
        for (var si = 0; si < sets.length; si++) {
            var sop = sets[si] || {};
            var sTarget = resolveTarget(sop.target);
            var sNode = sTarget >= 0 && !removedUids[sTarget] ? d.findNode(sTarget) : null;
            if (!sNode) {
                diags.push({
                    tab: "js",
                    line: 0,
                    message: qsTr("Set target not found"),
                    kind: "warning"
                });
                continue;
            }
            var props = sop.props ?? {};
            if (props.name !== undefined)
                sNode.name = String(props.name);
            if (props.x !== undefined) {
                var sx = Number(props.x);
                if (!isNaN(sx))
                    sNode.x = Math.round(sx);
            }
            if (props.y !== undefined) {
                var sy = Number(props.y);
                if (!isNaN(sy))
                    sNode.y = Math.round(sy);
            }
            if (props.w !== undefined) {
                var sw = Number(props.w);
                if (!isNaN(sw) && sw > 0)
                    sNode.w = Math.max(1, Math.round(sw));
            }
            if (props.h !== undefined) {
                var sh2 = Number(props.h);
                if (!isNaN(sh2) && sh2 > 0)
                    sNode.h = Math.max(1, Math.round(sh2));
            }
            if (props.rotation !== undefined || props.rotate !== undefined) {
                var sr = Number(props.rotation ?? props.rotate);
                if (!isNaN(sr))
                    sNode.rotation = sr;
            }
            if (props.opacity !== undefined) {
                var so2 = Number(props.opacity);
                if (!isNaN(so2))
                    sNode.opacity = Math.min(1, Math.max(0, so2));
            }
            if (props.radius !== undefined && sNode.kind === "shape") {
                var sr2 = Number(props.radius);
                if (!isNaN(sr2) && sr2 >= 0)
                    sNode.radius = sr2;
            }
            if (props.fill !== undefined && sNode.kind === "shape") {
                var fc = String(props.fill);
                if (fc !== "" && sNode.fills && sNode.fills.length > 0) {
                    var fl = sNode.fills.slice();
                    fl[0] = Object.assign({}, fl[0], {
                        color: fc
                    });
                    sNode.fills = fl;
                }
            }
            if (props.fillOpacity !== undefined && sNode.kind === "shape" && sNode.fills && sNode.fills.length > 0) {
                var fo2 = Number(props.fillOpacity);
                if (!isNaN(fo2)) {
                    var fl2 = sNode.fills.slice();
                    fl2[0] = Object.assign({}, fl2[0], {
                        opacity: Math.min(1, Math.max(0, fo2))
                    });
                    sNode.fills = fl2;
                }
            }
        }
        // Animations compile to native clips (single entry: the outer
        // transaction silences the helpers' own checkpoints). Custom
        // from-to presets (customMove/Scale/Rotate/Opacity/...) work
        // here via aop.options passthrough, same as the gallery.
        var validPresets = (d.anim && d.anim.presets) ? d.anim.presets.presetIds() : [];
        var animates = (ops ?? {}).animates ?? [];
        for (var ai = 0; ai < animates.length; ai++) {
            var aop = animates[ai] || {};
            var target = resolveTarget(aop.target);
            if (target === undefined || target < 0 || !d.findNode(target)) {
                diags.push({
                    tab: "js",
                    line: 0,
                    message: qsTr("Animate target not found"),
                    kind: "warning"
                });
                continue;
            }
            var preset = String(aop.preset ?? "");
            if (validPresets.indexOf(preset) < 0) {
                diags.push({
                    tab: "js",
                    line: 0,
                    message: qsTr("Unknown preset '%1'").arg(preset),
                    kind: "warning"
                });
                continue;
            }
            var t0 = Number(aop.t0);
            if (isNaN(t0) || t0 < 0)
                t0 = d.anim ? d.anim.currentTime : 0;
            var dur = Number(aop.duration);
            if (isNaN(dur) || dur <= 0)
                dur = 1.0;
            var mode = String(aop.mode ?? "in");
            if (mode === "")
                mode = "in";
            var easing = aop.easing;
            if (!easing || typeof easing !== "object" || Object.keys(easing).length === 0)
                easing = null;
            var made2 = d.applyPreset(preset, [target], t0, dur, mode, aop.options ?? {}, easing, 0);
            if (made2.length === 0) {
                diags.push({
                    tab: "js",
                    line: 0,
                    message: qsTr("Preset '%1' applied no clips").arg(preset),
                    kind: "warning"
                });
            }
        }
        var durOp = Number((ops ?? {}).duration);
        if (!isNaN(durOp) && durOp > 0 && d.setAnimDuration)
            d.setAnimDuration(durOp);
        return made;
    }

    // Compile + reconcile in one undo entry. HTML/CSS-only runs apply
    // synchronously; a non-empty JS tab evaluates async in the
    // sandboxed worker first, then applies everything together. File
    // picks (if any) pause between phases for panel-driven choosing.
    function run() {
        var d = devScript.doc;
        if (!d)
            return devScript.lastRun;
        // A fresh Run supersedes any in-flight worker or pick flow.
        if (devScript.jsRunning && devScript.pendingRunId >= 0)
            ScriptRunner.abort(devScript.pendingRunId);
        devScript.pending = null;
        devScript.pendingRunId = -1;
        devScript.jsRunning = false;
        devScript._clearPickFlow();
        devScript.pendingPick = null;
        // Stale audio-probe ticks must never apply an old plan.
        if (devScript.probeTimer)
            devScript.probeTimer.stop();
        devScript.probeCont = null;
        devScript.probeQueue = [];
        // Fail fast on oversize input: parsing/applying megabytes would
        // freeze then OOM the app, and spawning a helper is pointless.
        var htmlSrc = String((d.script ?? {}).html ?? "");
        var cssSrc = String((d.script ?? {}).css ?? "");
        var jsSrc = String((d.script ?? {}).js ?? "");
        if (htmlSrc.length > devScript.maxSourceChars || cssSrc.length > devScript.maxSourceChars || jsSrc.length > devScript.maxSourceChars) {
            var sizeDiags = [];
            if (htmlSrc.length > devScript.maxSourceChars) {
                sizeDiags.push({
                    tab: "html",
                    line: 0,
                    message: qsTr("HTML too large (max %1 characters)").arg(devScript.maxSourceChars),
                    kind: "error"
                });
            }
            if (cssSrc.length > devScript.maxSourceChars) {
                sizeDiags.push({
                    tab: "css",
                    line: 0,
                    message: qsTr("CSS too large (max %1 characters)").arg(devScript.maxSourceChars),
                    kind: "error"
                });
            }
            if (jsSrc.length > devScript.maxSourceChars) {
                sizeDiags.push({
                    tab: "js",
                    line: 0,
                    message: qsTr("Script too large (max %1 characters)").arg(devScript.maxSourceChars),
                    kind: "error"
                });
            }
            return devScript._finishReport(d, sizeDiags, [], {
                rules: []
            });
        }
        var plan = devScript._plan(d);
        var js = String((d.script ?? {}).js ?? "").trim();
        if (js === "") {
            return devScript._applyPhase(d, plan.elements, plan.sheet, plan.diags, null);
        }
        devScript.pending = {
            doc: d,
            elements: plan.elements,
            sheet: plan.sheet,
            diags: plan.diags
        };
        devScript.jsRunning = true;
        devScript.pendingRunId = ScriptRunner.run((d.script ?? {}).js, {});
        return {
            ok: true,
            diagnostics: [],
            created: [],
            running: true
        };
    }

    function _clearPickFlow() {
        devScript.jsPickFlow = false;
        devScript.pickDefs = [];
        devScript.pickBlobs = {};
        devScript.replaying = false;
    }

    // Shared transaction body for every path (sync HTML/CSS, async JS,
    // replay): replace owned nodes, create HTML + JS output, compile
    // audio lane clips. One undo entry; helpers' own checkpoints stay
    // silent inside the transaction.
    function _commitApply(d, elements, sheet, diags, jsOps) {
        // Combined HTML+JS budget: either side is capped alone, but both
        // at once could still double it past what one transaction holds.
        if (jsOps) {
            var jsCount = ((jsOps.creates ?? []).length) + ((jsOps.groups ?? []).length);
            if (devScript._countHtmlNodes(elements) + jsCount > devScript.maxTotalNodes) {
                diags.push({
                    tab: "js",
                    line: 0,
                    message: qsTr("Too many nodes (max %1) — JS output skipped").arg(devScript.maxTotalNodes),
                    kind: "error"
                });
                jsOps = null;
            }
        }
        var made = [];
        d.clearSelection();
        d.beginTransaction();
        devScript._deleteOwned();
        devScript._applyHtmlTree(elements, sheet, diags, made);
        if (jsOps) {
            var jsMade = devScript._applyJsOps(d, jsOps, diags);
            for (var j = 0; j < jsMade.length; j++)
                made.push(jsMade[j]);
            devScript._applyAudioOps(d, jsOps, diags);
        }
        if (made.length > 0)
            d.anchorUid = made[0];
        d.endTransaction();
        return devScript._finishReport(d, diags, made, sheet);
    }

    // Entry gate: audio ops without durations probe first (async),
    // everything else commits immediately.
    function _applyPhase(d, elements, sheet, diags, jsOps) {
        var queue = [];
        if (jsOps) {
            var al = jsOps.audio ?? [];
            for (var k = 0; k < al.length; k++) {
                var a = al[k] || {};
                var blob = String(a.blob ?? "");
                if (blob === "" || !LibraryStore.hasAudio(blob)) {
                    diags.push({
                        tab: "js",
                        line: 0,
                        message: qsTr("Unknown audio blob '%1'").arg(blob),
                        kind: "error"
                    });
                    a.skip = true;
                } else if (!(Number(a.duration) > 0)) {
                    queue.push(a);
                }
            }
        }
        if (queue.length === 0 || !devScript.probePlayer || !devScript.probeTimer)
            return devScript._commitApply(d, elements, sheet, diags, jsOps);
        devScript.probeCont = {
            d: d,
            elements: elements,
            sheet: sheet,
            diags: diags,
            jsOps: jsOps
        };
        devScript.probeQueue = queue;
        devScript.probeTries = 0;
        var first = queue[0];
        devScript.probePlayer.source = LibraryStore.audioUrl(String(first.blob));
        devScript.probeTimer.start();
        return devScript.lastRun;
    }

    function _onProbeTick() {
        if (!devScript.probeCont || devScript.probeQueue.length === 0) {
            if (devScript.probeTimer)
                devScript.probeTimer.stop();
            return;
        }
        var op = devScript.probeQueue[0];
        var dur = 0;
        try {
            dur = Number(devScript.probePlayer.duration) / 1000;
        } catch (e) {
            dur = 0;
        }
        if (dur > 0) {
            op.duration = dur;
            devScript.probeQueue.shift();
            devScript.probeTries = 0;
            devScript._probeNext();
            return;
        }
        devScript.probeTries++;
        if (devScript.probeTries > 50) {
            var cont = devScript.probeCont;
            cont.diags.push({
                tab: "js",
                line: 0,
                message: qsTr("Could not read audio file '%1'").arg(String(op.blob ?? "")),
                kind: "error"
            });
            op.skip = true;
            devScript.probeQueue.shift();
            devScript.probeTries = 0;
            devScript._probeNext();
        }
    }

    function _probeNext() {
        var cont = devScript.probeCont;
        if (!cont || devScript.probeQueue.length === 0) {
            if (devScript.probeTimer)
                devScript.probeTimer.stop();
            if (!cont)
                return;
            devScript.probeCont = null;
            // Tab closed mid-probe: drop the stale plan like the
            // worker path does.
            if (!cont.d || cont.d.uid === undefined)
                return;
            devScript._commitApply(cont.d, cont.elements, cont.sheet, cont.diags, cont.jsOps);
            return;
        }
        var next = devScript.probeQueue[0];
        devScript.probePlayer.source = LibraryStore.audioUrl(String(next.blob));
    }

    // Timeline lane clips for JS audio ops (durations probed above).
    // Skipped/failed ops never reach the lane.
    function _applyAudioOps(d, ops, diags) {
        var al = (ops ?? {}).audio ?? [];
        for (var k = 0; k < al.length; k++) {
            var a = al[k] || {};
            if (a.skip)
                continue;
            var blob = String(a.blob ?? "");
            if (blob === "" || !LibraryStore.hasAudio(blob)) {
                diags.push({
                    tab: "js",
                    line: 0,
                    message: qsTr("Unknown audio blob '%1'").arg(blob),
                    kind: "error"
                });
                continue;
            }
            var dur = Number(a.duration);
            if (!(dur > 0)) {
                diags.push({
                    tab: "js",
                    line: 0,
                    message: qsTr("Audio '%1' has no probed duration").arg(blob),
                    kind: "error"
                });
                continue;
            }
            var t0 = Math.max(0, Number(a.t0) || 0);
            var id = d.audio.addClip(blob, t0, dur);
            if (id < 0) {
                diags.push({
                    tab: "js",
                    line: 0,
                    message: qsTr("Audio '%1' fits nowhere (past composition end?)").arg(blob),
                    kind: "warning"
                });
            }
        }
    }

    // Worker resolution (main thread). Unresolved file picks open the
    // panel pick flow (no scene mutation yet); otherwise the waiting
    // plan applies, with audio durations probed first when needed.
    // Stale run ids fall away.
    function _onJsFinished(runId, result) {
        if (runId !== devScript.pendingRunId || !devScript.pending)
            return;
        var pend = devScript.pending;
        devScript.pending = null;
        devScript.pendingRunId = -1;
        devScript.jsRunning = false;
        var wasReplay = devScript.replaying;
        devScript.replaying = false;
        var d = pend.doc;
        // Tab closed mid-run: the design document is gone, drop it.
        if (!d || d.uid === undefined) {
            devScript._clearPickFlow();
            return;
        }
        var r = result ?? {};
        if (r.aborted === true) {
            devScript._clearPickFlow();
            pend.diags.push({
                tab: "js",
                line: 0,
                message: qsTr("Script stopped"),
                kind: "error"
            });
            return devScript._applyPhase(d, pend.elements, pend.sheet, pend.diags, null);
        }
        if (r.ok !== true) {
            devScript._clearPickFlow();
            pend.diags.push({
                tab: "js",
                line: Math.max(1, Math.round(Number(r.line) || 1)),
                message: String(r.error ?? qsTr("Script failed")),
                kind: "error"
            });
            return devScript._applyPhase(d, pend.elements, pend.sheet, pend.diags, null);
        }
        var ops = r.ops ?? {};
        // The worker caps its own output, but never trust IPC sizes on
        // the way in: drop oversize JS output (HTML still applies) rather
        // than opening a giant transaction.
        var opBudget = [["creates", devScript.maxJsCreates, qsTr("shapes")], ["groups", devScript.maxJsGroups, qsTr("groups")], ["animates", devScript.maxJsAnimates, qsTr("animations")], ["sets", devScript.maxJsSets, qsTr("set calls")], ["removes", devScript.maxJsRemoves, qsTr("remove calls")], ["finds", devScript.maxJsFinds, qsTr("finds")], ["picks", devScript.maxJsPicks, qsTr("file picks")], ["audio", devScript.maxJsAudio, qsTr("audio clips")]];
        for (var bi = 0; bi < opBudget.length; bi++) {
            var key = opBudget[bi][0];
            var max = opBudget[bi][1];
            if (((ops[key] ?? []).length) > max) {
                pend.diags.push({
                    tab: "js",
                    line: 0,
                    message: qsTr("Too many %1 (max %2) — HTML applied without JS").arg(opBudget[bi][2]).arg(max),
                    kind: "error"
                });
                return devScript._applyPhase(d, pend.elements, pend.sheet, pend.diags, null);
            }
        }
        var picks = ops.picks ?? [];
        var unresolved = [];
        for (var p = 0; p < picks.length; p++) {
            if (!picks[p].resolved)
                unresolved.push({
                    kind: String(picks[p].kind ?? "image"),
                    index: p
                });
        }
        if (unresolved.length > 0 && !wasReplay) {
            // Phase 1 done: hold the plan, ask for files.
            devScript.pendingPick = {
                doc: d,
                elements: pend.elements,
                sheet: pend.sheet,
                diags: pend.diags
            };
            devScript.pickDefs = unresolved;
            devScript.pickBlobs = {};
            devScript.jsPickFlow = true;
            devScript.lastRun = {
                ok: true,
                diagnostics: [],
                created: [],
                picking: true
            };
            return devScript.lastRun;
        }
        if (unresolved.length > 0 && wasReplay) {
            // Script changed mid-flow: restart choosing from scratch.
            devScript.pendingPick = {
                doc: d,
                elements: pend.elements,
                sheet: pend.sheet,
                diags: pend.diags
            };
            devScript.pickDefs = unresolved;
            devScript.pickBlobs = {};
            devScript.jsPickFlow = true;
            pend.diags.push({
                tab: "js",
                line: 0,
                message: qsTr("Script changed while picking — choose files again"),
                kind: "warning"
            });
            devScript.lastRun = {
                ok: true,
                diagnostics: [],
                created: [],
                picking: true
            };
            return devScript.lastRun;
        }
        devScript._clearPickFlow();
        return devScript._applyPhase(d, pend.elements, pend.sheet, pend.diags, ops);
    }

    // Panel pick flow: record one chosen blob; when all resolve,
    // replay with results and apply.
    function resolvePick(index, blob) {
        if (!devScript.jsPickFlow)
            return;
        devScript.pickBlobs[index] = String(blob ?? "");
        var pendingBlobs = devScript.pickBlobs;
        for (var i = 0; i < devScript.pickDefs.length; i++) {
            if (!pendingBlobs[devScript.pickDefs[i].index])
                return;
        }
        devScript._phase2();
    }

    function cancelPicks() {
        // No scene mutation happened yet in the pick flow: dropping
        // state is a clean abort with no undo entry.
        if (devScript.jsRunning && devScript.pendingRunId >= 0)
            ScriptRunner.abort(devScript.pendingRunId);
        devScript.pending = null;
        devScript.pendingRunId = -1;
        devScript.jsRunning = false;
        devScript._clearPickFlow();
        devScript.pendingPick = null;
        if (devScript.probeTimer)
            devScript.probeTimer.stop();
        devScript.probeCont = null;
        devScript.probeQueue = [];
    }

    function _phase2() {
        var pick = devScript.pendingPick;
        if (!pick || !pick.doc)
            return;
        var js = String((pick.doc.script ?? {}).js ?? "");
        // The script may have grown while picking: re-check before the
        // replay run instead of staging megabytes for nothing.
        if (js.length > devScript.maxSourceChars) {
            devScript._clearPickFlow();
            devScript.pendingPick = null;
            devScript.jsRunning = false;
            devScript.replaying = false;
            devScript.pending = null;
            pick.diags.push({
                tab: "js",
                line: 0,
                message: qsTr("Script too large (max %1 characters)").arg(devScript.maxSourceChars),
                kind: "error"
            });
            return devScript._applyPhase(pick.doc, pick.elements, pick.sheet, pick.diags, null);
        }
        devScript.jsPickFlow = false;
        devScript.jsRunning = true;
        devScript.replaying = true;
        devScript.pending = {
            doc: pick.doc,
            elements: pick.elements,
            sheet: pick.sheet,
            diags: pick.diags
        };
        devScript.pendingPick = null;
        devScript.pendingRunId = ScriptRunner.run(js, devScript.pickBlobs);
    }

    // Abort a running worker (timeout popup). Resolution arrives via
    // _onJsFinished as an aborted result.
    function abortJs() {
        if (devScript.jsRunning && devScript.pendingRunId >= 0)
            ScriptRunner.abort(devScript.pendingRunId);
    }
}
