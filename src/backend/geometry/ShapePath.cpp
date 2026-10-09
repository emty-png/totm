#include "ShapePath.h"

#include "AppPaths.h"
#include "EffectPainter.h"

#include <QCache>
#include <QDir>
#include <QFile>
#include <QHash>
#include <QImage>
#include <QImageReader>
#include <QMutex>
#include <QPainter>
#include <QStandardPaths>
#include <QSvgRenderer>
#include <QTransform>
#include <QtGlobal>

#include <functional>
#include <vector>

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

// Depth-guarded recursion worker (defined below): nested boolean
// groups resolve bottom-up with a cycle cap.
QPainterPath nodeToWorldPathDepth(const QVariantMap &node, int depth);

QPainterPath nodeToWorldPath(const QVariantMap &node)
{
    return nodeToWorldPathDepth(node, 0);
}

namespace {

constexpr int kMaxBooleanDepth = 32;

// Shared rotation/flip bake for silhouette providers that build
// axis-aligned geometry (vectors build it inline below; text and
// image providers return unrotated paths).
QPainterPath bakeNodeTransform(QPainterPath p, const QVariantMap &node) {
    if (p.isEmpty())
        return p;
    const double x = node.value(QStringLiteral("x")).toDouble();
    const double y = node.value(QStringLiteral("y")).toDouble();
    const double w = node.value(QStringLiteral("w")).toDouble();
    const double h = node.value(QStringLiteral("h")).toDouble();
    const double rot = node.value(QStringLiteral("rotation")).toDouble();
    const bool flipH = node.value(QStringLiteral("flipH")).toBool();
    const bool flipV = node.value(QStringLiteral("flipV")).toBool();
    if (rot == 0.0 && !flipH && !flipV)
        return p;
    const double cx = x + w / 2.0;
    const double cy = y + h / 2.0;
    QTransform t;
    t.translate(cx, cy);
    if (rot != 0.0)
        t.rotate(rot);
    t.scale(flipH ? -1.0 : 1.0, flipV ? -1.0 : 1.0);
    t.translate(-cx, -cy);
    return t.map(p);
}

} // namespace

QPainterPath nodeToWorldPathDepth(const QVariantMap &node, int depth)
{
    if (depth > kMaxBooleanDepth)
        return QPainterPath();
    const QString kind = node.value(QStringLiteral("kind")).toString();
    // Nested groups resolve recursively (their own op, union for plain
    // subgroups): the nested silhouette feeds the outer fold exactly,
    // so canvas, export and SVG agree. Folded export entries carry
    // kind "boolean" with the same shape and resolve identically.
    // Masks never contribute geometry here; they clip the combined
    // result at the group level instead.
    if (kind == QLatin1String("group") || kind == QLatin1String("boolean")) {
        if (!node.value(QStringLiteral("visible"), true).toBool())
            return QPainterPath();
        const QString rawOp = node.value(QStringLiteral("boolOp"), QStringLiteral("union")).toString();
        const QString useOp = isOp(normOp(rawOp)) ? normOp(rawOp) : QStringLiteral("union");
        QList<QPainterPath> paths;
        for (const QVariant &v : node.value(QStringLiteral("children")).toList()) {
            const QVariantMap c = v.toMap();
            if (c.isEmpty() || c.value(QStringLiteral("isMask"), false).toBool())
                continue;
            paths << nodeToWorldPathDepth(c, depth + 1);
        }
        return combinePaths(useOp, paths);
    }
    // Text and image silhouettes come from their dedicated providers
    // (glyph outline, alpha trace); rotation/flip bake the same way.
    const QString shapeKind = nodeKind(node);
    if (shapeKind == QLatin1String("text"))
        return bakeNodeTransform(textNodeToPath(node), node);
    if (shapeKind == QLatin1String("image"))
        return bakeNodeTransform(imageNodeToPath(node), node);
    if (!isCombinableNode(node))
        return QPainterPath();
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
    QPainterPath p = Effects::outlinePath(shapeKind, box, opts, st, 1.0);
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
    if (clean.size() == 1)
        return clean.first();
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

// Glyph-count cap for live combines: united()/subtracted() scale
// superlinearly on hundred-element glyph paths, so very long runs
// stay out of the fold (documented v1-production limit) instead of
// stalling drags and exports. Painted leaves are unaffected.
constexpr int kMaxCombineGlyphs = 256;

QPainterPath textNodeToPath(const QVariantMap &node)
{
    if (node.value(QStringLiteral("kind")).toString() != QLatin1String("shape"))
        return QPainterPath();
    if (nodeKind(node) != QLatin1String("text"))
        return QPainterPath();
    if (!node.value(QStringLiteral("visible"), true).toBool())
        return QPainterPath();
    const double x = node.value(QStringLiteral("x")).toDouble();
    const double y = node.value(QStringLiteral("y")).toDouble();
    const double w = node.value(QStringLiteral("w")).toDouble();
    const double h = node.value(QStringLiteral("h")).toDouble();
    if (!(w > 0.01) || !(h > 0.01))
        return QPainterPath();
    const QString content = node.value(QStringLiteral("textContent")).toString();
    if (content.isEmpty() || content.size() > kMaxCombineGlyphs)
        return QPainterPath();
    const Effects::TextOpts text = Effects::textOptsForNode(node);
    // Karaoke/sweep reveal clips the painted glyphs but the boolean
    // folds the full run (documented): reveal is a paint-time effect,
    // the silhouette stays structural.
    Effects::TextOpts structural = text;
    structural.fx = false;
    const QRectF box(x, y, w, h);
    return Effects::textGlyphPath(structural, 1.0, box);
}

namespace {

struct Traced {
    QPainterPath path;
    double tileW = 1.0;
    double tileH = 1.0;
};

// Traced local paths keyed by blob name (resolution-normalized, so one
// entry serves every node size). Combines run on the GUI thread
// (preview) and the export worker (video/PNG), so all access holds
// the mutex like FramePaint's image cache.
QCache<QString, Traced> &traceCache()
{
    static QCache<QString, Traced> cache(32);
    return cache;
}

QMutex &traceMutex()
{
    static QMutex mutex;
    return mutex;
}

// Same store FramePaint::loadExportImage reads (see FramePaint.cpp):
// <AppData>/totm/images/<name>, traversal-guarded.
QString booleanImagesDir()
{
    return AppPaths::totmBaseDir() + QStringLiteral("/images");
}

QImage loadBooleanImage(const QString &name)
{
    if (name.isEmpty() || name.contains(QLatin1Char('/')) || name.contains(QLatin1Char('\\'))
        || name.contains(QStringLiteral("..")))
        return {};
    const QString path = booleanImagesDir() + QStringLiteral("/") + name;
    if (!QFile::exists(path))
        return {};
    QImage img;
    if (name.endsWith(QStringLiteral(".svg"), Qt::CaseInsensitive)) {
        QSvgRenderer renderer(path);
        if (!renderer.isValid())
            return {};
        QSize natural = renderer.defaultSize();
        if (natural.isEmpty())
            natural = QSize(256, 256);
        const double s = 512.0 / double(qMax(1, qMax(natural.width(), natural.height())));
        const QSize target(qMax(1, qRound(natural.width() * qMin(1.0, s))),
            qMax(1, qRound(natural.height() * qMin(1.0, s))));
        img = QImage(target, QImage::Format_ARGB32_Premultiplied);
        img.fill(Qt::transparent);
        QPainter p(&img);
        renderer.render(&p, QRectF(QPointF(), QSizeF(target)));
    } else {
        QImageReader reader(path);
        reader.setAutoTransform(true);
        img = reader.read();
    }
    if (!img.isNull() && img.format() != QImage::Format_ARGB32_Premultiplied)
        img.convertTo(QImage::Format_ARGB32_Premultiplied);
    return img;
}

} // namespace

QPainterPath imageNodeToPath(const QVariantMap &node)
{
    if (node.value(QStringLiteral("kind")).toString() != QLatin1String("shape"))
        return QPainterPath();
    if (nodeKind(node) != QLatin1String("image"))
        return QPainterPath();
    if (!node.value(QStringLiteral("visible"), true).toBool())
        return QPainterPath();
    const double x = node.value(QStringLiteral("x")).toDouble();
    const double y = node.value(QStringLiteral("y")).toDouble();
    const double w = node.value(QStringLiteral("w")).toDouble();
    const double h = node.value(QStringLiteral("h")).toDouble();
    if (!(w > 0.01) || !(h > 0.01))
        return QPainterPath();
    const QRectF box(x, y, w, h);
    const QString name = node.value(QStringLiteral("imageSource"), node.value(QStringLiteral("image"))).toString();
    // Missing blob: box fallback so broken imports paint like their
    // leaf placeholder instead of vanishing (mirrors paintLeaf).
    const QImage img = loadBooleanImage(name);
    if (img.isNull()) {
        QPainterPath fallback;
        fallback.addRect(box);
        return fallback;
    }
    {
        QMutexLocker lock(&traceMutex());
        if (Traced *hit = traceCache().object(name)) {
            const Traced t = *hit;
            lock.unlock();
            if (t.path.isEmpty())
                return QPainterPath();
            QTransform m;
            m.translate(x, y);
            m.scale(w / qMax(1.0, t.tileW), h / qMax(1.0, t.tileH));
            return m.map(t.path);
        }
    }
    const QPainterPath local = traceAlpha(img);
    // Trace space mirrors traceAlpha's downscale exactly (same rounding
    // or the silhouette drifts up to a pixel on large blobs).
    double tileW = double(img.width()), tileH = double(img.height());
    if (qMax(tileW, tileH) > 256.0) {
        const double ts = 256.0 / qMax(tileW, tileH);
        tileW = double(qMax(1, qRound(tileW * ts)));
        tileH = double(qMax(1, qRound(tileH * ts)));
    }
    Traced traced{local, tileW, tileH};
    {
        QMutexLocker lock(&traceMutex());
        traceCache().insert(name, new Traced(traced), 1);
    }
    // Fully transparent image contributes nothing (unlike a missing
    // blob, which keeps its placeholder box above).
    if (local.isEmpty())
        return QPainterPath();
    QTransform t;
    t.translate(x, y);
    t.scale(w / qMax(1.0, traced.tileW), h / qMax(1.0, traced.tileH));
    return t.map(local);
}

QPainterPath traceAlpha(const QImage &img, double maxDim)
{
    if (img.isNull() || img.width() < 2 || img.height() < 2)
        return QPainterPath();
    // Work at <= maxDim px (nearest: hard alpha edges must survive).
    double s = 1.0;
    int w = img.width(), h = img.height();
    if (maxDim > 0.0 && qMax(w, h) > maxDim) {
        s = maxDim / double(qMax(w, h));
        w = qMax(1, qRound(w * s));
        h = qMax(1, qRound(h * s));
    }
    QImage small = img.convertedTo(QImage::Format_ARGB32_Premultiplied);
    if (s != 1.0)
        small = small.scaled(w, h, Qt::IgnoreAspectRatio, Qt::FastTransformation);
    const int sw = small.width(), sh = small.height();
    std::vector<char> inside(size_t(sw) * size_t(sh), 0);
    bool any = false;
    for (int y = 0; y < sh; ++y) {
        const QRgb *row = reinterpret_cast<const QRgb *>(small.constScanLine(y));
        for (int x = 0; x < sw; ++x) {
            const bool hit = qAlpha(row[x]) > 127;
            inside[size_t(y) * size_t(sw) + size_t(x)] = char(hit ? 1 : 0);
            any = any || hit;
        }
    }
    if (!any)
        return QPainterPath();
    auto at = [&](int x, int y) -> bool {
        if (x < 0 || y < 0 || x >= sw || y >= sh)
            return false;
        return inside[size_t(y) * size_t(sw) + size_t(x)] != 0;
    };
    struct Seg {
        int ax, ay, bx, by;
    };
    // Grid coords x2 (midpoints are half-integers); corners TL=8 TR=4 BR=2 BL=1.
    std::vector<Seg> segs;
    segs.reserve(size_t(sw) * size_t(sh));
    // Padded cell range (-1..size-1): contours hugging the image
    // border are emitted by the outer ring (outside reads as empty).
    for (int y = -1; y < sh; ++y) {
        for (int x = -1; x < sw; ++x) {
            const int idx = (at(x, y) ? 8 : 0) | (at(x + 1, y) ? 4 : 0) | (at(x + 1, y + 1) ? 2 : 0)
                | (at(x, y + 1) ? 1 : 0);
            if (idx == 0 || idx == 15)
                continue;
            const int X = x * 2, Y = y * 2;
            const int T0 = X + 1, T1 = Y, R0 = X + 2, R1 = Y + 1, B0 = X + 1, B1 = Y + 2, L0 = X, L1 = Y + 1;
            auto emit2 = [&](int ax, int ay, int bx, int by, int cx, int cy, int dx, int dy) {
                segs.push_back({ax, ay, bx, by});
                segs.push_back({cx, cy, dx, dy});
            };
            switch (idx) {
            case 1:
            case 14:
                segs.push_back({L0, L1, B0, B1});
                break;
            case 2:
            case 13:
                segs.push_back({B0, B1, R0, R1});
                break;
            case 3:
            case 12:
                segs.push_back({L0, L1, R0, R1});
                break;
            case 4:
            case 11:
                segs.push_back({T0, T1, R0, R1});
                break;
            case 6:
            case 9:
                segs.push_back({T0, T1, B0, B1});
                break;
            case 7:
            case 8:
                segs.push_back({T0, T1, L0, L1});
                break;
            case 5:
                // TR+BL inside: pair through so the diagonal stays
                // connected instead of pinching apart.
                emit2(T0, T1, L0, L1, R0, R1, B0, B1);
                break;
            case 10:
                // TL+BR inside: mirror pairing for the same rule.
                emit2(T0, T1, R0, R1, B0, B1, L0, L1);
                break;
            default:
                break;
            }
        }
    }
    if (segs.empty())
        return QPainterPath();
    // Stitch segments into closed rings by endpoint matching.
    auto key = [](int x, int y) -> qint64 { return (qint64(x) << 32) | quint32(y); };
    QHash<qint64, QList<int>> atPoint;
    for (int i = 0; i < segs.size(); ++i) {
        atPoint[key(segs[i].ax, segs[i].ay)].append(i);
        atPoint[key(segs[i].bx, segs[i].by)].append(i);
    }
    std::vector<char> used(segs.size(), 0);
    QPainterPath out;
    for (int i = 0; i < segs.size(); ++i) {
        if (used[size_t(i)])
            continue;
        // Walk one ring from integer grid coords (no float roundtrip).
        QList<QPointF> ring;
        int cur = i;
        const int sx = segs[size_t(i)].ax, sy = segs[size_t(i)].ay;
        int px = sx, py = sy;
        ring.append(QPointF(px / 2.0, py / 2.0));
        for (int guard = 0; guard <= segs.size(); ++guard) {
            used[size_t(cur)] = 1;
            const Seg &sg = segs[size_t(cur)];
            if (sg.ax == px && sg.ay == py) {
                px = sg.bx;
                py = sg.by;
            } else {
                px = sg.ax;
                py = sg.ay;
            }
            if (px == sx && py == sy)
                break;
            ring.append(QPointF(px / 2.0, py / 2.0));
            int next = -1;
            for (int cand : atPoint.value(key(px, py))) {
                if (!used[size_t(cand)]) {
                    next = cand;
                    break;
                }
            }
            if (next < 0)
                break;
            cur = next;
        }
        if (ring.size() < 3)
            continue;
        // Drop dust (sub-2px² at trace scale).
        double area = 0.0;
        for (int k = 0; k < ring.size(); ++k) {
            const QPointF &a = ring[k], &b = ring[(k + 1) % ring.size()];
            area += a.x() * b.y() - b.x() * a.y();
        }
        if (qAbs(area) < 2.0)
            continue;
        out.moveTo(ring.first());
        for (int k = 1; k < ring.size(); ++k)
            out.lineTo(ring[k]);
        out.closeSubpath();
    }
    return out;
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
