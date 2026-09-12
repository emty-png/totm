#include "EffectPainter.h"

#include "EffectSpec.h"

#include <QImage>
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
void blurImage(QImage &img, double radius)
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

} // namespace

namespace {
// Forward: shared tail defined below paintLeaf.
void paintPathShadow(QPainter *pt, const QPainterPath &path, const QRectF &fillBox, const QString &kind,
    const QRectF &box, const PathOpts &opts, const Style &st, const Shadow &sh, double s, double sw,
    double r, bool plainRect);
void paintInner(QPainter *pt, const QPainterPath &path, const Shadow &sh, double s);
} // namespace

double shadowPad(const Shadow &sh, double strokeWidth)
{
    if (!sh.enabled)
        return 0.0;
    const double pad = sh.spread + sh.blur * 2.0 + qHypot(sh.x, sh.y) + qMax(0.0, strokeWidth);
    return qMin(256.0, qMax(0.0, pad));
}

void paintLeaf(QPainter *pt, const QString &kind, const QRectF &box, const PathOpts &opts,
    const Style &st, const Shadow &sh, double scale)
{
    if (!pt || box.width() <= 0 || box.height() <= 0)
        return;
    const double s = scale > 0 ? scale : 1.0;
    const double sw = qMax(0.0, st.strokeWidth) * s;

    // Outline in device coords. Plain rects inset the stroke inside the
    // bounds (QML Rectangle parity); vector paths straddle it (ShapePath
    // parity, like the video renderer).
    const bool plainRect = kind == QLatin1String("rectangle") && !opts.independentCorners;
    QRectF fillBox = box;
    double r = qMax(0.0, st.radius) * s;
    QPainterPath path;
    if (plainRect) {
        if (sw > 0.01 && box.width() > sw && box.height() > sw) {
            const double inset = sw / 2.0;
            fillBox.adjust(inset, inset, -inset, -inset);
            r = qMax(0.0, r - inset);
        }
        r = qMin(r, qMin(fillBox.width(), fillBox.height()) / 2.0);
        if (r <= 0.01)
            path.addRect(fillBox);
        else
            path.addRoundedRect(fillBox, r, r);
        paintPathShadow(pt, path, fillBox, kind, box, opts, st, sh, s, sw, r, plainRect);
        return;
    }
    if (kind == QLatin1String("ellipse")) {
        path.addEllipse(box);
    } else if (kind == QLatin1String("rectangle")) {
        double rr[4] = {0, 0, 0, 0};
        const double cap = qMin(box.width(), box.height()) / 2.0;
        for (int i = 0; i < 4; ++i)
            rr[i] = qMin(i < opts.cornerRadii.size() ? qMax(0.0, opts.cornerRadii.at(i).toDouble()) * s : 0.0, cap);
        path = rectPath(box, rr);
    } else if (kind == QLatin1String("triangle") || kind == QLatin1String("star")) {
        const double uniform = qMax(0.0, st.radius) * s;
        QVariantList scaled;
        for (const QVariant &v : opts.cornerRadii)
            scaled << v.toDouble() * s;
        path = roundedPoly(kind, box, opts.points, uniform, opts.independentCorners, scaled);
    } else if (kind == QLatin1String("pen")) {
        path = penPath(opts.pathData, box.x() - opts.ox * s, box.y() - opts.oy * s, s);
    } else {
        path.addRect(box);
    }
    paintPathShadow(pt, path, box, kind, box, opts, st, sh, s, sw, r, plainRect);
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
        blurImage(mask, sh.blur * s);
        {
            QPainter mp(&mask);
            mp.setCompositionMode(QPainter::CompositionMode_SourceIn);
            mp.fillRect(mask.rect(), sh.color);
        }
        pt->drawImage(area.topLeft() + QPointF(sh.x * s, sh.y * s), mask);
    }
    pt->fillPath(path, paintBrush(fillBox, st.fillType, st.fillGradient, st.fill));
    if (sh.enabled && sh.inner)
        paintInner(pt, path, sh, s);
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
void paintInner(QPainter *pt, const QPainterPath &path, const Shadow &sh, double s)
{
    QPainterPath eroded = path;
    if (sh.spread * s > 0.01) {
        QPainterPathStroker stroker;
        stroker.setWidth(sh.spread * 2.0 * s);
        stroker.setCapStyle(Qt::RoundCap);
        stroker.setJoinStyle(Qt::RoundJoin);
        eroded = path.subtracted(stroker.createStroke(path));
    }
    const double m = sh.blur * s * 2.0 + 1.0 + qHypot(sh.x * s, sh.y * s);
    QRectF area = path.boundingRect();
    area.adjust(-m, -m, m, m);
    const QSize size(qMax(1, qRound(area.width())), qMax(1, qRound(area.height())));
    // Blurred shifted silhouette: the eraser.
    QImage cutter(size, QImage::Format_ARGB32_Premultiplied);
    cutter.fill(0);
    {
        QPainter mp(&cutter);
        mp.setRenderHint(QPainter::Antialiasing, true);
        mp.translate(-area.topLeft() + QPointF(sh.x * s, sh.y * s));
        mp.fillPath(eroded, Qt::black);
    }
    blurImage(cutter, sh.blur * s);
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

} // namespace

} // namespace Effects
