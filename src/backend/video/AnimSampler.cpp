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
    if (id == QLatin1String("backOut")) {
        const double c1 = 1.70158;
        const double c3 = c1 + 1.0;
        return 1.0 + c3 * qPow(x - 1.0, 3.0) + c1 * qPow(x - 1.0, 2.0);
    }
    if (id == QLatin1String("backInOut")) {
        const double c2 = 1.70158 * 1.525;
        return x < 0.5
            ? (qPow(2.0 * x, 2.0) * ((c2 + 1.0) * 2.0 * x - c2)) / 2.0
            : (qPow(2.0 * x - 2.0, 2.0) * ((c2 + 1.0) * (x * 2.0 - 2.0) + c2) + 2.0) / 2.0;
    }
    if (id == QLatin1String("bounceOut")) {
        const double n1 = 7.5625;
        const double d1 = 2.75;
        if (x < 1.0 / d1)
            return n1 * x * x;
        if (x < 2.0 / d1) {
            const double t = x - 1.5 / d1;
            return n1 * t * t + 0.75;
        }
        if (x < 2.5 / d1) {
            const double t = x - 2.25 / d1;
            return n1 * t * t + 0.9375;
        }
        const double t = x - 2.625 / d1;
        return n1 * t * t + 0.984375;
    }
    if (id == QLatin1String("elasticOut")) {
        if (x <= 0.0)
            return 0.0;
        if (x >= 1.0)
            return 1.0;
        constexpr double kPi = 3.14159265358979323846;
        const double c4 = (2.0 * kPi) / 3.0;
        return qPow(2.0, -10.0 * x) * qSin((x * 10.0 - 0.75) * c4) + 1.0;
    }
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

// Style/effect-clip stack entry index (0 = top); missing key reads 0
// so old clips keep the legacy flat path.
int entryIndexOf(const QVariantMap &o, const char *key) {
    if (!o.contains(QString::fromLatin1(key)))
        return 0;
    bool ok = false;
    const int n = qRound(o.value(QString::fromLatin1(key)).toDouble(&ok));
    return ok ? qBound(0, n, 32) : 0;
}

double entryOpacityOf(const QVariantMap &m) {
    bool ok = false;
    const double v = m.value(QStringLiteral("opacity"), 1.0).toDouble(&ok);
    return ok ? qBound(0.0, v, 1.0) : 1.0;
}

QVariantMap gradientFrom(const QVariantMap &src) {
    const QVariantMap g = src.value(QStringLiteral("gradient")).toMap();
    const QVariantList stops = g.value(QStringLiteral("stops")).toList();
    QVariantMap s0 = stops.size() > 0 ? stops.at(0).toMap() : QVariantMap();
    QVariantMap s1 = stops.size() > 1 ? stops.at(1).toMap() : QVariantMap();
    QVariantMap out;
    out[QStringLiteral("angle")] = g.value(QStringLiteral("angle"), 0.0).toDouble();
    QVariantList sl;
    QVariantMap a;
    a[QStringLiteral("color")] = s0.value(QStringLiteral("color"), QStringLiteral("#000000")).toString();
    a[QStringLiteral("pos")] = 0.0;
    QVariantMap b;
    b[QStringLiteral("color")] = s1.value(QStringLiteral("color"), QStringLiteral("#ffffff")).toString();
    b[QStringLiteral("pos")] = 1.0;
    sl << a << b;
    out[QStringLiteral("stops")] = sl;
    return out;
}

// Fresh full entry objects from the frozen base (never aliased).
QVariantMap fillEntryFromBase(const QVariantMap &base, int i) {
    const QVariantList list = base.value(QStringLiteral("fills")).toList();
    const QVariantMap src = (i >= 0 && i < list.size()) ? list.at(i).toMap() : QVariantMap();
    QVariantMap out;
    out[QStringLiteral("enabled")] = src.value(QStringLiteral("enabled"), true).toBool();
    out[QStringLiteral("color")] = src.value(QStringLiteral("color"), QStringLiteral("#d9d9d9")).toString();
    const QString t = src.value(QStringLiteral("type"), QStringLiteral("solid")).toString();
    out[QStringLiteral("type")] = t == QLatin1String("linear") ? t : QString(QStringLiteral("solid"));
    out[QStringLiteral("gradient")] = gradientFrom(src);
    out[QStringLiteral("opacity")] = entryOpacityOf(src);
    return out;
}

QVariantMap strokeEntryFromBase(const QVariantMap &base, int i) {
    const QVariantList list = base.value(QStringLiteral("strokes")).toList();
    const QVariantMap src = (i >= 0 && i < list.size()) ? list.at(i).toMap() : QVariantMap();
    QVariantMap out;
    out[QStringLiteral("enabled")] = src.value(QStringLiteral("enabled"), true).toBool();
    out[QStringLiteral("color")] = src.value(QStringLiteral("color"), QStringLiteral("#000000")).toString();
    const QString t = src.value(QStringLiteral("type"), QStringLiteral("solid")).toString();
    out[QStringLiteral("type")] = t == QLatin1String("linear") ? t : QString(QStringLiteral("solid"));
    out[QStringLiteral("gradient")] = gradientFrom(src);
    out[QStringLiteral("width")] = qMax(0.0, src.value(QStringLiteral("width"), 0.0).toDouble());
    const QVariantList dash = src.value(QStringLiteral("dash")).toList();
    const double dd = dash.size() > 0 ? qMax(0.0, dash.at(0).toDouble()) : 0.0;
    const double dg = dash.size() > 1 ? qMax(0.0, dash.at(1).toDouble()) : 0.0;
    if (dd > 0.001 && dg > 0.001)
        out[QStringLiteral("dash")] = QVariantList{dd, dg};
    else
        out[QStringLiteral("dash")] = QVariantList{};
    const QString pos = src.value(QStringLiteral("position"), QStringLiteral("center")).toString();
    out[QStringLiteral("position")] = (pos == QLatin1String("inside") || pos == QLatin1String("outside"))
        ? pos
        : QString(QStringLiteral("center"));
    out[QStringLiteral("opacity")] = entryOpacityOf(src);
    return out;
}

// Fresh full effect entries from the frozen base (never aliased).
QVariantMap shadowEntryFromBase(const QVariantMap &base, int i) {
    const QVariantList list = base.value(QStringLiteral("shadows")).toList();
    const QVariantMap src = (i >= 0 && i < list.size()) ? list.at(i).toMap() : QVariantMap();
    QVariantMap out;
    out[QStringLiteral("enabled")] = src.value(QStringLiteral("enabled"), true).toBool();
    out[QStringLiteral("inner")] = src.value(QStringLiteral("inner"), false).toBool();
    out[QStringLiteral("color")] = src.value(QStringLiteral("color"), QStringLiteral("#80000000")).toString();
    out[QStringLiteral("x")] = src.value(QStringLiteral("x"), 0.0).toDouble();
    out[QStringLiteral("y")] = src.contains(QStringLiteral("y")) ? src.value(QStringLiteral("y")).toDouble() : 4.0;
    out[QStringLiteral("blur")] = qMax(0.0, src.value(QStringLiteral("blur"), 8.0).toDouble());
    out[QStringLiteral("spread")] = qMax(0.0, src.value(QStringLiteral("spread"), 0.0).toDouble());
    return out;
}

QVariantMap glowEntryFromBase(const QVariantMap &base, int i) {
    const QVariantList list = base.value(QStringLiteral("glows")).toList();
    const QVariantMap src = (i >= 0 && i < list.size()) ? list.at(i).toMap() : QVariantMap();
    QVariantMap out;
    out[QStringLiteral("enabled")] = src.value(QStringLiteral("enabled"), true).toBool();
    out[QStringLiteral("inner")] = src.value(QStringLiteral("inner"), false).toBool();
    out[QStringLiteral("color")] = src.value(QStringLiteral("color"), QStringLiteral("#cc00ffff")).toString();
    out[QStringLiteral("blur")] = qMax(0.0, src.value(QStringLiteral("blur"), 16.0).toDouble());
    out[QStringLiteral("spread")] = qMax(0.0, src.value(QStringLiteral("spread"), 4.0).toDouble());
    return out;
}

double lerpOpacityOpt(const QVariantMap &o, double e, bool *present = nullptr) {
    const bool has = o.contains(QStringLiteral("fromOpacity")) || o.contains(QStringLiteral("toOpacity"));
    if (present)
        *present = has;
    if (!has)
        return 1.0;
    return qBound(0.0, num(o, "fromOpacity", 1.0) + (num(o, "toOpacity", 1.0) - num(o, "fromOpacity", 1.0)) * e, 1.0);
}

// Nearest mask below branchIndex in a top-first sibling list (Figma
// segmentation: each mask clips siblings directly above it, up to the
// next mask). Groups never count as masks. Mirrors DocTree.maskBelowIn.
QVariantMap maskBelowIn(const QVariantList &list, int branchIndex) {
    for (int i = branchIndex + 1; i < list.size(); ++i) {
        const QVariantMap n = list.at(i).toMap();
        if (n.value(QStringLiteral("kind")).toString() != QLatin1String("group")
            && n.value(QStringLiteral("isMask"), false).toBool())
            return n;
    }
    return {};
}

// Keyed mask values at raw progress p over o["keys"] (clip-local
// 0..1, absolute geometry). Bracketing segment eases by the target
// key's easing. True when usable; value holds interpolated fields.
// Mirrors DocAnimSample.maskKeysAt.
bool maskKeysAt(const QVariantMap &o, double p, QVariantMap &value) {
    QVariantList keys = o.value(QStringLiteral("keys")).toList();
    if (keys.size() < 2)
        return false;
    // Stored sorted by the QML normalizer; sort defensively so
    // hand-edited scenes bracket correctly too.
    std::sort(keys.begin(), keys.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("t"), 0.0).toDouble()
            < b.toMap().value(QStringLiteral("t"), 0.0).toDouble();
    });
    const double p2 = qBound(0.0, p, 1.0);
    QVariantMap a = keys.first().toMap(), b = keys.last().toMap();
    if (p2 <= a.value(QStringLiteral("t"), 0.0).toDouble()) {
        value = a.value(QStringLiteral("value")).toMap();
        return true;
    }
    if (p2 >= b.value(QStringLiteral("t"), 1.0).toDouble()) {
        value = b.value(QStringLiteral("value")).toMap();
        return true;
    }
    for (int i = 0; i + 1 < keys.size(); ++i) {
        const double t0 = keys.at(i).toMap().value(QStringLiteral("t"), 0.0).toDouble();
        const double t1 = keys.at(i + 1).toMap().value(QStringLiteral("t"), 1.0).toDouble();
        if (p2 >= t0 && p2 <= t1) {
            a = keys.at(i).toMap();
            b = keys.at(i + 1).toMap();
            break;
        }
    }
    const double at = a.value(QStringLiteral("t"), 0.0).toDouble();
    const double bt = b.value(QStringLiteral("t"), 1.0).toDouble();
    const double span = qMax(1e-6, bt - at);
    const double raw = (p2 - at) / span;
    const QVariantMap ez = b.value(QStringLiteral("easing")).toMap();
    const double ke = Anims::easeValue(ez.value(QStringLiteral("id"), QStringLiteral("easeOut")).toString(),
        ez.value(QStringLiteral("bezier")).toList(), raw);
    const QVariantMap av = a.value(QStringLiteral("value")).toMap();
    const QVariantMap bv = b.value(QStringLiteral("value")).toMap();
    static const char *fields[] = {"x", "y", "w", "h", "rotation", "opacity", "feather"};
    for (const char *f : fields) {
        const QString k = QString::fromLatin1(f);
        const bool hasA = av.contains(k), hasB = bv.contains(k);
        if (!hasA && !hasB)
            continue;
        const double an = hasA ? av.value(k).toDouble() : bv.value(k).toDouble();
        const double bn = hasB ? bv.value(k).toDouble() : av.value(k).toDouble();
        value[k] = an + (bn - an) * ke;
    }
    if (av.contains(QStringLiteral("invert")) || bv.contains(QStringLiteral("invert"))) {
        if (!av.contains(QStringLiteral("invert")))
            value[QStringLiteral("invert")] = bv.value(QStringLiteral("invert")).toBool();
        else if (!bv.contains(QStringLiteral("invert")))
            value[QStringLiteral("invert")] = av.value(QStringLiteral("invert")).toBool();
        else
            value[QStringLiteral("invert")] = ke < 0.5 ? av.value(QStringLiteral("invert")).toBool()
                                                       : bv.value(QStringLiteral("invert")).toBool();
    }
    return true;
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
    } else if (preset == QLatin1String("maskWipe") || preset == QLatin1String("maskIris")) {
        // Mask reveals: absolute mask geometry (later-wins, never
        // chained). Mirrors DocAnimSample (keys drive multi-stop).
        QVariantMap kv;
        if (maskKeysAt(o, p, kv)) {
            out[QStringLiteral("x")] = kv.contains(QStringLiteral("x")) ? kv.value(QStringLiteral("x")).toDouble() : num(base, "x");
            out[QStringLiteral("y")] = kv.contains(QStringLiteral("y")) ? kv.value(QStringLiteral("y")).toDouble() : num(base, "y");
            out[QStringLiteral("w")] = qMax(0.01, kv.contains(QStringLiteral("w")) ? kv.value(QStringLiteral("w")).toDouble() : num(base, "w"));
            out[QStringLiteral("h")] = qMax(0.01, kv.contains(QStringLiteral("h")) ? kv.value(QStringLiteral("h")).toDouble() : num(base, "h"));
            if (kv.contains(QStringLiteral("rotation")))
                out[QStringLiteral("rotation")] = kv.value(QStringLiteral("rotation")).toDouble();
            if (kv.contains(QStringLiteral("opacity")))
                out[QStringLiteral("opacity")] = qBound(0.0, kv.value(QStringLiteral("opacity")).toDouble(), 1.0);
            out[QStringLiteral("maskFeather")] = qMax(0.0,
                kv.contains(QStringLiteral("feather")) ? kv.value(QStringLiteral("feather")).toDouble() : num(o, "feather"));
            out[QStringLiteral("maskInverted")] = kv.contains(QStringLiteral("invert"))
                ? kv.value(QStringLiteral("invert")).toBool()
                : o.value(QStringLiteral("invert")).toBool();
        } else {
            const double prog = inward ? e : 1.0 - e;
            const double mx = num(base, "x"), my = num(base, "y");
            const double mw = qMax(0.01, num(base, "w")), mh = qMax(0.01, num(base, "h"));
            if (preset == QLatin1String("maskWipe")) {
                const QString md = str(o, "direction", QStringLiteral("left"));
                if (md == QLatin1String("right")) {
                    out[QStringLiteral("x")] = mx + mw * (1.0 - prog);
                    out[QStringLiteral("y")] = my;
                    out[QStringLiteral("w")] = qMax(0.01, mw * prog);
                    out[QStringLiteral("h")] = mh;
                } else if (md == QLatin1String("up")) {
                    out[QStringLiteral("x")] = mx;
                    out[QStringLiteral("y")] = my;
                    out[QStringLiteral("w")] = mw;
                    out[QStringLiteral("h")] = qMax(0.01, mh * prog);
                } else if (md == QLatin1String("down")) {
                    out[QStringLiteral("x")] = mx;
                    out[QStringLiteral("y")] = my + mh * (1.0 - prog);
                    out[QStringLiteral("w")] = mw;
                    out[QStringLiteral("h")] = qMax(0.01, mh * prog);
                } else {
                    out[QStringLiteral("x")] = mx;
                    out[QStringLiteral("y")] = my;
                    out[QStringLiteral("w")] = qMax(0.01, mw * prog);
                    out[QStringLiteral("h")] = mh;
                }
            } else {
                const double ms = qMax(0.001, prog);
                out[QStringLiteral("x")] = cx + (mx - cx) * ms;
                out[QStringLiteral("y")] = cy + (my - cy) * ms;
                out[QStringLiteral("w")] = qMax(0.01, mw * ms);
                out[QStringLiteral("h")] = qMax(0.01, mh * ms);
                if (shapeType == QLatin1String("text") && num(base, "fontSize") > 0)
                    out[QStringLiteral("fontSize")] = num(base, "fontSize") * prog;
            }
            out[QStringLiteral("maskFeather")] = qMax(0.0, num(o, "feather"));
            out[QStringLiteral("maskInverted")] = o.value(QStringLiteral("invert")).toBool();
        }
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
        const int fIdx = entryIndexOf(o, "fillIndex");
        const QString c = lerpColor(str(o, "from", QStringLiteral("#000000")), str(o, "to", QStringLiteral("#ff0000")), e);
        bool hasOp = false;
        const double fo = lerpOpacityOpt(o, e, &hasOp);
        if (fIdx == 0) {
            if (!c.isEmpty())
                out[QStringLiteral("fill")] = c;
            if (hasOp)
                out[QStringLiteral("fillOpacity")] = fo;
        } else {
            QVariantMap fe = fillEntryFromBase(base, fIdx);
            if (!c.isEmpty())
                fe[QStringLiteral("color")] = c;
            if (hasOp)
                fe[QStringLiteral("opacity")] = fo;
            out[QStringLiteral("fillEntry") + QString::number(fIdx)] = fe;
        }
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
        const int sIdx = entryIndexOf(o, "strokeIndex");
        const double w = num(o, "from") + (num(o, "to") - num(o, "from")) * e;
        bool hasOp = false;
        const double so = lerpOpacityOpt(o, e, &hasOp);
        const bool hasDash = o.contains(QStringLiteral("fromDash")) || o.contains(QStringLiteral("toDash"))
            || o.contains(QStringLiteral("fromGap")) || o.contains(QStringLiteral("toGap"));
        QVariantList dashOut;
        if (hasDash) {
            const double dd = qMax(0.0, num(o, "fromDash") + (num(o, "toDash") - num(o, "fromDash")) * e);
            const double gg = qMax(0.0, num(o, "fromGap") + (num(o, "toGap") - num(o, "fromGap")) * e);
            if (dd > 0.001 && gg > 0.001)
                dashOut = QVariantList{dd, gg};
        }
        bool hasPos = false;
        QString posOut;
        if (o.contains(QStringLiteral("fromPosition")) || o.contains(QStringLiteral("toPosition"))) {
            hasPos = true;
            const QString fp = str(o, "fromPosition", QStringLiteral("center"));
            const QString tp = str(o, "toPosition", QStringLiteral("center"));
            const auto normPos = [](const QString &v) {
                return (v == QLatin1String("inside") || v == QLatin1String("outside")) ? v : QString(QStringLiteral("center"));
            };
            posOut = e < 0.5 ? normPos(fp) : normPos(tp);
        }
        if (sIdx == 0) {
            out[QStringLiteral("strokeWidth")] = w;
            if (hasOp)
                out[QStringLiteral("strokeOpacity")] = so;
            if (hasDash)
                out[QStringLiteral("strokeDash")] = dashOut;
            if (hasPos)
                out[QStringLiteral("strokePosition")] = posOut;
        } else {
            QVariantMap se = strokeEntryFromBase(base, sIdx);
            se[QStringLiteral("width")] = w;
            if (hasOp)
                se[QStringLiteral("opacity")] = so;
            if (hasDash)
                se[QStringLiteral("dash")] = dashOut;
            if (hasPos)
                se[QStringLiteral("position")] = posOut;
            out[QStringLiteral("strokeEntry") + QString::number(sIdx)] = se;
        }
    } else if (preset == QLatin1String("customStrokeColor")) {
        const int scIdx = entryIndexOf(o, "strokeIndex");
        const QString c = lerpColor(str(o, "from", QStringLiteral("#000000")), str(o, "to", QStringLiteral("#ff0000")), e);
        bool hasOp2 = false;
        const double so2 = lerpOpacityOpt(o, e, &hasOp2);
        if (scIdx == 0) {
            if (!c.isEmpty())
                out[QStringLiteral("stroke")] = c;
            if (hasOp2)
                out[QStringLiteral("strokeOpacity")] = so2;
        } else {
            QVariantMap sce = strokeEntryFromBase(base, scIdx);
            if (!c.isEmpty())
                sce[QStringLiteral("color")] = c;
            if (hasOp2)
                sce[QStringLiteral("opacity")] = so2;
            out[QStringLiteral("strokeEntry") + QString::number(scIdx)] = sce;
        }
    } else if (preset == QLatin1String("customStrokeGradient")) {
        const int sgIdx = entryIndexOf(o, "strokeIndex");
        const QString c1 = lerpColor(str(o, "fromC1", QStringLiteral("#000000")),
            str(o, "toC1", QStringLiteral("#000000")), e);
        const QString c2 = lerpColor(str(o, "fromC2", QStringLiteral("#ffffff")),
            str(o, "toC2", QStringLiteral("#ffffff")), e);
        bool hasGrad = false;
        QVariantMap grad;
        if (!c1.isEmpty() && !c2.isEmpty()) {
            hasGrad = true;
            const double ang = num(o, "fromAngle") + (num(o, "toAngle") - num(o, "fromAngle")) * e;
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
        }
        bool hasOp3 = false;
        const double so3 = lerpOpacityOpt(o, e, &hasOp3);
        const bool hasW = o.contains(QStringLiteral("from")) || o.contains(QStringLiteral("to"));
        const double wOut = num(o, "from") + (num(o, "to") - num(o, "from")) * e;
        const bool hasDash = o.contains(QStringLiteral("fromDash")) || o.contains(QStringLiteral("toDash"))
            || o.contains(QStringLiteral("fromGap")) || o.contains(QStringLiteral("toGap"));
        QVariantList dashOut;
        if (hasDash) {
            const double dd = qMax(0.0, num(o, "fromDash") + (num(o, "toDash") - num(o, "fromDash")) * e);
            const double gg = qMax(0.0, num(o, "fromGap") + (num(o, "toGap") - num(o, "fromGap")) * e);
            if (dd > 0.001 && gg > 0.001)
                dashOut = QVariantList{dd, gg};
        }
        bool hasPos = false;
        QString posOut;
        if (o.contains(QStringLiteral("fromPosition")) || o.contains(QStringLiteral("toPosition"))) {
            hasPos = true;
            const QString fp = str(o, "fromPosition", QStringLiteral("center"));
            const QString tp = str(o, "toPosition", QStringLiteral("center"));
            const auto normPos = [](const QString &v) {
                return (v == QLatin1String("inside") || v == QLatin1String("outside")) ? v : QString(QStringLiteral("center"));
            };
            posOut = e < 0.5 ? normPos(fp) : normPos(tp);
        }
        if (sgIdx == 0) {
            if (hasGrad) {
                out[QStringLiteral("strokeGradient")] = grad;
                out[QStringLiteral("strokeType")] = QStringLiteral("linear");
            }
            if (hasOp3)
                out[QStringLiteral("strokeOpacity")] = so3;
            if (hasW)
                out[QStringLiteral("strokeWidth")] = wOut;
            if (hasDash)
                out[QStringLiteral("strokeDash")] = dashOut;
            if (hasPos)
                out[QStringLiteral("strokePosition")] = posOut;
        } else {
            QVariantMap sge = strokeEntryFromBase(base, sgIdx);
            if (hasGrad) {
                sge[QStringLiteral("gradient")] = grad;
                sge[QStringLiteral("type")] = QStringLiteral("linear");
            }
            if (hasOp3)
                sge[QStringLiteral("opacity")] = so3;
            if (hasW)
                sge[QStringLiteral("width")] = wOut;
            if (hasDash)
                sge[QStringLiteral("dash")] = dashOut;
            if (hasPos)
                sge[QStringLiteral("position")] = posOut;
            out[QStringLiteral("strokeEntry") + QString::number(sgIdx)] = sge;
        }
    } else if (preset == QLatin1String("customFontSize")) {
        out[QStringLiteral("fontSize")] = qMax(1.0, num(o, "from") + (num(o, "to") - num(o, "from")) * e);
    } else if (preset == QLatin1String("customFlip")) {
        // Stepped mirror flip about the base state (mirrors DocAnimSample).
        if (str(o, "axis", QStringLiteral("h")) == QLatin1String("v"))
            out[QStringLiteral("flipV")] = e < 0.5 ? base.value(QStringLiteral("flipV")).toBool()
                                                   : !base.value(QStringLiteral("flipV")).toBool();
        else
            out[QStringLiteral("flipH")] = e < 0.5 ? base.value(QStringLiteral("flipH")).toBool()
                                                   : !base.value(QStringLiteral("flipH")).toBool();
    } else if (preset == QLatin1String("customGradient")) {
        // Fill gradient from-to: stop colors lerp in sRGB, angle lerps
        // linearly. Mirrors DocAnimSample (which also flips fillType).
        const int gIdx = entryIndexOf(o, "fillIndex");
        const QString c1 = lerpColor(str(o, "fromC1", QStringLiteral("#000000")),
            str(o, "toC1", QStringLiteral("#000000")), e);
        const QString c2 = lerpColor(str(o, "fromC2", QStringLiteral("#ffffff")),
            str(o, "toC2", QStringLiteral("#ffffff")), e);
        bool hasGrad = false;
        QVariantMap grad;
        if (!c1.isEmpty() && !c2.isEmpty()) {
            hasGrad = true;
            const double ang = num(o, "fromAngle") + (num(o, "toAngle") - num(o, "fromAngle")) * e;
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
        }
        bool hasOp = false;
        const double fo = lerpOpacityOpt(o, e, &hasOp);
        if (gIdx == 0) {
            if (hasGrad) {
                out[QStringLiteral("fillGradient")] = grad;
                out[QStringLiteral("fillType")] = QStringLiteral("linear");
            }
            if (hasOp)
                out[QStringLiteral("fillOpacity")] = fo;
        } else {
            QVariantMap ge = fillEntryFromBase(base, gIdx);
            if (hasGrad) {
                ge[QStringLiteral("gradient")] = grad;
                ge[QStringLiteral("type")] = QStringLiteral("linear");
            }
            if (hasOp)
                ge[QStringLiteral("opacity")] = fo;
            out[QStringLiteral("fillEntry") + QString::number(gIdx)] = ge;
        }
    } else if (preset == QLatin1String("customShadow")) {
        const int shIdx = entryIndexOf(o, "shadowIndex");
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
            if (shIdx == 0) {
                out[QStringLiteral("shadows")] = QVariantList{sh};
            } else {
                QVariantMap se = shadowEntryFromBase(base, shIdx);
                se[QStringLiteral("enabled")] = true;
                se[QStringLiteral("inner")] = sh.value(QStringLiteral("inner")).toBool();
                se[QStringLiteral("color")] = c;
                se[QStringLiteral("x")] = sh.value(QStringLiteral("x")).toDouble();
                se[QStringLiteral("y")] = sh.value(QStringLiteral("y")).toDouble();
                se[QStringLiteral("blur")] = sh.value(QStringLiteral("blur")).toDouble();
                se[QStringLiteral("spread")] = sh.value(QStringLiteral("spread")).toDouble();
                out[QStringLiteral("shadowEntry") + QString::number(shIdx)] = se;
            }
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
        const int glIdx = entryIndexOf(o, "glowIndex");
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
            if (glIdx == 0) {
                out[QStringLiteral("glows")] = QVariantList{g};
            } else {
                QVariantMap ge = glowEntryFromBase(base, glIdx);
                ge[QStringLiteral("enabled")] = true;
                ge[QStringLiteral("inner")] = g.value(QStringLiteral("inner")).toBool();
                ge[QStringLiteral("color")] = c;
                ge[QStringLiteral("blur")] = g.value(QStringLiteral("blur")).toDouble();
                ge[QStringLiteral("spread")] = g.value(QStringLiteral("spread")).toDouble();
                out[QStringLiteral("glowEntry") + QString::number(glIdx)] = ge;
            }
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
    } else if (preset == QLatin1String("type")) {
        // Typewriter reveal, mirroring DocAnimSample: CRLF/CR fold to LF,
        // words split on U+0020 keeping empties, lines on LF, letters
        // count UTF-16 units like JS string length. cps seeds the clip
        // duration at apply time; sampling reads eased progress only.
        QString full = str(base, "textContent");
        full.replace(QStringLiteral("\r\n"), QStringLiteral("\n"));
        full.replace(QLatin1Char('\r'), QLatin1Char('\n'));
        const QString unit = str(o, "unit", QStringLiteral("letters"));
        const bool words = unit == QLatin1String("words");
        const bool lines = !words && unit == QLatin1String("lines");
        QStringList parts;
        int total = 0;
        if (!words && !lines) {
            total = full.size();
        } else {
            parts = full.split(words ? QLatin1Char(' ') : QLatin1Char('\n'), Qt::KeepEmptyParts);
            total = parts.size();
        }
        int shown = 0;
        if (total > 0) {
            const double frac = inward ? e : 1.0 - e;
            shown = qBound(0, int(frac * total + 1e-6), total);
        }
        QString txt;
        if (!words && !lines) {
            txt = full.left(shown);
        } else {
            txt = parts.mid(0, shown).join(words ? QStringLiteral(" ") : QStringLiteral("\n"));
        }
        if (o.value(QStringLiteral("cursor")).toBool() && shown < total)
            txt += QLatin1Char('|');
        out[QStringLiteral("textContent")] = txt;
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
        b[QStringLiteral("textContent")] = str(m, "textContent");
        b[QStringLiteral("shapeType")] = str(m, "type", str(m, "shapeType", QStringLiteral("rectangle")));
        b[QStringLiteral("fills")] = m.value(QStringLiteral("fills")).toList();
        b[QStringLiteral("strokes")] = m.value(QStringLiteral("strokes")).toList();
        b[QStringLiteral("flipH")] = m.value(QStringLiteral("flipH")).toBool();
        b[QStringLiteral("flipV")] = m.value(QStringLiteral("flipV")).toBool();
        // Legacy single keys ride along so old clips sampling base
        // still resolve; new clips read the stacks above.
        b[QStringLiteral("fill")] = str(m, "fill", QStringLiteral("#d9d9d9"));
        b[QStringLiteral("stroke")] = str(m, "stroke", QStringLiteral("#000000"));
        b[QStringLiteral("fillType")] = str(m, "fillType", QStringLiteral("solid"));
        b[QStringLiteral("fillGradient")] = m.value(QStringLiteral("fillGradient")).toMap();
        b[QStringLiteral("shadows")] = m.value(QStringLiteral("shadows")).toList();
        b[QStringLiteral("layerBlur")] = m.value(QStringLiteral("layerBlur")).toMap();
        b[QStringLiteral("backgroundBlur")] = m.value(QStringLiteral("backgroundBlur")).toMap();
        b[QStringLiteral("glows")] = m.value(QStringLiteral("glows")).toList();
        b[QStringLiteral("grain")] = m.value(QStringLiteral("grain")).toMap();
        b[QStringLiteral("visible")] = m.value(QStringLiteral("visible"), true).toBool();
        b[QStringLiteral("radius")] = num(m, "radius");
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
// Position presets output x/y. Their x/y chain from the previous end so
// sequential moves accumulate; all other props stay base-relative.
bool isPositionPreset(const QString &preset) {
    return preset == QLatin1String("slide") || preset == QLatin1String("movescale")
        || preset == QLatin1String("grow") || preset == QLatin1String("shrink")
        || preset == QLatin1String("customScale") || preset == QLatin1String("customMove")
        || preset == QLatin1String("customResize") || preset == QLatin1String("customPath");
}

// Loop-aware linear progress: none holds at the end (clamped), loop
// restarts each cycle, pingpong runs 0->1->0. Mirrors
// DocAnimSample.loopProgress (old scenes miss the key and read none).
double loopProgress(const QString &loop, double t, double t0, double dur) {
    const double d = qMax(0.001, dur);
    const double raw = (t - t0) / d;
    if (loop == QLatin1String("loop")) {
        double p = std::fmod(raw, 1.0);
        if (p < 0.0)
            p += 1.0;
        return p;
    }
    if (loop == QLatin1String("pingpong")) {
        double cyc = std::fmod(raw, 2.0);
        if (cyc < 0.0)
            cyc += 2.0;
        return cyc <= 1.0 ? cyc : 2.0 - cyc;
    }
    return qBound(0.0, raw, 1.0);
}

struct PosClip {
    QVariantMap c;
    int idx = -1;
    double cx = 0.0;
    double cy = 0.0;
};

// Local x/y offset of one clip from its own base (overlay minus base).
QPointF moveOffsetFor(const QVariantMap &c, const QVariantMap &base, double cx, double cy, double e, double p, bool *has = nullptr) {
    const QString preset = c.value(QStringLiteral("preset")).toString();
    const QVariantMap ov = Anims::presetOverlay(preset, c.value(QStringLiteral("mode"), QStringLiteral("in")).toString(),
        c.value(QStringLiteral("options")).toMap(), base, cx, cy, e, p);
    const bool hasX = ov.contains(QStringLiteral("x"));
    const bool hasY = ov.contains(QStringLiteral("y"));
    if (has)
        *has = hasX || hasY;
    double dx = 0.0, dy = 0.0;
    if (hasX)
        dx = ov.value(QStringLiteral("x")).toDouble() - Anims::num(base, "x");
    if (hasY)
        dy = ov.value(QStringLiteral("y")).toDouble() - Anims::num(base, "y");
    return {dx, dy};
}

// Chained offset at time t over a time-sorted position list. Latest
// started wins; its start is the chained value at its own t0.
QPointF chainedOffsetAt(const QList<PosClip> &list, const QVariantMap &base, double t, int upTo) {
    int li = -1;
    for (int i = 0; i <= upTo && i < list.size(); ++i) {
        if (list.at(i).c.value(QStringLiteral("t0"), 0.0).toDouble() <= t)
            li = i;
        else
            break;
    }
    if (li < 0)
        return {0.0, 0.0};
    const PosClip &cur = list.at(li);
    const double dur = qMax(0.001, cur.c.value(QStringLiteral("duration"), 0.8).toDouble());
    const double p = loopProgress(cur.c.value(QStringLiteral("loop"), QStringLiteral("none")).toString(), t,
        cur.c.value(QStringLiteral("t0"), 0.0).toDouble(), dur);
    const QVariantMap ez = cur.c.value(QStringLiteral("easing")).toMap();
    const double e = Anims::easeValue(ez.value(QStringLiteral("id"), QStringLiteral("easeOut")).toString(),
        ez.value(QStringLiteral("bezier")).toList(), p);
    const QPointF off = moveOffsetFor(cur.c, base, cur.cx, cur.cy, e, p);
    QPointF before(0.0, 0.0);
    if (li > 0)
        before = chainedOffsetAt(list, base, cur.c.value(QStringLiteral("t0"), 0.0).toDouble(), li - 1);
    return {before.x() + off.x(), before.y() + off.y()};
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
    struct ClipInfo {
        QVariantMap c;
        int idx = -1;
        QList<int> targetLeaves;
        double cx = 0.0;
        double cy = 0.0;
        bool hasBox = false;
    };
    QList<ClipInfo> infos;
    infos.reserve(clips.size());
    for (int ci = 0; ci < clips.size(); ++ci) {
        const QVariantMap c = clips.at(ci).toMap();
        ClipInfo info;
        info.c = c;
        info.idx = ci;
        const int targetUid = c.value(QStringLiteral("targetUid"), -1).toInt();
        if (!nodeByUid.contains(targetUid)) {
            infos.append(info);
            continue;
        }
        info.targetLeaves = leavesUnder(nodeByUid.value(targetUid));
        double x0 = 1e18, y0 = 1e18, x1 = -1e18, y1 = -1e18;
        bool found = false;
        for (int uid : info.targetLeaves) {
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
        if (found) {
            info.hasBox = true;
            info.cx = (x0 + x1) / 2.0;
            info.cy = (y0 + y1) / 2.0;
        }
        infos.append(info);
    }
    for (const ClipInfo &info : infos) {
        const QVariantMap c = info.c;
        if (t < c.value(QStringLiteral("t0"), 0.0).toDouble())
            continue;
        if (!info.hasBox)
            continue;
        const double dur = qMax(0.001, c.value(QStringLiteral("duration"), 0.8).toDouble());
        const double p = loopProgress(c.value(QStringLiteral("loop"), QStringLiteral("none")).toString(), t,
            c.value(QStringLiteral("t0"), 0.0).toDouble(), dur);
        const QVariantMap ez = c.value(QStringLiteral("easing")).toMap();
        const double e = easeValue(ez.value(QStringLiteral("id"), QStringLiteral("easeOut")).toString(),
            ez.value(QStringLiteral("bezier")).toList(), p);
        const QString preset = c.value(QStringLiteral("preset")).toString();
        const bool skipXY = isPositionPreset(preset);
        for (int uid : info.targetLeaves) {
            if (preset != QLatin1String("customHide") && !chainVisible(roots, uid))
                continue;
            if (!base.contains(uid))
                continue;
            const QVariantMap ov = presetOverlay(preset, c.value(QStringLiteral("mode"), QStringLiteral("in")).toString(),
                c.value(QStringLiteral("options")).toMap(), base[uid], info.cx, info.cy, e, p);
            QVariantMap entry = acc.value(uid);
            for (auto it = ov.constBegin(); it != ov.constEnd(); ++it) {
                // Movement x/y resolves in the chaining pass below.
                if (skipXY && (it.key() == QLatin1String("x") || it.key() == QLatin1String("y")))
                    continue;
                entry[it.key()] = it.value();
            }
            acc[uid] = entry;
        }
    }
    // Chained x/y per leaf over time-sorted position clips: sequential
    // moves accumulate instead of snapping to origin.
    QMap<int, QList<PosClip>> posByUid;
    for (const ClipInfo &info : infos) {
        const QVariantMap c = info.c;
        if (!isPositionPreset(c.value(QStringLiteral("preset")).toString()))
            continue;
        if (t < c.value(QStringLiteral("t0"), 0.0).toDouble())
            continue;
        if (!info.hasBox)
            continue;
        const QString preset = c.value(QStringLiteral("preset")).toString();
        for (int uid : info.targetLeaves) {
            if (preset != QLatin1String("customHide") && !chainVisible(roots, uid))
                continue;
            if (!base.contains(uid))
                continue;
            PosClip pc;
            pc.c = c;
            pc.idx = info.idx;
            pc.cx = info.cx;
            pc.cy = info.cy;
            posByUid[uid].append(pc);
        }
    }
    for (auto it = posByUid.begin(); it != posByUid.end(); ++it) {
        const int uid = it.key();
        QList<PosClip> list = it.value();
        std::sort(list.begin(), list.end(), [](const PosClip &a, const PosClip &b) {
            const double ta = a.c.value(QStringLiteral("t0"), 0.0).toDouble();
            const double tb = b.c.value(QStringLiteral("t0"), 0.0).toDouble();
            if (!qFuzzyCompare(1.0 + ta, 1.0 + tb))
                return ta < tb;
            return a.idx < b.idx;
        });
        const QPointF total = chainedOffsetAt(list, base[uid], t, list.size() - 1);
        QVariantMap entry = acc.value(uid);
        entry[QStringLiteral("x")] = num(base[uid], "x") + total.x();
        entry[QStringLiteral("y")] = num(base[uid], "y") + total.y();
        acc[uid] = entry;
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
        for (const QString &k : {QStringLiteral("rotation"), QStringLiteral("opacity"),
                 QStringLiteral("layerBlur"), QStringLiteral("backgroundBlur"),
                 QStringLiteral("grain"), QStringLiteral("visible"), QStringLiteral("radius"),
                 QStringLiteral("fills"), QStringLiteral("strokes"), QStringLiteral("flipH"), QStringLiteral("flipV"),
                 QStringLiteral("textContent")}) {
            if (ov.contains(k))
                m[k] = ov.value(k);
        }
        // Shadow/glow top-entry clips fold onto entry 0 like fill/stroke
        // legacy keys, preserving the rest of the stack. Multi-entry
        // arrays (legacy fallback) replace whole.
        if (ov.contains(QStringLiteral("shadows"))) {
            const QVariantList src = ov.value(QStringLiteral("shadows")).toList();
            if (src.size() == 1) {
                QVariantList l = m.value(QStringLiteral("shadows")).toList();
                if (l.isEmpty()) {
                    QVariantMap d;
                    d[QStringLiteral("enabled")] = true;
                    d[QStringLiteral("inner")] = false;
                    d[QStringLiteral("color")] = QStringLiteral("#80000000");
                    d[QStringLiteral("x")] = 0.0;
                    d[QStringLiteral("y")] = 4.0;
                    d[QStringLiteral("blur")] = 8.0;
                    d[QStringLiteral("spread")] = 0.0;
                    l.append(d);
                }
                l[0] = src.first().toMap();
                m[QStringLiteral("shadows")] = l;
            } else {
                m[QStringLiteral("shadows")] = src;
            }
        }
        if (ov.contains(QStringLiteral("glows"))) {
            const QVariantList src = ov.value(QStringLiteral("glows")).toList();
            if (src.size() == 1) {
                QVariantList l = m.value(QStringLiteral("glows")).toList();
                if (l.isEmpty()) {
                    QVariantMap d;
                    d[QStringLiteral("enabled")] = true;
                    d[QStringLiteral("inner")] = false;
                    d[QStringLiteral("color")] = QStringLiteral("#cc00ffff");
                    d[QStringLiteral("blur")] = 16.0;
                    d[QStringLiteral("spread")] = 4.0;
                    l.append(d);
                }
                l[0] = src.first().toMap();
                m[QStringLiteral("glows")] = l;
            } else {
                m[QStringLiteral("glows")] = src;
            }
        }
        // Style clips animate the top stack entry via legacy single
        // keys (customColor/customStroke/etc.): fold them onto
        // fills[0]/strokes[0] so old clips keep working on stacks.
        auto ensureFills = [&](QVariantMap &mm) -> QVariantList {
            QVariantList l = mm.value(QStringLiteral("fills")).toList();
            if (l.isEmpty()) {
                QVariantMap d;
                d[QStringLiteral("enabled")] = true;
                d[QStringLiteral("color")] = QStringLiteral("#d9d9d9");
                d[QStringLiteral("type")] = QStringLiteral("solid");
                d[QStringLiteral("opacity")] = 1.0;
                l.append(d);
            }
            return l;
        };
        auto ensureStrokes = [&](QVariantMap &mm) -> QVariantList {
            QVariantList l = mm.value(QStringLiteral("strokes")).toList();
            if (l.isEmpty()) {
                QVariantMap d;
                d[QStringLiteral("enabled")] = true;
                d[QStringLiteral("color")] = QStringLiteral("#000000");
                d[QStringLiteral("type")] = QStringLiteral("solid");
                d[QStringLiteral("width")] = 0.0;
                d[QStringLiteral("position")] = QStringLiteral("center");
                d[QStringLiteral("opacity")] = 1.0;
                l.append(d);
            }
            return l;
        };
        if (ov.contains(QStringLiteral("fill")) || ov.contains(QStringLiteral("fillType"))
            || ov.contains(QStringLiteral("fillGradient")) || ov.contains(QStringLiteral("fillOpacity"))) {
            QVariantList l = ensureFills(m);
            QVariantMap f0 = l.first().toMap();
            if (ov.contains(QStringLiteral("fill")))
                f0[QStringLiteral("color")] = ov.value(QStringLiteral("fill")).toString();
            if (ov.contains(QStringLiteral("fillType")))
                f0[QStringLiteral("type")] = ov.value(QStringLiteral("fillType")).toString();
            if (ov.contains(QStringLiteral("fillGradient")))
                f0[QStringLiteral("gradient")] = ov.value(QStringLiteral("fillGradient")).toMap();
            if (ov.contains(QStringLiteral("fillOpacity")))
                f0[QStringLiteral("opacity")] = qBound(0.0, ov.value(QStringLiteral("fillOpacity")).toDouble(), 1.0);
            l[0] = f0;
            m[QStringLiteral("fills")] = l;
        }
        if (ov.contains(QStringLiteral("stroke")) || ov.contains(QStringLiteral("strokeWidth"))
            || ov.contains(QStringLiteral("strokeType")) || ov.contains(QStringLiteral("strokeGradient"))
            || ov.contains(QStringLiteral("strokeOpacity")) || ov.contains(QStringLiteral("strokeDash"))
            || ov.contains(QStringLiteral("strokePosition"))) {
            QVariantList l = ensureStrokes(m);
            QVariantMap s0 = l.first().toMap();
            if (ov.contains(QStringLiteral("stroke")))
                s0[QStringLiteral("color")] = ov.value(QStringLiteral("stroke")).toString();
            if (ov.contains(QStringLiteral("strokeType")))
                s0[QStringLiteral("type")] = ov.value(QStringLiteral("strokeType")).toString();
            if (ov.contains(QStringLiteral("strokeGradient")))
                s0[QStringLiteral("gradient")] = ov.value(QStringLiteral("strokeGradient")).toMap();
            if (ov.contains(QStringLiteral("strokeWidth")))
                s0[QStringLiteral("width")] = qMax(0.0, ov.value(QStringLiteral("strokeWidth")).toDouble());
            if (ov.contains(QStringLiteral("strokeOpacity")))
                s0[QStringLiteral("opacity")] = qBound(0.0, ov.value(QStringLiteral("strokeOpacity")).toDouble(), 1.0);
            if (ov.contains(QStringLiteral("strokeDash")))
                s0[QStringLiteral("dash")] = ov.value(QStringLiteral("strokeDash")).toList();
            if (ov.contains(QStringLiteral("strokePosition")))
                s0[QStringLiteral("position")] = ov.value(QStringLiteral("strokePosition")).toString();
            l[0] = s0;
            m[QStringLiteral("strokes")] = l;
        }
        // Indexed style overlays (entry 1+): complete entry objects on
        // fillEntry{i}/strokeEntry{i} keys, padding short stacks with
        // defaults like the canvas writeback. Shadow/glow entries ride
        // shadowEntry{i}/glowEntry{i} the same way.
        auto ensureShadows = [&](QVariantMap &mm) -> QVariantList {
            QVariantList l = mm.value(QStringLiteral("shadows")).toList();
            return l;
        };
        auto ensureGlows = [&](QVariantMap &mm) -> QVariantList {
            QVariantList l = mm.value(QStringLiteral("glows")).toList();
            return l;
        };
        for (auto it = ov.constBegin(); it != ov.constEnd(); ++it) {
            const QString k = it.key();
            bool isFill = k.startsWith(QStringLiteral("fillEntry"));
            bool isStroke = !isFill && k.startsWith(QStringLiteral("strokeEntry"));
            bool isShadow = !isFill && !isStroke && k.startsWith(QStringLiteral("shadowEntry"));
            bool isGlow = !isFill && !isStroke && !isShadow && k.startsWith(QStringLiteral("glowEntry"));
            if (!isFill && !isStroke && !isShadow && !isGlow)
                continue;
            bool ok = false;
            int idx = -1;
            if (isFill)
                idx = k.mid(9).toInt(&ok);
            else if (isStroke)
                idx = k.mid(11).toInt(&ok);
            else if (isShadow)
                idx = k.mid(11).toInt(&ok);
            else
                idx = k.mid(9).toInt(&ok);
            if (!ok || idx < 1 || idx > 32)
                continue;
            if (isFill) {
                QVariantList l = ensureFills(m);
                while (l.size() <= idx) {
                    QVariantMap d;
                    d[QStringLiteral("enabled")] = true;
                    d[QStringLiteral("color")] = QStringLiteral("#d9d9d9");
                    d[QStringLiteral("type")] = QStringLiteral("solid");
                    d[QStringLiteral("opacity")] = 1.0;
                    l.append(d);
                }
                l[idx] = it.value().toMap();
                m[QStringLiteral("fills")] = l;
            } else if (isStroke) {
                QVariantList l = ensureStrokes(m);
                while (l.size() <= idx) {
                    QVariantMap d;
                    d[QStringLiteral("enabled")] = true;
                    d[QStringLiteral("color")] = QStringLiteral("#000000");
                    d[QStringLiteral("type")] = QStringLiteral("solid");
                    d[QStringLiteral("width")] = 0.0;
                    d[QStringLiteral("position")] = QStringLiteral("center");
                    d[QStringLiteral("opacity")] = 1.0;
                    l.append(d);
                }
                l[idx] = it.value().toMap();
                m[QStringLiteral("strokes")] = l;
            } else if (isShadow) {
                QVariantList l = ensureShadows(m);
                while (l.size() <= idx) {
                    QVariantMap d;
                    d[QStringLiteral("enabled")] = true;
                    d[QStringLiteral("inner")] = false;
                    d[QStringLiteral("color")] = QStringLiteral("#80000000");
                    d[QStringLiteral("x")] = 0.0;
                    d[QStringLiteral("y")] = 4.0;
                    d[QStringLiteral("blur")] = 8.0;
                    d[QStringLiteral("spread")] = 0.0;
                    l.append(d);
                }
                l[idx] = it.value().toMap();
                m[QStringLiteral("shadows")] = l;
            } else {
                QVariantList l = ensureGlows(m);
                while (l.size() <= idx) {
                    QVariantMap d;
                    d[QStringLiteral("enabled")] = true;
                    d[QStringLiteral("inner")] = false;
                    d[QStringLiteral("color")] = QStringLiteral("#cc00ffff");
                    d[QStringLiteral("blur")] = 16.0;
                    d[QStringLiteral("spread")] = 4.0;
                    l.append(d);
                }
                l[idx] = it.value().toMap();
                m[QStringLiteral("glows")] = l;
            }
        }
        if (ov.contains(QStringLiteral("fontSize")) && shapeType == QLatin1String("text"))
            m[QStringLiteral("fontSize")] = ov.value(QStringLiteral("fontSize"));
        if (ov.contains(QStringLiteral("maskFeather")))
            m[QStringLiteral("maskFeather")] = qMax(0.0, ov.value(QStringLiteral("maskFeather")).toDouble());
        if (ov.contains(QStringLiteral("maskInverted")))
            m[QStringLiteral("maskInverted")] = ov.value(QStringLiteral("maskInverted")).toBool();
        if (ov.contains(QStringLiteral("radius")) && m.value(QStringLiteral("independentCorners")).toBool()) {
            const double rv = qMax(0.0, ov.value(QStringLiteral("radius")).toDouble());
            m[QStringLiteral("cornerRadii")] = QVariantList{rv, rv, rv, rv};
        }
        work[i] = m;
    }
    return work;
}

bool isMaskMap(const QVariantMap &m) {
    return m.value(QStringLiteral("isMask"), false).toBool();
}

QMap<int, QList<int>> maskMapForWork(const QVariantMap &scene, const QList<QVariantMap> &work) {
    Q_UNUSED(work);
    // Parent chain from the scene hierarchy (uid -> parentUid/index).
    QMap<int, QVariantMap> nodeByUid;
    QMap<int, int> parentByUid;
    QMap<int, int> indexByUid;
    QMap<int, QVariantList> childrenByParent;
    std::function<void(const QVariantList &, int)> walk = [&](const QVariantList &nodes, int parentUid) {
        childrenByParent[parentUid] = nodes;
        for (int i = 0; i < nodes.size(); ++i) {
            const QVariantMap n = nodes.at(i).toMap();
            const int uid = n.value(QStringLiteral("uid"), -1).toInt();
            if (uid < 0)
                continue;
            nodeByUid[uid] = n;
            parentByUid[uid] = parentUid;
            indexByUid[uid] = i;
            if (n.value(QStringLiteral("kind")).toString() == QLatin1String("group"))
                walk(n.value(QStringLiteral("children")).toList(), uid);
        }
    };
    walk(scene.value(QStringLiteral("nodes")).toList(), -1);
    QMap<int, QList<int>> out;
    // Every shape uid in the hierarchy (leaves + masks themselves).
    QList<int> allUids = nodeByUid.keys();
    for (int uid : allUids) {
        const QVariantMap n = nodeByUid.value(uid);
        if (n.value(QStringLiteral("kind")).toString() == QLatin1String("group"))
            continue;
        if (isMaskMap(n))
            continue;
        QList<int> masks;
        // Walk up: branch at each level is the child containing uid.
        int branchUid = uid;
        int levelParent = parentByUid.value(uid, -1);
        // Guard against cycles: cap chain length.
        for (int depth = 0; depth < 64; ++depth) {
            if (!childrenByParent.contains(levelParent))
                break;
            const QVariantList siblings = childrenByParent.value(levelParent);
            const int branchIdx = indexByUid.value(branchUid, -1);
            if (branchIdx >= 0) {
                const QVariantMap mask = maskBelowIn(siblings, branchIdx);
                if (!mask.isEmpty())
                    masks.append(mask.value(QStringLiteral("uid"), -1).toInt());
            }
            if (levelParent < 0)
                break;
            branchUid = levelParent;
            levelParent = parentByUid.value(levelParent, -2);
            if (levelParent == -2)
                break;
        }
        if (!masks.isEmpty())
            out[uid] = masks;
    }
    return out;
}

} // namespace Anims
