#include "AnimSampler.h"

#include <QPointF>
#include <QtMath>

#include <algorithm>
#include <functional>

namespace Anims {

double num(const QVariantMap &m, const char *key, double fallback) {
    const QVariant v = m.value(QString::fromLatin1(key));
    bool ok = false;
    const double d = v.toDouble(&ok);
    return ok ? d : fallback;
}

QString str(const QVariantMap &m, const char *key, const QString &fallback) {
    const QVariant v = m.value(QString::fromLatin1(key));
    return v.isValid() ? v.toString() : fallback;
}

double cubicBezier(double x1, double y1, double x2, double y2, double x) {
    if (x <= 0.0)
        return 0.0;
    if (x >= 1.0)
        return 1.0;
    double s = x;
    bool converged = false;
    for (int i = 0; i < 8; ++i) {
        const double u = 1.0 - s;
        const double xs = 3 * u * u * s * x1 + 3 * u * s * s * x2 + s * s * s;
        const double dx = 3 * u * u * x1 + 6 * u * s * (x2 - x1) + 3 * s * s * (1 - x2);
        if (qAbs(xs - x) < 1e-6) {
            converged = true;
            break;
        }
        if (qAbs(dx) < 1e-6)
            break;
        s = s - (xs - x) / dx;
        if (s < 0.0 || s > 1.0)
            break;
    }
    if (!converged) {
        double lo = 0.0, hi = 1.0;
        s = qBound(0.0, s, 1.0);
        for (int j = 0; j < 24; ++j) {
            const double v = 1.0 - s;
            const double xsv = 3 * v * v * s * x1 + 3 * v * s * s * x2 + s * s * s;
            if (qAbs(xsv - x) < 1e-6)
                break;
            if (xsv < x)
                lo = s;
            else
                hi = s;
            s = (lo + hi) / 2;
        }
    }
    const double w = 1.0 - s;
    return 3 * w * w * s * y1 + 3 * w * s * s * y2 + s * s * s;
}

double easeValue(const QString &id, const QVariantList &bezier, double t) {
    const double x = qBound(0.0, t, 1.0);
    if (id == QLatin1String("linear"))
        return x;
    if (id == QLatin1String("easeIn"))
        return x * x * x;
    if (id == QLatin1String("easeOut")) {
        const double u = 1.0 - x;
        return 1.0 - u * u * u;
    }
    if (id == QLatin1String("easeInOut"))
        return x < 0.5 ? 4 * x * x * x : 1.0 - qPow(-2.0 * x + 2.0, 3.0) / 2.0;
    if (id == QLatin1String("custom")) {
        const double b0 = bezier.size() > 0 ? bezier.at(0).toDouble() : 0.25;
        const double b1 = bezier.size() > 1 ? bezier.at(1).toDouble() : 0.1;
        const double b2 = bezier.size() > 2 ? bezier.at(2).toDouble() : 0.25;
        const double b3 = bezier.size() > 3 ? bezier.at(3).toDouble() : 1.0;
        return cubicBezier(b0, b1, b2, b3, x);
    }
    if (id == QLatin1String("slowDown"))
        return cubicBezier(0.22, 1.0, 0.36, 1.0, x);
    return x;
}

PathSample samplePath(const QVariantList &pts, bool closed, double e) {
    PathSample out;
    if (pts.size() < 2)
        return out;
    struct Seg {
        QVariantMap a, b;
    };
    QList<Seg> segs;
    const int count = closed ? pts.size() : pts.size() - 1;
    for (int i = 0; i < count; ++i)
        segs.append({pts.at(i).toMap(), pts.at((i + 1) % pts.size()).toMap()});
    struct Flat {
        double x0, y0, x1, y1, tx, ty, len;
    };
    QList<Flat> flat;
    const int steps = 16;
    auto cubicPoint = [](const QVariantMap &a, const QVariantMap &b, double t, double &x, double &y, double &tx, double &ty) {
        const double ax = num(a, "x"), ay = num(a, "y");
        const double bx = num(b, "x"), by = num(b, "y");
        const bool aS = a.value(QStringLiteral("smooth")).toBool();
        const bool bS = b.value(QStringLiteral("smooth")).toBool();
        if (!aS && !bS) {
            x = ax + (bx - ax) * t;
            y = ay + (by - ay) * t;
            tx = bx - ax;
            ty = by - ay;
            return;
        }
        const double c1x = aS ? num(a, "outX", ax) : ax;
        const double c1y = aS ? num(a, "outY", ay) : ay;
        const double c2x = bS ? num(b, "inX", bx) : bx;
        const double c2y = bS ? num(b, "inY", by) : by;
        const double u = 1.0 - t;
        x = u * u * u * ax + 3 * u * u * t * c1x + 3 * u * t * t * c2x + t * t * t * bx;
        y = u * u * u * ay + 3 * u * u * t * c1y + 3 * u * t * t * c2y + t * t * t * by;
        tx = 3 * u * u * (c1x - ax) + 6 * u * t * (c2x - c1x) + 3 * t * t * (bx - c2x);
        ty = 3 * u * u * (c1y - ay) + 6 * u * t * (c2y - c1y) + 3 * t * t * (by - c2y);
    };
    for (const Seg &s : segs) {
        for (int k = 0; k < steps; ++k) {
            double x0, y0, tx0, ty0, x1, y1, tx1, ty1;
            cubicPoint(s.a, s.b, double(k) / steps, x0, y0, tx0, ty0);
            cubicPoint(s.a, s.b, double(k + 1) / steps, x1, y1, tx1, ty1);
            flat.append({x0, y0, x1, y1, tx1, ty1, qHypot(x1 - x0, y1 - y0)});
        }
    }
    double total = 0.0;
    for (const Flat &f : flat)
        total += f.len;
    if (total <= 0.0) {
        out.valid = true;
        out.dx = num(pts.at(0).toMap(), "x");
        out.dy = num(pts.at(0).toMap(), "y");
        return out;
    }
    const double target = qBound(0.0, e, 1.0) * total;
    double acc = 0.0, prev = 0.0;
    Flat at = flat.last();
    for (const Flat &f : flat) {
        prev = acc;
        acc += f.len;
        if (acc >= target) {
            at = f;
            break;
        }
    }
    const double segLen = at.len > 0.0 ? at.len : 1.0;
    const double f = qBound(0.0, (target - prev) / segLen, 1.0);
    out.valid = true;
    out.dx = at.x0 + (at.x1 - at.x0) * f;
    out.dy = at.y0 + (at.y1 - at.y0) * f;
    const Flat &start = flat.first();
    double delta = qRadiansToDegrees(qAtan2(at.ty, at.tx)) - qRadiansToDegrees(qAtan2(start.ty, start.tx));
    while (delta > 180.0)
        delta -= 360.0;
    while (delta < -180.0)
        delta += 360.0;
    if (qHypot(at.tx, at.ty) < 1e-6 || qHypot(start.tx, start.ty) < 1e-6)
        delta = 0.0;
    out.angleDelta = delta;
    return out;
}

bool parseHex(const QString &hex, int &r, int &g, int &b) {
    QString t = hex.trimmed().toLower();
    if (t.startsWith(QLatin1Char('#')))
        t = t.mid(1);
    if (t.size() == 3)
        t = QString() + t[0] + t[0] + t[1] + t[1] + t[2] + t[2];
    if (t.size() != 6)
        return false;
    bool ok = false;
    r = t.mid(0, 2).toInt(&ok, 16);
    if (!ok)
        return false;
    g = t.mid(2, 2).toInt(&ok, 16);
    if (!ok)
        return false;
    b = t.mid(4, 2).toInt(&ok, 16);
    return ok;
}

QString lerpColor(const QString &from, const QString &to, double t) {
    int ar, ag, ab, br, bg, bb;
    if (!parseHex(from, ar, ag, ab) || !parseHex(to, br, bg, bb))
        return {};
    const auto hx = [](double v) {
        return QString::number(qBound(0, qRound(v), 255), 16).rightJustified(2, QLatin1Char('0'));
    };
    const double k = qBound(0.0, t, 1.0);
    return QLatin1Char('#') + hx(ar + (br - ar) * k) + hx(ag + (bg - ag) * k) + hx(ab + (bb - ab) * k);
}

bool parseHexA(const QString &hex, int &a, int &r, int &g, int &b)
{
    QString t = hex.trimmed().toLower();
    if (t.startsWith(QLatin1Char('#')))
        t = t.mid(1);
    if (t.size() == 3)
        t = QString() + t[0] + t[0] + t[1] + t[1] + t[2] + t[2];
    bool ok = false;
    if (t.size() == 8) {
        a = t.mid(0, 2).toInt(&ok, 16);
        if (!ok)
            return false;
        t = t.mid(2);
    } else if (t.size() == 6) {
        a = 255;
    } else {
        return false;
    }
    r = t.mid(0, 2).toInt(&ok, 16);
    if (!ok)
        return false;
    g = t.mid(2, 2).toInt(&ok, 16);
    if (!ok)
        return false;
    b = t.mid(4, 2).toInt(&ok, 16);
    return ok;
}

QString lerpColorA(const QString &from, const QString &to, double t)
{
    int aa, ar, ag, ab, ba, br, bg, bb;
    if (!parseHexA(from, aa, ar, ag, ab) || !parseHexA(to, ba, br, bg, bb))
        return {};
    const auto hx = [](double v) {
        return QString::number(qBound(0, qRound(v), 255), 16).rightJustified(2, QLatin1Char('0'));
    };
    const double k = qBound(0.0, t, 1.0);
    const int a = qBound(0, qRound(aa + (ba - aa) * k), 255);
    QString out = QStringLiteral("#");
    if (a < 255)
        out += hx(a);
    return out + hx(ar + (br - ar) * k) + hx(ag + (bg - ag) * k) + hx(ab + (bb - ab) * k);
}

namespace {
QPointF slideVec(const QString &direction) {
    if (direction == QLatin1String("right"))
        return {1, 0};
    if (direction == QLatin1String("up"))
        return {0, -1};
    if (direction == QLatin1String("down"))
        return {0, 1};
    return {-1, 0};
}
} // namespace

QVariantMap presetOverlay(const QString &preset, const QString &mode, const QVariantMap &o,
    const QVariantMap &base, double cx, double cy, double e, double p) {
    QVariantMap out;
    const bool inward = mode != QLatin1String("out");
    const double baseOpacity = num(base, "opacity", 1.0);
    const double bx = num(base, "x"), by = num(base, "y");
    const double bw = num(base, "w"), bh = num(base, "h");
    const QString shapeType = str(base, "shapeType", str(base, "type", QStringLiteral("rectangle")));
    if (preset == QLatin1String("appear")) {
        out[QStringLiteral("opacity")] = baseOpacity * (inward ? (p <= 0 ? 0.0 : 1.0) : (p >= 1 ? 0.0 : 1.0));
    } else if (preset == QLatin1String("fade")) {
        out[QStringLiteral("opacity")] = baseOpacity * (inward ? e : 1.0 - e);
    } else if (preset == QLatin1String("slide") || preset == QLatin1String("movescale")) {
        const QPointF d = slideVec(str(o, "direction", QStringLiteral("left")));
        const double dist = qMax(0.0, num(o, "distance"));
        const double k = inward ? 1.0 - e : e;
        const double sgn = inward ? -1.0 : 1.0;
        double nx = bx, ny = by, nw = bw, nh = bh;
        if (preset == QLatin1String("movescale")) {
            const double s0 = qMax(0.0, num(o, "scale", 0.0) / 100.0);
            const double s = inward ? s0 + (1.0 - s0) * e : 1.0 + (s0 - 1.0) * e;
            const double sc = qMax(0.001, s);
            nx = cx + (bx - cx) * sc;
            ny = cy + (by - cy) * sc;
            nw = qMax(0.01, bw * sc);
            nh = qMax(0.01, bh * sc);
        }
        out[QStringLiteral("x")] = nx + sgn * d.x() * dist * k;
        out[QStringLiteral("y")] = ny + sgn * d.y() * dist * k;
        if (preset == QLatin1String("movescale") || o.value(QStringLiteral("fade")).toBool()) {
            out[QStringLiteral("opacity")] = baseOpacity * (inward ? e : 1.0 - e);
        }
        if (preset == QLatin1String("movescale")) {
            out[QStringLiteral("w")] = nw;
            out[QStringLiteral("h")] = nh;
        }
    } else if (preset == QLatin1String("grow") || preset == QLatin1String("shrink")) {
        const double end = preset == QLatin1String("grow") ? 0.0 : 1.5;
        // Parity: QML clamps only the box; glyphs use the raw factor, so
        // both are preserved here.
        const double raw = inward ? end + (1.0 - end) * e : 1.0 + (end - 1.0) * e;
        const double sc = qMax(0.001, raw);
        out[QStringLiteral("x")] = cx + (bx - cx) * sc;
        out[QStringLiteral("y")] = cy + (by - cy) * sc;
        out[QStringLiteral("w")] = qMax(0.01, bw * sc);
        out[QStringLiteral("h")] = qMax(0.01, bh * sc);
        if (shapeType == QLatin1String("text") && num(base, "fontSize") > 0)
            out[QStringLiteral("fontSize")] = num(base, "fontSize") * raw;
    } else if (preset == QLatin1String("spin")) {
        const double turns = qBound(0.25, num(o, "turns", 1.0), 10.0);
        const double dir = str(o, "direction") == QLatin1String("ccw") ? -1.0 : 1.0;
        out[QStringLiteral("rotation")] = num(base, "rotation") + dir * 360.0 * turns * (inward ? 1.0 - e : e);
    } else if (preset == QLatin1String("twist")) {
        const double dir = str(o, "direction") == QLatin1String("ccw") ? -1.0 : 1.0;
        const double env = inward ? 1.0 - p : p;
        out[QStringLiteral("rotation")] = num(base, "rotation") + dir * 15.0 * qSin(p * 4.0 * M_PI) * env;
    } else if (preset == QLatin1String("customScale")) {
        const double raw = num(o, "from") + (num(o, "to") - num(o, "from")) * e;
        const double sc = qMax(0.001, raw);
        out[QStringLiteral("x")] = cx + (bx - cx) * sc;
        out[QStringLiteral("y")] = cy + (by - cy) * sc;
        out[QStringLiteral("w")] = qMax(0.01, bw * sc);
        out[QStringLiteral("h")] = qMax(0.01, bh * sc);
        // Parity: customScale clamps the glyph factor, unlike grow/shrink.
        if (shapeType == QLatin1String("text") && num(base, "fontSize") > 0)
            out[QStringLiteral("fontSize")] = num(base, "fontSize") * sc;
    } else if (preset == QLatin1String("customRotate")) {
        out[QStringLiteral("rotation")] = num(base, "rotation") + (num(o, "from") + (num(o, "to") - num(o, "from")) * e);
    } else if (preset == QLatin1String("customMove")) {
        out[QStringLiteral("x")] = num(base, "x") + (num(o, "fromX") + (num(o, "toX") - num(o, "fromX")) * e);
        out[QStringLiteral("y")] = num(base, "y") + (num(o, "fromY") + (num(o, "toY") - num(o, "fromY")) * e);
    } else if (preset == QLatin1String("customOpacity")) {
        out[QStringLiteral("opacity")] = num(o, "from") + (num(o, "to") - num(o, "from")) * e;
    } else if (preset == QLatin1String("customColor")) {
        const QString c = lerpColor(str(o, "from", QStringLiteral("#000000")), str(o, "to", QStringLiteral("#ff0000")), e);
        if (!c.isEmpty())
            out[QStringLiteral("fill")] = c;
    } else if (preset == QLatin1String("customHide")) {
        out[QStringLiteral("visible")] = e < 0.5 ? o.value(QStringLiteral("fromVisible"), true).toBool()
                                                 : o.value(QStringLiteral("toVisible"), false).toBool();
    } else if (preset == QLatin1String("customResize")) {
        const double nw = qMax(1.0, num(o, "fromW") + (num(o, "toW") - num(o, "fromW")) * e);
        const double nh = qMax(1.0, num(o, "fromH") + (num(o, "toH") - num(o, "fromH")) * e);
        const double lcx = num(base, "x") + num(base, "w") / 2.0;
        const double lcy = num(base, "y") + num(base, "h") / 2.0;
        out[QStringLiteral("x")] = lcx - nw / 2.0;
        out[QStringLiteral("y")] = lcy - nh / 2.0;
        out[QStringLiteral("w")] = nw;
        out[QStringLiteral("h")] = nh;
    } else if (preset == QLatin1String("customCorner")) {
        out[QStringLiteral("radius")] = num(o, "from") + (num(o, "to") - num(o, "from")) * e;
    } else if (preset == QLatin1String("customStroke")) {
        out[QStringLiteral("strokeWidth")] = num(o, "from") + (num(o, "to") - num(o, "from")) * e;
    } else if (preset == QLatin1String("customGradient")) {
        // Fill gradient from-to: stop colors lerp in sRGB, angle lerps
        // linearly. Mirrors DocAnimSample (which also flips fillType).
        const QString c1 = lerpColor(str(o, "fromC1", QStringLiteral("#000000")),
            str(o, "toC1", QStringLiteral("#000000")), e);
        const QString c2 = lerpColor(str(o, "fromC2", QStringLiteral("#ffffff")),
            str(o, "toC2", QStringLiteral("#ffffff")), e);
        if (!c1.isEmpty() && !c2.isEmpty()) {
            const double ang = num(o, "fromAngle") + (num(o, "toAngle") - num(o, "fromAngle")) * e;
            QVariantMap grad;
            grad[QStringLiteral("angle")] = ang;
            QVariantList stops;
            QVariantMap s1;
            s1[QStringLiteral("color")] = c1;
            s1[QStringLiteral("pos")] = 0.0;
            QVariantMap s2;
            s2[QStringLiteral("color")] = c2;
            s2[QStringLiteral("pos")] = 1.0;
            stops << s1 << s2;
            grad[QStringLiteral("stops")] = stops;
            out[QStringLiteral("fillGradient")] = grad;
            out[QStringLiteral("fillType")] = QStringLiteral("linear");
        }
    } else if (preset == QLatin1String("customShadow")) {
        const QString c = lerpColorA(str(o, "fromColor", QStringLiteral("#000000")),
            str(o, "toColor", QStringLiteral("#000000")), e);
        if (!c.isEmpty()) {
            QVariantMap sh;
            sh[QStringLiteral("enabled")] = true;
            // Stepped like customHide (mirrors DocAnimSample).
            sh[QStringLiteral("inner")] = e < 0.5 ? o.value(QStringLiteral("fromInner")).toBool() : o.value(QStringLiteral("toInner")).toBool();
            sh[QStringLiteral("color")] = c;
            sh[QStringLiteral("x")] = num(o, "fromX") + (num(o, "toX") - num(o, "fromX")) * e;
            sh[QStringLiteral("y")] = num(o, "fromY") + (num(o, "toY") - num(o, "fromY")) * e;
            sh[QStringLiteral("blur")] = qMax(0.0, num(o, "fromBlur") + (num(o, "toBlur") - num(o, "fromBlur")) * e);
            sh[QStringLiteral("spread")] = qMax(0.0, num(o, "fromSpread") + (num(o, "toSpread") - num(o, "fromSpread")) * e);
            out[QStringLiteral("shadows")] = QVariantList{sh};
        }
    } else if (preset == QLatin1String("customLayerBlur")) {
        QVariantMap b;
        b[QStringLiteral("enabled")] = true;
        b[QStringLiteral("radius")] = qMax(0.0, num(o, "fromRadius") + (num(o, "toRadius") - num(o, "fromRadius")) * e);
        b[QStringLiteral("opacity")] = qBound(0.0, num(o, "fromOpacity", 1.0) + (num(o, "toOpacity", 1.0) - num(o, "fromOpacity", 1.0)) * e, 1.0);
        out[QStringLiteral("layerBlur")] = b;
    } else if (preset == QLatin1String("customBackgroundBlur")) {
        QVariantMap b;
        b[QStringLiteral("enabled")] = true;
        b[QStringLiteral("radius")] = qMax(0.0, num(o, "fromRadius") + (num(o, "toRadius") - num(o, "fromRadius")) * e);
        b[QStringLiteral("opacity")] = qBound(0.0, num(o, "fromOpacity", 0.7) + (num(o, "toOpacity", 0.7) - num(o, "fromOpacity", 0.7)) * e, 1.0);
        out[QStringLiteral("backgroundBlur")] = b;
    } else if (preset == QLatin1String("customGlow")) {
        const QString c = lerpColorA(str(o, "fromColor", QStringLiteral("#cc00ffff")),
            str(o, "toColor", QStringLiteral("#cc00ffff")), e);
        if (!c.isEmpty()) {
            QVariantMap g;
            g[QStringLiteral("enabled")] = true;
            // Stepped like customHide (mirrors DocAnimSample).
            g[QStringLiteral("inner")] = e < 0.5 ? o.value(QStringLiteral("fromInner")).toBool() : o.value(QStringLiteral("toInner")).toBool();
            g[QStringLiteral("color")] = c;
            g[QStringLiteral("blur")] = qMax(0.0, num(o, "fromBlur") + (num(o, "toBlur") - num(o, "fromBlur")) * e);
            g[QStringLiteral("spread")] = qMax(0.0, num(o, "fromSpread") + (num(o, "toSpread") - num(o, "fromSpread")) * e);
            out[QStringLiteral("glows")] = QVariantList{g};
        }
    } else if (preset == QLatin1String("customGrain")) {
        QVariantMap g;
        g[QStringLiteral("enabled")] = true;
        g[QStringLiteral("amount")] = qBound(0.0, num(o, "fromAmount") + (num(o, "toAmount") - num(o, "fromAmount")) * e, 1.0);
        g[QStringLiteral("size")] = qBound(1.0, num(o, "fromSize", 2.0) + (num(o, "toSize", 2.0) - num(o, "fromSize", 2.0)) * e, 10.0);
        out[QStringLiteral("grain")] = g;
    } else if (preset == QLatin1String("customPath")) {
        const PathSample s = samplePath(o.value(QStringLiteral("pts")).toList(), o.value(QStringLiteral("closed")).toBool(), e);
        if (s.valid) {
            out[QStringLiteral("x")] = num(base, "x") + s.dx;
            out[QStringLiteral("y")] = num(base, "y") + s.dy;
            if (o.value(QStringLiteral("orient")).toBool())
                out[QStringLiteral("rotation")] = num(base, "rotation") + s.angleDelta;
        }
    }
    return out;
}

QList<Leaf> collectLeaves(const QVariantMap &scene) {
    QList<Leaf> leaves;
    std::function<void(const QVariantList &, bool, bool)> walk = [&](const QVariantList &nodes, bool vis, bool lock) {
        for (const QVariant &v : nodes) {
            const QVariantMap n = v.toMap();
            if (n.value(QStringLiteral("kind")).toString() == QLatin1String("group")) {
                const bool self = n.value(QStringLiteral("visible"), true).toBool();
                const bool selfLock = n.value(QStringLiteral("locked"), false).toBool();
                walk(n.value(QStringLiteral("children")).toList(), vis && self, lock || selfLock);
            } else {
                leaves.append({n, vis, lock || n.value(QStringLiteral("locked"), false).toBool()});
            }
        }
    };
    walk(scene.value(QStringLiteral("nodes")).toList(), true, false);
    return leaves;
}

QMap<int, QVariantMap> captureBase(const QList<Leaf> &leaves) {
    QMap<int, QVariantMap> base;
    for (const Leaf &l : leaves) {
        const QVariantMap &m = l.map;
        const int uid = m.value(QStringLiteral("uid"), -1).toInt();
        if (uid < 0)
            continue;
        QVariantMap b;
        b[QStringLiteral("x")] = num(m, "x");
        b[QStringLiteral("y")] = num(m, "y");
        b[QStringLiteral("w")] = num(m, "w");
        b[QStringLiteral("h")] = num(m, "h");
        b[QStringLiteral("rotation")] = num(m, "rotation");
        b[QStringLiteral("opacity")] = num(m, "opacity", 1.0);
        b[QStringLiteral("fontSize")] = num(m, "fontSize", 16.0);
        b[QStringLiteral("shapeType")] = str(m, "type", str(m, "shapeType", QStringLiteral("rectangle")));
        b[QStringLiteral("fill")] = str(m, "fill", QStringLiteral("#d9d9d9"));
        b[QStringLiteral("fillType")] = str(m, "fillType", QStringLiteral("solid"));
        b[QStringLiteral("fillGradient")] = m.value(QStringLiteral("fillGradient")).toMap();
        b[QStringLiteral("shadows")] = m.value(QStringLiteral("shadows")).toList();
        b[QStringLiteral("layerBlur")] = m.value(QStringLiteral("layerBlur")).toMap();
        b[QStringLiteral("backgroundBlur")] = m.value(QStringLiteral("backgroundBlur")).toMap();
        b[QStringLiteral("glows")] = m.value(QStringLiteral("glows")).toList();
        b[QStringLiteral("grain")] = m.value(QStringLiteral("grain")).toMap();
        b[QStringLiteral("visible")] = m.value(QStringLiteral("visible"), true).toBool();
        b[QStringLiteral("radius")] = num(m, "radius");
        b[QStringLiteral("strokeWidth")] = num(m, "strokeWidth");
        base[uid] = b;
    }
    return base;
}

namespace {
// uid -> node index for clip target resolution (groups included).
void indexNodes(const QVariantList &nodes, QMap<int, QVariantMap> &out) {
    for (const QVariant &v : nodes) {
        const QVariantMap n = v.toMap();
        out[n.value(QStringLiteral("uid"), -1).toInt()] = n;
        if (n.value(QStringLiteral("kind")).toString() == QLatin1String("group"))
            indexNodes(n.value(QStringLiteral("children")).toList(), out);
    }
}

QList<int> leavesUnder(const QVariantMap &node) {
    QList<int> out;
    std::function<void(const QVariantMap &)> rec = [&](const QVariantMap &n) {
        if (n.value(QStringLiteral("kind")).toString() == QLatin1String("group")) {
            for (const QVariant &c : n.value(QStringLiteral("children")).toList())
                rec(c.toMap());
        } else {
            out.append(n.value(QStringLiteral("uid"), -1).toInt());
        }
    };
    rec(node);
    return out;
}

// Effective visibility of target through its ancestor chain.
bool chainVisible(const QVariantList &nodes, int target) {
    for (const QVariant &v : nodes) {
        const QVariantMap n = v.toMap();
        if (n.value(QStringLiteral("uid"), -1).toInt() == target)
            return n.value(QStringLiteral("visible"), true).toBool();
        if (n.value(QStringLiteral("kind")).toString() == QLatin1String("group")) {
            std::function<bool(const QVariantMap &)> contains = [&](const QVariantMap &g) -> bool {
                for (const QVariant &c : g.value(QStringLiteral("children")).toList()) {
                    const QVariantMap cm = c.toMap();
                    if (cm.value(QStringLiteral("uid"), -1).toInt() == target)
                        return true;
                    if (cm.value(QStringLiteral("kind")).toString() == QLatin1String("group") && contains(cm))
                        return true;
                }
                return false;
            };
            if (contains(n)) {
                if (!n.value(QStringLiteral("visible"), true).toBool())
                    return false;
                return chainVisible(n.value(QStringLiteral("children")).toList(), target);
            }
        }
    }
    return true;
}
} // namespace

QList<QVariantMap> sampleFrame(const QVariantMap &scene, double t) {
    const QList<Leaf> leaves = collectLeaves(scene);
    const QMap<int, QVariantMap> base = captureBase(leaves);
    QMap<int, int> leafIndex;
    for (int i = 0; i < leaves.size(); ++i) {
        const int uid = leaves.at(i).map.value(QStringLiteral("uid"), -1).toInt();
        if (uid >= 0)
            leafIndex[uid] = i;
    }
    QMap<int, QVariantMap> nodeByUid;
    indexNodes(scene.value(QStringLiteral("nodes")).toList(), nodeByUid);

    QList<QVariantMap> work;
    work.reserve(leaves.size());
    for (const Leaf &l : leaves)
        work.append(l.map);

    const QVariantMap anim = scene.value(QStringLiteral("anim")).toMap();
    const QVariantList clips = anim.value(QStringLiteral("clips")).toList();
    const QVariantList roots = scene.value(QStringLiteral("nodes")).toList();

    QMap<int, QVariantMap> acc;
    for (const QVariant &cv : clips) {
        const QVariantMap c = cv.toMap();
        if (t < c.value(QStringLiteral("t0"), 0.0).toDouble())
            continue;
        const double dur = qMax(0.001, c.value(QStringLiteral("duration"), 0.8).toDouble());
        const double p = qBound(0.0, (t - c.value(QStringLiteral("t0"), 0.0).toDouble()) / dur, 1.0);
        const QVariantMap ez = c.value(QStringLiteral("easing")).toMap();
        const double e = easeValue(ez.value(QStringLiteral("id"), QStringLiteral("easeOut")).toString(),
            ez.value(QStringLiteral("bezier")).toList(), p);
        const int targetUid = c.value(QStringLiteral("targetUid"), -1).toInt();
        if (!nodeByUid.contains(targetUid))
            continue;
        const QList<int> targetLeaves = leavesUnder(nodeByUid.value(targetUid));
        double x0 = 1e18, y0 = 1e18, x1 = -1e18, y1 = -1e18;
        bool found = false;
        for (int uid : targetLeaves) {
            if (!base.contains(uid))
                continue;
            const QVariantMap b = base[uid];
            if (num(b, "w") <= 0 || num(b, "h") <= 0)
                continue;
            found = true;
            x0 = qMin(x0, num(b, "x"));
            y0 = qMin(y0, num(b, "y"));
            x1 = qMax(x1, num(b, "x") + num(b, "w"));
            y1 = qMax(y1, num(b, "y") + num(b, "h"));
        }
        if (!found)
            continue;
        const double cx = (x0 + x1) / 2.0, cy = (y0 + y1) / 2.0;
        const QString preset = c.value(QStringLiteral("preset")).toString();
        for (int uid : targetLeaves) {
            if (preset != QLatin1String("customHide") && !chainVisible(roots, uid))
                continue;
            if (!base.contains(uid))
                continue;
            const QVariantMap ov = presetOverlay(preset, c.value(QStringLiteral("mode"), QStringLiteral("in")).toString(),
                c.value(QStringLiteral("options")).toMap(), base[uid], cx, cy, e, p);
            QVariantMap entry = acc.value(uid);
            for (auto it = ov.constBegin(); it != ov.constEnd(); ++it)
                entry[it.key()] = it.value();
            acc[uid] = entry;
        }
    }

    for (int i = 0; i < work.size(); ++i) {
        QVariantMap m = work[i];
        const int uid = m.value(QStringLiteral("uid"), -1).toInt();
        const int src = leafIndex.value(uid, -1);
        if (src >= 0 && leaves.at(src).locked)
            continue;
        if (!acc.contains(uid))
            continue;
        const QVariantMap ov = acc.value(uid);
        const QString shapeType = str(m, "type", str(m, "shapeType", QStringLiteral("rectangle")));
        if (shapeType == QLatin1String("pen")
            && (ov.contains(QStringLiteral("x")) || ov.contains(QStringLiteral("y"))
                || ov.contains(QStringLiteral("w")) || ov.contains(QStringLiteral("h")))) {
            const double nx = ov.contains(QStringLiteral("x")) ? ov.value(QStringLiteral("x")).toDouble() : num(m, "x");
            const double ny = ov.contains(QStringLiteral("y")) ? ov.value(QStringLiteral("y")).toDouble() : num(m, "y");
            const double nw = qMax(0.01, ov.contains(QStringLiteral("w")) ? ov.value(QStringLiteral("w")).toDouble() : num(m, "w"));
            const double nh = qMax(0.01, ov.contains(QStringLiteral("h")) ? ov.value(QStringLiteral("h")).toDouble() : num(m, "h"));
            const double ow = num(m, "w"), oh = num(m, "h");
            const double sx = ow > 0 ? nw / ow : 1.0;
            const double sy = oh > 0 ? nh / oh : 1.0;
            QVariantList subs;
            for (const QVariant &sv : m.value(QStringLiteral("pathData")).toList()) {
                QVariantMap sub = sv.toMap();
                QVariantList pts;
                for (const QVariant &pv : sub.value(QStringLiteral("pts")).toList()) {
                    QVariantMap pt = pv.toMap();
                    const double px = num(pt, "x"), py = num(pt, "y");
                    pt[QStringLiteral("x")] = nx + (px - num(m, "x")) * sx;
                    pt[QStringLiteral("y")] = ny + (py - num(m, "y")) * sy;
                    pt[QStringLiteral("inX")] = nx + (num(pt, "inX", px) - num(m, "x")) * sx;
                    pt[QStringLiteral("inY")] = ny + (num(pt, "inY", py) - num(m, "y")) * sy;
                    pt[QStringLiteral("outX")] = nx + (num(pt, "outX", px) - num(m, "x")) * sx;
                    pt[QStringLiteral("outY")] = ny + (num(pt, "outY", py) - num(m, "y")) * sy;
                    pts.append(pt);
                }
                sub[QStringLiteral("pts")] = pts;
                subs.append(sub);
            }
            m[QStringLiteral("pathData")] = subs;
            m[QStringLiteral("x")] = nx;
            m[QStringLiteral("y")] = ny;
            m[QStringLiteral("w")] = nw;
            m[QStringLiteral("h")] = nh;
        } else {
            for (const QString &k : {QStringLiteral("x"), QStringLiteral("y"), QStringLiteral("w"), QStringLiteral("h")}) {
                if (ov.contains(k))
                    m[k] = ov.value(k);
            }
        }
        for (const QString &k : {QStringLiteral("rotation"), QStringLiteral("opacity"), QStringLiteral("fill"),
                 QStringLiteral("fillType"), QStringLiteral("fillGradient"), QStringLiteral("shadows"),
                 QStringLiteral("layerBlur"), QStringLiteral("backgroundBlur"), QStringLiteral("glows"),
                 QStringLiteral("grain"), QStringLiteral("visible"), QStringLiteral("radius"),
                 QStringLiteral("strokeWidth")}) {
            if (ov.contains(k))
                m[k] = ov.value(k);
        }
        if (ov.contains(QStringLiteral("fontSize")) && shapeType == QLatin1String("text"))
            m[QStringLiteral("fontSize")] = ov.value(QStringLiteral("fontSize"));
        if (ov.contains(QStringLiteral("radius")) && m.value(QStringLiteral("independentCorners")).toBool()) {
            const double rv = qMax(0.0, ov.value(QStringLiteral("radius")).toDouble());
            m[QStringLiteral("cornerRadii")] = QVariantList{rv, rv, rv, rv};
        }
        work[i] = m;
    }
    return work;
}

} // namespace Anims
