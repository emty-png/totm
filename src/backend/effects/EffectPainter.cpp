#include "EffectPainter.h"

#include "EffectSpec.h"

#include <QDataStream>
#include <QImage>
#include <QIODevice>
#include <QLinearGradient>
#include <QPainterPathStroker>
#include <QtMath>

namespace Effects {

Style Style::fromMap(const QVariantMap &m)
{
    Style st;
    st.fill = colorFrom(m.value(QStringLiteral("fill")), st.fill);
    st.fillType = m.value(QStringLiteral("fillType"), QStringLiteral("solid")).toString();
    st.fillGradient = m.value(QStringLiteral("fillGradient")).toMap();
    st.stroke = colorFrom(m.value(QStringLiteral("stroke")), st.stroke);
    st.strokeType = m.value(QStringLiteral("strokeType"), QStringLiteral("solid")).toString();
    st.strokeGradient = m.value(QStringLiteral("strokeGradient")).toMap();
    st.strokeWidth = qMax(0.0, m.value(QStringLiteral("strokeWidth"), 0.0).toDouble());
    st.radius = qMax(0.0, m.value(QStringLiteral("radius"), 0.0).toDouble());
    return st;
}

PathOpts PathOpts::fromMap(const QVariantMap &m)
{
    PathOpts o;
    o.cornerRadii = m.value(QStringLiteral("cornerRadii")).toList();
    o.points = qBound(3, m.value(QStringLiteral("points"), 5).toInt(), 12);
    o.independentCorners = m.value(QStringLiteral("independentCorners")).toBool();
    o.pathData = m.value(QStringLiteral("pathData")).toList();
    o.ox = m.value(QStringLiteral("x"), 0.0).toDouble();
    o.oy = m.value(QStringLiteral("y"), 0.0).toDouble();
    return o;
}

Shadow Shadow::fromMap(const QVariantMap &m)
{
    Shadow sh;
    sh.enabled = m.value(QStringLiteral("enabled")).toBool();
    sh.inner = m.value(QStringLiteral("inner")).toBool();
    sh.color = colorFrom(m.value(QStringLiteral("color")), sh.color);
    sh.x = m.value(QStringLiteral("x"), 0.0).toDouble();
    sh.y = m.value(QStringLiteral("y"), 4.0).toDouble();
    sh.blur = qMax(0.0, m.value(QStringLiteral("blur"), 8.0).toDouble());
    sh.spread = qMax(0.0, m.value(QStringLiteral("spread"), 0.0).toDouble());
    return sh;
}

QList<Shadow> Shadow::listFrom(const QVariantList &l)
{
    QList<Shadow> out;
    for (const QVariant &v : l) {
        const Shadow sh = Shadow::fromMap(v.toMap());
        if (sh.enabled)
            out.append(sh);
    }
    return out;
}

Blur Blur::fromMap(const QVariantMap &m)
{
    Blur b;
    b.enabled = m.value(QStringLiteral("enabled")).toBool();
    b.radius = qMax(0.0, m.value(QStringLiteral("radius"), 0.0).toDouble());
    b.opacity = qBound(0.0, m.value(QStringLiteral("opacity"), 1.0).toDouble(), 1.0);
    return b;
}

Glow Glow::fromMap(const QVariantMap &m)
{
    Glow g;
    g.enabled = m.value(QStringLiteral("enabled")).toBool();
    g.inner = m.value(QStringLiteral("inner")).toBool();
    g.color = colorFrom(m.value(QStringLiteral("color")), g.color);
    g.blur = qMax(0.0, m.value(QStringLiteral("blur"), 16.0).toDouble());
    g.spread = qMax(0.0, m.value(QStringLiteral("spread"), 0.0).toDouble());
    return g;
}

QList<Glow> Glow::listFrom(const QVariantList &l)
{
    QList<Glow> out;
    for (const QVariant &v : l) {
        const Glow g = Glow::fromMap(v.toMap());
        if (g.enabled)
            out.append(g);
    }
    return out;
}

Grain Grain::fromMap(const QVariantMap &m)
{
    Grain g;
    g.enabled = m.value(QStringLiteral("enabled")).toBool();
    g.amount = qBound(0.0, m.value(QStringLiteral("amount"), 0.5).toDouble(), 1.0);
    g.size = qBound(1.0, m.value(QStringLiteral("size"), 2.0).toDouble(), 10.0);
    return g;
}

uint32_t grainSeed(int uid, int frameNo)
{
    return uint32_t(uid) * 73856093u ^ uint32_t(frameNo) * 19349663u;
}

uint32_t grainHash(uint32_t cx, uint32_t cy, uint32_t seed)
{
    uint32_t h = cx * 374761393u + cy * 668265263u + seed;
    h = (h ^ (h >> 13u)) * 1274126177u;
    h ^= h >> 16u;
    return h;
}

namespace {

// Corner points for pointed shapes in a w*h box at origin.
// Mirrors ShapeGeometry.cornerPoints (star notch ratio 0.4, first tip up).
QList<QPointF> cornerPoints(const QString &kind, int points, double w, double h)
{
    QList<QPointF> pts;
    if (kind == QLatin1String("triangle")) {
        pts << QPointF(w / 2, 0) << QPointF(w, h) << QPointF(0, h);
        return pts;
    }
    const double cx = w / 2.0, cy = h / 2.0;
    for (int k = 0; k < points * 2; ++k) {
        const double a = -M_PI / 2.0 + k * M_PI / points;
        const double rr = (k % 2 == 0) ? 1.0 : 0.4;
        pts << QPointF(cx + w / 2 * rr * qCos(a), cy + h / 2 * rr * qSin(a));
    }
    return pts;
}

double radiusAt(bool independent, const QString &kind, const QVariantList &arr, int i)
{
    if (!independent)
        return -1.0;
    if (kind == QLatin1String("star")) {
        if (i % 2 == 1)
            return 0.0;
        const int tip = i / 2;
        return tip < arr.size() ? qMax(0.0, arr.at(tip).toDouble()) : 0.0;
    }
    return i < arr.size() ? qMax(0.0, arr.at(i).toDouble()) : 0.0;
}

// Per-corner rounded rect in paint coords. Mirrors the video renderer.
QPainterPath rectPath(const QRectF &box, const double r[4])
{
    const double x = box.x(), y = box.y(), w = box.width(), h = box.height();
    QPainterPath d;
    d.moveTo(x + r[0], y);
    d.lineTo(x + w - r[1], y);
    if (r[1] > 0)
        d.quadTo(x + w, y, x + w, y + r[1]);
    else
        d.lineTo(x + w, y);
    d.lineTo(x + w, y + h - r[2]);
    if (r[2] > 0)
        d.quadTo(x + w, y + h, x + w - r[2], y + h);
    else
        d.lineTo(x + w, y + h);
    d.lineTo(x + r[3], y + h);
    if (r[3] > 0)
        d.quadTo(x, y + h, x, y + h - r[3]);
    else
        d.lineTo(x, y + h);
    d.lineTo(x, y + r[0]);
    if (r[0] > 0)
        d.quadTo(x, y, x + r[0], y);
    else
        d.lineTo(x, y);
    d.closeSubpath();
    return d;
}

// Closed polygon with per-vertex rounding. Overclaimed edges share
// proportionally so roundings meet instead of folding over.
QPainterPath roundedPoly(const QString &kind, const QRectF &box, int points, double uniform,
    bool independent, const QVariantList &arr)
{
    const bool tipsOnly = kind == QLatin1String("star");
    const QList<QPointF> local = cornerPoints(kind, points, box.width(), box.height());
    const int n = local.size();
    QList<QPointF> pts;
    for (const QPointF &p : local)
        pts << QPointF(box.x() + p.x(), box.y() + p.y());
    QList<double> cut;
    for (int i = 0; i < n; ++i) {
        const double want = radiusAt(independent, kind, arr, i);
        const double r = want >= 0 ? want : uniform;
        if (r <= 0 || (tipsOnly && i % 2 == 1 && !independent)) {
            cut << 0.0;
            continue;
        }
        const QPointF pv = pts[(i - 1 + n) % n], v = pts[i], nx = pts[(i + 1) % n];
        const double l1 = qHypot(v.x() - pv.x(), v.y() - pv.y());
        const double l2 = qHypot(nx.x() - v.x(), nx.y() - v.y());
        cut << (l1 <= 0 || l2 <= 0 ? 0.0 : qMin(r, qMin(l1, l2)));
    }
    for (int e = 0; e < n; ++e) {
        const int f = e, g = (e + 1) % n;
        const double len = qHypot(pts[g].x() - pts[f].x(), pts[g].y() - pts[f].y());
        const double sum = cut[f] + cut[g];
        if (len > 0 && sum > len) {
            cut[f] *= len / sum;
            cut[g] *= len / sum;
        }
    }
    QPainterPath d;
    for (int j = 0; j < n; ++j) {
        const QPointF q = pts[(j - 1 + n) % n], v = pts[j], e = pts[(j + 1) % n];
        const double m1 = qHypot(v.x() - q.x(), v.y() - q.y());
        const double m2 = qHypot(e.x() - v.x(), e.y() - v.y());
        QPointF a = v, b = v;
        if (cut[j] > 0 && m1 > 0 && m2 > 0) {
            a = QPointF(v.x() - (v.x() - q.x()) / m1 * cut[j], v.y() - (v.y() - q.y()) / m1 * cut[j]);
            b = QPointF(v.x() + (e.x() - v.x()) / m2 * cut[j], v.y() + (e.y() - v.y()) / m2 * cut[j]);
        }
        if (j == 0)
            d.moveTo(a);
        else
            d.lineTo(a);
        if (cut[j] > 0)
            d.quadTo(v, b);
    }
    d.closeSubpath();
    return d;
}

double numKey(const QVariantMap &m, const char *key, double fallback = 0.0)
{
    bool ok = false;
    const double d = m.value(QString::fromLatin1(key)).toDouble(&ok);
    return ok ? d : fallback;
}

// Pen subpaths: anchors stay absolute so moves stay exact; paint lands
// them on origin + (v - nodeOrigin) * s. Mirrors the video renderer.
QPainterPath penPath(const QVariantList &subs, double ox, double oy, double s)
{
    QPainterPath d;
    const auto X = [&](double v) { return ox + v * s; };
    for (const QVariant &sv : subs) {
        const QVariantMap sub = sv.toMap();
        const QVariantList raw = sub.value(QStringLiteral("pts")).toList();
        if (raw.isEmpty())
            continue;
        const QVariantMap p0 = raw.first().toMap();
        d.moveTo(X(numKey(p0, "x")), oy + numKey(p0, "y") * s);
        for (int i = 1; i < raw.size(); ++i) {
            const QVariantMap a = raw.at(i - 1).toMap(), b = raw.at(i).toMap();
            const bool aS = a.value(QStringLiteral("smooth")).toBool();
            const bool bS = b.value(QStringLiteral("smooth")).toBool();
            const double bx = X(numKey(b, "x")), by = oy + numKey(b, "y") * s;
            if (!aS && !bS) {
                d.lineTo(bx, by);
                continue;
            }
            const double ax = X(numKey(a, "x")), ay = oy + numKey(a, "y") * s;
            const double c1x = aS ? X(numKey(a, "outX", numKey(a, "x"))) : ax;
            const double c1y = aS ? oy + numKey(a, "outY", numKey(a, "y")) * s : ay;
            const double c2x = bS ? X(numKey(b, "inX", numKey(b, "x"))) : bx;
            const double c2y = bS ? oy + numKey(b, "inY", numKey(b, "y")) * s : by;
            d.cubicTo(c1x, c1y, c2x, c2y, bx, by);
        }
        if (sub.value(QStringLiteral("closed")).toBool() && raw.size() > 1) {
            const QVariantMap a = raw.last().toMap(), b = raw.first().toMap();
            const bool aS = a.value(QStringLiteral("smooth")).toBool();
            const bool bS = b.value(QStringLiteral("smooth")).toBool();
            const double bx = X(numKey(b, "x")), by = oy + numKey(b, "y") * s;
            if (!aS && !bS) {
                d.lineTo(bx, by);
            } else {
                const double ax = X(numKey(a, "x")), ay = oy + numKey(a, "y") * s;
                const double c1x = aS ? X(numKey(a, "outX", numKey(a, "x"))) : ax;
                const double c1y = aS ? oy + numKey(a, "outY", numKey(a, "y")) * s : ay;
                const double c2x = bS ? X(numKey(b, "inX", numKey(b, "x"))) : bx;
                const double c2y = bS ? oy + numKey(b, "inY", numKey(b, "y")) * s : by;
                d.cubicTo(c1x, c1y, c2x, c2y, bx, by);
            }
            d.closeSubpath();
        }
    }
    return d;
}

QBrush paintBrush(const QRectF &box, const QString &type, const QVariantMap &grad, const QColor &solid)
{
    if (type == QLatin1String("linear")) {
        const LinearSpec spec = linearFrom(grad);
        QPointF p0, p1;
        gradientEndpoints(box, spec.angle, &p0, &p1);
        QLinearGradient g(p0, p1);
        g.setCoordinateMode(QGradient::LogicalMode);
        g.setColorAt(spec.stops[0].pos, spec.stops[0].color);
        g.setColorAt(spec.stops[1].pos, spec.stops[1].color);
        return QBrush(g);
    }
    return QBrush(solid);
}

// Fast separable box blur (3 passes ~= gaussian) on premultiplied data.
// Radius is in device px; kept small by the pad cap.
void blurImageImpl(QImage &img, double radius)
{
    const int r = qBound(0, qRound(radius), 64);
    if (r < 1 || img.isNull())
        return;
    const int w = img.width(), h = img.height();
    QImage tmp(w, h, QImage::Format_ARGB32_Premultiplied);
    for (int pass = 0; pass < 3; ++pass) {
        // Horizontal.
        for (int y = 0; y < h; ++y) {
            const QRgb *src = reinterpret_cast<const QRgb *>(img.constScanLine(y));
            QRgb *dst = reinterpret_cast<QRgb *>(tmp.scanLine(y));
            long sr = 0, sg = 0, sb = 0, sa = 0;
            for (int x = -r; x < w + r; ++x) {
                const int add = qBound(0, x + r, w - 1);
                const QRgb pa = src[add];
                sr += qRed(pa);
                sg += qGreen(pa);
                sb += qBlue(pa);
                sa += qAlpha(pa);
                const int sub = x - r - 1;
                if (sub >= 0) {
                    const QRgb ps = src[sub];
                    sr -= qRed(ps);
                    sg -= qGreen(ps);
                    sb -= qBlue(ps);
                    sa -= qAlpha(ps);
                }
                if (x >= 0 && x < w) {
                    const int n = qMin(x + r, w - 1) - qMax(x - r - 1, -1);
                    dst[x] = qRgba(sr / n, sg / n, sb / n, sa / n);
                }
            }
        }
        // Vertical.
        for (int x = 0; x < w; ++x) {
            long sr = 0, sg = 0, sb = 0, sa = 0;
            for (int y = -r; y < h + r; ++y) {
                const int add = qBound(0, y + r, h - 1);
                const QRgb *row = reinterpret_cast<const QRgb *>(tmp.constScanLine(add));
                sr += qRed(row[x]);
                sg += qGreen(row[x]);
                sb += qBlue(row[x]);
                sa += qAlpha(row[x]);
                const int sub = y - r - 1;
                if (sub >= 0) {
                    const QRgb *srow = reinterpret_cast<const QRgb *>(tmp.constScanLine(sub));
                    sr -= qRed(srow[x]);
                    sg -= qGreen(srow[x]);
                    sb -= qBlue(srow[x]);
                    sa -= qAlpha(srow[x]);
                }
                if (y >= 0 && y < h) {
                    const int n = qMin(y + r, h - 1) - qMax(y - r - 1, -1);
                    QRgb *drow = reinterpret_cast<QRgb *>(img.scanLine(y));
                    drow[x] = qRgba(sr / n, sg / n, sb / n, sa / n);
                }
            }
        }
    }
}

// Geometry fingerprint for blurred-mask caching. Covers exactly the
// silhouette raster inputs (kind, size, corner/star rounding, stroke
// width for the plain-rect inset, pen anchors relative to the node
// origin so pure moves keep the key stable). Fill/stroke colors,
// offsets and tints never enter: they apply after the blur, so
// color/offset-only edits reuse the cached raster bit-for-bit.
QByteArray geometryKey(const QString &kind, double w, double h, const PathOpts &opts, double radius,
    double strokeWidth)
{
    QByteArray bytes;
    QDataStream ds(&bytes, QIODevice::WriteOnly);
    ds.setVersion(QDataStream::Qt_6_0);
    ds << kind << w << h << radius << strokeWidth << opts.independentCorners << opts.points;
    ds << opts.cornerRadii.size();
    for (const QVariant &v : opts.cornerRadii)
        ds << v.toDouble();
    const bool pen = kind == QLatin1String("pen");
    ds << pen;
    if (pen) {
        // Mirror penPath coercions (missing/non-numeric falls back), so
        // key equality implies raster equality. Anchors go relative.
        const auto numRel = [&](const QVariantMap &p, const char *k, double origin, double fallbackAbs) {
            bool ok = false;
            const double v = p.value(QString::fromLatin1(k)).toDouble(&ok);
            ds << (ok ? v - origin : fallbackAbs - origin);
        };
        ds << opts.ox << opts.oy;
        const QVariantList subs = opts.pathData;
        ds << subs.size();
        for (const QVariant &sv : subs) {
            const QVariantMap sub = sv.toMap();
            ds << sub.value(QStringLiteral("closed")).toBool();
            const QVariantList raw = sub.value(QStringLiteral("pts")).toList();
            ds << raw.size();
            for (const QVariant &pv : raw) {
                const QVariantMap p = pv.toMap();
                bool okx = false, oky = false;
                const double px = p.value(QStringLiteral("x")).toDouble(&okx);
                const double py = p.value(QStringLiteral("y")).toDouble(&oky);
                const double ax = okx ? px : 0.0, ay = oky ? py : 0.0;
                ds << (ax - opts.ox) << (ay - opts.oy);
                ds << p.value(QStringLiteral("smooth")).toBool();
                numRel(p, "inX", opts.ox, ax);
                numRel(p, "inY", opts.oy, ay);
                numRel(p, "outX", opts.ox, ax);
                numRel(p, "outY", opts.oy, ay);
            }
        }
    }
    return bytes;
}

QByteArray outerKey(const QByteArray &geom, double spread, double blur, double s)
{
    QByteArray key;
    QDataStream ds(&key, QIODevice::WriteOnly);
    ds.setVersion(QDataStream::Qt_6_0);
    ds << quint8('O') << spread << blur << s << geom;
    return key;
}

QByteArray innerKey(const QByteArray &geom, double spread, double blur, double ox, double oy, double s)
{
    QByteArray key;
    QDataStream ds(&key, QIODevice::WriteOnly);
    ds.setVersion(QDataStream::Qt_6_0);
    ds << quint8('I') << spread << blur << ox << oy << s << geom;
    return key;
}

// Blurred black silhouette for outer halos, shared by shadows and
// glows (same raster; tint and offset apply per entry after). Null
// cache recomputes inline, so export matches preview by construction.
QImage outerMask(const QPainterPath &path, const QByteArray &geom, double spread, double blur, double s,
    QCache<QByteArray, QImage> *cache, QRectF *areaOut)
{
    QPainterPath silhouette = path;
    if (spread * s > 0.01) {
        QPainterPathStroker stroker;
        stroker.setWidth(spread * 2.0 * s);
        stroker.setCapStyle(Qt::RoundCap);
        stroker.setJoinStyle(Qt::RoundJoin);
        silhouette = stroker.createStroke(path).united(path);
    }
    const double m = blur * s * 2.0 + 1.0;
    QRectF area = silhouette.boundingRect();
    area.adjust(-m, -m, m, m);
    if (areaOut)
        *areaOut = area;
    const QByteArray key = outerKey(geom, spread, blur, s);
    if (cache) {
        if (QImage *hit = cache->object(key))
            return *hit;
    }
    const QSize size(qMax(1, qRound(area.width())), qMax(1, qRound(area.height())));
    QImage mask(size, QImage::Format_ARGB32_Premultiplied);
    mask.fill(0);
    {
        QPainter mp(&mask);
        mp.setRenderHint(QPainter::Antialiasing, true);
        mp.translate(-area.topLeft());
        mp.fillPath(silhouette, Qt::black);
    }
    blurImageImpl(mask, blur * s);
    if (cache && !mask.isNull())
        cache->insert(key, new QImage(mask), qMax(1, int(mask.sizeInBytes())));
    return mask;
}

// Blurred shifted eroded silhouette for inner bands. The tinted-shape
// composite stays per paint (cheap); only the blur is memoized.
QImage innerCutter(const QPainterPath &path, const QByteArray &geom, double spread, double blur, double ox,
    double oy, double s, QCache<QByteArray, QImage> *cache, QRectF *areaOut)
{
    QPainterPath eroded = path;
    if (spread * s > 0.01) {
        QPainterPathStroker stroker;
        stroker.setWidth(spread * 2.0 * s);
        stroker.setCapStyle(Qt::RoundCap);
        stroker.setJoinStyle(Qt::RoundJoin);
        eroded = path.subtracted(stroker.createStroke(path));
    }
    const double m = blur * s * 2.0 + 1.0 + qHypot(ox * s, oy * s);
    QRectF area = path.boundingRect();
    area.adjust(-m, -m, m, m);
    if (areaOut)
        *areaOut = area;
    const QByteArray key = innerKey(geom, spread, blur, ox, oy, s);
    if (cache) {
        if (QImage *hit = cache->object(key))
            return *hit;
    }
    const QSize size(qMax(1, qRound(area.width())), qMax(1, qRound(area.height())));
    QImage cutter(size, QImage::Format_ARGB32_Premultiplied);
    cutter.fill(0);
    {
        QPainter mp(&cutter);
        mp.setRenderHint(QPainter::Antialiasing, true);
        mp.translate(-area.topLeft() + QPointF(ox * s, oy * s));
        mp.fillPath(eroded, Qt::black);
    }
    blurImageImpl(cutter, blur * s);
    if (cache && !cutter.isNull())
        cache->insert(key, new QImage(cutter), qMax(1, int(cutter.sizeInBytes())));
    return cutter;
}

} // namespace

namespace {
// Forward: shared tails defined below paintLeaf.
void paintPathShadow(QPainter *pt, const QPainterPath &path, const QRectF &fillBox, const QString &kind,
    const QRectF &box, const PathOpts &opts, const Style &st, const Shadow &sh, double s, double sw,
    double r, bool plainRect);
void paintInner(QPainter *pt, const QPainterPath &path, const Shadow &sh, double s,
    const QByteArray &geom, QCache<QByteArray, QImage> *cache);
// Glow tail (centered halo, no offset term).
void paintPathGlow(QPainter *pt, const QPainterPath &path, const QRectF &fillBox, const Style &st,
    const Glow &glow, double s, double sw);
void paintGlowInner(QPainter *pt, const QPainterPath &path, const Glow &glow, double s,
    const QByteArray &geom, QCache<QByteArray, QImage> *cache);

// Vector outline in device coords plus the fill box the brushes span.
// Shared by the shadow/blur and glow leaves so geometry never drifts.
struct Outline {
    QPainterPath path;
    QRectF fillBox;
    double r = 0.0;
    double sw = 0.0;
    bool plainRect = false;
};
Outline outlineFor(const QString &kind, const QRectF &box, const PathOpts &opts, const Style &st, double s)
{
    Outline o;
    o.sw = qMax(0.0, st.strokeWidth) * s;
    // Plain rects inset the stroke inside the bounds (QML Rectangle
    // parity); vector paths straddle it (ShapePath parity).
    o.plainRect = kind == QLatin1String("rectangle") && !opts.independentCorners;
    o.fillBox = box;
    o.r = qMax(0.0, st.radius) * s;
    if (o.plainRect) {
        if (o.sw > 0.01 && box.width() > o.sw && box.height() > o.sw) {
            const double inset = o.sw / 2.0;
            o.fillBox.adjust(inset, inset, -inset, -inset);
            o.r = qMax(0.0, o.r - inset);
        }
        o.r = qMin(o.r, qMin(o.fillBox.width(), o.fillBox.height()) / 2.0);
        if (o.r <= 0.01)
            o.path.addRect(o.fillBox);
        else
            o.path.addRoundedRect(o.fillBox, o.r, o.r);
        return o;
    }
    if (kind == QLatin1String("ellipse")) {
        o.path.addEllipse(box);
    } else if (kind == QLatin1String("rectangle")) {
        double rr[4] = {0, 0, 0, 0};
        const double cap = qMin(box.width(), box.height()) / 2.0;
        for (int i = 0; i < 4; ++i)
            rr[i] = qMin(i < opts.cornerRadii.size() ? qMax(0.0, opts.cornerRadii.at(i).toDouble()) * s : 0.0, cap);
        o.path = rectPath(box, rr);
    } else if (kind == QLatin1String("triangle") || kind == QLatin1String("star")) {
        const double uniform = qMax(0.0, st.radius) * s;
        QVariantList scaled;
        for (const QVariant &v : opts.cornerRadii)
            scaled << v.toDouble() * s;
        o.path = roundedPoly(kind, box, opts.points, uniform, opts.independentCorners, scaled);
    } else if (kind == QLatin1String("pen")) {
        o.path = penPath(opts.pathData, box.x() - opts.ox * s, box.y() - opts.oy * s, s);
    } else {
        o.path.addRect(box);
    }
    return o;
}
} // namespace

double shadowPad(const Shadow &sh, double strokeWidth)
{
    if (!sh.enabled)
        return 0.0;
    const double pad = sh.spread + sh.blur * 2.0 + qHypot(sh.x, sh.y) + qMax(0.0, strokeWidth);
    return qMin(256.0, qMax(0.0, pad));
}

double blurPad(const Blur &b)
{
    if (!b.enabled)
        return 0.0;
    return qMin(256.0, qMax(0.0, b.radius * 2.0));
}

double shadowsPad(const QList<Shadow> &shadows, double strokeWidth)
{
    double pad = 0.0;
    for (const Shadow &sh : shadows) {
        if (!sh.enabled || sh.inner)
            continue;
        pad = qMax(pad, shadowPad(sh, strokeWidth));
    }
    return pad;
}

double glowsPad(const QList<Glow> &glows)
{
    double pad = 0.0;
    for (const Glow &g : glows) {
        if (!g.enabled || g.inner)
            continue;
        pad = qMax(pad, glowPad(g));
    }
    return pad;
}

double effectPad(const Shadow &sh, const Blur &b, double strokeWidth)
{
    return qMin(256.0, qMax(shadowPad(sh, strokeWidth), blurPad(b)));
}

double effectPad(const Shadow &sh, const Blur &b, const Glow &g, double strokeWidth)
{
    return qMin(256.0, qMax(effectPad(sh, b, strokeWidth), glowPad(g)));
}

double effectPad(const QList<Shadow> &shadows, const QList<Glow> &glows, const Blur &b,
    double strokeWidth)
{
    return qMin(256.0, qMax(shadowsPad(shadows, strokeWidth), qMax(glowsPad(glows), blurPad(b))));
}

void blurImage(QImage &img, double radius)
{
    blurImageImpl(img, radius);
}

void mixBlurred(QImage &sharp, const QImage &blurred, double opacity)
{
    const double k = qBound(0.0, opacity, 1.0);
    if (k <= 0.0 || sharp.isNull() || blurred.isNull())
        return;
    if (k >= 1.0) {
        sharp = blurred.copy();
        return;
    }
    if (sharp.size() != blurred.size())
        return;
    const int w = sharp.width(), h = sharp.height();
    for (int y = 0; y < h; ++y) {
        QRgb *d = reinterpret_cast<QRgb *>(sharp.scanLine(y));
        const QRgb *b = reinterpret_cast<const QRgb *>(blurred.constScanLine(y));
        for (int x = 0; x < w; ++x) {
            const int sa = qAlpha(d[x]), ba = qAlpha(b[x]);
            const int a = qRound(sa + (ba - sa) * k);
            const int r = qRound(qRed(d[x]) + (qRed(b[x]) - qRed(d[x])) * k);
            const int g = qRound(qGreen(d[x]) + (qGreen(b[x]) - qGreen(d[x])) * k);
            const int bl = qRound(qBlue(d[x]) + (qBlue(b[x]) - qBlue(d[x])) * k);
            d[x] = qRgba(r, g, bl, a);
        }
    }
}

QImage grainDots(const QSize &px, double cellD, uint32_t seed, double amount)
{
    QImage out(qMax(1, px.width()), qMax(1, px.height()), QImage::Format_ARGB32_Premultiplied);
    out.fill(0);
    const double cell = qMax(1.0, cellD);
    const double k = qBound(0.0, amount, 1.0);
    if (k <= 0.001)
        return out;
    const uint32_t salt = seed ^ 974634211u;
    for (int y = 0; y < out.height(); ++y) {
        QRgb *row = reinterpret_cast<QRgb *>(out.scanLine(y));
        const uint32_t cy = uint32_t(double(y) / cell);
        for (int x = 0; x < out.width(); ++x) {
            const uint32_t cx = uint32_t(double(x) / cell);
            const uint32_t h1 = grainHash(cx, cy, seed);
            const uint32_t h2 = grainHash(cx, cy, salt);
            // 65535 is odd so pick never lands exactly on 0.5: the GLSL
            // twin compares the same float ratio with the same outcome.
            const bool white = (h1 & 0xffffu) >= 32768u;
            const double b = double(h2 & 0xffffu) / 65535.0;
            const int v = qRound(k * (0.25 + 0.75 * b) * 255.0);
            if (v > 0)
                row[x] = white ? qRgba(v, v, v, v) : qRgba(0, 0, 0, v);
        }
    }
    return out;
}

QPainterPath outlinePath(const QString &kind, const QRectF &box, const PathOpts &opts, const Style &st,
    double scale)
{
    return outlineFor(kind, box, opts, st, scale > 0 ? scale : 1.0).path;
}

void paintGrainPath(QPainter *pt, const QPainterPath &clip, double strokeWidth, const QRectF &dotBox,
    const Grain &gr, int uid, int frameNo, double scale)
{
    if (!pt || !gr.enabled || gr.amount <= 0.001 || dotBox.width() <= 0 || dotBox.height() <= 0)
        return;
    const double s = scale > 0 ? scale : 1.0;
    QPainterPath area = clip;
    // Stroke straddles the path (non-plain shapes): union it in so the
    // outer hairline grains like the fill. Mirrors the preview mask,
    // which strokes its silhouette the same way.
    if (strokeWidth * s > 0.01) {
        QPainterPathStroker stroker;
        stroker.setWidth(qMax(0.0, strokeWidth) * s);
        stroker.setCapStyle(Qt::RoundCap);
        stroker.setJoinStyle(Qt::RoundJoin);
        area = stroker.createStroke(clip).united(clip);
    }
    QImage dots = grainDots(QSize(qMax(1, qRound(dotBox.width())), qMax(1, qRound(dotBox.height()))),
        qMax(1.0, gr.size * s), grainSeed(uid, frameNo), gr.amount);
    pt->save();
    pt->setClipPath(area, Qt::IntersectClip);
    pt->drawImage(dotBox.topLeft(), dots);
    pt->restore();
}

void paintLeaf(QPainter *pt, const QString &kind, const QRectF &box, const PathOpts &opts,
    const Style &st, const Shadow &sh, const Blur &layerBlur, double scale)
{
    if (!pt || box.width() <= 0 || box.height() <= 0)
        return;
    // Layer blur (single-effect: shadow stays off): render sharp
    // offscreen, blur a copy, mix by opacity, then composite. Margin
    // keeps the blur from clipping; pad from effectPad covers it.
    if (layerBlur.enabled && layerBlur.radius > 0.01) {
        const double s = scale > 0 ? scale : 1.0;
        const double rad = qMax(0.0, layerBlur.radius) * s;
        const double margin = qMin(256.0, rad * 2.0) + 1.0;
        const QSize tsz(qMax(1, qRound(box.width() + margin * 2.0)), qMax(1, qRound(box.height() + margin * 2.0)));
        QImage sharp(tsz, QImage::Format_ARGB32_Premultiplied);
        sharp.fill(0);
        {
            QPainter tp(&sharp);
            tp.setRenderHint(QPainter::Antialiasing, true);
            tp.translate(-box.topLeft() + QPointF(margin, margin));
            Shadow off;
            paintLeaf(&tp, kind, box, opts, st, off, scale);
        }
        QImage blurred = sharp.copy();
        blurImageImpl(blurred, rad);
        mixBlurred(sharp, blurred, layerBlur.opacity);
        pt->drawImage(box.topLeft() - QPointF(margin, margin), sharp);
        return;
    }
    const double s = scale > 0 ? scale : 1.0;
    const Outline o = outlineFor(kind, box, opts, st, s);
    paintPathShadow(pt, o.path, o.fillBox, kind, box, opts, st, sh, s, o.sw, o.r, o.plainRect);
}

void paintLeaf(QPainter *pt, const QString &kind, const QRectF &box, const PathOpts &opts,
    const Style &st, const Shadow &sh, double scale)
{
    Blur off;
    paintLeaf(pt, kind, box, opts, st, sh, off, scale);
}

double glowPad(const Glow &g)
{
    if (!g.enabled)
        return 0.0;
    return qMin(256.0, qMax(0.0, g.spread + g.blur * 2.0));
}

void paintLeaf(QPainter *pt, const QString &kind, const QRectF &box, const PathOpts &opts,
    const Style &st, const Glow &glow, double scale)
{
    if (!pt || box.width() <= 0 || box.height() <= 0)
        return;
    const double s = scale > 0 ? scale : 1.0;
    const Outline o = outlineFor(kind, box, opts, st, s);
    paintPathGlow(pt, o.path, o.fillBox, st, glow, s, o.sw);
}

namespace {

// Shared tail: outer shadow under the shape, then fill, then the inner
// shadow above the fill (Figma order), then the stroke on top.
void paintPathShadow(QPainter *pt, const QPainterPath &path, const QRectF &fillBox, const QString &kind,
    const QRectF &box, const PathOpts &opts, const Style &st, const Shadow &sh, double s, double sw,
    double r, bool plainRect)
{
    Q_UNUSED(kind);
    Q_UNUSED(box);
    Q_UNUSED(opts);
    Q_UNUSED(r);
    Q_UNUSED(plainRect);
    if (sh.enabled && !sh.inner) {
        QPainterPath silhouette = path;
        if (sh.spread * s > 0.01) {
            QPainterPathStroker stroker;
            stroker.setWidth(sh.spread * 2.0 * s);
            stroker.setCapStyle(Qt::RoundCap);
            stroker.setJoinStyle(Qt::RoundJoin);
            silhouette = stroker.createStroke(path).united(path);
        }
        const double m = sh.blur * s * 2.0 + 1.0;
        QRectF area = silhouette.boundingRect();
        area.adjust(-m, -m, m, m);
        const QSize size(qMax(1, qRound(area.width())), qMax(1, qRound(area.height())));
        QImage mask(size, QImage::Format_ARGB32_Premultiplied);
        mask.fill(0);
        {
            QPainter mp(&mask);
            mp.setRenderHint(QPainter::Antialiasing, true);
            mp.translate(-area.topLeft());
            mp.fillPath(silhouette, Qt::black);
        }
        blurImageImpl(mask, sh.blur * s);
        {
            QPainter mp(&mask);
            mp.setCompositionMode(QPainter::CompositionMode_SourceIn);
            mp.fillRect(mask.rect(), sh.color);
        }
        pt->drawImage(area.topLeft() + QPointF(sh.x * s, sh.y * s), mask);
    }
    pt->fillPath(path, paintBrush(fillBox, st.fillType, st.fillGradient, st.fill));
    if (sh.enabled && sh.inner)
        paintInner(pt, path, sh, s, QByteArray(), nullptr);
    if (sw > 0.01) {
        const QBrush sb = paintBrush(fillBox, st.strokeType, st.strokeGradient, st.stroke);
        pt->setPen(QPen(sb, sw, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        pt->setBrush(Qt::NoBrush);
        pt->drawPath(path);
    }
}

// Inner shadow: tinted shape with the blurred shifted silhouette erased
// out of it, leaving a soft band at the edges (CSS inset semantics: a
// +Y offset darkens the top inside edge). Spread erodes the erased copy
// so the band thickens toward the center. Open paths use their fill
// silhouette, which can read oddly (accepted v1 behavior).
void paintInner(QPainter *pt, const QPainterPath &path, const Shadow &sh, double s,
    const QByteArray &geom, QCache<QByteArray, QImage> *cache)
{
    QRectF area;
    const QImage cutter = innerCutter(path, geom, sh.spread, sh.blur, sh.x, sh.y, s, cache, &area);
    const QSize size(qMax(1, qRound(area.width())), qMax(1, qRound(area.height())));
    // Tinted shape minus the blurred copy: the edge band. The cutter is
    // area-sized with content baked at mask coords, so the shape
    // translate must come off before drawing it (drawImage honors the
    // world transform: leaving it on misaligns the erase by the margin
    // and the tint survives almost whole, i.e. a black shape).
    QImage mask(size, QImage::Format_ARGB32_Premultiplied);
    mask.fill(0);
    {
        QPainter mp(&mask);
        mp.setRenderHint(QPainter::Antialiasing, true);
        mp.translate(-area.topLeft());
        mp.fillPath(path, sh.color);
        mp.setCompositionMode(QPainter::CompositionMode_DestinationOut);
        mp.resetTransform();
        mp.drawImage(0, 0, cutter);
    }
    pt->drawImage(area.topLeft(), mask);
}

// Shared tail for glow leaves: centered halo (outer under the shape,
// inner above the fill like Figma), then the stroke on top. Spread
// dilates the silhouette before blur; with zero blur and spread the
// halo hugs the edge exactly.
void paintPathGlow(QPainter *pt, const QPainterPath &path, const QRectF &fillBox, const Style &st,
    const Glow &glow, double s, double sw)
{
    if (glow.enabled && !glow.inner) {
        QPainterPath silhouette = path;
        if (glow.spread * s > 0.01) {
            QPainterPathStroker stroker;
            stroker.setWidth(glow.spread * 2.0 * s);
            stroker.setCapStyle(Qt::RoundCap);
            stroker.setJoinStyle(Qt::RoundJoin);
            silhouette = stroker.createStroke(path).united(path);
        }
        const double m = glow.blur * s * 2.0 + 1.0;
        QRectF area = silhouette.boundingRect();
        area.adjust(-m, -m, m, m);
        const QSize size(qMax(1, qRound(area.width())), qMax(1, qRound(area.height())));
        QImage mask(size, QImage::Format_ARGB32_Premultiplied);
        mask.fill(0);
        {
            QPainter mp(&mask);
            mp.setRenderHint(QPainter::Antialiasing, true);
            mp.translate(-area.topLeft());
            mp.fillPath(silhouette, Qt::black);
        }
        blurImageImpl(mask, glow.blur * s);
        {
            QPainter mp(&mask);
            mp.setCompositionMode(QPainter::CompositionMode_SourceIn);
            mp.fillRect(mask.rect(), glow.color);
        }
        pt->drawImage(area.topLeft(), mask);
    }
    pt->fillPath(path, paintBrush(fillBox, st.fillType, st.fillGradient, st.fill));
    if (glow.enabled && glow.inner)
        paintGlowInner(pt, path, glow, s, QByteArray(), nullptr);
    if (sw > 0.01) {
        const QBrush sb = paintBrush(fillBox, st.strokeType, st.strokeGradient, st.stroke);
        pt->setPen(QPen(sb, sw, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        pt->setBrush(Qt::NoBrush);
        pt->drawPath(path);
    }
}

// Inner glow: same edge-band construction as the inner shadow but
// centered (no offset), so the halo reads evenly on all inside edges.
void paintGlowInner(QPainter *pt, const QPainterPath &path, const Glow &glow, double s,
    const QByteArray &geom, QCache<QByteArray, QImage> *cache)
{
    QRectF area;
    const QImage cutter = innerCutter(path, geom, glow.spread, glow.blur, 0.0, 0.0, s, cache, &area);
    const QSize size(qMax(1, qRound(area.width())), qMax(1, qRound(area.height())));
    QImage mask(size, QImage::Format_ARGB32_Premultiplied);
    mask.fill(0);
    {
        QPainter mp(&mask);
        mp.setRenderHint(QPainter::Antialiasing, true);
        mp.translate(-area.topLeft());
        mp.fillPath(path, glow.color);
        mp.setCompositionMode(QPainter::CompositionMode_DestinationOut);
        mp.resetTransform();
        mp.drawImage(0, 0, cutter);
    }
    pt->drawImage(area.topLeft(), mask);
}

void paintOuterShadow(QPainter *pt, const QPainterPath &path, const Shadow &sh, double s,
    const QByteArray &geom, QCache<QByteArray, QImage> *cache)
{
    if (!sh.enabled || sh.inner)
        return;
    QRectF area;
    QImage mask = outerMask(path, geom, sh.spread, sh.blur, s, cache, &area);
    {
        QPainter mp(&mask);
        mp.setCompositionMode(QPainter::CompositionMode_SourceIn);
        mp.fillRect(mask.rect(), sh.color);
    }
    pt->drawImage(area.topLeft() + QPointF(sh.x * s, sh.y * s), mask);
}

void paintOuterGlow(QPainter *pt, const QPainterPath &path, const Glow &glow, double s,
    const QByteArray &geom, QCache<QByteArray, QImage> *cache)
{
    if (!glow.enabled || glow.inner)
        return;
    QRectF area;
    QImage mask = outerMask(path, geom, glow.spread, glow.blur, s, cache, &area);
    {
        QPainter mp(&mask);
        mp.setCompositionMode(QPainter::CompositionMode_SourceIn);
        mp.fillRect(mask.rect(), glow.color);
    }
    pt->drawImage(area.topLeft(), mask);
}

} // namespace

// Stacked leaf: outer shadows -> outer glows -> fill -> inner shadows
// -> inner glows -> stroke, then layer-blur mixes the whole stack.
// Lists paint index 0 topmost, so outers iterate last-to-first and
// inners do the same (0 paints last, closest to the top).
void paintLeaf(QPainter *pt, const QString &kind, const QRectF &box, const PathOpts &opts,
    const Style &st, const QList<Shadow> &shadows, const QList<Glow> &glows, const Blur &layerBlur,
    double scale, QCache<QByteArray, QImage> *maskCache)
{
    if (!pt || box.width() <= 0 || box.height() <= 0)
        return;
    if (layerBlur.enabled && layerBlur.radius > 0.01) {
        const double s = scale > 0 ? scale : 1.0;
        const double rad = qMax(0.0, layerBlur.radius) * s;
        const double margin = qMin(256.0, rad * 2.0) + 1.0;
        const QSize tsz(qMax(1, qRound(box.width() + margin * 2.0)), qMax(1, qRound(box.height() + margin * 2.0)));
        QImage sharp(tsz, QImage::Format_ARGB32_Premultiplied);
        sharp.fill(0);
        {
            QPainter tp(&sharp);
            tp.setRenderHint(QPainter::Antialiasing, true);
            tp.translate(-box.topLeft() + QPointF(margin, margin));
            Blur off;
            paintLeaf(&tp, kind, box, opts, st, shadows, glows, off, scale, maskCache);
        }
        QImage blurred = sharp.copy();
        blurImageImpl(blurred, rad);
        mixBlurred(sharp, blurred, layerBlur.opacity);
        pt->drawImage(box.topLeft() - QPointF(margin, margin), sharp);
        return;
    }
    const double s = scale > 0 ? scale : 1.0;
    const Outline o = outlineFor(kind, box, opts, st, s);
    // Silhouette fingerprint: blurred masks memoize on this while tints
    // and offsets stay per paint, so stacked siblings and offset/color
    // edits reuse the raster bit-for-bit.
    const QByteArray geom = geometryKey(kind, box.width(), box.height(), opts, st.radius, st.strokeWidth);
    for (int i = shadows.size() - 1; i >= 0; --i)
        paintOuterShadow(pt, o.path, shadows.at(i), s, geom, maskCache);
    for (int i = glows.size() - 1; i >= 0; --i)
        paintOuterGlow(pt, o.path, glows.at(i), s, geom, maskCache);
    pt->fillPath(o.path, paintBrush(o.fillBox, st.fillType, st.fillGradient, st.fill));
    for (int i = shadows.size() - 1; i >= 0; --i) {
        const Shadow &sh = shadows.at(i);
        if (sh.enabled && sh.inner)
            paintInner(pt, o.path, sh, s, geom, maskCache);
    }
    for (int i = glows.size() - 1; i >= 0; --i) {
        const Glow &g = glows.at(i);
        if (g.enabled && g.inner)
            paintGlowInner(pt, o.path, g, s, geom, maskCache);
    }
    if (o.sw > 0.01) {
        const QBrush sb = paintBrush(o.fillBox, st.strokeType, st.strokeGradient, st.stroke);
        pt->setPen(QPen(sb, o.sw, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        pt->setBrush(Qt::NoBrush);
        pt->drawPath(o.path);
    }
}

} // namespace Effects
