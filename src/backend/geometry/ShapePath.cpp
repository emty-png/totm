#include "ShapePath.h"

#include "EffectPainter.h"

#include <QTransform>
#include <QtGlobal>

#include <functional>

namespace ShapePath {

bool isOp(const QString &op)
{
    const QString o = normOp(op);
    return o == QLatin1String("union") || o == QLatin1String("subtract") || o == QLatin1String("intersect")
        || o == QLatin1String("exclude");
}

QString normOp(const QString &op)
{
    const QString o = op.trimmed().toLower();
    if (o == QLatin1String("add") || o == QLatin1String("unite"))
        return QStringLiteral("union");
    if (o == QLatin1String("difference"))
        return QStringLiteral("subtract");
    if (o == QLatin1String("intersection"))
        return QStringLiteral("intersect");
    if (o == QLatin1String("xor") || o == QLatin1String("exclusion"))
        return QStringLiteral("exclude");
    return o;
}

static QString nodeKind(const QVariantMap &node)
{
    // Snapshot shapes carry `type`; live DocNode carries `shapeType`.
    const QString t = node.value(QStringLiteral("type")).toString();
    if (!t.isEmpty())
        return t;
    return node.value(QStringLiteral("shapeType")).toString();
}

bool isCombinableNode(const QVariantMap &node)
{
    if (node.value(QStringLiteral("kind")).toString() != QLatin1String("shape"))
        return false;
    if (!node.value(QStringLiteral("visible"), true).toBool())
        return false;
    if (node.value(QStringLiteral("isMask")).toBool())
        return false;
    const QString kind = nodeKind(node);
    if (kind != QLatin1String("rectangle") && kind != QLatin1String("ellipse") && kind != QLatin1String("triangle")
        && kind != QLatin1String("star") && kind != QLatin1String("pen"))
        return false;
    const double w = node.value(QStringLiteral("w")).toDouble();
    const double h = node.value(QStringLiteral("h")).toDouble();
    if (!(w > 0.01) || !(h > 0.01))
        return false;
    if (kind == QLatin1String("pen")) {
        const QVariantList subs = node.value(QStringLiteral("pathData")).toList();
        for (const QVariant &s : subs) {
            if (s.toMap().value(QStringLiteral("pts")).toList().size() > 0)
                return true;
        }
        return false;
    }
    return true;
}

QPainterPath nodeToWorldPath(const QVariantMap &node)
{
    if (!isCombinableNode(node))
        return QPainterPath();
    const QString kind = nodeKind(node);
    const double x = node.value(QStringLiteral("x")).toDouble();
    const double y = node.value(QStringLiteral("y")).toDouble();
    const double w = node.value(QStringLiteral("w")).toDouble();
    const double h = node.value(QStringLiteral("h")).toDouble();
    if (!(w > 0.01) || !(h > 0.01))
        return QPainterPath();

    QVariantMap styleMap;
    styleMap[QStringLiteral("radius")] = node.value(QStringLiteral("radius"), 0.0);
    // Style::fromMap reads fills/strokes only for width; geometry needs
    // radius alone, so an empty stack is fine here.
    Effects::Style st = Effects::Style::fromMap(styleMap);
    Effects::PathOpts opts;
    opts.cornerRadii = node.value(QStringLiteral("cornerRadii")).toList();
    opts.points = qBound(3, node.value(QStringLiteral("points"), 5).toInt(), 12);
    opts.independentCorners = node.value(QStringLiteral("independentCorners")).toBool();
    opts.pathData = node.value(QStringLiteral("pathData")).toList();
    opts.ox = x;
    opts.oy = y;

    QRectF box(x, y, w, h);
    QPainterPath p = Effects::outlinePath(kind, box, opts, st, 1.0);
    if (p.isEmpty())
        return p;

    const double rot = node.value(QStringLiteral("rotation")).toDouble();
    const bool flipH = node.value(QStringLiteral("flipH")).toBool();
    const bool flipV = node.value(QStringLiteral("flipV")).toBool();
    if (rot != 0.0 || flipH || flipV) {
        const double cx = x + w / 2.0;
        const double cy = y + h / 2.0;
        QTransform t;
        t.translate(cx, cy);
        if (rot != 0.0)
            t.rotate(rot);
        t.scale(flipH ? -1.0 : 1.0, flipV ? -1.0 : 1.0);
        t.translate(-cx, -cy);
        p = t.map(p);
    }
    return p;
}

QPainterPath combinePaths(const QString &op, const QList<QPainterPath> &paths)
{
    const QString o = normOp(op);
    QList<QPainterPath> clean;
    for (const QPainterPath &p : paths) {
        if (!p.isEmpty())
            clean << p;
    }
    if (clean.isEmpty())
        return QPainterPath();
    if (o == QLatin1String("union")) {
        QPainterPath out = clean.first();
        for (int i = 1; i < clean.size(); ++i)
            out = out.united(clean.at(i));
        return out;
    }
    if (o == QLatin1String("intersect")) {
        QPainterPath out = clean.first();
        for (int i = 1; i < clean.size(); ++i)
            out = out.intersected(clean.at(i));
        return out;
    }
    if (o == QLatin1String("subtract")) {
        // Figma-style: first (bottommost input order is caller-owned)
        // minus the union of the rest.
        QPainterPath out = clean.first();
        for (int i = 1; i < clean.size(); ++i)
            out = out.subtracted(clean.at(i));
        return out;
    }
    if (o == QLatin1String("exclude")) {
        QPainterPath uni = clean.first();
        QPainterPath inter = clean.first();
        for (int i = 1; i < clean.size(); ++i) {
            uni = uni.united(clean.at(i));
            inter = inter.intersected(clean.at(i));
        }
        return uni.subtracted(inter);
    }
    return QPainterPath();
}

QPainterPath combineNodes(const QString &op, const QVariantList &nodes)
{
    QList<QPainterPath> paths;
    for (const QVariant &v : nodes)
        paths << nodeToWorldPath(v.toMap());
    return combinePaths(op, paths);
}

QString toSvgD(const QPainterPath &path)
{
    if (path.isEmpty())
        return QString();
    QString d;
    d.reserve(256);
    for (int i = 0; i < path.elementCount(); ++i) {
        const QPainterPath::Element e = path.elementAt(i);
        switch (e.type) {
        case QPainterPath::MoveToElement:
            d += QStringLiteral("M %1,%2").arg(e.x).arg(e.y);
            break;
        case QPainterPath::LineToElement:
            d += QStringLiteral(" L %1,%2").arg(e.x).arg(e.y);
            break;
        case QPainterPath::CurveToElement: {
            const QPainterPath::Element c2 = path.elementAt(++i);
            const QPainterPath::Element end = path.elementAt(++i);
            d += QStringLiteral(" C %1,%2 %3,%4 %5,%6").arg(e.x).arg(e.y).arg(c2.x).arg(c2.y).arg(end.x).arg(end.y);
            break;
        }
        case QPainterPath::CurveToDataElement:
            break;
        }
    }
    // Closed subpaths in QPainterPath carry no explicit flag here;
    // united/subtracted results are closed by construction.
    d += QStringLiteral(" Z");
    return d;
}

bool isBooleanGroupMap(const QVariantMap &node)
{
    if (node.value(QStringLiteral("kind")).toString() != QLatin1String("group"))
        return false;
    const QString op = normOp(node.value(QStringLiteral("boolOp"), QStringLiteral("none")).toString());
    return isOp(op);
}

QList<QVariantMap> booleanGroupsIn(const QVariantList &nodes)
{
    QList<QVariantMap> out;
    std::function<void(const QVariantList &)> walk = [&](const QVariantList &list) {
        for (const QVariant &v : list) {
            const QVariantMap n = v.toMap();
            if (n.isEmpty())
                continue;
            if (isBooleanGroupMap(n))
                out.append(n);
            if (n.value(QStringLiteral("kind")).toString() == QLatin1String("group"))
                walk(n.value(QStringLiteral("children")).toList());
        }
    };
    walk(nodes);
    return out;
}

QList<int> descendantLeafUids(const QVariantMap &group)
{
    QList<int> out;
    std::function<void(const QVariantMap &)> rec = [&](const QVariantMap &n) {
        if (n.value(QStringLiteral("kind")).toString() == QLatin1String("group")) {
            for (const QVariant &c : n.value(QStringLiteral("children")).toList())
                rec(c.toMap());
        } else {
            const int uid = n.value(QStringLiteral("uid"), -1).toInt();
            if (uid >= 0)
                out.append(uid);
        }
    };
    rec(group);
    return out;
}

} // namespace ShapePath

ShapePathHelper::ShapePathHelper(QObject *parent)
    : QObject(parent)
{
}

QString ShapePathHelper::nodeSvg(const QVariantMap &node)
{
    return ShapePath::toSvgD(ShapePath::nodeToWorldPath(node));
}

QString ShapePathHelper::combineSvg(const QVariantList &nodes, const QString &op)
{
    return ShapePath::toSvgD(ShapePath::combineNodes(op, nodes));
}

QRectF ShapePathHelper::combineBounds(const QVariantList &nodes, const QString &op)
{
    const QPainterPath p = ShapePath::combineNodes(op, nodes);
    if (p.isEmpty())
        return QRectF();
    return p.boundingRect();
}

bool ShapePathHelper::canCombineNodes(const QVariantList &nodes)
{
    int n = 0;
    for (const QVariant &v : nodes) {
        if (ShapePath::isCombinableNode(v.toMap()))
            ++n;
    }
    return n >= 2;
}

bool ShapePathHelper::isOp(const QString &op)
{
    return ShapePath::isOp(op);
}
