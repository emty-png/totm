#include "SvgPaint.h"

#include "AnimSampler.h"
#include "EffectPainter.h"
#include "EffectSpec.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QPainterPath>
#include <QPointF>
#include <QRectF>
#include <QStandardPaths>
#include <QtMath>

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
QString dashAttr(const Effects::Style &st, double sw)
{
    if (st.strokeDash.isEmpty() || sw <= 0.01)
        return QString();
    QStringList parts;
    for (const qreal d : st.strokeDash)
        parts.append(fmtNum(d * sw));
    return QStringLiteral(" stroke-dasharray=\"%1\"").arg(parts.join(QLatin1Char(' ')));
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
// PNG parity: image leaves ignore shadows (the raster image painter
// takes glows/blurs only).
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
// Spread erodes the inverted copy so the band thickens inward.
QString innerBand(FilterChain &f, double dx, double dy, double blur, double spread, const QColor &c) {
    const QString inv = f.take("v");
    f.prims.append(QStringLiteral("<feComponentTransfer in=\"SourceAlpha\" result=\"%1\"><feFuncA type=\"table\" "
                                  "tableValues=\"1 0\"/></feComponentTransfer>")
            .arg(inv));
    QString cur = inv;
    if (spread > 0.01) {
        const QString e = f.take("e");
        f.prims.append(QStringLiteral("<feMorphology in=\"%1\" operator=\"erode\" radius=\"%2\" result=\"%3\"/>")
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
    const bool isImage = shapeType == QLatin1String("image");
    QList<Effects::Shadow> shadows = Effects::Shadow::listFrom(m.value(QStringLiteral("shadows")).toList());
    if (isImage)
        shadows.clear();
    const QList<Effects::Glow> glows = Effects::Glow::listFrom(m.value(QStringLiteral("glows")).toList());
    const Effects::Blur layerBlur = Effects::Blur::fromMap(m.value(QStringLiteral("layerBlur")).toMap());
    const Effects::Grain grain = Effects::Grain::fromMap(m.value(QStringLiteral("grain")).toMap());
    if (shadows.isEmpty() && glows.isEmpty() && !(layerBlur.enabled && layerBlur.radius > 0.01)
        && !(grain.enabled && grain.amount > 0.001))
        return 0.0;
    return qMax(double(Effects::effectPad(shadows, glows, layerBlur, sw)), sw / 2.0 + 1.0);
}

// Builds the leaf filter, appends its <filter> to defs and returns the
// id (empty when the leaf carries nothing renderable). Region is the
// shared effect pad over the leaf box in bbox fractions, so halos and
// blurs never clip; stroke and grain need no extra room (grain is
// confined, SourceAlpha already straddles the stroke).
QString buildLeafFilter(const QVariantMap &m, const QString &shapeType, double sw, double w, double h, int uid,
    const QString &id, QStringList &defs) {
    const bool isImage = shapeType == QLatin1String("image");
    QList<Effects::Shadow> shadows = Effects::Shadow::listFrom(m.value(QStringLiteral("shadows")).toList());
    if (isImage)
        shadows.clear();
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
    // Halos land under the base in Figma order: shadows below glows,
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
    QList<QVariantMap> paint;
    paint.reserve(work.size());
    for (const QVariantMap &m : work) {
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
        maxPad = qMax(maxPad, filterPadFor(m, shapeType, qMax(0.0, num(m, "strokeWidth"))));
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
        const QString xf = leafTransform(x, y, w, h, rot, flipH, flipV, ox, oy);

        // Empty text paints nothing: skip before the filter so no
        // unused <filter> def leaks into the document.
        if (shapeType == QLatin1String("text") && str(m, "textContent").isEmpty())
            continue;
        const int uid = m.value(QStringLiteral("uid"), -1).toInt();
        const QString fxCand = QStringLiteral("svgfl%1").arg(fxSeq);
        const QString fxId = buildLeafFilter(m, shapeType, qMax(0.0, num(m, "strokeWidth")), w, h, uid, fxCand, defs);
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

        if (shapeType == QLatin1String("text")) {
            const QString content = str(m, "textContent");
            const QRectF box(x, y, w, h);
            const QString family = str(m, "fontFamily", QStringLiteral("Inter"));
            const int weight = qBound(100, m.value(QStringLiteral("fontWeight"), 400).toInt(), 900);
            const double size = qMax(1.0, num(m, "fontSize", 16.0));
            const double spacing = num(m, "letterSpacing");
            const double leading = qMax(0.5, num(m, "lineHeight", 1.2));
            const QString halign = str(m, "hAlign", QStringLiteral("left"));
            const QString valign = str(m, "vAlign", QStringLiteral("top"));
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
            // Fill mirrors the PNG text leaf (solid or box-spanning linear).
            const QString fillType = str(m, "fillType", QStringLiteral("solid"));
            QString fillAttr;
            if (fillType == QLatin1String("linear")) {
                GradientOut g = gradientFill(m.value(QStringLiteral("fillGradient")).toMap(), box,
                    QStringLiteral("svgft%1").arg(gradSeq++), true);
                defs.append(g.def);
                fillAttr = g.attr;
            } else {
                QColor fc(str(m, "fill", QStringLiteral("#d9d9d9")));
                if (!fc.isValid())
                    fc = fillFallback();
                fillAttr = solidFillAttr(fc, true);
            }
            QStringList tAttrs;
            tAttrs.append(QStringLiteral("x=\"%1\"").arg(fmtNum(tx)));
            tAttrs.append(QStringLiteral("y=\"%1\"").arg(fmtNum(ty)));
            tAttrs.append(QStringLiteral("font-family=\"%1\"").arg(xmlEscape(family)));
            tAttrs.append(QStringLiteral("font-size=\"%1\"").arg(fmtNum(size)));
            tAttrs.append(QStringLiteral("font-weight=\"%1\"").arg(weight));
            if (!anchor.isEmpty())
                tAttrs.append(QStringLiteral("text-anchor=\"%1\"").arg(anchor));
            if (spacing != 0.0)
                tAttrs.append(QStringLiteral("letter-spacing=\"%1\"").arg(fmtNum(spacing)));
            tAttrs.append(fillAttr);
            const double sw = qMax(0.0, num(m, "strokeWidth"));
            if (sw > 0.01) {
                QColor sc(str(m, "stroke", QStringLiteral("#000000")));
                if (sc.isValid() && sc.alpha() > 0) {
                    tAttrs.append(QStringLiteral("stroke=\"%1\"").arg(colorHex(sc)));
                    if (sc.alpha() < 255)
                        tAttrs.append(QStringLiteral("stroke-opacity=\"%1\"").arg(fmtNum(colorAlpha01(sc))));
                    tAttrs.append(QStringLiteral("stroke-width=\"%1\"").arg(fmtNum(sw)));
                }
            }
            const QStringList lines = content.split(QLatin1Char('\n'));
            QString el = gOpen + QStringLiteral("<text %1>").arg(tAttrs.join(QLatin1Char(' ')));
            for (int li2 = 0; li2 < lines.size(); ++li2) {
                if (li2 == 0) {
                    el += xmlEscape(lines.at(li2));
                } else {
                    el += QStringLiteral("<tspan x=\"%1\" dy=\"%2\">%3</tspan>")
                              .arg(fmtNum(tx))
                              .arg(fmtNum(size * leading))
                              .arg(xmlEscape(lines.at(li2)));
                }
            }
            el += QStringLiteral("</text></g>");
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
                body.append(gOpen
                    + QStringLiteral("<rect x=\"%1\" y=\"%2\" width=\"%3\" height=\"%4\" fill=\"#d9d9d9\"/></g>")
                          .arg(fmtNum(x))
                          .arg(fmtNum(y))
                          .arg(fmtNum(w))
                          .arg(fmtNum(h)));
                continue;
            }
            const QString href = QStringLiteral("data:%1;base64,%2>")
                                     .arg(mime)
                                     .arg(QString::fromLatin1(bytes.toBase64()));
            // Note: href (SVG2) over xlink:href for modern viewers.
            body.append(gOpen
                + QStringLiteral("<image x=\"%1\" y=\"%2\" width=\"%3\" height=\"%4\" preserveAspectRatio=\"none\"%5 "
                                 "href=\"%6\"/></g>")
                      .arg(fmtNum(x))
                      .arg(fmtNum(y))
                      .arg(fmtNum(w))
                      .arg(fmtNum(h))
                      .arg(clipAttr)
                      .arg(href));
            continue;
        }

        // Vector shapes share the outline builder with the canvas, so
        // silhouettes match the PNG export by construction.
        const Effects::Style st = Effects::Style::fromMap(m);
        const QPainterPath path = Effects::outlinePath(shapeType, QRectF(x, y, w, h),
            Effects::PathOpts::fromMap(m), st, 1.0);
        const QString d = pathToSvg(path);
        if (d.isEmpty())
            continue;
        const bool fills = shapeType != QLatin1String("pen") || st.penFill;
        QString fillAttr = QStringLiteral("fill=\"none\"");
        if (fills) {
            if (st.fillType == QLatin1String("linear")) {
                GradientOut g = gradientFill(m.value(QStringLiteral("fillGradient")).toMap(), QRectF(x, y, w, h),
                    QStringLiteral("svgfg%1").arg(gradSeq++), true);
                defs.append(g.def);
                fillAttr = g.attr;
            } else {
                QColor fc = st.fill;
                if (!fc.isValid())
                    fc = fillFallback();
                fillAttr = solidFillAttr(fc, true);
            }
        }
        QString strokeAttr = QStringLiteral("stroke=\"none\"");
        const double sw = qMax(0.0, st.strokeWidth);
        if (sw > 0.01) {
            if (st.strokeType == QLatin1String("linear")) {
                GradientOut g = gradientFill(m.value(QStringLiteral("strokeGradient")).toMap(), QRectF(x, y, w, h),
                    QStringLiteral("svgsg%1").arg(gradSeq++), false);
                defs.append(g.def);
                strokeAttr = QStringLiteral("%1 stroke-width=\"%2\" stroke-linecap=\"%3\" stroke-linejoin=\"%4\"%5")
                                 .arg(g.attr)
                                 .arg(fmtNum(sw))
                                 .arg(capFor(st.strokeCap))
                                 .arg(joinFor(st.strokeJoin))
                                 .arg(dashAttr(st, sw));
            } else {
                const QColor sc = st.stroke;
                if (sc.isValid() && sc.alpha() > 0) {
                    strokeAttr = QStringLiteral("stroke=\"%1\"").arg(colorHex(sc));
                    if (sc.alpha() < 255)
                        strokeAttr += QStringLiteral(" stroke-opacity=\"%1\"").arg(fmtNum(colorAlpha01(sc)));
                    strokeAttr += QStringLiteral(" stroke-width=\"%1\" stroke-linecap=\"%2\" stroke-linejoin=\"%3\"%4")
                                      .arg(fmtNum(sw))
                                      .arg(capFor(st.strokeCap))
                                      .arg(joinFor(st.strokeJoin))
                                      .arg(dashAttr(st, sw));
                }
            }
        }
        body.append(gOpen
            + QStringLiteral("<path d=\"%1\" %2 %3/></g>").arg(xmlEscape(d)).arg(fillAttr).arg(strokeAttr));
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
