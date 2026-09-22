#include "SvgImport.h"

#include <QColor>
#include <QFile>
#include <QFont>
#include <QFontMetrics>
#include <QPainterPath>
#include <QPointF>
#include <QRegularExpression>
#include <QSet>
#include <QTransform>
#include <QVariantList>
#include <QVariantMap>
#include <QXmlStreamReader>
#include <QtMath>

namespace SvgImport {
namespace {

// One pen anchor: cubic handles ride in/out (smooth only). Absolute
// SVG user-space coords; the import normalizes at the end.
struct Anchor {
    double x = 0.0;
    double y = 0.0;
    bool smooth = false;
    double inX = 0.0;
    double inY = 0.0;
    double outX = 0.0;
    double outY = 0.0;
};

struct Sub {
    bool closed = false;
    QList<Anchor> pts;
};

// One drawable element: subpaths plus resolved solid paints.
struct Shape {
    QList<Sub> subs;
    QColor fill = QColor(QStringLiteral("#000000"));
    bool penFill = true;
    QColor stroke = QColor(0, 0, 0, 0);
    double strokeWidth = 0.0;
    QString strokeCap = QStringLiteral("round");
    QString strokeJoin = QStringLiteral("round");
};

// Inherited presentation state while walking the element tree.
struct Style {
    bool hasFill = false;
    QColor fill = QColor(QStringLiteral("#000000"));
    double fillOpacity = 1.0;
    bool hasStroke = false;
    QColor stroke = QColor(0, 0, 0, 0);
    double strokeWidth = 1.0;
    double strokeOpacity = 1.0;
    QString strokeCap;
    QString strokeJoin;
    double opacity = 1.0;
    bool display = true;
    // Text type (inherited like other presentation attributes).
    QString fontFamily;
    double fontSize = 16.0;
    int fontWeight = 400;
    bool fontItalic = false;
    double letterSpacing = 0.0;
};

double round2(double v)
{
    return qRound(v * 100.0) / 100.0;
}

// SVG length with CSS units (px default). Percentages and em/ex need
// layout context; treat as unset (NaN) so callers fall back.
double parseLength(const QString &s, bool *ok = nullptr)
{
    static const QRegularExpression re(
        QStringLiteral("^\\s*([-+]?\\d*\\.?\\d+(?:[eE][-+]?\\d+)?)\\s*([a-zA-Z%]*)\\s*$"));
    const QRegularExpressionMatch m = re.match(s);
    if (!m.hasMatch()) {
        if (ok)
            *ok = false;
        return qQNaN();
    }
    double v = m.captured(1).toDouble();
    const QString u = m.captured(2).toLower();
    if (u.isEmpty() || u == QLatin1String("px"))
        ;
    else if (u == QLatin1String("pt"))
        v *= 96.0 / 72.0;
    else if (u == QLatin1String("pc"))
        v *= 16.0;
    else if (u == QLatin1String("in"))
        v *= 96.0;
    else if (u == QLatin1String("cm"))
        v *= 96.0 / 2.54;
    else if (u == QLatin1String("mm"))
        v *= 96.0 / 25.4;
    else if (u == QLatin1String("q"))
        v *= 96.0 / 25.4 / 4.0;
    else {
        if (ok)
            *ok = false;
        return qQNaN();
    }
    if (ok)
        *ok = true;
    return v;
}

// Solid paint or unset. "none"/"transparent" and url() gradients read
// as unset so the SVG default (black fill, no stroke) applies.
QColor parsePaint(const QString &s, bool *set)
{
    const QString t = s.trimmed();
    if (t.isEmpty() || t.startsWith(QLatin1String("url("), Qt::CaseInsensitive)) {
        *set = false;
        return {};
    }
    if (t.compare(QLatin1String("none"), Qt::CaseInsensitive) == 0
        || t.compare(QLatin1String("transparent"), Qt::CaseInsensitive) == 0) {
        *set = true;
        return QColor(0, 0, 0, 0);
    }
    const QColor c(t);
    if (!c.isValid()) {
        *set = false;
        return {};
    }
    *set = true;
    return c;
}

double numAttr(const QXmlStreamAttributes &a, const char *key, double fallback)
{
    if (!a.hasAttribute(QLatin1String(key)))
        return fallback;
    bool ok = false;
    const double v = parseLength(a.value(QLatin1String(key)).toString(), &ok);
    return ok ? v : fallback;
}

// Presentation attributes plus inline style="k:v;..." (attribute wins
// on conflict, per the CSS cascade for presentation attributes).
QMap<QString, QString> elementStyle(const QXmlStreamAttributes &a)
{
    QMap<QString, QString> out;
    const QString style = a.value(QLatin1String("style")).toString();
    for (const QString &decl : style.split(QLatin1Char(';'))) {
        const int ci = decl.indexOf(QLatin1Char(':'));
        if (ci <= 0)
            continue;
        out[decl.left(ci).trimmed().toLower()] = decl.mid(ci + 1).trimmed();
    }
    for (const QXmlStreamAttribute &attr : a) {
        const QString k = attr.name().toString().toLower();
        if (k == QLatin1String("fill") || k == QLatin1String("fill-opacity")
            || k == QLatin1String("stroke") || k == QLatin1String("stroke-width")
            || k == QLatin1String("stroke-opacity") || k == QLatin1String("stroke-linecap")
            || k == QLatin1String("stroke-linejoin") || k == QLatin1String("opacity")
            || k == QLatin1String("display") || k == QLatin1String("visibility")
            || k == QLatin1String("font-family") || k == QLatin1String("font-size")
            || k == QLatin1String("font-weight") || k == QLatin1String("font-style")
            || k == QLatin1String("letter-spacing"))
            out[k] = attr.value().toString().trimmed();
    }
    return out;
}

Style childStyle(const Style &parent, const QMap<QString, QString> &props)
{
    Style s = parent;
    if (props.contains(QStringLiteral("display")))
        s.display = props.value(QStringLiteral("display")).compare(QLatin1String("none"),
                          Qt::CaseInsensitive)
            != 0;
    if (props.contains(QStringLiteral("visibility")))
        s.display = s.display
            && props.value(QStringLiteral("visibility")).compare(QLatin1String("hidden"),
                   Qt::CaseInsensitive)
                != 0
            && props.value(QStringLiteral("visibility")).compare(QLatin1String("collapse"),
                   Qt::CaseInsensitive)
                != 0;
    if (props.contains(QStringLiteral("opacity"))) {
        bool ok = false;
        const double o = props.value(QStringLiteral("opacity")).toDouble(&ok);
        if (ok)
            s.opacity = qBound(0.0, o, 1.0);
    }
    if (props.contains(QStringLiteral("fill"))) {
        bool set = false;
        const QColor c = parsePaint(props.value(QStringLiteral("fill")), &set);
        if (set) {
            s.hasFill = true;
            s.fill = c;
        }
    }
    if (props.contains(QStringLiteral("fill-opacity"))) {
        bool ok = false;
        const double o = props.value(QStringLiteral("fill-opacity")).toDouble(&ok);
        if (ok)
            s.fillOpacity = qBound(0.0, o, 1.0);
    }
    if (props.contains(QStringLiteral("stroke"))) {
        bool set = false;
        const QColor c = parsePaint(props.value(QStringLiteral("stroke")), &set);
        if (set) {
            s.hasStroke = true;
            s.stroke = c;
        }
    }
    if (props.contains(QStringLiteral("stroke-width"))) {
        bool ok = false;
        const double w = parseLength(props.value(QStringLiteral("stroke-width")), &ok);
        if (ok)
            s.strokeWidth = qMax(0.0, w);
    }
    if (props.contains(QStringLiteral("stroke-opacity"))) {
        bool ok = false;
        const double o = props.value(QStringLiteral("stroke-opacity")).toDouble(&ok);
        if (ok)
            s.strokeOpacity = qBound(0.0, o, 1.0);
    }
    if (props.contains(QStringLiteral("stroke-linecap"))) {
        const QString c = props.value(QStringLiteral("stroke-linecap")).toLower();
        s.strokeCap = c == QLatin1String("square") || c == QLatin1String("butt") ? c : QString();
    }
    if (props.contains(QStringLiteral("stroke-linejoin"))) {
        const QString j = props.value(QStringLiteral("stroke-linejoin")).toLower();
        s.strokeJoin = j == QLatin1String("bevel") || j == QLatin1String("miter") ? j
                                                                                  : QString();
    }
    if (props.contains(QStringLiteral("font-family"))) {
        QString f = props.value(QStringLiteral("font-family")).trimmed();
        if ((f.startsWith(QLatin1Char('\'')) && f.endsWith(QLatin1Char('\'')))
            || (f.startsWith(QLatin1Char('"')) && f.endsWith(QLatin1Char('"'))))
            f = f.mid(1, f.size() - 2);
        // First family wins (fallbacks after the comma are ignored).
        s.fontFamily = f.split(QLatin1Char(',')).first().trimmed();
    }
    if (props.contains(QStringLiteral("font-size"))) {
        const QString t = props.value(QStringLiteral("font-size")).trimmed().toLower();
        bool ok = false;
        double v = 0.0;
        if (t.endsWith(QLatin1Char('%'))) {
            v = t.left(t.size() - 1).toDouble(&ok);
            if (ok)
                v = parent.fontSize * v / 100.0;
        } else if (t == QLatin1String("xx-small")) {
            v = 9.0;
            ok = true;
        } else if (t == QLatin1String("x-small")) {
            v = 10.0;
            ok = true;
        } else if (t == QLatin1String("small")) {
            v = 13.0;
            ok = true;
        } else if (t == QLatin1String("medium")) {
            v = 16.0;
            ok = true;
        } else if (t == QLatin1String("large")) {
            v = 18.0;
            ok = true;
        } else if (t == QLatin1String("x-large")) {
            v = 24.0;
            ok = true;
        } else if (t == QLatin1String("xx-large")) {
            v = 32.0;
            ok = true;
        } else if (t == QLatin1String("smaller")) {
            v = parent.fontSize / 1.2;
            ok = true;
        } else if (t == QLatin1String("larger")) {
            v = parent.fontSize * 1.2;
            ok = true;
        } else {
            v = parseLength(t, &ok);
        }
        if (ok && v > 0.0)
            s.fontSize = v;
    }
    if (props.contains(QStringLiteral("font-weight"))) {
        const QString t = props.value(QStringLiteral("font-weight")).trimmed().toLower();
        bool ok = false;
        int w = t.toInt(&ok);
        if (!ok) {
            if (t == QLatin1String("normal")) {
                w = 400;
                ok = true;
            } else if (t == QLatin1String("bold")) {
                w = 700;
                ok = true;
            } else if (t == QLatin1String("bolder")) {
                w = parent.fontWeight + 100;
                ok = true;
            } else if (t == QLatin1String("lighter")) {
                w = parent.fontWeight - 100;
                ok = true;
            }
        }
        if (ok)
            s.fontWeight = qBound(100, w, 900);
    }
    if (props.contains(QStringLiteral("font-style"))) {
        const QString t = props.value(QStringLiteral("font-style")).trimmed().toLower();
        s.fontItalic = t == QLatin1String("italic") || t == QLatin1String("oblique");
    }
    if (props.contains(QStringLiteral("letter-spacing"))) {
        const QString t = props.value(QStringLiteral("letter-spacing")).trimmed().toLower();
        if (t == QLatin1String("normal")) {
            s.letterSpacing = 0.0;
        } else {
            bool ok = false;
            const double v = parseLength(t, &ok);
            if (ok)
                s.letterSpacing = v;
        }
    }
    return s;
}

QColor withOpacity(QColor c, double o)
{
    if (!c.isValid())
        return c;
    c.setAlpha(qBound(0, qRound(c.alpha() * qBound(0.0, o, 1.0)), 255));
    return c;
}

// transform="translate(10 20) scale(2) rotate(45 5 5) ..." applied in
// order (post-multiplied, matching SVG).
QTransform parseTransform(const QString &s)
{
    QTransform t;
    static const QRegularExpression re(QStringLiteral("(\\w+)\\s*\\(([^)]*)\\)"));
    static const QRegularExpression num(QStringLiteral("[-+]?\\d*\\.?\\d+(?:[eE][-+]?\\d+)?"));
    QRegularExpressionMatchIterator it = re.globalMatch(s);
    while (it.hasNext()) {
        const QRegularExpressionMatch m = it.next();
        const QString op = m.captured(1).toLower();
        QList<double> args;
        QRegularExpressionMatchIterator ni = num.globalMatch(m.captured(2));
        while (ni.hasNext())
            args.append(ni.next().captured(0).toDouble());
        if (op == QLatin1String("translate"))
            t.translate(args.value(0), args.value(1));
        else if (op == QLatin1String("scale"))
            t.scale(args.value(0), args.size() > 1 ? args.value(1) : args.value(0));
        else if (op == QLatin1String("rotate")) {
            if (args.size() > 2) {
                t.translate(args.at(1), args.at(2));
                t.rotate(args.at(0));
                t.translate(-args.at(1), -args.at(2));
            } else if (!args.isEmpty()) {
                t.rotate(args.at(0));
            }
        } else if (op == QLatin1String("skewx")) {
            if (!args.isEmpty())
                t.shear(qTan(qDegreesToRadians(args.at(0))), 0.0);
        } else if (op == QLatin1String("skewy")) {
            if (!args.isEmpty())
                t.shear(0.0, qTan(qDegreesToRadians(args.at(0))));
        } else if (op == QLatin1String("matrix") && args.size() >= 6) {
            t *= QTransform(args.at(0), args.at(1), args.at(2), args.at(3), args.at(4), args.at(5));
        }
    }
    return t;
}

// Path data tokenizer: commands plus numbers (".5", "10-20", "1e-3").
QList<QString> tokenizePath(const QString &d)
{
    QList<QString> out;
    static const QRegularExpression re(
        QStringLiteral("[AaCcHhLlMmQqSsTtVvZz]|[-+]?\\d*\\.?\\d+(?:[eE][-+]?\\d+)?"));
    QRegularExpressionMatchIterator it = re.globalMatch(d);
    while (it.hasNext())
        out.append(it.next().captured(0));
    return out;
}

bool isCommand(const QString &t)
{
    return t.size() == 1 && QStringLiteral("AaCcHhLlMmQqSsTtVvZz").contains(t);
}

// Cubic arc approximation (endpoint parametrization, split at 90deg).
// Emits one smooth end anchor per segment; the previous anchor gains
// its outgoing handle (its incoming handle stays put, so earlier
// segments keep rendering exactly as before).
void arcTo(QList<Anchor> &pts, double x0, double y0, double rx, double ry, double rotDeg,
    bool largeArc, bool sweep, double x1, double y1)
{
    if (rx <= 0.0 || ry <= 0.0 || (qFuzzyCompare(x0, x1) && qFuzzyCompare(y0, y1)))
        return;
    const double rot = qDegreesToRadians(rotDeg);
    const double cosR = qCos(rot), sinR = qSin(rot);
    const double dx = (x0 - x1) / 2.0, dy = (y0 - y1) / 2.0;
    double x1p = cosR * dx + sinR * dy, y1p = -sinR * dx + cosR * dy;
    double lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
    if (lam > 1.0) {
        const double s = qSqrt(lam);
        rx *= s;
        ry *= s;
    }
    double num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p;
    double den = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
    double f = den <= 0.0 ? 0.0 : qSqrt(qMax(0.0, num / den));
    if (largeArc == sweep)
        f = -f;
    const double cxp = f * rx * y1p / ry, cyp = -f * ry * x1p / rx;
    const double cx = cosR * cxp - sinR * cyp + (x0 + x1) / 2.0;
    const double cy = sinR * cxp + cosR * cyp + (y0 + y1) / 2.0;
    auto angle = [&](double ux, double uy, double vx, double vy) {
        const double d = qSqrt(ux * ux + uy * uy) * qSqrt(vx * vx + vy * vy);
        double a = d <= 0.0 ? 0.0 : qAcos(qBound(-1.0, (ux * vx + uy * vy) / d, 1.0));
        if (ux * vy - uy * vx < 0.0)
            a = -a;
        return a;
    };
    double a0 = angle(1.0, 0.0, (x1p - cxp) / rx, (y1p - cyp) / ry);
    double da = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry);
    if (!sweep && da > 0.0)
        da -= 2.0 * M_PI;
    else if (sweep && da < 0.0)
        da += 2.0 * M_PI;
    auto E = [&](double a) {
        return QPointF(cx + rx * cosR * qCos(a) - ry * sinR * qSin(a),
            cy + rx * sinR * qCos(a) + ry * cosR * qSin(a));
    };
    auto Ep = [&](double a) {
        return QPointF(-rx * cosR * qSin(a) - ry * sinR * qCos(a),
            -rx * sinR * qSin(a) + ry * cosR * qCos(a));
    };
    const int n = qMax(1, qCeil(qAbs(da) / (M_PI / 2.0)));
    const double step = da / n;
    const double k = 4.0 / 3.0 * qTan(step / 4.0);
    for (int i = 1; i <= n; ++i) {
        const double sa = a0 + step * (i - 1), ea = a0 + step * i;
        const QPointF p0 = E(sa), p1 = E(ea);
        const QPointF c1 = p0 + Ep(sa) * k, c2 = p1 - Ep(ea) * k;
        if (i == 1 && !pts.isEmpty()) {
            Anchor &prev = pts.last();
            prev.smooth = true;
            prev.outX = c1.x();
            prev.outY = c1.y();
        }
        Anchor an;
        an.x = p1.x();
        an.y = p1.y();
        an.smooth = true;
        an.inX = c2.x();
        an.inY = c2.y();
        an.outX = p1.x();
        an.outY = p1.y();
        pts.append(an);
    }
    // Float drift lands the arc end exactly on the endpoint.
    pts.last().x = x1;
    pts.last().y = y1;
}

// Path d interpreter. One Sub per moveto; smooth flags carry cubics so
// the pen renderer replays them exactly.
QList<Sub> parsePathData(const QString &d)
{
    QList<Sub> subs;
    const QList<QString> toks = tokenizePath(d);
    int i = 0;
    auto take = [&](double fallback = 0.0) {
        if (i < toks.size() && !isCommand(toks.at(i))) {
            const double v = toks.at(i).toDouble();
            ++i;
            return v;
        }
        return fallback;
    };
    char cmd = 0;
    double cx = 0.0, cy = 0.0, sx = 0.0, sy = 0.0;
    double prevCx2 = 0.0, prevCy2 = 0.0, prevQx = 0.0, prevQy = 0.0;
    char prevCubic = 0, prevQuad = 0;
    Sub *cur = nullptr;
    auto needSub = [&]() {
        if (!cur) {
            subs.append(Sub());
            cur = &subs.last();
        }
    };
    auto lineAnchor = [&](double x, double y) {
        needSub();
        Anchor a;
        a.x = x;
        a.y = y;
        a.inX = x;
        a.inY = y;
        a.outX = x;
        a.outY = y;
        cur->pts.append(a);
    };
    auto cubicAnchor = [&](double x, double y, double c1x, double c1y, double c2x, double c2y) {
        needSub();
        if (!cur->pts.isEmpty()) {
            Anchor &p = cur->pts.last();
            p.smooth = true;
            p.outX = c1x;
            p.outY = c1y;
        }
        Anchor a;
        a.x = x;
        a.y = y;
        a.smooth = true;
        a.inX = c2x;
        a.inY = c2y;
        a.outX = x;
        a.outY = y;
        cur->pts.append(a);
    };
    while (i < toks.size()) {
        if (isCommand(toks.at(i))) {
            cmd = toks.at(i).at(0).toLatin1();
            ++i;
            if (cmd == 'Z' || cmd == 'z') {
                if (cur && cur->pts.size() > 1)
                    cur->closed = true;
                if (cur && !cur->pts.isEmpty()) {
                    cx = cur->pts.first().x;
                    cy = cur->pts.first().y;
                } else {
                    cx = sx;
                    cy = sy;
                }
                prevCubic = 0;
                prevQuad = 0;
                continue;
            }
        }
        if (cmd == 0)
            break;
        const bool rel = cmd >= 'a' && cmd <= 'z';
        const auto X = [&](double v) { return rel ? cx + v : v; };
        const auto Y = [&](double v) { return rel ? cy + v : v; };
        switch (cmd) {
        case 'M':
        case 'm': {
            const double x = X(take()), y = Y(take());
            subs.append(Sub());
            cur = &subs.last();
            Anchor a;
            a.x = x;
            a.y = y;
            a.inX = x;
            a.inY = y;
            a.outX = x;
            a.outY = y;
            cur->pts.append(a);
            cx = sx = x;
            cy = sy = y;
            cmd = rel ? 'l' : 'L';
            prevCubic = 0;
            prevQuad = 0;
            break;
        }
        case 'L':
        case 'l': {
            const double x = X(take()), y = Y(take());
            lineAnchor(x, y);
            cx = x;
            cy = y;
            prevCubic = 0;
            prevQuad = 0;
            break;
        }
        case 'H':
        case 'h': {
            const double x = X(take());
            lineAnchor(x, cy);
            cx = x;
            prevCubic = 0;
            prevQuad = 0;
            break;
        }
        case 'V':
        case 'v': {
            const double y = Y(take());
            lineAnchor(cx, y);
            cy = y;
            prevCubic = 0;
            prevQuad = 0;
            break;
        }
        case 'C':
        case 'c': {
            const double c1x = X(take()), c1y = Y(take()), c2x = X(take()), c2y = Y(take()),
                         x = X(take()), y = Y(take());
            cubicAnchor(x, y, c1x, c1y, c2x, c2y);
            prevCx2 = c2x;
            prevCy2 = c2y;
            prevCubic = cmd;
            prevQuad = 0;
            cx = x;
            cy = y;
            break;
        }
        case 'S':
        case 's': {
            const double c2x = X(take()), c2y = Y(take()), x = X(take()), y = Y(take());
            double c1x = cx, c1y = cy;
            if (prevCubic == 'C' || prevCubic == 'c' || prevCubic == 'S' || prevCubic == 's') {
                c1x = 2 * cx - prevCx2;
                c1y = 2 * cy - prevCy2;
            }
            cubicAnchor(x, y, c1x, c1y, c2x, c2y);
            prevCx2 = c2x;
            prevCy2 = c2y;
            prevCubic = cmd;
            prevQuad = 0;
            cx = x;
            cy = y;
            break;
        }
        case 'Q':
        case 'q': {
            const double qx = X(take()), qy = Y(take()), x = X(take()), y = Y(take());
            cubicAnchor(x, y, cx + 2.0 / 3.0 * (qx - cx), cy + 2.0 / 3.0 * (qy - cy),
                x + 2.0 / 3.0 * (qx - x), y + 2.0 / 3.0 * (qy - y));
            prevQx = qx;
            prevQy = qy;
            prevQuad = cmd;
            prevCubic = 0;
            cx = x;
            cy = y;
            break;
        }
        case 'T':
        case 't': {
            const double x = X(take()), y = Y(take());
            double qx = cx, qy = cy;
            if (prevQuad == 'Q' || prevQuad == 'q' || prevQuad == 'T' || prevQuad == 't') {
                qx = 2 * cx - prevQx;
                qy = 2 * cy - prevQy;
            }
            cubicAnchor(x, y, cx + 2.0 / 3.0 * (qx - cx), cy + 2.0 / 3.0 * (qy - cy),
                x + 2.0 / 3.0 * (qx - x), y + 2.0 / 3.0 * (qy - y));
            prevQx = qx;
            prevQy = qy;
            prevQuad = cmd;
            prevCubic = 0;
            cx = x;
            cy = y;
            break;
        }
        case 'A':
        case 'a': {
            const double rx = take(), ry = take(), rot = take();
            const bool large = take() != 0.0, sweep = take() != 0.0;
            const double x = X(take()), y = Y(take());
            needSub();
            if (cur->pts.isEmpty())
                lineAnchor(cx, cy);
            const int before = cur->pts.size();
            arcTo(cur->pts, cx, cy, qAbs(rx), qAbs(ry), rot, large, sweep, x, y);
            if (cur->pts.size() == before)
                lineAnchor(x, y);
            else {
                // Arc end lands exactly; keep the interpreter in sync.
                cur->pts.last().x = x;
                cur->pts.last().y = y;
            }
            prevCubic = 0;
            prevQuad = 0;
            cx = x;
            cy = y;
            break;
        }
        default:
            ++i;
            break;
        }
    }
    // Drop empty moveto-only subs.
    QList<Sub> out;
    for (const Sub &s : subs) {
        if (!s.pts.isEmpty())
            out.append(s);
    }
    return out;
}

void applyTransform(QList<Sub> &subs, const QTransform &t)
{
    if (t.isIdentity())
        return;
    for (Sub &s : subs) {
        for (Anchor &p : s.pts) {
            QPointF a = t.map(QPointF(p.x, p.y));
            QPointF in = t.map(QPointF(p.inX, p.inY));
            QPointF ou = t.map(QPointF(p.outX, p.outY));
            p.x = a.x();
            p.y = a.y();
            p.inX = in.x();
            p.inY = in.y();
            p.outX = ou.x();
            p.outY = ou.y();
        }
    }
}

// Rounded-rect corner as one cubic (kappa), appended as a smooth end.
void rectCorner(QList<Anchor> &pts, double ex, double ey, double hx, double hy)
{
    Anchor a;
    a.x = ex;
    a.y = ey;
    a.smooth = true;
    a.inX = hx;
    a.inY = hy;
    a.outX = ex;
    a.outY = ey;
    pts.append(a);
}

QList<Sub> shapeSubs(const QString &tag, const QXmlStreamAttributes &a)
{
    QList<Sub> out;
    if (tag == QLatin1String("rect")) {
        const double x = numAttr(a, "x", 0.0), y = numAttr(a, "y", 0.0);
        const double w = numAttr(a, "width", 0.0), h = numAttr(a, "height", 0.0);
        if (w <= 0.0 || h <= 0.0)
            return out;
        double rx = numAttr(a, "rx", 0.0), ry = numAttr(a, "ry", 0.0);
        if (a.hasAttribute(QLatin1String("rx")) && !a.hasAttribute(QLatin1String("ry")))
            ry = rx;
        if (a.hasAttribute(QLatin1String("ry")) && !a.hasAttribute(QLatin1String("rx")))
            rx = ry;
        rx = qBound(0.0, rx, w / 2.0);
        ry = qBound(0.0, ry, h / 2.0);
        Sub s;
        s.closed = true;
        const double k = 0.5522847498;
        auto corner = [&](double ex, double ey, double hx, double hy) {
            rectCorner(s.pts, ex, ey, hx, hy);
        };
        auto line = [&](double ex, double ey) {
            Anchor p;
            p.x = ex;
            p.y = ey;
            p.inX = ex;
            p.inY = ey;
            p.outX = ex;
            p.outY = ey;
            s.pts.append(p);
        };
        // Start at top edge after the top-left corner, clockwise.
        Anchor start;
        start.x = x + rx;
        start.y = y;
        start.inX = start.x;
        start.inY = start.y;
        start.outX = start.x;
        start.outY = start.y;
        s.pts.append(start);
        if (rx > 0.0 || ry > 0.0) {
            // Top edge -> top-right corner -> right edge -> ... each
            // corner a smooth cubic, edges plain lines.
            line(x + w - rx, y);
            // Outgoing handle of the edge end aims along the edge into
            // the corner start; set it before appending the corner.
            Anchor &e0 = s.pts.last();
            e0.smooth = true;
            e0.outX = x + w - rx + rx * k;
            e0.outY = y;
            corner(x + w, y + ry, x + w, y + ry - ry * k);
            line(x + w, y + h - ry);
            Anchor &e1 = s.pts.last();
            e1.smooth = true;
            e1.outX = x + w;
            e1.outY = y + h - ry + ry * k;
            corner(x + w - rx, y + h, x + w - rx + rx * k, y + h);
            line(x + rx, y + h);
            Anchor &e2 = s.pts.last();
            e2.smooth = true;
            e2.outX = x + rx - rx * k;
            e2.outY = y + h;
            corner(x, y + h - ry, x, y + h - ry + ry * k);
            line(x, y + ry);
            Anchor &e3 = s.pts.last();
            e3.smooth = true;
            e3.outX = x;
            e3.outY = y + ry - ry * k;
            corner(x + rx, y, x + rx - rx * k, y);
        } else {
            line(x + w, y);
            line(x + w, y + h);
            line(x, y + h);
        }
        out.append(s);
        return out;
    }
    if (tag == QLatin1String("circle") || tag == QLatin1String("ellipse")) {
        const double cx = numAttr(a, "cx", 0.0), cy = numAttr(a, "cy", 0.0);
        double rx = tag == QLatin1String("circle") ? numAttr(a, "r", 0.0) : numAttr(a, "rx", 0.0);
        double ry = tag == QLatin1String("circle") ? rx : numAttr(a, "ry", 0.0);
        if (rx <= 0.0 || ry <= 0.0)
            return out;
        const double k = 0.5522847498;
        Sub s;
        s.closed = true;
        const double hx[4] = {cx + rx, cx, cx - rx, cx};
        const double hy[4] = {cy, cy + ry, cy, cy - ry};
        for (int i = 0; i < 4; ++i) {
            Anchor p;
            p.x = hx[i];
            p.y = hy[i];
            p.smooth = true;
            p.inX = hx[i];
            p.inY = hy[i];
            p.outX = hx[i];
            p.outY = hy[i];
            s.pts.append(p);
        }
        // Quadrant tangents: at angle a the outgoing handle leads by k.
        const double angs[4] = {0.0, M_PI / 2.0, M_PI, 3.0 * M_PI / 2.0};
        for (int i = 0; i < 4; ++i) {
            const double a0 = angs[i], a1 = angs[(i + 1) % 4];
            const double t0x = -rx * qSin(a0), t0y = ry * qCos(a0);
            const double t1x = -rx * qSin(a1), t1y = ry * qCos(a1);
            Anchor &p0 = s.pts[i];
            Anchor &p1 = s.pts[(i + 1) % 4];
            p0.outX = p0.x + t0x * k;
            p0.outY = p0.y + t0y * k;
            p1.inX = p1.x - t1x * k;
            p1.inY = p1.y - t1y * k;
        }
        out.append(s);
        return out;
    }
    if (tag == QLatin1String("line")) {
        Sub s;
        for (int e = 0; e < 2; ++e) {
            Anchor p;
            p.x = e == 0 ? numAttr(a, "x1", 0.0) : numAttr(a, "x2", 0.0);
            p.y = e == 0 ? numAttr(a, "y1", 0.0) : numAttr(a, "y2", 0.0);
            p.inX = p.x;
            p.inY = p.y;
            p.outX = p.x;
            p.outY = p.y;
            s.pts.append(p);
        }
        out.append(s);
        return out;
    }
    if (tag == QLatin1String("polyline") || tag == QLatin1String("polygon")) {
        static const QRegularExpression num(QStringLiteral("[-+]?\\d*\\.?\\d+(?:[eE][-+]?\\d+)?"));
        QList<double> v;
        QRegularExpressionMatchIterator it = num.globalMatch(a.value(QLatin1String("points")).toString());
        while (it.hasNext())
            v.append(it.next().captured(0).toDouble());
        Sub s;
        s.closed = tag == QLatin1String("polygon") && v.size() >= 4;
        for (int i = 0; i + 1 < v.size(); i += 2) {
            Anchor p;
            p.x = v.at(i);
            p.y = v.at(i + 1);
            p.inX = p.x;
            p.inY = p.y;
            p.outX = p.x;
            p.outY = p.y;
            s.pts.append(p);
        }
        if (!s.pts.isEmpty())
            out.append(s);
        return out;
    }
    if (tag == QLatin1String("path"))
        return parsePathData(a.value(QLatin1String("d")).toString());
    return out;
}

} // namespace

// Element tree: one pre-pass builds this so <use> resolves forward
// references and cycles stay detectable. Attributes ride along verbatim
// (QXmlStreamAttributes), so shape/text converters run unchanged.
struct DomNode {
    QString tag;
    QXmlStreamAttributes attrs;
    struct Chunk {
        bool isText = false;
        QString text;
        DomNode *node = nullptr;
    };
    QList<Chunk> content;
};

void deleteDom(DomNode *n)
{
    if (!n)
        return;
    for (const DomNode::Chunk &c : n->content) {
        if (!c.isText)
            deleteDom(c.node);
    }
    delete n;
}

// Local attribute by name, namespace-agnostic (finds xlink:href too).
QString attrLocal(const QXmlStreamAttributes &a, const char *key)
{
    const QString k = QString::fromLatin1(key);
    for (const QXmlStreamAttribute &attr : a) {
        if (attr.name().compare(k, Qt::CaseInsensitive) == 0
            || attr.qualifiedName().toString().endsWith(QLatin1Char(':') + k, Qt::CaseInsensitive))
            return attr.value().toString();
    }
    return {};
}

DomNode *buildDom(QXmlStreamReader &xml, QHash<QString, DomNode *> &ids)
{
    DomNode *root = nullptr;
    QList<DomNode *> stack;
    while (!xml.atEnd() && !xml.hasError()) {
        const QXmlStreamReader::TokenType tok = xml.readNext();
        if (tok == QXmlStreamReader::StartElement) {
            DomNode *n = new DomNode();
            n->tag = xml.name().toString().toLower();
            n->attrs = xml.attributes();
            const QString id = attrLocal(n->attrs, "id");
            if (!id.isEmpty() && !ids.contains(id))
                ids[id] = n;
            if (!stack.isEmpty()) {
                DomNode::Chunk c;
                c.node = n;
                stack.last()->content.append(c);
            } else if (!root) {
                root = n;
            } else {
                // Stray top-level element past the root: drop it.
                deleteDom(n);
                continue;
            }
            stack.append(n);
        } else if (tok == QXmlStreamReader::EndElement) {
            if (!stack.isEmpty())
                stack.removeLast();
        } else if (tok == QXmlStreamReader::Characters) {
            if (!stack.isEmpty()) {
                DomNode *top = stack.last();
                if (!top->content.isEmpty() && top->content.last().isText)
                    top->content.last().text += xml.text().toString();
                else {
                    DomNode::Chunk c;
                    c.isText = true;
                    c.text = xml.text().toString();
                    top->content.append(c);
                }
            }
        }
    }
    return root;
}

bool isDrawable(const QString &tag)
{
    return tag == QLatin1String("path") || tag == QLatin1String("rect")
        || tag == QLatin1String("circle") || tag == QLatin1String("ellipse")
        || tag == QLatin1String("line") || tag == QLatin1String("polyline")
        || tag == QLatin1String("polygon");
}

bool isSilentContainer(const QString &tag)
{
    // Never renders directly (only feeds <use> through the id table).
    return tag == QLatin1String("defs") || tag == QLatin1String("clippath")
        || tag == QLatin1String("mask") || tag == QLatin1String("pattern")
        || tag == QLatin1String("filter") || tag == QLatin1String("marker")
        || tag == QLatin1String("symbol");
}

// Shared paint resolution for converted shapes and glyph runs.
void appendShape(QList<Sub> subs, const Style &st, QList<Shape> &shapes)
{
    QList<Sub> kept;
    for (const Sub &s : subs) {
        if (s.pts.size() >= 2)
            kept.append(s);
    }
    if (kept.isEmpty())
        return;
    Shape sh;
    sh.subs = kept;
    const double op = qBound(0.0, st.opacity, 1.0);
    if (st.hasFill && st.fill.alpha() > 0) {
        sh.fill = withOpacity(st.fill, op * st.fillOpacity);
        sh.penFill = true;
    } else if (st.hasFill) {
        sh.penFill = false;
    } else {
        sh.fill = withOpacity(QColor(QStringLiteral("#000000")), op);
        sh.penFill = true;
    }
    if (st.hasStroke && st.stroke.alpha() > 0 && st.strokeWidth > 0.0) {
        sh.stroke = withOpacity(st.stroke, op * st.strokeOpacity);
        sh.strokeWidth = st.strokeWidth;
    }
    if (!st.strokeCap.isEmpty())
        sh.strokeCap = st.strokeCap == QLatin1String("butt") ? QStringLiteral("flat") : st.strokeCap;
    if (!st.strokeJoin.isEmpty())
        sh.strokeJoin = st.strokeJoin;
    shapes.append(sh);
}

QFont importFont(const Style &st)
{
    QFont f(st.fontFamily.isEmpty() ? QStringLiteral("sans-serif") : st.fontFamily);
    f.setPixelSize(qMax(1, qRound(st.fontSize)));
    f.setWeight(QFont::Weight(qBound(100, qRound(st.fontWeight / 100.0) * 100, 900)));
    f.setStyle(st.fontItalic ? QFont::StyleItalic : QFont::StyleNormal);
    if (st.letterSpacing != 0.0)
        f.setLetterSpacing(QFont::AbsoluteSpacing, st.letterSpacing);
    return f;
}

// One positioned text run with its resolved font.
struct TextRun {
    QString str;
    double x = 0.0;
    double y = 0.0;
    QFont font;
};

// Whitespace collapse for text content (xml:space="preserve" keeps raw).
QString collapseText(const QString &s, bool preserve)
{
    if (preserve)
        return s;
    QString out;
    out.reserve(s.size());
    bool ws = false;
    for (QChar c : s) {
        if (c == QLatin1Char(' ') || c == QLatin1Char('\t') || c == QLatin1Char('\n')
            || c == QLatin1Char('\r') || c == QLatin1Char('\f')) {
            ws = true;
            continue;
        }
        if (ws && !out.isEmpty())
            out += QLatin1Char(' ');
        ws = false;
        out += c;
    }
    return out;
}

// Document-order run collection. Absolute x/y (first values) reset the
// pen; dx/dy shift it. Whitespace-only chunks between content read as a
// single space; leading indentation never does.
void collectTextRuns(DomNode *node, const Style &style, bool preserve, double &penX, double &penY,
    QList<TextRun> &runs)
{
    const QString keep = attrLocal(node->attrs, "space");
    if (!keep.isEmpty())
        preserve = keep.compare(QLatin1String("preserve"), Qt::CaseInsensitive) == 0;
    for (const DomNode::Chunk &c : node->content) {
        if (c.isText) {
            const QString s = collapseText(c.text, preserve);
            if (s.isEmpty())
                continue;
            if (s.trimmed().isEmpty()) {
                if (!runs.isEmpty() && !runs.last().str.endsWith(QLatin1Char(' ')))
                    runs.last().str += QLatin1Char(' ');
                penX += QFontMetricsF(importFont(style)).horizontalAdvance(QLatin1Char(' '));
                continue;
            }
            TextRun r;
            r.str = s;
            r.x = penX;
            r.y = penY;
            r.font = importFont(style);
            runs.append(r);
            penX += QFontMetricsF(r.font).horizontalAdvance(s);
            continue;
        }
        DomNode *kid = c.node;
        if (kid->tag != QLatin1String("tspan"))
            continue;
        Style st = childStyle(style, elementStyle(kid->attrs));
        const QString xs = attrLocal(kid->attrs, "x"), ys = attrLocal(kid->attrs, "y");
        static const QRegularExpression num(QStringLiteral("[-+]?\\d*\\.?\\d+(?:[eE][-+]?\\d+)?"));
        if (!xs.isEmpty()) {
            QRegularExpressionMatch m = num.match(xs);
            if (m.hasMatch())
                penX = m.captured(0).toDouble();
        }
        if (!ys.isEmpty()) {
            QRegularExpressionMatch m = num.match(ys);
            if (m.hasMatch())
                penY = m.captured(0).toDouble();
        }
        bool ok = false;
        const double dx = parseLength(attrLocal(kid->attrs, "dx"), &ok);
        if (ok)
            penX += dx;
        const double dy = parseLength(attrLocal(kid->attrs, "dy"), &ok);
        if (ok)
            penY += dy;
        collectTextRuns(kid, st, preserve, penX, penY, runs);
    }
}

// Glyph outlines via the font engine: one pen subpath per contour,
// closed when the contour returns to its start (holes included, the
// painter fills odd-even like the source).
QList<Sub> glyphOutlines(const QPainterPath &path)
{
    QList<Sub> out;
    Sub cur;
    double c1x = 0.0, c1y = 0.0;
    bool haveC1 = false;
    auto flush = [&]() {
        if (cur.pts.size() >= 2) {
            const Anchor &f = cur.pts.first(), &l = cur.pts.last();
            if (qAbs(f.x - l.x) < 1e-4 && qAbs(f.y - l.y) < 1e-4) {
                cur.pts.removeLast();
                if (cur.pts.size() >= 2)
                    cur.closed = true;
            }
        }
        if (cur.pts.size() >= 2)
            out.append(cur);
        cur = Sub();
    };
    const int n = path.elementCount();
    for (int i = 0; i < n; ++i) {
        const QPainterPath::Element e = path.elementAt(i);
        if (e.type == QPainterPath::MoveToElement) {
            if (!cur.pts.isEmpty())
                flush();
            Anchor a;
            a.x = e.x;
            a.y = e.y;
            a.inX = e.x;
            a.inY = e.y;
            a.outX = e.x;
            a.outY = e.y;
            cur.pts.append(a);
            haveC1 = false;
        } else if (e.type == QPainterPath::LineToElement) {
            Anchor a;
            a.x = e.x;
            a.y = e.y;
            a.inX = e.x;
            a.inY = e.y;
            a.outX = e.x;
            a.outY = e.y;
            cur.pts.append(a);
            haveC1 = false;
        } else if (e.type == QPainterPath::CurveToElement) {
            c1x = e.x;
            c1y = e.y;
            haveC1 = true;
        } else if (e.type == QPainterPath::CurveToDataElement) {
            if (!haveC1) {
                // Malformed sequence: second control point doubles as
                // the first, so nothing renders bent that isn't.
                c1x = e.x;
                c1y = e.y;
                haveC1 = true;
                continue;
            }
            if (i + 1 < n && path.elementAt(i + 1).type == QPainterPath::CurveToDataElement) {
                const QPainterPath::Element c2 = e;
                const QPainterPath::Element end = path.elementAt(i + 1);
                if (!cur.pts.isEmpty()) {
                    Anchor &p = cur.pts.last();
                    p.smooth = true;
                    p.outX = c1x;
                    p.outY = c1y;
                }
                Anchor a;
                a.x = end.x;
                a.y = end.y;
                a.smooth = true;
                a.inX = c2.x;
                a.inY = c2.y;
                a.outX = end.x;
                a.outY = end.y;
                cur.pts.append(a);
                ++i;
            } else {
                // Dangling control: fall back to a corner anchor.
                Anchor a;
                a.x = e.x;
                a.y = e.y;
                a.inX = e.x;
                a.inY = e.y;
                a.outX = e.x;
                a.outY = e.y;
                cur.pts.append(a);
            }
            haveC1 = false;
        }
    }
    if (!cur.pts.isEmpty())
        flush();
    return out;
}

// text-anchor shifts the run start by its own advance (exact for the
// common single-run label; multi-run anchored spans keep positions).
void convertText(DomNode *node, const Style &style, const QTransform &ctm, QList<Shape> &shapes)
{
    double penX = 0.0, penY = 0.0;
    const QString xs = attrLocal(node->attrs, "x"), ys = attrLocal(node->attrs, "y");
    static const QRegularExpression num(QStringLiteral("[-+]?\\d*\\.?\\d+(?:[eE][-+]?\\d+)?"));
    if (!xs.isEmpty()) {
        QRegularExpressionMatch m = num.match(xs);
        if (m.hasMatch())
            penX = m.captured(0).toDouble();
    }
    if (!ys.isEmpty()) {
        QRegularExpressionMatch m = num.match(ys);
        if (m.hasMatch())
            penY = m.captured(0).toDouble();
    }
    bool ok = false;
    const double dx = parseLength(attrLocal(node->attrs, "dx"), &ok);
    if (ok)
        penX += dx;
    const double dy = parseLength(attrLocal(node->attrs, "dy"), &ok);
    if (ok)
        penY += dy;
    QList<TextRun> runs;
    collectTextRuns(node, style, false, penX, penY, runs);
    const QString anchor = attrLocal(node->attrs, "text-anchor").toLower();
    QList<Sub> subs;
    for (const TextRun &r : runs) {
        if (r.str.isEmpty())
            continue;
        double rx = r.x;
        if ((anchor == QLatin1String("middle") || anchor == QLatin1String("end"))
            && !r.str.trimmed().isEmpty()) {
            const double adv = QFontMetricsF(r.font).horizontalAdvance(r.str);
            rx -= anchor == QLatin1String("middle") ? adv / 2.0 : adv;
        }
        QPainterPath pp;
        pp.addText(rx, r.y, r.font, r.str);
        subs.append(glyphOutlines(pp));
    }
    if (subs.isEmpty())
        return;
    applyTransform(subs, ctm);
    appendShape(subs, style, shapes);
}

// Viewport mapping for nested svg/symbol viewports (meet only; slice
// would need clipping the import does not do).
QTransform viewportMap(double vbx, double vby, double vbw, double vbh, double vpw, double vph,
    const QString &par)
{
    QTransform t;
    t.translate(-vbx, -vby);
    if (vbw <= 0.0 || vbh <= 0.0 || vpw <= 0.0 || vph <= 0.0)
        return t;
    QStringList bits = par.toLower().split(QLatin1Char(' '), Qt::SkipEmptyParts);
    const QString mode = bits.size() > 1 ? bits.at(1) : QStringLiteral("meet");
    if (mode == QLatin1String("none")) {
        t.scale(vpw / vbw, vph / vbh);
        return t;
    }
    const double k = qMin(vpw / vbw, vph / vbh);
    const QString align = bits.isEmpty() ? QStringLiteral("xmidymid") : bits.at(0);
    double ox = 0.0, oy = 0.0;
    if (align.contains(QLatin1String("xmid")))
        ox = (vpw - vbw * k) / 2.0;
    else if (align.contains(QLatin1String("xmax")))
        ox = vpw - vbw * k;
    if (align.contains(QLatin1String("ymid")))
        oy = (vph - vbh * k) / 2.0;
    else if (align.contains(QLatin1String("ymax")))
        oy = vph - vbh * k;
    t.scale(k, k);
    t.translate(ox, oy);
    return t;
}

QList<double> numList(const QString &s, int need)
{
    static const QRegularExpression num(QStringLiteral("[-+]?\\d*\\.?\\d+(?:[eE][-+]?\\d+)?"));
    QList<double> v;
    QRegularExpressionMatchIterator it = num.globalMatch(s);
    while (it.hasNext() && (need <= 0 || v.size() < need))
        v.append(it.next().captured(0).toDouble());
    return v;
}

void walkNode(DomNode *node, const QTransform &ctm, const Style &style, bool inDefs,
    const QHash<QString, DomNode *> &ids, QSet<QString> &activeUses, int useDepth, QList<Shape> &shapes,
    bool viaUse = false)
{
    if (!node)
        return;
    const QString &tag = node->tag;
    Style st = childStyle(style, elementStyle(node->attrs));
    QTransform local = ctm;
    if (node->attrs.hasAttribute(QLatin1String("transform"))) {
        // Element transforms nest inside the parent CTM (applied first).
        local = parseTransform(node->attrs.value(QLatin1String("transform")).toString()) * local;
    }
    if (!st.display)
        return;
    if (tag == QLatin1String("use")) {
        QString href = attrLocal(node->attrs, "href");
        if (href.startsWith(QLatin1Char('#')))
            href = href.mid(1);
        if (href.isEmpty() || !ids.contains(href) || activeUses.contains(href) || useDepth > 32)
            return;
        DomNode *target = ids.value(href);
        // Symbol viewports map viewBox to the use width/height first,
        // then the x/y shift, then the outer CTM (explicit products:
        // transform methods prepend, so call order misleads here).
        bool okX = false, okY = false;
        const double ux = parseLength(attrLocal(node->attrs, "x"), &okX);
        const double uy = parseLength(attrLocal(node->attrs, "y"), &okY);
        const double tx = okX ? ux : 0.0, ty = okY ? uy : 0.0;
        QTransform uc = local;
        uc.translate(tx, ty);
        if (target->tag == QLatin1String("symbol") || target->tag == QLatin1String("svg")) {
            const QList<double> vb = numList(attrLocal(target->attrs, "viewbox"), 4);
            bool okW = false, okH = false;
            const double vw = parseLength(attrLocal(node->attrs, "width"), &okW);
            const double vh = parseLength(attrLocal(node->attrs, "height"), &okH);
            if (vb.size() >= 4 && vb.at(2) > 0.0 && vb.at(3) > 0.0) {
                if (okW && vw > 0.0 && okH && vh > 0.0)
                    uc = viewportMap(vb.at(0), vb.at(1), vb.at(2), vb.at(3), vw, vh,
                                       attrLocal(target->attrs, "preserveaspectratio"))
                        * uc;
                else
                    uc = QTransform::fromTranslate(-vb.at(0), -vb.at(1)) * uc;
            }
        }
        activeUses.insert(href);
        // Referenced symbols render their children (a direct walk would
        // hit the silent-container rule below).
        const bool renderRoot = target->tag == QLatin1String("symbol");
        walkNode(target, uc, st, false, ids, activeUses, useDepth + 1, shapes, renderRoot);
        activeUses.remove(href);
        return;
    }
    if (tag == QLatin1String("text")) {
        if (!inDefs)
            convertText(node, st, local, shapes);
        return;
    }
    if (isDrawable(tag)) {
        if (!inDefs) {
            QList<Sub> subs = shapeSubs(tag, node->attrs);
            applyTransform(subs, local);
            appendShape(subs, st, shapes);
        }
        return;
    }
    if (isSilentContainer(tag) && !viaUse)
        return;
    if (tag == QLatin1String("svg")) {
        // Nested viewport: x/y shift plus an optional viewBox fit.
        bool okX = false, okY = false;
        const double nx = parseLength(attrLocal(node->attrs, "x"), &okX);
        const double ny = parseLength(attrLocal(node->attrs, "y"), &okY);
        local.translate(okX ? nx : 0.0, okY ? ny : 0.0);
        const QList<double> vb = numList(attrLocal(node->attrs, "viewbox"), 4);
        bool okW = false, okH = false;
        const double nw = parseLength(attrLocal(node->attrs, "width"), &okW);
        const double nh = parseLength(attrLocal(node->attrs, "height"), &okH);
        if (vb.size() >= 4 && vb.at(2) > 0.0 && vb.at(3) > 0.0 && okW && nw > 0.0 && okH && nh > 0.0)
            local = viewportMap(vb.at(0), vb.at(1), vb.at(2), vb.at(3), nw, nh,
                attrLocal(node->attrs, "preserveaspectratio"))
                * local;
    }
    for (const DomNode::Chunk &c : node->content) {
        if (!c.isText)
            walkNode(c.node, local, st, inDefs, ids, activeUses, useDepth, shapes);
    }
}

QVariantMap importFile(const QString &localPath, double maxSize)
{
    QVariantMap out;
    out[QStringLiteral("ok")] = false;
    QFile f(localPath);
    if (!f.exists()) {
        out[QStringLiteral("error")] = QStringLiteral("Could not read that SVG file.");
        return out;
    }
    if (f.size() > 10 * 1024 * 1024) {
        out[QStringLiteral("error")] = QStringLiteral("That SVG is too large to vectorize; placed as an image instead.");
        return out;
    }
    if (!f.open(QIODevice::ReadOnly)) {
        out[QStringLiteral("error")] = QStringLiteral("Could not read that SVG file.");
        return out;
    }
    QXmlStreamReader xml(&f);
    QHash<QString, DomNode *> ids;
    DomNode *dom = buildDom(xml, ids);
    if (xml.hasError()) {
        deleteDom(dom);
        out[QStringLiteral("error")] = QStringLiteral("That SVG could not be parsed; placed as an image instead.");
        return out;
    }
    QList<Shape> shapes;
    double svgW = 0.0, svgH = 0.0, vbX = 0.0, vbY = 0.0, vbW = 0.0, vbH = 0.0;
    bool haveVb = false, haveSize = false;
    if (dom && dom->tag == QLatin1String("svg")) {
        bool okW = false, okH = false;
        const double w = parseLength(attrLocal(dom->attrs, "width"), &okW);
        const double h = parseLength(attrLocal(dom->attrs, "height"), &okH);
        if (okW && w > 0.0 && okH && h > 0.0) {
            svgW = w;
            svgH = h;
            haveSize = true;
        }
        const QList<double> v = numList(attrLocal(dom->attrs, "viewbox"), 4);
        if (v.size() >= 4 && v.at(2) > 0.0 && v.at(3) > 0.0) {
            vbX = v.at(0);
            vbY = v.at(1);
            vbW = v.at(2);
            vbH = v.at(3);
            haveVb = true;
        }
        Style base;
        QSet<QString> activeUses;
        walkNode(dom, QTransform(), base, false, ids, activeUses, 0, shapes);
    }
    deleteDom(dom);
    if (shapes.isEmpty()) {
        out[QStringLiteral("error")] = QStringLiteral("That SVG has no convertible shapes; placed as an image instead.");
        return out;
    }
    // viewBox mapping: shift into viewBox origin, scale to width/height.
    QTransform vbMap;
    if (haveVb) {
        vbMap.translate(-vbX, -vbY);
        if (haveSize)
            vbMap.scale(svgW / vbW, svgH / vbH);
    }
    for (Shape &sh : shapes)
        applyTransform(sh.subs, vbMap);
    // Tight bbox over anchors and handles.
    double x0 = 0, y0 = 0, x1 = 0, y1 = 0;
    bool first = true;
    for (const Shape &sh : shapes) {
        for (const Sub &s : sh.subs) {
            for (const Anchor &p : s.pts) {
                const double xs[3] = {p.x, p.inX, p.outX};
                const double ys[3] = {p.y, p.inY, p.outY};
                for (int k = 0; k < 3; ++k) {
                    if (first) {
                        x0 = x1 = xs[k];
                        y0 = y1 = ys[k];
                        first = false;
                    } else {
                        x0 = qMin(x0, xs[k]);
                        y0 = qMin(y0, ys[k]);
                        x1 = qMax(x1, xs[k]);
                        y1 = qMax(y1, ys[k]);
                    }
                }
            }
        }
    }
    double bw = qMax(1.0, x1 - x0), bh = qMax(1.0, y1 - y0);
    double k = 1.0;
    if (maxSize > 0.0)
        k = qMin(1.0, maxSize / qMax(bw, bh));
    const double w = qMax(1.0, bw * k), h = qMax(1.0, bh * k);
    QVariantList paths;
    for (const Shape &sh : shapes) {
        QVariantList subs;
        for (const Sub &s : sh.subs) {
            QVariantList pts;
            for (const Anchor &p : s.pts) {
                pts.append(QVariantMap{
                    {QStringLiteral("x"), round2((p.x - x0) * k)},
                    {QStringLiteral("y"), round2((p.y - y0) * k)},
                    {QStringLiteral("smooth"), p.smooth},
                    {QStringLiteral("inX"), round2((p.inX - x0) * k)},
                    {QStringLiteral("inY"), round2((p.inY - y0) * k)},
                    {QStringLiteral("outX"), round2((p.outX - x0) * k)},
                    {QStringLiteral("outY"), round2((p.outY - y0) * k)},
                });
            }
            subs.append(QVariantMap{
                {QStringLiteral("closed"), s.closed},
                {QStringLiteral("pts"), pts},
            });
        }
        QVariantMap entry;
        entry[QStringLiteral("pathData")] = subs;
        entry[QStringLiteral("fill")] = sh.fill.name(QColor::HexArgb);
        entry[QStringLiteral("penFill")] = sh.penFill;
        entry[QStringLiteral("stroke")] = sh.stroke.alpha() > 0
            ? sh.stroke.name(QColor::HexArgb)
            : QStringLiteral("#00000000");
        entry[QStringLiteral("strokeWidth")] = round2(sh.strokeWidth * k);
        entry[QStringLiteral("strokeCap")] = sh.strokeCap;
        entry[QStringLiteral("strokeJoin")] = sh.strokeJoin;
        paths.append(entry);
    }
    out[QStringLiteral("ok")] = true;
    out[QStringLiteral("width")] = w;
    out[QStringLiteral("height")] = h;
    out[QStringLiteral("paths")] = paths;
    return out;
}

} // namespace SvgImport
