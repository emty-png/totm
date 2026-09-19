import QtQuick

// Starter templates: full-blown motion graphics, not sketches — a dark
// product-launch teaser, a vertical story promo, and a three-tier
// pricing scene, each with in/out beats across its whole duration.
// Builders use only the public Document API (factory + applyPreset
// with the named easings), so template scenes stay valid by
// construction; each build runs inside one transaction, so a template
// lands as a single undo entry.
QtObject {
    id: library

    function templates() {
        return [
            {
                id: "storyPromo",
                name: qsTr("Story promo"),
                blurb: qsTr("6s clean vertical offer for stories")
            },
            {
                id: "pricingTiers",
                name: qsTr("Pricing tiers"),
                blurb: qsTr("7s three-plan pricing with highlight")
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
        if (templateId === "storyPromo")
            return library.buildStoryPromo(doc);
        if (templateId === "pricingTiers")
            return library.buildPricingTiers(doc);
        return false;
    }

    function styleNode(doc, uid, name, props) {
        var n = doc.findNode(uid);
        if (!n)
            return null;
        n.name = name;
        for (var key in props)
            n[key] = props[key];
        return n;
    }

    function styleText(doc, uid, name, content, size, weight, fill, align) {
        return library.styleNode(doc, uid, name, {
            textContent: content,
            fontSize: size,
            fontWeight: weight,
            fill: fill,
            hAlign: align || "center"
        });
    }

    // Light vertical 9:16 offer in five beats: eyebrow fades, the
    // headline slides up, a rule draws itself, the card rises with a
    // checklist cascade, the CTA pops and breathes, then everything
    // fades for the loop point. Pricing-scene restraint, portrait.
    function buildStoryPromo(doc) {
        doc.beginTransaction();
        doc.sceneWidth = 1080;
        doc.sceneHeight = 1920;
        doc.sceneColor = "#ffffff";
        doc.setAnimDuration(6.0);
        var brow = doc.addText(240, 300, 600, 54, false);
        var head = doc.addText(140, 380, 800, 230, false);
        var rule = doc.addShape("rectangle", 490, 660, 100, 4);
        var sub = doc.addText(290, 700, 500, 60, false);
        var card = doc.addShape("rectangle", 190, 820, 700, 420);
        var dots = [doc.addShape("ellipse", 250, 888, 20, 20), doc.addShape("ellipse", 250, 978, 20, 20), doc.addShape("ellipse", 250, 1068, 20, 20)];
        var rows = [doc.addText(290, 872, 560, 52, false), doc.addText(290, 962, 560, 52, false), doc.addText(290, 1052, 560, 52, false)];
        var cta = doc.addShape("rectangle", 290, 1300, 500, 110);
        var ctaLabel = doc.addText(290, 1300, 500, 110, false);
        var foot = doc.addText(390, 1450, 300, 50, false);
        library.styleText(doc, brow, "Eyebrow", "LIMITED TIME", 32, 600, "#0d99ff", "center");
        var ew = doc.findNode(brow);
        if (ew)
            ew.letterSpacing = 5;
        library.styleText(doc, head, "Headline", "50% off", 190, 800, "#0f0f0f", "center");
        library.styleNode(doc, rule, "Rule", {
            fill: "#0d99ff",
            radius: 2
        });
        library.styleText(doc, sub, "Subhead", "All annual plans", 36, 400, "#555555", "center");
        library.styleNode(doc, card, "Card", {
            fill: "#f2f2f2",
            radius: 28
        });
        var rowWords = ["Unlimited designs", "4K video export", "Priority support"];
        for (var i = 0; i < dots.length; i++) {
            library.styleNode(doc, dots[i], "Check " + (i + 1), {
                fill: "#0d99ff"
            });
            library.styleText(doc, rows[i], "Row " + (i + 1), rowWords[i], 30, 400, "#333333", "left");
        }
        library.styleNode(doc, cta, "CTA", {
            fill: "#0d99ff",
            radius: 55
        });
        library.styleText(doc, ctaLabel, "CTA label", "Claim offer", 40, 600, "#ffffff", "center");
        var sl = doc.findNode(ctaLabel);
        if (sl)
            sl.vAlign = "middle";
        library.styleText(doc, foot, "Footnote", "Ends Sunday", 28, 400, "#888888", "center");
        doc.applyPreset("fade", [brow], 0.1, 0.4, "in", {}, null, "none", 0);
        doc.applyPreset("slide", [head], 0.3, 0.6, "in", {
            direction: "up",
            distance: 110,
            fade: true
        }, {
            id: "easeOut"
        }, "none", 0);
        doc.applyPreset("customResize", [rule], 0.8, 0.5, "in", {
            fromW: 8,
            fromH: 4,
            toW: 100,
            toH: 4
        }, {
            id: "easeOut"
        }, "none", 0);
        doc.applyPreset("fade", [sub], 1.0, 0.4, "in", {}, null, "none", 0);
        doc.applyPreset("slide", [card], 1.2, 0.55, "in", {
            direction: "up",
            distance: 90,
            fade: true
        }, {
            id: "easeOut"
        }, "none", 0);
        doc.applyPreset("slide", dots.concat(rows), 1.4, 0.45, "in", {
            direction: "left",
            distance: 80,
            fade: true
        }, {
            id: "easeOut"
        }, "none", 0.09);
        doc.applyPreset("customScale", [cta, ctaLabel], 1.9, 0.5, "in", {
            from: 0,
            to: 1
        }, {
            id: "backOut"
        }, "none", 0);
        doc.applyPreset("customOpacity", [cta], 2.5, 2.7, "in", {
            from: 1,
            to: 0.75
        }, {
            id: "easeInOut"
        }, "pingpong", 0);
        doc.applyPreset("fade", [foot], 2.2, 0.4, "in", {}, null, "none", 0);
        doc.applyPreset("fade", [brow, head, rule, sub, card, cta, ctaLabel, foot].concat(dots, rows), 5.2, 0.6, "out", {}, null, "none", 0);
        doc.endTransaction();
        return true;
    }

    // Light 16:9 pricing in four beats: title fades, three tier cards
    // cascade up, prices pop, CTAs follow, the footnote lands, then the
    // board fades. The middle plan carries a brand glow.
    function buildPricingTiers(doc) {
        doc.beginTransaction();
        doc.sceneWidth = 1920;
        doc.sceneHeight = 1080;
        doc.sceneColor = "#ffffff";
        doc.setAnimDuration(7.0);
        var title = doc.addText(560, 90, 800, 90, false);
        var sub = doc.addText(660, 180, 600, 50, false);
        var foot = doc.addText(660, 940, 600, 44, false);
        library.styleText(doc, title, "Title", "Simple pricing", 64, 600, "#0f0f0f", "center");
        library.styleText(doc, sub, "Subhead", "Pick your plan", 30, 400, "#666666", "center");
        library.styleText(doc, foot, "Footnote", "Cancel anytime", 26, 400, "#888888", "center");
        var cards = [doc.addShape("rectangle", 270, 300, 420, 560), doc.addShape("rectangle", 750, 270, 420, 620), doc.addShape("rectangle", 1230, 300, 420, 560)];
        var names = [doc.addText(270, 340, 420, 50, false), doc.addText(750, 310, 420, 50, false), doc.addText(1230, 340, 420, 50, false)];
        var prices = [doc.addText(270, 400, 420, 110, false), doc.addText(750, 370, 420, 110, false), doc.addText(1230, 400, 420, 110, false)];
        var pers = [doc.addText(270, 505, 420, 40, false), doc.addText(750, 475, 420, 40, false), doc.addText(1230, 505, 420, 40, false)];
        var feats = [doc.addText(270, 570, 420, 40, false), doc.addText(270, 615, 420, 40, false), doc.addText(270, 660, 420, 40, false), doc.addText(750, 540, 420, 40, false), doc.addText(750, 585, 420, 40, false), doc.addText(750, 630, 420, 40, false), doc.addText(1230, 570, 420, 40, false), doc.addText(1230, 615, 420, 40, false), doc.addText(1230, 660, 420, 40, false)];
        var ctas = [doc.addShape("rectangle", 340, 740, 280, 64), doc.addShape("rectangle", 820, 790, 280, 64), doc.addShape("rectangle", 1300, 740, 280, 64)];
        var ctaLabels = [doc.addText(340, 740, 280, 64, false), doc.addText(820, 790, 280, 64, false), doc.addText(1300, 740, 280, 64, false)];
        var planNames = ["Starter", "Pro", "Team"];
        var planPrices = ["$0", "$12", "$29"];
        var featWords = ["3 designs", "720p export", "Community", "Unlimited designs", "4K + SVG export", "Priority support", "Everything in Pro", "Shared workspaces", "SSO login"];
        var fills = ["#f2f2f2", "#0d99ff", "#f2f2f2"];
        var inks = ["#0f0f0f", "#ffffff", "#0f0f0f"];
        var subInks = ["#555555", "#d6ecff", "#555555"];
        for (var i = 0; i < 3; i++) {
            library.styleNode(doc, cards[i], "Card " + planNames[i], {
                fill: fills[i],
                radius: 24
            });
            library.styleText(doc, names[i], planNames[i], planNames[i], 34, 600, inks[i], "center");
            library.styleText(doc, prices[i], planNames[i] + " price", planPrices[i], 84, 800, inks[i], "center");
            library.styleText(doc, pers[i], planNames[i] + " per", "per month", 24, 400, subInks[i], "center");
            for (var f = 0; f < 3; f++)
                library.styleText(doc, feats[i * 3 + f], planNames[i] + " feature " + (f + 1), featWords[i * 3 + f], 24, 400, subInks[i], "center");
            var ctaFill = i === 1 ? "#ffffff" : "#0f0f0f";
            var ctaInk = i === 1 ? "#0d99ff" : "#ffffff";
            library.styleNode(doc, ctas[i], planNames[i] + " CTA", {
                fill: ctaFill,
                radius: 32
            });
            library.styleText(doc, ctaLabels[i], planNames[i] + " CTA label", "Choose", 26, 600, ctaInk, "center");
            var ll = doc.findNode(ctaLabels[i]);
            if (ll)
                ll.vAlign = "middle";
        }
        var glow = doc.factory.defaultGlow(false);
        glow.color = "#800d99ff";
        var hl = doc.findNode(cards[1]);
        if (hl)
            hl.glows = [glow];
        var board = [title, sub].concat(cards, names, prices, pers, feats, ctas, ctaLabels);
        doc.applyPreset("fade", [title], 0.1, 0.5, "in", {}, null, "none", 0);
        doc.applyPreset("fade", [sub], 0.25, 0.5, "in", {}, null, "none", 0);
        doc.applyPreset("slide", cards.concat(names, prices, pers, feats, ctas, ctaLabels), 0.4, 0.7, "in", {
            direction: "up",
            distance: 90,
            fade: true
        }, {
            id: "easeOut"
        }, "none", 0.06);
        doc.applyPreset("customScale", prices, 1.6, 0.5, "in", {
            from: 0.5,
            to: 1
        }, {
            id: "backOut"
        }, "none", 0.15);
        doc.applyPreset("fade", [foot], 2.4, 0.5, "in", {}, null, "none", 0);
        doc.applyPreset("fade", board.concat([foot]), 6.0, 0.8, "out", {}, null, "none", 0);
        doc.endTransaction();
        return true;
    }
}
