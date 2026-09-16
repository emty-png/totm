import QtQuick

// Starter templates: one-click designs for logo stings, product hero
// loops, lower thirds and onboarding carousels. Builders use only the
// public Document API (factory + applyPreset with the pop/loop easings),
// so template scenes stay valid by construction; each build runs inside
// one transaction, so a template lands as a single undo entry.
QtObject {
    id: library

    function templates() {
        return [
            {
                id: "logoSting",
                name: qsTr("Logo sting"),
                blurb: qsTr("3s dark reveal with a looping pulse")
            },
            {
                id: "heroLoop",
                name: qsTr("Hero loop"),
                blurb: qsTr("4s app card cascade with CTA pulse")
            },
            {
                id: "lowerThird",
                name: qsTr("Lower third"),
                blurb: qsTr("4s name bar with in/out animation")
            },
            {
                id: "onboarding",
                name: qsTr("Onboarding"),
                blurb: qsTr("4s three-card picker cascade")
            }
        ];
    }

    function templateName(templateId) {
        var all = library.templates();
        for (var i = 0; i < all.length; i++) {
            if (all[i].id === templateId)
                return all[i].name;
        }
        return "";
    }

    function build(doc, templateId) {
        if (!doc)
            return false;
        if (templateId === "logoSting")
            return library.buildLogoSting(doc);
        if (templateId === "heroLoop")
            return library.buildHeroLoop(doc);
        if (templateId === "lowerThird")
            return library.buildLowerThird(doc);
        if (templateId === "onboarding")
            return library.buildOnboarding(doc);
        return false;
    }

    // Dark scene, overshoot pop on the dot, typewriter wordmark, and a
    // ping-pong opacity pulse that loops till the composition ends.
    function buildLogoSting(doc) {
        doc.beginTransaction();
        doc.sceneColor = "#101010";
        doc.setAnimDuration(3.0);
        var dot = doc.addShape("ellipse", 860, 360, 200, 200);
        var word = doc.addText(660, 610, 600, 140, false);
        var n = doc.findNode(dot);
        if (n) {
            n.name = "Logo dot";
            n.fill = "#0d99ff";
        }
        var w = doc.findNode(word);
        if (w) {
            w.name = "Wordmark";
            w.textContent = "totm";
            w.fontSize = 110;
            w.fontWeight = 600;
            w.fill = "#f6f6f6";
            w.hAlign = "center";
        }
        doc.applyPreset("customScale", [dot], 0, 0.6, "in", {
            from: 0,
            to: 1
        }, {
            id: "backOut"
        }, "none", 0);
        doc.applyPreset("type", [word], 0.35, 0.9, "in", {
            unit: "letters",
            cps: 12,
            cursor: false
        }, {
            id: "linear"
        }, "none", 0);
        doc.applyPreset("customOpacity", [dot], 1.4, 0.8, "in", {
            from: 1,
            to: 0.55
        }, {
            id: "easeInOut"
        }, "pingpong", 0);
        doc.endTransaction();
        return true;
    }

    // Light scene, card + copy rising in one staggered cascade, CTA pill
    // breathing on a loop for that live product feel.
    function buildHeroLoop(doc) {
        doc.beginTransaction();
        doc.sceneColor = "#ffffff";
        doc.setAnimDuration(4.0);
        var card = doc.addShape("rectangle", 650, 220, 620, 460);
        var headline = doc.addText(710, 280, 500, 110, false);
        var sub = doc.addText(710, 400, 500, 60, false);
        var cta = doc.addShape("rectangle", 710, 520, 250, 76);
        var label = doc.addText(710, 520, 250, 76, false);
        var c = doc.findNode(card);
        if (c) {
            c.name = "Card";
            c.fill = "#f2f2f2";
            c.radius = 28;
        }
        var h = doc.findNode(headline);
        if (h) {
            h.name = "Headline";
            h.textContent = "Ship it";
            h.fontSize = 76;
            h.fontWeight = 600;
            h.fill = "#0f0f0f";
        }
        var s = doc.findNode(sub);
        if (s) {
            s.name = "Subhead";
            s.textContent = "Motion in minutes";
            s.fontSize = 32;
            s.fill = "#555555";
        }
        var b = doc.findNode(cta);
        if (b) {
            b.name = "CTA";
            b.fill = "#0d99ff";
            b.radius = 38;
        }
        var l = doc.findNode(label);
        if (l) {
            l.name = "CTA label";
            l.textContent = "Get started";
            l.fontSize = 28;
            l.fill = "#ffffff";
            l.hAlign = "center";
            l.vAlign = "middle";
        }
        doc.applyPreset("slide", [card, headline, sub, cta, label], 0.2, 0.7, "in", {
            direction: "up",
            distance: 90,
            fade: true
        }, {
            id: "easeOut"
        }, "none", 0.12);
        doc.applyPreset("customOpacity", [cta], 1.6, 0.7, "in", {
            from: 1,
            to: 0.7
        }, {
            id: "easeInOut"
        }, "pingpong", 0);
        doc.endTransaction();
        return true;
    }

    // Name bar that slides in with its stripe and copy, holds, then
    // fades out together before the composition ends.
    function buildLowerThird(doc) {
        doc.beginTransaction();
        doc.sceneColor = "#ffffff";
        doc.setAnimDuration(4.0);
        var bar = doc.addShape("rectangle", 120, 800, 560, 120);
        var stripe = doc.addShape("rectangle", 120, 800, 12, 120);
        var name = doc.addText(160, 816, 480, 62, false);
        var role = doc.addText(160, 878, 480, 44, false);
        var r = doc.findNode(bar);
        if (r) {
            r.name = "Bar";
            r.fill = "#101010";
            r.radius = 16;
        }
        var t = doc.findNode(stripe);
        if (t) {
            t.name = "Stripe";
            t.fill = "#0d99ff";
        }
        var m = doc.findNode(name);
        if (m) {
            m.name = "Name";
            m.textContent = "Jane Doe";
            m.fontSize = 44;
            m.fontWeight = 600;
            m.fill = "#f6f6f6";
        }
        var o = doc.findNode(role);
        if (o) {
            o.name = "Role";
            o.textContent = "Motion designer";
            o.fontSize = 28;
            o.fill = "#9a9a9a";
        }
        doc.applyPreset("slide", [bar, stripe, name, role], 0.2, 0.6, "in", {
            direction: "left",
            distance: 260,
            fade: true
        }, {
            id: "easeOut"
        }, "none", 0.08);
        doc.applyPreset("fade", [bar, stripe, name, role], 3.0, 0.7, "out", {}, null, "none", 0);
        doc.endTransaction();
        return true;
    }

    // Title plus three tinted cards whose numbers and labels cascade in
    // card order: one staggered slide-up carries the whole picker.
    function buildOnboarding(doc) {
        doc.beginTransaction();
        doc.sceneColor = "#ffffff";
        doc.setAnimDuration(4.0);
        var title = doc.addText(560, 140, 800, 100, false);
        var c1 = doc.addShape("rectangle", 240, 380, 360, 300);
        var c2 = doc.addShape("rectangle", 780, 380, 360, 300);
        var c3 = doc.addShape("rectangle", 1320, 380, 360, 300);
        var n1 = doc.addText(240, 420, 360, 130, false);
        var n2 = doc.addText(780, 420, 360, 130, false);
        var n3 = doc.addText(1320, 420, 360, 130, false);
        var l1 = doc.addText(240, 560, 360, 60, false);
        var l2 = doc.addText(780, 560, 360, 60, false);
        var l3 = doc.addText(1320, 560, 360, 60, false);
        var v = doc.findNode(title);
        if (v) {
            v.name = "Title";
            v.textContent = "Pick a path";
            v.fontSize = 64;
            v.fontWeight = 600;
            v.fill = "#0f0f0f";
            v.hAlign = "center";
        }
        var cards = [c1, c2, c3];
        var fills = ["#e3efff", "#ece5ff", "#ddf5ea"];
        for (var i = 0; i < cards.length; i++) {
            var cn = doc.findNode(cards[i]);
            if (cn) {
                cn.name = "Card " + (i + 1);
                cn.fill = fills[i];
                cn.radius = 24;
            }
        }
        var nums = [n1, n2, n3];
        for (var j = 0; j < nums.length; j++) {
            var nn = doc.findNode(nums[j]);
            if (nn) {
                nn.name = "Number " + (j + 1);
                nn.textContent = String(j + 1);
                nn.fontSize = 110;
                nn.fontWeight = 600;
                nn.fill = "#0f0f0f";
                nn.hAlign = "center";
            }
        }
        var labels = [l1, l2, l3];
        var words = ["Design", "Animate", "Export"];
        for (var k = 0; k < labels.length; k++) {
            var ln = doc.findNode(labels[k]);
            if (ln) {
                ln.name = words[k];
                ln.textContent = words[k];
                ln.fontSize = 34;
                ln.fill = "#0f0f0f";
                ln.hAlign = "center";
            }
        }
        doc.applyPreset("fade", [title], 0.1, 0.5, "in", {}, null, "none", 0);
        doc.applyPreset("slide", [c1, n1, l1, c2, n2, l2, c3, n3, l3], 0.25, 0.6, "in", {
            direction: "up",
            distance: 80,
            fade: true
        }, {
            id: "easeOut"
        }, "none", 0.09);
        doc.endTransaction();
        return true;
    }
}
