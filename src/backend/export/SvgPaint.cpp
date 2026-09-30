#include "SvgPaint.h"

#include "AnimSampler.h"
#include "EffectPainter.h"
#include "EffectSpec.h"
#include "ShapePath.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QPainterPath>
#include <QPointF>
#include <QRectF>
#include <QStandardPaths>
#include <QtMath>

#include <algorithm>

namespace SvgPaint {

using namespace Anims;

namespace {

// Two decimals, trailing zeros stripped ("10.00" -> "10").
QString fmtNum(double v) {
    if (!std::isfinite(v))
        return QStringLiteral("0");
    if (qAbs(v) < 0.0005)
        v = 0.0;
    QString s = QString::number(v, 'f', 2);
    if (s.contains(QLatin1Char('.'))) {
        while (s.endsWith(QLatin1Char('0')))
            s.chop(1);
        if (s.endsWith(QLatin1Char('.')))
            s.chop(1);
    }
    if (s.isEmpty() || s == QLatin1String("-0"))
        return QStringLiteral("0");
    return s;
}

QString xmlEscape(const QString &s) {
    QString out;
    out.reserve(s.size() + 16);
    for (QChar c : s) {
        if (c == QLatin1Char('&'))
            out += QLatin1String("&amp;");
        else if (c == QLatin1Char('<'))
            out += QLatin1String("&lt;");
        else if (c == QLatin1Char('>'))
            out += QLatin1String("&gt;");
        else if (c == QLatin1Char('"'))
            out += QLatin1String("&quot;");
        else if (c == QLatin1Char('\''))
            out += QLatin1String("&apos;");
        else
            out += c;
    }
    return out;
}

QString colorHex(const QColor &c) {
    return QStringLiteral("#%1%2%3")
        .arg(c.red(), 2, 16, QLatin1Char('0'))
        .arg(c.green(), 2, 16, QLatin1Char('0'))
        .arg(c.blue(), 2, 16, QLatin1Char('0'));
}

double colorAlpha01(const QColor &c) {
    return qBound(0.0, c.alphaF(), 1.0);
}

// Three decimals for filter-region fractions (two would shave coverage
// off small shapes with large blurs).
QString fmtFrac(double v) {
    if (!std::isfinite(v))
        return QStringLiteral("0");
    if (qAbs(v) < 0.0000005)
        v = 0.0;
    QString s = QString::number(v, 'f', 3);
    if (s.contains(QLatin1Char('.'))) {
        while (s.endsWith(QLatin1Char('0')))
            s.chop(1);
        if (s.endsWith(QLatin1Char('.')))
            s.chop(1);
    }
    if (s.isEmpty() || s == QLatin1String("-0"))
        return QStringLiteral("0");
    return s;
}

QColor fillFallback() {
    return QColor(QStringLiteral("#d9d9d9"));
}

// Rotated bbox corners (flips never change the box). Mirrors the PNG
// crop so SVG viewBoxes agree with PNG pixels at 1x.
QRectF rotatedBox(const QVariantMap &m) {
    const double x = num(m, "x"), y = num(m, "y");
    const double w = num(m, "w"), h = num(m, "h");
    if (w <= 0 || h <= 0)
        return {};
    const double cx = x + w / 2.0, cy = y + h / 2.0;
    const double a = qDegreesToRadians(num(m, "rotation"));
    const double c = qCos(a), s = qSin(a);
    double x0 = 1e18, y0 = 1e18, x1 = -1e18, y1 = -1e18;
    const QPointF corners[4] = {QPointF(x, y), QPointF(x + w, y), QPointF(x + w, y + h), QPointF(x, y + h)};
    for (const QPointF &p : corners) {
        const double dx = p.x() - cx, dy = p.y() - cy;
        x0 = qMin(x0, cx + dx * c - dy * s);
        y0 = qMin(y0, cy + dx * s + dy * c);
        x1 = qMax(x1, cx + dx * c - dy * s);
        y1 = qMax(y1, cy + dx * s + dy * c);
    }
    return QRectF(QPointF(x0, y0), QPointF(x1, y1));
}

// QPainterPath (from Effects::outlinePath) to SVG path data. CurveTo
// elements always arrive as anchor + two data points.
QString pathToSvg(const QPainterPath &p) {
    QString d;
    d.reserve(256);
    const int n = p.elementCount();
    for (int i = 0; i < n; ++i) {
        const QPainterPath::Element e = p.elementAt(i);
        if (e.type == QPainterPath::MoveToElement) {
            d += QStringLiteral("M%1 %2 ").arg(fmtNum(e.x)).arg(fmtNum(e.y));
        } else if (e.type == QPainterPath::LineToElement) {
            d += QStringLiteral("L%1 %2 ").arg(fmtNum(e.x)).arg(fmtNum(e.y));
        } else if (e.type == QPainterPath::CurveToElement) {
            if (i + 2 >= n)
                break;
            const QPainterPath::Element c2 = p.elementAt(i + 1);
            const QPainterPath::Element end = p.elementAt(i + 2);
            d += QStringLiteral("C%1 %2 %3 %4 %5 %6 ")
                     .arg(fmtNum(e.x))
                     .arg(fmtNum(e.y))
                     .arg(fmtNum(c2.x))
                     .arg(fmtNum(c2.y))
                     .arg(fmtNum(end.x))
                     .arg(fmtNum(end.y));
            i += 2;
        }
    }
    return d.trimmed();
}

QString leafTransform(
    double x, double y, double w, double h, double rot, bool flipH, bool flipV, double ox, double oy) {
    QStringList parts;
    if (ox != 0.0 || oy != 0.0)
        parts.append(QStringLiteral("translate(%1 %2)").arg(fmtNum(ox)).arg(fmtNum(oy)));
    const bool around = rot != 0.0 || flipH || flipV;
    const double cx = x + w / 2.0, cy = y + h / 2.0;
    if (around)
        parts.append(QStringLiteral("translate(%1 %2)").arg(fmtNum(cx)).arg(fmtNum(cy)));
    if (rot != 0.0)
        parts.append(QStringLiteral("rotate(%1)").arg(fmtNum(rot)));
    if (flipH || flipV)
        parts.append(QStringLiteral("scale(%1 %2)").arg(flipH ? -1 : 1).arg(flipV ? -1 : 1));
    if (around)
        parts.append(QStringLiteral("translate(%1 %2)").arg(fmtNum(-cx)).arg(fmtNum(-cy)));
    return parts.join(QLatin1Char(' '));
}

struct GradientOut {
    QString attr; // e.g. fill="url(#svgfg3)"
    QString def; // <linearGradient .../> or empty
};

// White text silhouette for masks (luminance/alpha source, never a
// fill paint): same layout math as the main text branch so glyph
// coverage registers with canvas and PNG.
QString maskTextEl(const QVariantMap &m, double x, double y, double w, double h) {
    const QString content = str(m, "textContent");
    if (content.isEmpty())
        return {};
    const QString family = str(m, "fontFamily", QStringLiteral("Inter"));
    const int weight = qBound(1, m.value(QStringLiteral("fontWeight"), 400).toInt(), 1000);
    const double size = qMax(1.0, num(m, "fontSize", 16.0));
    const QString halign = str(m, "hAlign", QStringLiteral("left"));
    const double spacingPx = size * num(m, "letterSpacing") / 100.0;
    const bool italic = m.value(QStringLiteral("fontItalic"), false).toBool();
    double tx = x;
    QString anchor;
    if (halign == QLatin1String("center")) {
        tx = x + w / 2.0;
        anchor = QStringLiteral("middle");
    } else if (halign == QLatin1String("right")) {
        tx = x + w;
        anchor = QStringLiteral("end");
    }
    const double ty = y + size;
    QStringList tAttrs;
    tAttrs.append(QStringLiteral("x=\"%1\"").arg(fmtNum(tx)));
    tAttrs.append(QStringLiteral("y=\"%1\"").arg(fmtNum(ty)));
    tAttrs.append(QStringLiteral("font-family=\"%1\"").arg(xmlEscape(family)));
    tAttrs.append(QStringLiteral("font-size=\"%1\"").arg(fmtNum(size)));
    tAttrs.append(QStringLiteral("font-weight=\"%1\"").arg(weight));
    if (italic)
        tAttrs.append(QStringLiteral("font-style=\"italic\""));
    if (!anchor.isEmpty())
        tAttrs.append(QStringLiteral("text-anchor=\"%1\"").arg(anchor));
    if (!qFuzzyIsNull(spacingPx))
        tAttrs.append(QStringLiteral("letter-spacing=\"%1\"").arg(fmtNum(spacingPx)));
    tAttrs.append(QStringLiteral("fill=\"white\""));
    const QStringList lines = content.split(QLatin1Char('\n'));
    QString el = QStringLiteral("<text %1>").arg(tAttrs.join(QLatin1Char(' ')));
    for (int i = 0; i < lines.size(); ++i) {
        if (i == 0) {
            el += xmlEscape(lines.at(i));
        } else {
            el += QStringLiteral("<tspan x=\"%1\" dy=\"%2\">%3</tspan>")
                      .arg(fmtNum(tx))
                      .arg(fmtNum(size * qMax(0.5, num(m, "lineHeight", 1.2))))
                      .arg(xmlEscape(lines.at(i)));
        }
    }
    el += QStringLiteral("</text>");
    return el;
}

// One mask def for a sampled mask leaf, in scene coords (same space as
// the existing image clipPath rects: referencing g transforms never
// apply to mask/clip content). Vector silhouettes reuse outlinePath,
// images a rounded rect (content alpha stays a raster-only nuance),
// text the glyph silhouette above. Hard edges emit clipPath; feather
// or invert need alpha, so they emit mask (mask-type alpha, optional
// blur + alpha-invert filter). Returns the full g attribute to wrap
// the leaf in (clip-path="..." / mask="..."), or {} when degenerate,
// in which case the caller must hide the leaf like the rasterizer does.
QString buildSvgMask(const QVariantMap &mm, const QRectF &region, QStringList &defs, int &maskSeq) {
    const QString shapeType = str(mm, "type", str(mm, "shapeType", QStringLiteral("rectangle")));
    const double x = num(mm, "x"), y = num(mm, "y");
    const double w = num(mm, "w"), h = num(mm, "h");
    if (w <= 0 || h <= 0)
        return {};
    const double opacity = qBound(0.0, num(mm, "opacity", 1.0), 1.0);
    if (opacity <= 0.001)
        return {};
    const double rot = num(mm, "rotation");
    const bool flipH = mm.value(QStringLiteral("flipH")).toBool();
    const bool flipV = mm.value(QStringLiteral("flipV")).toBool();
    const double feather = qMax(0.0, num(mm, "maskFeather"));
    const bool inverted = mm.value(QStringLiteral("maskInverted")).toBool();

    QString inner;
    if (shapeType == QLatin1String("text")) {
        inner = maskTextEl(mm, x, y, w, h);
    } else if (shapeType == QLatin1String("image")) {
        const double r = qMin(qMax(0.0, num(mm, "radius")), qMin(w, h) / 2.0);
        inner = QStringLiteral("<rect x=\"%1\" y=\"%2\" width=\"%3\" height=\"%4\" rx=\"%5\" fill=\"white\"/>")
                    .arg(fmtNum(x))
                    .arg(fmtNum(y))
                    .arg(fmtNum(w))
                    .arg(fmtNum(h))
                    .arg(fmtNum(r));
    } else {
        const QPainterPath path = Effects::outlinePath(shapeType, QRectF(x, y, w, h),
            Effects::PathOpts::fromMap(mm), Effects::Style::fromMap(mm), 1.0);
        const QString d = pathToSvg(path);
        if (d.isEmpty())
            return {};
        inner = QStringLiteral("<path d=\"%1\" fill=\"white\" stroke=\"none\"/>").arg(xmlEscape(d));
    }
    if (inner.isEmpty())
        return {};
    const QString xf = leafTransform(x, y, w, h, rot, flipH, flipV, 0.0, 0.0);
    QStringList gAttrs;
    if (!xf.isEmpty())
        gAttrs.append(QStringLiteral("transform=\"%1\"").arg(xf));
    if (opacity < 0.999)
        gAttrs.append(QStringLiteral("opacity=\"%1\"").arg(fmtNum(opacity)));
    if (feather > 0.01 || inverted) {
        const QString fid = QStringLiteral("svgmff%1").arg(maskSeq);
        QString f = QStringLiteral("<filter id=\"%1\">").arg(fid);
        if (feather > 0.01)
            f += QStringLiteral("<feGaussianBlur stdDeviation=\"%1\"/>").arg(fmtNum(feather));
        if (inverted)
            f += QStringLiteral("<feComponentTransfer><feFuncA type=\"table\" tableValues=\"1 0\"/></feComponentTransfer>");
        f += QStringLiteral("</filter>");
        defs.append(f);
        gAttrs.append(QStringLiteral("filter=\"url(#%1)\"").arg(fid));
    }
    inner = gAttrs.isEmpty() ? QStringLiteral("<g>%1</g>").arg(inner)
                             : QStringLiteral("<g %1>%2</g>").arg(gAttrs.join(QLatin1Char(' '))).arg(inner);
    // Hard edges take the universally-supported clipPath; soft or
    // inverted edges need a real alpha mask. Returns the full g
    // attribute (clip-path="..." / mask="...") or {} for degenerate
    // silhouettes, whose leaf the caller hides like the rasterizer.
    if (feather <= 0.01 && !inverted) {
        const QString cid = QStringLiteral("svgmclip%1").arg(maskSeq++);
        defs.append(QStringLiteral("<clipPath id=\"%1\">%2</clipPath>").arg(cid).arg(inner));
        return QStringLiteral("clip-path=\"url(#%1)\"").arg(cid);
    }
    const QString mid = QStringLiteral("svgmask%1").arg(maskSeq++);
    defs.append(QStringLiteral("<mask id=\"%1\" maskUnits=\"userSpaceOnUse\" x=\"%2\" y=\"%3\" width=\"%4\" "
                                "height=\"%5\" mask-type=\"alpha\">%6</mask>")
                    .arg(mid)
                    .arg(fmtNum(region.left()))
                    .arg(fmtNum(region.top()))
                    .arg(fmtNum(region.width()))
                    .arg(fmtNum(region.height()))
                    .arg(inner));
    return QStringLiteral("mask=\"url(#%1)\"").arg(mid);
}

// Two-stop linear gradient in the shape's local coords (same space as
// the path data, so the transform applies to both like QPainter's
// logical-mode brush).
GradientOut gradientFill(const QVariantMap &gradMap, const QRectF &box, const QString &id, bool isFill) {
    GradientOut out;
    const Effects::LinearSpec spec = Effects::linearFrom(gradMap);
    QPointF p0, p1;
    Effects::gradientEndpoints(box, spec.angle, &p0, &p1);
    QString def = QStringLiteral("<linearGradient id=\"%1\" gradientUnits=\"userSpaceOnUse\" x1=\"%2\" y1=\"%3\" "
                                 "x2=\"%4\" y2=\"%5\">")
                      .arg(id)
                      .arg(fmtNum(p0.x()))
                      .arg(fmtNum(p0.y()))
                      .arg(fmtNum(p1.x()))
                      .arg(fmtNum(p1.y()));
    for (int i = 0; i < 2; ++i) {
        const QColor c = spec.stops[i].color;
        const double off = qBound(0.0, spec.stops[i].pos, 1.0);
        def += QStringLiteral("<stop offset=\"%1\" stop-color=\"%2\" stop-opacity=\"%3\"/>")
                   .arg(fmtNum(off))
                   .arg(colorHex(c.isValid() ? c : (i == 0 ? QColor(Qt::black) : QColor(Qt::white))))
                   .arg(fmtNum(colorAlpha01(c)));
    }
    def += QStringLiteral("</linearGradient>");
    out.def = def;
    out.attr = QStringLiteral("%1=\"url(#%2)\"").arg(isFill ? QStringLiteral("fill") : QStringLiteral("stroke")).arg(id);
    return out;
}

QString solidFillAttr(const QColor &c, bool isFill) {
    const char *key = isFill ? "fill" : "stroke";
    if (!c.isValid() || c.alpha() == 0)
        return QStringLiteral("%1=\"none\"").arg(QLatin1String(key));
    QString attr = QStringLiteral("%1=\"%2\"").arg(QLatin1String(key)).arg(colorHex(c));
    if (c.alpha() < 255)
        attr += QStringLiteral(" %1-opacity=\"%2\"").arg(QLatin1String(key)).arg(fmtNum(colorAlpha01(c)));
    return attr;
}

GradientOut gradientFillOpacity(
    const QVariantMap &gradMap, const QRectF &box, const QString &id, bool isFill, double opacity) {
    GradientOut out;
    Effects::LinearSpec spec = Effects::linearFrom(gradMap);
    spec.stops[0].color.setAlphaF(
        qBound(0.0, spec.stops[0].color.alphaF() * qBound(0.0, opacity, 1.0), 1.0));
    spec.stops[1].color.setAlphaF(
        qBound(0.0, spec.stops[1].color.alphaF() * qBound(0.0, opacity, 1.0), 1.0));
    QPointF p0, p1;
    Effects::gradientEndpoints(box, spec.angle, &p0, &p1);
    QString def = QStringLiteral("<linearGradient id=\"%1\" gradientUnits=\"userSpaceOnUse\" x1=\"%2\" y1=\"%3\" "
                                 "x2=\"%4\" y2=\"%5\">")
                      .arg(id)
                      .arg(fmtNum(p0.x()))
                      .arg(fmtNum(p0.y()))
                      .arg(fmtNum(p1.x()))
                      .arg(fmtNum(p1.y()));
    for (int i = 0; i < 2; ++i) {
        const QColor c = spec.stops[i].color;
        const double off = qBound(0.0, spec.stops[i].pos, 1.0);
        def += QStringLiteral("<stop offset=\"%1\" stop-color=\"%2\" stop-opacity=\"%3\"/>")
                   .arg(fmtNum(off))
                   .arg(colorHex(c.isValid() ? c : (i == 0 ? QColor(Qt::black) : QColor(Qt::white))))
                   .arg(fmtNum(colorAlpha01(c)));
    }
    def += QStringLiteral("</linearGradient>");
    out.def = def;
    out.attr = QStringLiteral("%1=\"url(#%2)\"").arg(isFill ? QStringLiteral("fill") : QStringLiteral("stroke")).arg(id);
    // Per-entry opacity rides on the stop alphas above, but SVG
    // viewers also honor the element opacity; the caller adds
    // fill-/stroke-opacity only for solid paints.
    return out;
}

QString capFor(const QString &cap) {
    if (cap == QLatin1String("square"))
        return QStringLiteral("square");
    if (cap == QLatin1String("flat"))
        return QStringLiteral("butt");
    return QStringLiteral("round");
}

QString joinFor(const QString &join) {
    if (join == QLatin1String("bevel"))
        return QStringLiteral("bevel");
    if (join == QLatin1String("miter"))
        return QStringLiteral("miter");
    return QStringLiteral("round");
}

// Dash pattern in stroke-width units, scaled to SVG user units by the
// stroke width. Empty when the stroke paints solid.
QString dashAttr(const QVector<qreal> &dash, double sw)
{
    if (dash.isEmpty() || sw <= 0.01)
        return QString();
    QStringList parts;
    for (const qreal d : dash)
        parts.append(fmtNum(d * sw));
    return QStringLiteral(" stroke-dasharray=\"%1\"").arg(parts.join(QLatin1Char(' ')));
}

QString solidFillAttrOpacity(const QColor &c, bool isFill, double opacity)
{
    QColor cc = c;
    cc.setAlphaF(qBound(0.0, cc.alphaF() * qBound(0.0, opacity, 1.0), 1.0));
    return solidFillAttr(cc, isFill);
}

QString imageMime(const QString &name) {
    const QString lower = name.toLower();
    if (lower.endsWith(QStringLiteral(".png")))
        return QStringLiteral("image/png");
    if (lower.endsWith(QStringLiteral(".jpg")) || lower.endsWith(QStringLiteral(".jpeg")))
        return QStringLiteral("image/jpeg");
    if (lower.endsWith(QStringLiteral(".webp")))
        return QStringLiteral("image/webp");
    if (lower.endsWith(QStringLiteral(".gif")))
        return QStringLiteral("image/gif");
    if (lower.endsWith(QStringLiteral(".svg")))
        return QStringLiteral("image/svg+xml");
    return QString();
}

QString exportImagesDir() {
    QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (dir.isEmpty())
        dir = QDir::homePath() + QStringLiteral("/.totm");
    if (!dir.endsWith(QStringLiteral("/totm"), Qt::CaseInsensitive))
        dir += QStringLiteral("/totm");
    return dir + QStringLiteral("/images");
}

QByteArray loadImageBytes(const QString &name) {
    if (name.isEmpty() || name.contains(QLatin1Char('/')) || name.contains(QLatin1Char('\\'))
        || name.contains(QStringLiteral("..")))
        return {};
    const QString path = exportImagesDir() + QStringLiteral("/") + name;
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return f.readAll();
}

// Effect filters: the PNG stack (outer shadows -> outer glows under
// the shape, inner bands above the fill, whole-stack layer blur, grain
// confined to the silhouette) rebuilt with SVG filter primitives on
// the leaf's <g>, so shapes, text and images all carry their effects.
// Mapping is approximate by nature: box-blur radii ride as
// stdDeviation = radius/2, and grain is feTurbulence noise instead of
// the hashed dots. Background blur has no standalone-SVG equivalent
// (there is no backdrop to sample), so it is skipped, never failed.
struct FilterChain {
    QStringList prims;
    int seq = 0;
    QString take(const QString &prefix) {
        return prefix + QString::number(seq++);
    }
};

QString floodAttrs(const QColor &c) {
    return QStringLiteral("flood-color=\"%1\" flood-opacity=\"%2\"").arg(colorHex(c)).arg(fmtNum(colorAlpha01(c)));
}

// One outer shadow/glow halo from the shape alpha. Spread dilates the
// silhouette first (feMorphology); without spread a single
// feDropShadow does the same job.
QString outerHalo(FilterChain &f, double dx, double dy, double blur, double spread, const QColor &c) {
    if (spread <= 0.01) {
        const QString r = f.take("o");
        f.prims.append(QStringLiteral("<feDropShadow in=\"SourceAlpha\" dx=\"%1\" dy=\"%2\" stdDeviation=\"%3\" %4 "
                                      "result=\"%5\"/>")
                .arg(fmtNum(dx))
                .arg(fmtNum(dy))
                .arg(fmtNum(blur * 0.5))
                .arg(floodAttrs(c))
                .arg(r));
        return r;
    }
    const QString a = f.take("a");
    f.prims.append(QStringLiteral("<feMorphology in=\"SourceAlpha\" operator=\"dilate\" radius=\"%1\" result=\"%2\"/>")
            .arg(fmtNum(spread))
            .arg(a));
    const QString b = f.take("b");
    f.prims.append(QStringLiteral("<feGaussianBlur in=\"%1\" stdDeviation=\"%2\" result=\"%3\"/>")
            .arg(a)
            .arg(fmtNum(blur * 0.5))
            .arg(b));
    const QString o = f.take("c");
    f.prims.append(QStringLiteral("<feOffset in=\"%1\" dx=\"%2\" dy=\"%3\" result=\"%4\"/>")
            .arg(b)
            .arg(fmtNum(dx))
            .arg(fmtNum(dy))
            .arg(o));
    const QString fl = f.take("f");
    f.prims.append(QStringLiteral("<feFlood %1 result=\"%2\"/>").arg(floodAttrs(c)).arg(fl));
    const QString r = f.take("o");
    f.prims.append(QStringLiteral("<feComposite in=\"%1\" in2=\"%2\" operator=\"in\" result=\"%3\"/>")
            .arg(fl)
            .arg(o)
            .arg(r));
    return r;
}

// One inner shadow/glow band: the inverted shape alpha blurs, tints
// and clips back to the silhouette (the standard inset recipe).
// Spread dilates the inverted copy (the dual of eroding the shape, so
// the band thickens inward like the raster painter); eroding here
// would push the edge outward and thin the band with spread.
QString innerBand(FilterChain &f, double dx, double dy, double blur, double spread, const QColor &c) {
    const QString inv = f.take("v");
    f.prims.append(QStringLiteral("<feComponentTransfer in=\"SourceAlpha\" result=\"%1\"><feFuncA type=\"table\" "
                                  "tableValues=\"1 0\"/></feComponentTransfer>")
            .arg(inv));
    QString cur = inv;
    if (spread > 0.01) {
        const QString e = f.take("e");
        f.prims.append(QStringLiteral("<feMorphology in=\"%1\" operator=\"dilate\" radius=\"%2\" result=\"%3\"/>")
                .arg(cur)
                .arg(fmtNum(spread))
                .arg(e));
        cur = e;
    }
    const QString b = f.take("b");
    f.prims.append(QStringLiteral("<feGaussianBlur in=\"%1\" stdDeviation=\"%2\" result=\"%3\"/>")
            .arg(cur)
            .arg(fmtNum(blur * 0.5))
            .arg(b));
    const QString o = f.take("c");
    f.prims.append(QStringLiteral("<feOffset in=\"%1\" dx=\"%2\" dy=\"%3\" result=\"%4\"/>")
            .arg(b)
            .arg(fmtNum(dx))
            .arg(fmtNum(dy))
            .arg(o));
    const QString fl = f.take("f");
    f.prims.append(QStringLiteral("<feFlood %1 result=\"%2\"/>").arg(floodAttrs(c)).arg(fl));
    const QString cl = f.take("n");
    f.prims.append(QStringLiteral("<feComposite in=\"%1\" in2=\"%2\" operator=\"in\" result=\"%3\"/>")
            .arg(fl)
            .arg(o)
            .arg(cl));
    const QString r = f.take("n");
    f.prims.append(QStringLiteral("<feComposite in=\"%1\" in2=\"SourceAlpha\" operator=\"in\" result=\"%2\"/>")
            .arg(cl)
            .arg(r));
    return r;
}

QString mergeNodes(const QStringList &inputs, const QString &result) {
    QString out = QStringLiteral("<feMerge result=\"%1\">").arg(result);
    for (const QString &in : inputs)
        out += QStringLiteral("<feMergeNode in=\"%1\"/>").arg(in);
    out += QStringLiteral("</feMerge>");
    return out;
}

// Pad the leaf filter region needs (0 when the leaf carries nothing
// renderable). Mirrors buildLeafFilter's effect set so the viewBox and
// the region can never disagree.
double filterPadFor(const QVariantMap &m, const QString &shapeType, double sw) {
    Q_UNUSED(shapeType);
    const QList<Effects::Shadow> shadows = Effects::Shadow::listFrom(m.value(QStringLiteral("shadows")).toList());
    const QList<Effects::Glow> glows = Effects::Glow::listFrom(m.value(QStringLiteral("glows")).toList());
    const Effects::Blur layerBlur = Effects::Blur::fromMap(m.value(QStringLiteral("layerBlur")).toMap());
    const Effects::Grain grain = Effects::Grain::fromMap(m.value(QStringLiteral("grain")).toMap());
    const Effects::Style st = Effects::Style::fromMap(m);
    const double maxSw = st.maxStrokeWidth();
    if (shadows.isEmpty() && glows.isEmpty() && !(layerBlur.enabled && layerBlur.radius > 0.01)
        && !(grain.enabled && grain.amount > 0.001))
        return qMax(0.0, Effects::strokesPad(st.strokes));
    Q_UNUSED(sw);
    return qMax(double(Effects::effectPad(shadows, glows, layerBlur, st.strokes)), maxSw / 2.0 + 1.0);
}

// Builds the leaf filter, appends its <filter> to defs and returns the
// id (empty when the leaf carries nothing renderable). Region is the
// shared effect pad over the leaf box in bbox fractions, so halos and
// blurs never clip; stroke and grain need no extra room (grain is
// confined, SourceAlpha already straddles the stroke).
QString buildLeafFilter(const QVariantMap &m, const QString &shapeType, double sw, double w, double h, int uid,
    const QString &id, QStringList &defs) {
    const QList<Effects::Shadow> shadows = Effects::Shadow::listFrom(m.value(QStringLiteral("shadows")).toList());
    const QList<Effects::Glow> glows = Effects::Glow::listFrom(m.value(QStringLiteral("glows")).toList());
    const Effects::Blur layerBlur = Effects::Blur::fromMap(m.value(QStringLiteral("layerBlur")).toMap());
    const Effects::Grain grain = Effects::Grain::fromMap(m.value(QStringLiteral("grain")).toMap());
    const bool useBlur = layerBlur.enabled && layerBlur.radius > 0.01;
    const bool useGrain = grain.enabled && grain.amount > 0.001;

    QList<QString> outerSh; // shadow halos, index 0 paints topmost
    QList<QString> outerGl; // glow halos, index 0 paints topmost
    QList<QString> innerSh; // shadow bands, index 0 paints topmost
    QList<QString> innerGl; // glow bands, index 0 paints topmost
    FilterChain f;
    for (const Effects::Shadow &sh : shadows) {
        if (sh.inner)
            innerSh.append(innerBand(f, sh.x, sh.y, sh.blur, sh.spread, sh.color));
        else
            outerSh.append(outerHalo(f, sh.x, sh.y, sh.blur, sh.spread, sh.color));
    }
    for (const Effects::Glow &g : glows) {
        if (g.inner)
            innerGl.append(innerBand(f, 0.0, 0.0, g.blur, g.spread, g.color));
        else
            outerGl.append(outerHalo(f, 0.0, 0.0, g.blur, g.spread, g.color));
    }
    if (outerSh.isEmpty() && outerGl.isEmpty() && innerSh.isEmpty() && innerGl.isEmpty() && !useBlur && !useGrain)
        return {};

    // Base: source plus inner bands. PNG paints inner shadows first
    // (below) and inner glows over them; index 0 stays topmost inside
    // each group.
    QString cur = QStringLiteral("SourceGraphic");
    for (const QList<QString> &group : {innerSh, innerGl}) {
        for (int i = group.size() - 1; i >= 0; --i) {
            const QString mg = f.take("m");
            QStringList nodes{cur, group.at(i)};
            f.prims.append(mergeNodes(nodes, mg));
            cur = mg;
        }
    }
    // Halos land under the base in stack order: shadows below glows,
    // last entry bottommost inside each group.
    if (!outerSh.isEmpty() || !outerGl.isEmpty()) {
        const QString mg = f.take("m");
        QStringList nodes;
        for (int i = outerSh.size() - 1; i >= 0; --i)
            nodes.append(outerSh.at(i));
        for (int i = outerGl.size() - 1; i >= 0; --i)
            nodes.append(outerGl.at(i));
        nodes.append(cur);
        f.prims.append(mergeNodes(nodes, mg));
        cur = mg;
    }
    // Whole-stack layer blur mixed back with the sharp stack by opacity
    // (arithmetic: out = o*blurred + (1-o)*sharp).
    if (useBlur) {
        const QString b = f.take("b");
        f.prims.append(QStringLiteral("<feGaussianBlur in=\"%1\" stdDeviation=\"%2\" result=\"%3\"/>")
                .arg(cur)
                .arg(fmtNum(layerBlur.radius * 0.5))
                .arg(b));
        const QString mx = f.take("m");
        const double o = qBound(0.0, layerBlur.opacity, 1.0);
        f.prims.append(QStringLiteral("<feComposite in=\"%1\" in2=\"%2\" operator=\"arithmetic\" k1=\"0\" k2=\"%3\" "
                                      "k3=\"%4\" k4=\"0\" result=\"%5\"/>")
                .arg(b)
                .arg(cur)
                .arg(fmtNum(o))
                .arg(fmtNum(1.0 - o))
                .arg(mx));
        cur = mx;
    }
    // Grain over everything, confined to the silhouette (SourceAlpha
    // already includes the stroke, like the PNG stroke union).
    if (useGrain) {
        const QString t = f.take("t");
        f.prims.append(QStringLiteral("<feTurbulence type=\"fractalNoise\" baseFrequency=\"%1\" numOctaves=\"1\" "
                                      "seed=\"%2\" stitchTiles=\"stitch\" result=\"%3\"/>")
                .arg(fmtNum(1.0 / qMax(1.0, grain.size)))
                .arg(qMax(0, uid))
                .arg(t));
        const QString g = f.take("g");
        f.prims.append(QStringLiteral("<feColorMatrix in=\"%1\" type=\"matrix\" "
                                      "values=\"0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 %2 0\" result=\"%3\"/>")
                .arg(t)
                .arg(fmtNum(qBound(0.0, grain.amount, 1.0)))
                .arg(g));
        const QString gc = f.take("g");
        f.prims.append(QStringLiteral("<feComposite in=\"%1\" in2=\"SourceAlpha\" operator=\"in\" result=\"%2\"/>")
                .arg(g)
                .arg(gc));
        const QString mg = f.take("m");
        f.prims.append(mergeNodes({cur, gc}, mg));
        cur = mg;
    }

    const double pad = filterPadFor(m, shapeType, sw);
    if (pad <= 0.0)
        return {};
    QString def = QStringLiteral("<filter id=\"%1\" x=\"%2\" y=\"%3\" width=\"%4\" height=\"%5\">")
                      .arg(id)
                      .arg(fmtFrac(-pad / w))
                      .arg(fmtFrac(-pad / h))
                      .arg(fmtFrac(1.0 + 2.0 * pad / w))
                      .arg(fmtFrac(1.0 + 2.0 * pad / h));
    for (const QString &p : f.prims)
        def += p;
    def += QStringLiteral("</filter>");
    defs.append(def);
    Q_UNUSED(cur);
    return id;
}

} // namespace

QString renderNodes(const QVariantList &topNodes, QString *error) {
    auto fail = [&](const QString &message) {
        if (error)
            *error = message;
        return QString();
    };
    if (topNodes.isEmpty())
        return fail(QCoreApplication::translate("SvgPaint", "Nothing selected to export."));
    QVariantMap subset;
    QVariantList nodes;
    for (const QVariant &v : topNodes) {
        QVariantMap n = v.toMap();
        if (n.isEmpty())
            continue;
        // Explicit selection exports even when hidden; nested
        // visibility stays authored (same rule as the PNG path).
        n[QStringLiteral("visible")] = true;
        nodes.append(n);
    }
    if (nodes.isEmpty())
        return fail(QCoreApplication::translate("SvgPaint", "Nothing selected to export."));
    subset[QStringLiteral("nodes")] = nodes;

    const QList<Leaf> leaves = collectLeaves(subset);
    QMap<int, int> leafIndex;
    for (int i = 0; i < leaves.size(); ++i) {
        const int uid = leaves.at(i).map.value(QStringLiteral("uid"), -1).toInt();
        if (uid >= 0)
            leafIndex[uid] = i;
    }
    // No anim blob rides along, so the frame holds base values.
    const QList<QVariantMap> work = sampleFrame(subset, 0.0);
    QMap<int, QVariantMap> workByUid;
    for (const QVariantMap &m : work) {
        const int uid = m.value(QStringLiteral("uid"), -1).toInt();
        if (uid >= 0)
            workByUid[uid] = m;
    }
    const QMap<int, QList<int>> maskMap = maskMapForWork(subset, work);
    QList<QVariantMap> paint;
    paint.reserve(work.size());
    for (const QVariantMap &m : work) {
        if (isMaskMap(m))
            continue;
        const int uid = m.value(QStringLiteral("uid"), -1).toInt();
        const int srcIdx = leafIndex.value(uid, -1);
        const bool ancVis = srcIdx >= 0 ? leaves.at(srcIdx).ancestorsVisible : true;
        if (!ancVis || !m.value(QStringLiteral("visible"), true).toBool())
            continue;
        if (qBound(0.0, Anims::num(m, "opacity", 1.0), 1.0) <= 0.001)
            continue;
        if (Anims::num(m, "w") <= 0 || Anims::num(m, "h") <= 0)
            continue;
        paint.append(m);
    }
    if (paint.isEmpty())
        return fail(QCoreApplication::translate("SvgPaint", "Nothing visible to export."));

    // Tight union of rotated boxes, expanded by the largest leaf
    // effect pad so halos and blurs never clip at the viewport edge
    // (the outer svg clips to its viewBox).
    QRectF bounds;
    double maxPad = 0.0;
    for (const QVariantMap &m : paint) {
        const QRectF box = rotatedBox(m);
        if (box.isEmpty())
            continue;
        bounds = bounds.united(box);
        const QString shapeType = str(m, "type", str(m, "shapeType", QStringLiteral("rectangle")));
        maxPad = qMax(maxPad, filterPadFor(m, shapeType, 0.0));
    }
    bounds.adjust(-maxPad, -maxPad, maxPad, maxPad);
    if (bounds.isEmpty() || bounds.width() < 0.01 || bounds.height() < 0.01)
        return fail(QCoreApplication::translate("SvgPaint", "Nothing visible to export."));
    constexpr double kMaxSide = 32768.0;
    if (bounds.width() > kMaxSide || bounds.height() > kMaxSide)
        return fail(QCoreApplication::translate("SvgPaint", "Selection is too large to export as SVG."));

    const double ox = -bounds.left(), oy = -bounds.top();
    QStringList defs;
    QStringList body;
    int gradSeq = 0;
    int clipSeq = 0;
    int fxSeq = 0;
    int maskSeq = 0;

    // Leaves arrive top-first; emit bottom-first so document order
    // paints the selection correctly.
    for (int li = paint.size() - 1; li >= 0; --li) {
        const QVariantMap m = paint.at(li);
        const QString shapeType = str(m, "type", str(m, "shapeType", QStringLiteral("rectangle")));
        const double x = num(m, "x"), y = num(m, "y");
        const double w = num(m, "w"), h = num(m, "h");
        if (w <= 0 || h <= 0)
            continue;
        const double opacity = qBound(0.0, num(m, "opacity", 1.0), 1.0);
        if (opacity <= 0.001)
            continue;
        const double rot = num(m, "rotation");
        const bool flipH = m.value(QStringLiteral("flipH")).toBool();
        const bool flipV = m.value(QStringLiteral("flipV")).toBool();
        // Boolean silhouettes arrive in world coords (rotation baked),
        // pre-shifted below: no leaf transform, just the export offset.
        // Frames behave the same (derived box, rotation baked as 0).
        const bool isBool = shapeType == QLatin1String("boolean");
        const bool isFrame = shapeType == QLatin1String("frame");
        const QString xf = (isBool || isFrame) ? QString() : leafTransform(x, y, w, h, rot, flipH, flipV, ox, oy);

        // Empty text paints nothing: skip before the filter so no
        // unused <filter> def leaks into the document.
        if (shapeType == QLatin1String("text") && str(m, "textContent").isEmpty())
            continue;
        const int uid = m.value(QStringLiteral("uid"), -1).toInt();
        const Effects::Style stFx = Effects::Style::fromMap(m);
        const QString fxCand = QStringLiteral("svgfl%1").arg(fxSeq);
        const QString fxId = buildLeafFilter(m, shapeType, stFx.maxStrokeWidth(), w, h, uid, fxCand, defs);
        if (!fxId.isEmpty())
            ++fxSeq;

        QStringList gAttrs;
        if (!xf.isEmpty())
            gAttrs.append(QStringLiteral("transform=\"%1\"").arg(xf));
        if (opacity < 0.999)
            gAttrs.append(QStringLiteral("opacity=\"%1\"").arg(fmtNum(opacity)));
        if (!fxId.isEmpty())
            gAttrs.append(QStringLiteral("filter=\"url(#%1)\"").arg(fxId));
        const QString gOpen = gAttrs.isEmpty() ? QStringLiteral("<g>")
                                               : QStringLiteral("<g %1>").arg(gAttrs.join(QLatin1Char(' ')));

        // Mask wraps (nearest first, nesting intersects like the PNG
        // DestinationIn chain). Degenerate silhouettes hide the leaf,
        // matching the rasterizer's empty-mask transparency.
        const int muid = m.value(QStringLiteral("uid"), -1).toInt();
        QString maskPre, maskPost;
        bool maskHide = false;
        for (int mid : maskMap.value(muid)) {
            const QVariantMap mm = workByUid.value(mid);
            if (mm.isEmpty() || !mm.value(QStringLiteral("visible"), true).toBool())
                continue;
            const int mSrc = leafIndex.value(mid, -1);
            if (mSrc >= 0 && !leaves.at(mSrc).ancestorsVisible)
                continue;
            const QString ref = buildSvgMask(mm, bounds, defs, maskSeq);
            if (ref.isEmpty()) {
                maskHide = true;
                break;
            }
            maskPre += QStringLiteral("<g %1>").arg(ref);
            maskPost.prepend(QStringLiteral("</g>"));
        }
        if (maskHide)
            continue;

        if (shapeType == QLatin1String("text")) {
            const QString content = str(m, "textContent");
            const QRectF box(x, y, w, h);
            const QString family = str(m, "fontFamily", QStringLiteral("Inter"));
            const int weight = qBound(1, m.value(QStringLiteral("fontWeight"), 400).toInt(), 1000);
            const double size = qMax(1.0, num(m, "fontSize", 16.0));
            const double spacingPct = num(m, "letterSpacing");
            const double spacingPx = size * spacingPct / 100.0;
            const double leading = qMax(0.5, num(m, "lineHeight", 1.2));
            const QString halign = str(m, "hAlign", QStringLiteral("left"));
            const QString valign = str(m, "vAlign", QStringLiteral("top"));
            const bool italic = m.value(QStringLiteral("fontItalic"), false).toBool();
            const bool underline = m.value(QStringLiteral("fontUnderline"), false).toBool();
            const bool strike = m.value(QStringLiteral("fontStrike"), false).toBool();
            const QString caps = str(m, "fontCaps", QStringLiteral("none"));
            const QString join = str(m, "strokeJoin", QStringLiteral("round"));
            double tx = x;
            QString anchor;
            if (halign == QLatin1String("center")) {
                tx = x + w / 2.0;
                anchor = QStringLiteral("middle");
            } else if (halign == QLatin1String("right")) {
                tx = x + w;
                anchor = QStringLiteral("end");
            }
            double ty = y + size;
            if (valign == QLatin1String("middle"))
                ty = y + h / 2.0;
            else if (valign == QLatin1String("bottom"))
                ty = y + h;
            // Shared text attributes (no paint): family/size/weight/style,
            // decoration, case, spacing. Paint layers below carry their own
            // fill/stroke so stacked entries survive as duplicated <text>
            // (bottom-first, index 0 topmost like PNG).
            QStringList baseAttrs;
            baseAttrs.append(QStringLiteral("x=\"%1\"").arg(fmtNum(tx)));
            baseAttrs.append(QStringLiteral("y=\"%1\"").arg(fmtNum(ty)));
            baseAttrs.append(QStringLiteral("font-family=\"%1\"").arg(xmlEscape(family)));
            baseAttrs.append(QStringLiteral("font-size=\"%1\"").arg(fmtNum(size)));
            baseAttrs.append(QStringLiteral("font-weight=\"%1\"").arg(weight));
            if (italic)
                baseAttrs.append(QStringLiteral("font-style=\"italic\""));
            if (!anchor.isEmpty())
                baseAttrs.append(QStringLiteral("text-anchor=\"%1\"").arg(anchor));
            if (!qFuzzyIsNull(spacingPx))
                baseAttrs.append(QStringLiteral("letter-spacing=\"%1\"").arg(fmtNum(spacingPx)));
            QString deco;
            if (underline && strike)
                deco = QStringLiteral("underline line-through");
            else if (underline)
                deco = QStringLiteral("underline");
            else if (strike)
                deco = QStringLiteral("line-through");
            if (!deco.isEmpty())
                baseAttrs.append(QStringLiteral("text-decoration=\"%1\"").arg(deco));
            if (caps == QLatin1String("upper"))
                baseAttrs.append(QStringLiteral("text-transform=\"uppercase\""));
            else if (caps == QLatin1String("lower"))
                baseAttrs.append(QStringLiteral("text-transform=\"lowercase\""));
            const QString joinSvg = (join == QLatin1String("bevel") || join == QLatin1String("miter"))
                ? join
                : QStringLiteral("round");
            const QStringList lines = content.split(QLatin1Char('\n'));
            // Rich runs, bridge-canonical (sorted) with defensive clamp.
            // Offsets are UTF-16 units over content, like the samplers.
            struct SvgRun {
                int start = 0;
                int len = 0;
                bool bold = false;
                bool italic = false;
                bool ul = false;
                bool strike = false;
                QString color;
            };
            QList<SvgRun> svgRuns;
            for (const QVariant &rv : m.value(QStringLiteral("textRuns")).toList()) {
                const QVariantMap rm = rv.toMap();
                SvgRun r;
                r.start = qMax(0, rm.value(QStringLiteral("start"), 0).toInt());
                r.len = qMax(0, rm.value(QStringLiteral("len"), 0).toInt());
                r.len = qBound(0, r.len, qMax(0, content.size() - r.start));
                r.bold = rm.value(QStringLiteral("bold"), false).toBool();
                r.italic = rm.value(QStringLiteral("italic"), false).toBool();
                r.ul = rm.value(QStringLiteral("underline"), false).toBool();
                r.strike = rm.value(QStringLiteral("strike"), false).toBool();
                r.color = rm.value(QStringLiteral("color")).toString();
                if (r.len > 0 && (r.bold || r.italic || r.ul || r.strike || !r.color.isEmpty()))
                    svgRuns.append(r);
            }
            std::sort(svgRuns.begin(), svgRuns.end(),
                [](const SvgRun &a, const SvgRun &b) { return a.start < b.start; });
            auto svgRunAt = [&](int off) {
                for (int i = 0; i < svgRuns.size(); ++i) {
                    const SvgRun &r = svgRuns.at(i);
                    if (off >= r.start && off < r.start + r.len)
                        return i;
                }
                return -1;
            };
            struct SvgSeg {
                QString text;
                int run = -1;
            };
            // Per-line segments split by run; lineOff tracks content offsets.
            auto lineSegs = [&](const QString &line, int lineOff) {
                QList<SvgSeg> segs;
                int i = 0;
                while (i < line.size()) {
                    const int r = svgRunAt(lineOff + i);
                    int j = i + 1;
                    while (j < line.size() && svgRunAt(lineOff + j) == r)
                        ++j;
                    segs.append({line.mid(i, j - i), r});
                    i = j;
                }
                return segs;
            };
            auto segDeco = [&](int r) {
                const bool u = underline || (r >= 0 && svgRuns.at(r).ul);
                const bool k = strike || (r >= 0 && svgRuns.at(r).strike);
                if (u && k)
                    return QStringLiteral("underline line-through");
                if (u)
                    return QStringLiteral("underline");
                if (k)
                    return QStringLiteral("line-through");
                return QString();
            };
            // Run-aware body: every segment rides a tspan carrying only
            // its divergences (weight/style/decoration/fill). mode "box"
            // inherits the layer fill on unset ranges (set ranges hide
            // with fill=none); mode "color" paints set ranges solid.
            auto textBody = [&](const QString &extra, const QString &mode, const QString &fillAttr) {
                QString inner;
                int lineOff = 0;
                for (int li2 = 0; li2 < lines.size(); ++li2) {
                    const QString &ln = lines.at(li2);
                    const QList<SvgSeg> segs = lineSegs(ln, lineOff);
                    for (int si = 0; si < segs.size(); ++si) {
                        const SvgSeg &sg = segs.at(si);
                        QStringList ta;
                        if (si == 0 && li2 > 0) {
                            ta.append(QStringLiteral("x=\"%1\"").arg(fmtNum(tx)));
                            ta.append(QStringLiteral("dy=\"%1\"").arg(fmtNum(size * leading)));
                        }
                        if (sg.run >= 0 && svgRuns.at(sg.run).bold)
                            ta.append(QStringLiteral("font-weight=\"700\""));
                        const bool it = italic || (sg.run >= 0 && svgRuns.at(sg.run).italic);
                        if (it && !italic)
                            ta.append(QStringLiteral("font-style=\"italic\""));
                        if (!it && italic)
                            ta.append(QStringLiteral("font-style=\"normal\""));
                        const QString rd = segDeco(sg.run);
                        if (rd != deco)
                            ta.append(rd.isEmpty() ? QStringLiteral("text-decoration=\"none\"")
                                                   : QStringLiteral("text-decoration=\"%1\"").arg(rd));
                        if (mode == QLatin1String("color")) {
                            if (sg.run >= 0 && !svgRuns.at(sg.run).color.isEmpty()) {
                                const QColor rc(svgRuns.at(sg.run).color);
                                ta.append(solidFillAttrOpacity(rc.isValid() ? rc : fillFallback(), true, 1.0));
                            } else {
                                ta.append(QStringLiteral("fill=\"none\""));
                            }
                        } else if (sg.run >= 0 && !svgRuns.at(sg.run).color.isEmpty()) {
                            ta.append(QStringLiteral("fill=\"none\""));
                        }
                        if (ta.isEmpty())
                            inner += xmlEscape(sg.text);
                        else
                            inner += QStringLiteral("<tspan %1>%2</tspan>").arg(ta.join(QLatin1Char(' '))).arg(xmlEscape(sg.text));
                    }
                    lineOff += ln.size() + 1;
                }
                return QStringLiteral("<text %1 %2>%3</text>")
                    .arg(baseAttrs.join(QLatin1Char(' ')))
                    .arg(extra)
                    .arg(inner);
            };
            const Effects::Style stText = Effects::Style::fromMap(m);
            // Stroked text exports glyph outlines as paths (exact width,
            // dash, join, gradient and center/inside/outside position like
            // PNG); unstroked text stays selectable <text>. Inside clips
            // the doubled stroke to the glyphs, outside masks it out.
            bool needPaths = false;
            for (const Effects::StrokeEntry &se : stText.strokes) {
                if (se.enabled && se.width > 0.01) {
                    needPaths = true;
                    break;
                }
            }
            if (needPaths) {
                QVariantMap tm;
                tm[QStringLiteral("content")] = content;
                tm[QStringLiteral("family")] = family;
                tm[QStringLiteral("weight")] = weight;
                tm[QStringLiteral("size")] = size;
                tm[QStringLiteral("spacing")] = spacingPct;
                tm[QStringLiteral("halign")] = halign;
                tm[QStringLiteral("valign")] = valign;
                tm[QStringLiteral("autoSize")] = m.value(QStringLiteral("autoSize"), true).toBool();
                tm[QStringLiteral("lineAuto")] = m.value(QStringLiteral("lineHeightAuto"), true).toBool();
                tm[QStringLiteral("leading")] = leading;
                tm[QStringLiteral("boxW")] = w;
                tm[QStringLiteral("boxH")] = h;
                tm[QStringLiteral("italic")] = italic;
                tm[QStringLiteral("underline")] = underline;
                tm[QStringLiteral("strike")] = strike;
                tm[QStringLiteral("caps")] = caps;
                tm[QStringLiteral("runs")] = m.value(QStringLiteral("textRuns")).toList();
                const Effects::TextOpts to = Effects::TextOpts::fromMap(tm);
                const QPainterPath glyphs = Effects::textGlyphPath(to, 1.0, box);
                if (glyphs.isEmpty())
                    continue;
                const QString gd = pathToSvg(glyphs);
                if (gd.isEmpty())
                    continue;
                QStringList players;
                // Fills per run piece (box stacks paint unset runs, set
                // run colors paint solid); bottom-first like PNG.
                const QList<Effects::RunGlyphs> runPaths = Effects::textRunPaths(to, 1.0, box);
                auto boxFillAttr = [&](const Effects::FillEntry &f) {
                    if (f.type == QLatin1String("linear")) {
                        GradientOut g = gradientFillOpacity(f.gradient, box,
                            QStringLiteral("svgft%1").arg(gradSeq++), true, f.opacity);
                        defs.append(g.def);
                        return g.attr;
                    }
                    QColor fc = f.color;
                    if (!fc.isValid())
                        fc = fillFallback();
                    return solidFillAttrOpacity(fc, true, f.opacity);
                };
                for (const Effects::RunGlyphs &rg : runPaths) {
                    if (rg.path.isEmpty())
                        continue;
                    const QString pd = pathToSvg(rg.path);
                    if (pd.isEmpty())
                        continue;
                    if (rg.hasColor) {
                        const QColor rc = rg.color.isValid() ? rg.color : fillFallback();
                        players.append(QStringLiteral("<path d=\"%1\" %2 stroke=\"none\"/>")
                                .arg(xmlEscape(pd))
                                .arg(solidFillAttrOpacity(rc, true, 1.0)));
                        continue;
                    }
                    for (int fi = stText.fills.size() - 1; fi >= 0; --fi) {
                        const Effects::FillEntry &f = stText.fills.at(fi);
                        if (!f.enabled)
                            continue;
                        const QString fillAttr = boxFillAttr(f);
                        if (fillAttr == QLatin1String("fill=\"none\""))
                            continue;
                        players.append(QStringLiteral("<path d=\"%1\" %2 stroke=\"none\"/>").arg(xmlEscape(pd)).arg(fillAttr));
                    }
                }
                if (players.isEmpty() && stText.fills.isEmpty()) {
                    QColor fc(QStringLiteral("#d9d9d9"));
                    players.append(QStringLiteral("<path d=\"%1\" %2 stroke=\"none\"/>")
                            .arg(xmlEscape(gd))
                            .arg(solidFillAttrOpacity(fc, true, 1.0)));
                }
                for (int si = stText.strokes.size() - 1; si >= 0; --si) {
                    const Effects::StrokeEntry &se = stText.strokes.at(si);
                    if (!se.enabled || se.width <= 0.01)
                        continue;
                    const bool side = se.position == QLatin1String("inside") || se.position == QLatin1String("outside");
                    const double sw = side ? se.width * 2.0 : se.width;
                    QString strokeAttr = QStringLiteral("stroke=\"none\"");
                    if (se.type == QLatin1String("linear")) {
                        GradientOut g = gradientFillOpacity(se.gradient, box,
                            QStringLiteral("svgst%1").arg(gradSeq++), false, se.opacity);
                        defs.append(g.def);
                        strokeAttr = QStringLiteral("%1 stroke-width=\"%2\" stroke-linecap=\"%3\" stroke-linejoin=\"%4\"%5")
                                         .arg(g.attr)
                                         .arg(fmtNum(sw))
                                         .arg(capFor(stText.strokeCap))
                                         .arg(joinSvg)
                                         .arg(dashAttr(se.dash, se.width));
                    } else {
                        QColor sc = se.color;
                        sc.setAlphaF(qBound(0.0, sc.alphaF() * se.opacity, 1.0));
                        if (!sc.isValid() || sc.alpha() <= 0)
                            continue;
                        strokeAttr = QStringLiteral("stroke=\"%1\"").arg(colorHex(sc));
                        if (sc.alpha() < 255)
                            strokeAttr += QStringLiteral(" stroke-opacity=\"%1\"").arg(fmtNum(colorAlpha01(sc)));
                        strokeAttr += QStringLiteral(" stroke-width=\"%1\" stroke-linecap=\"%2\" stroke-linejoin=\"%3\"%4")
                                          .arg(fmtNum(sw))
                                          .arg(capFor(stText.strokeCap))
                                          .arg(joinSvg)
                                          .arg(dashAttr(se.dash, se.width));
                    }
                    if (strokeAttr == QLatin1String("stroke=\"none\""))
                        continue;
                    const QString el = QStringLiteral("<path d=\"%1\" fill=\"none\" %2/>").arg(xmlEscape(gd)).arg(strokeAttr);
                    if (!side) {
                        players.append(el);
                    } else if (se.position == QLatin1String("inside")) {
                        const QString cid = QStringLiteral("svgclip%1").arg(clipSeq++);
                        defs.append(QStringLiteral("<clipPath id=\"%1\"><path d=\"%2\"/></clipPath>").arg(cid).arg(xmlEscape(gd)));
                        players.append(QStringLiteral("<g clip-path=\"url(#%1)\">%2</g>").arg(cid).arg(el));
                    } else {
                        const QString mid = QStringLiteral("svgm%1").arg(maskSeq++);
                        const QRectF gb = glyphs.boundingRect().adjusted(-sw - 1.0, -sw - 1.0, sw + 1.0, sw + 1.0);
                        defs.append(QStringLiteral("<mask id=\"%1\" maskUnits=\"userSpaceOnUse\" x=\"%2\" y=\"%3\" width=\"%4\" height=\"%5\"><rect x=\"%2\" y=\"%3\" width=\"%4\" height=\"%5\" fill=\"white\"/><path d=\"%6\" fill=\"black\"/></mask>")
                                .arg(mid)
                                .arg(fmtNum(gb.x()))
                                .arg(fmtNum(gb.y()))
                                .arg(fmtNum(gb.width()))
                                .arg(fmtNum(gb.height()))
                                .arg(xmlEscape(gd)));
                        players.append(QStringLiteral("<path d=\"%1\" fill=\"none\" %2 mask=\"url(#%3)\"/>")
                                .arg(xmlEscape(gd))
                                .arg(strokeAttr)
                                .arg(mid));
                    }
                }
                if (players.isEmpty())
                    continue;
                QString el = gOpen + maskPre;
                for (const QString &layer : players)
                    el += layer;
                el += maskPost + QStringLiteral("</g>");
                body.append(el);
                continue;
            }
            QStringList layers;
            // Stacked fills bottom-first (fill + stroke none). Set run
            // ranges hide per layer; one color layer paints them solid.
            for (int fi = stText.fills.size() - 1; fi >= 0; --fi) {
                const Effects::FillEntry &f = stText.fills.at(fi);
                if (!f.enabled)
                    continue;
                QString fillAttr;
                if (f.type == QLatin1String("linear")) {
                    GradientOut g = gradientFillOpacity(f.gradient, box,
                        QStringLiteral("svgft%1").arg(gradSeq++), true, f.opacity);
                    defs.append(g.def);
                    fillAttr = g.attr;
                } else {
                    QColor fc = f.color;
                    if (!fc.isValid())
                        fc = fillFallback();
                    fillAttr = solidFillAttrOpacity(fc, true, f.opacity);
                }
                if (fillAttr == QLatin1String("fill=\"none\""))
                    continue;
                layers.append(textBody(QStringLiteral("%1 stroke=\"none\"").arg(fillAttr), QStringLiteral("box"), fillAttr));
            }
            if (layers.isEmpty() && !stText.fills.isEmpty()) {
                // All fills disabled: keep one transparent layer so empty
                // text still skips like before (no naked unfilled text).
            } else if (layers.isEmpty() && stText.fills.isEmpty()) {
                QColor fc(QStringLiteral("#d9d9d9"));
                layers.append(textBody(QStringLiteral("%1 stroke=\"none\"").arg(solidFillAttrOpacity(fc, true, 1.0)), QStringLiteral("box"), QString()));
            }
            bool hasColored = false;
            for (const SvgRun &r : svgRuns) {
                if (!r.color.isEmpty()) {
                    hasColored = true;
                    break;
                }
            }
            if (hasColored)
                layers.append(textBody(QStringLiteral("fill=\"none\" stroke=\"none\""), QStringLiteral("color"), QString()));
            // Unstroked text only reaches here (any enabled stroke takes
            // the outlined-path branch above), so no stroke layers follow.
            if (layers.isEmpty())
                continue;
            QString el = gOpen + maskPre + layers.join(QString()) + maskPost + QStringLiteral("</g>");
            body.append(el);
            continue;
        }

        if (shapeType == QLatin1String("image")) {
            const QString name = str(m, "imageSource", str(m, "image", QString()));
            const QByteArray bytes = loadImageBytes(name);
            const QString mime = imageMime(name);
            const double r = qMin(qMax(0.0, num(m, "radius")), qMin(w, h) / 2.0);
            QString clipAttr;
            if (r > 0.01 && !bytes.isEmpty() && !mime.isEmpty()) {
                const QString cid = QStringLiteral("svgclip%1").arg(clipSeq++);
                defs.append(QStringLiteral("<clipPath id=\"%1\"><rect x=\"%2\" y=\"%3\" width=\"%4\" height=\"%5\" "
                                            "rx=\"%6\"/></clipPath>")
                                .arg(cid)
                                .arg(fmtNum(x))
                                .arg(fmtNum(y))
                                .arg(fmtNum(w))
                                .arg(fmtNum(h))
                                .arg(fmtNum(r)));
                clipAttr = QStringLiteral(" clip-path=\"url(#%1)\"").arg(cid);
            }
            if (bytes.isEmpty() || mime.isEmpty()) {
                // Missing blobs paint a neutral box so broken imports
                // never vanish silently (same rule as the PNG path).
                body.append(gOpen + maskPre
                    + QStringLiteral("<rect x=\"%1\" y=\"%2\" width=\"%3\" height=\"%4\" fill=\"#d9d9d9\"/>")
                          .arg(fmtNum(x))
                          .arg(fmtNum(y))
                          .arg(fmtNum(w))
                          .arg(fmtNum(h))
                    + maskPost + QStringLiteral("</g>"));
                continue;
            }
            const QString href = QStringLiteral("data:%1;base64,%2>")
                                     .arg(mime)
                                     .arg(QString::fromLatin1(bytes.toBase64()));
            // Note: href (SVG2) over xlink:href for modern viewers.
            body.append(gOpen + maskPre
                + QStringLiteral("<image x=\"%1\" y=\"%2\" width=\"%3\" height=\"%4\" preserveAspectRatio=\"none\"%5 "
                                 "href=\"%6\"/>")
                      .arg(fmtNum(x))
                      .arg(fmtNum(y))
                      .arg(fmtNum(w))
                      .arg(fmtNum(h))
                      .arg(clipAttr)
                      .arg(href)
                + maskPost + QStringLiteral("</g>"));
            continue;
        }

        // Vector shapes share the outline builder with the canvas, so
        // silhouettes match the PNG export by construction. Stacked
        // paints layer as separate paths: fills bottom-first, then
        // strokes bottom-first on top (index 0 topmost in both).
        // Position stays centered in standalone SVG (no backdrop to
        // clip against); per-entry opacity folds into the paint.
        const Effects::Style st = Effects::Style::fromMap(m);
        QRectF gradBox(x, y, w, h);
        QPainterPath path;
        if (isBool) {
            path = ShapePath::combineNodes(
                ShapePath::normOp(m.value(QStringLiteral("boolOp"), QStringLiteral("union")).toString()),
                m.value(QStringLiteral("children")).toList());
            if (path.isEmpty())
                continue;
            path.translate(ox, oy);
            gradBox = path.boundingRect();
        } else if (isFrame) {
            path = Effects::outlinePath(QStringLiteral("rectangle"), QRectF(x, y, w, h),
                Effects::PathOpts::fromMap(m), st, 1.0);
            if (path.isEmpty())
                continue;
            path.translate(ox, oy);
            gradBox = path.boundingRect();
        } else {
            path = Effects::outlinePath(
                shapeType, QRectF(x, y, w, h), Effects::PathOpts::fromMap(m), st, 1.0);
        }
        const QString d = pathToSvg(path);
        if (d.isEmpty())
            continue;
        const bool fills = shapeType != QLatin1String("pen") || st.penFill;
        QStringList layers;
        if (fills) {
            for (int fi = st.fills.size() - 1; fi >= 0; --fi) {
                const Effects::FillEntry &f = st.fills.at(fi);
                if (!f.enabled)
                    continue;
                QString fillAttr = QStringLiteral("fill=\"none\"");
                if (f.type == QLatin1String("linear")) {
                    GradientOut g = gradientFillOpacity(f.gradient, gradBox,
                        QStringLiteral("svgfg%1").arg(gradSeq++), true, f.opacity);
                    defs.append(g.def);
                    fillAttr = g.attr;
                } else {
                    QColor fc = f.color;
                    if (!fc.isValid())
                        fc = fillFallback();
                    fillAttr = solidFillAttrOpacity(fc, true, f.opacity);
                }
                if (fillAttr == QLatin1String("fill=\"none\""))
                    continue;
                layers.append(QStringLiteral("<path d=\"%1\" %2 stroke=\"none\"/>").arg(xmlEscape(d)).arg(fillAttr));
            }
        }
        for (int si = st.strokes.size() - 1; si >= 0; --si) {
            const Effects::StrokeEntry &se = st.strokes.at(si);
            if (!se.enabled || se.width <= 0.01)
                continue;
            const double sw = se.width;
            QString strokeAttr = QStringLiteral("stroke=\"none\"");
            if (se.type == QLatin1String("linear")) {
                GradientOut g = gradientFillOpacity(se.gradient, gradBox,
                    QStringLiteral("svgsg%1").arg(gradSeq++), false, se.opacity);
                defs.append(g.def);
                strokeAttr = QStringLiteral("%1 stroke-width=\"%2\" stroke-linecap=\"%3\" stroke-linejoin=\"%4\"%5")
                                 .arg(g.attr)
                                 .arg(fmtNum(sw))
                                 .arg(capFor(st.strokeCap))
                                 .arg(joinFor(st.strokeJoin))
                                 .arg(dashAttr(se.dash, sw));
            } else {
                QColor sc = se.color;
                sc.setAlphaF(qBound(0.0, sc.alphaF() * se.opacity, 1.0));
                if (sc.isValid() && sc.alpha() > 0) {
                    strokeAttr = QStringLiteral("stroke=\"%1\"").arg(colorHex(sc));
                    if (sc.alpha() < 255)
                        strokeAttr += QStringLiteral(" stroke-opacity=\"%1\"").arg(fmtNum(colorAlpha01(sc)));
                    strokeAttr += QStringLiteral(" stroke-width=\"%1\" stroke-linecap=\"%2\" stroke-linejoin=\"%3\"%4")
                                      .arg(fmtNum(sw))
                                      .arg(capFor(st.strokeCap))
                                      .arg(joinFor(st.strokeJoin))
                                      .arg(dashAttr(se.dash, sw));
                }
            }
            if (strokeAttr == QLatin1String("stroke=\"none\""))
                continue;
            layers.append(QStringLiteral("<path d=\"%1\" fill=\"none\" %2/>").arg(xmlEscape(d)).arg(strokeAttr));
        }
        if (layers.isEmpty())
            continue;
        QString el = gOpen + maskPre;
        for (const QString &layer : layers)
            el += layer;
        el += maskPost + QStringLiteral("</g>");
        body.append(el);
    }

    if (body.isEmpty())
        return fail(QCoreApplication::translate("SvgPaint", "Nothing visible to export."));

    QString svg = QStringLiteral("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    svg += QStringLiteral("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%1\" height=\"%2\" viewBox=\"0 0 %1 %2\">\n")
               .arg(fmtNum(bounds.width()))
               .arg(fmtNum(bounds.height()));
    if (!defs.isEmpty()) {
        svg += QStringLiteral("<defs>");
        for (const QString &d : defs)
            svg += d;
        svg += QStringLiteral("</defs>\n");
    }
    for (const QString &el : body)
        svg += el + QLatin1Char('\n');
    svg += QStringLiteral("</svg>\n");
    return svg;
}

} // namespace SvgPaint
