#pragma once

#include <QObject>
#include <QImage>
#include <QPainterPath>
#include <QRectF>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// ShapePath: shared vector-geometry core for boolean ops.
// Ownership: pure helpers over snapshot maps (see DocClipboard.snapshotNode),
// so QML preview and C++ export combine identical inputs by construction.
// Coordinates are content px (scale 1). Rotation/flip bake into the world
// path; callers combine in world space and read boundingRect for the group.
namespace ShapePath {

// Single node silhouette in world coords. Groups resolve recursively
// (own op, union for plain subgroups, masks excluded); text and image
// leaves resolve through their providers. Empty for masks and for
// vector leaves with no silhouette.
QPainterPath nodeToWorldPath(const QVariantMap &node);

// Silhouette providers for non-vector children (production booleans).
// Text builds its glyph outline (empty content yields empty); images
// trace their alpha channel (missing blobs fall back to the node box
// so broken imports never vanish silently).
QPainterPath textNodeToPath(const QVariantMap &node);
QPainterPath imageNodeToPath(const QVariantMap &node);
// Marching-squares alpha trace at <= maxDim px: one polygon per
// connected run, merged into a single path, returned in tile px
// (callers map to their own box). Empty when nothing crosses
// the 50% alpha threshold.
QPainterPath traceAlpha(const QImage &img, double maxDim = 256.0);

// Fold helpers over world paths. Empty input yields empty.
QPainterPath combinePaths(const QString &op, const QList<QPainterPath> &paths);
QPainterPath combineNodes(const QString &op, const QVariantList &nodes);

// Minimal SVG d (M/L/C/Z only) for QML PathSvg preview.
QString toSvgD(const QPainterPath &path);

// Supported ops: union|subtract|intersect|exclude. Anything else is invalid.
bool isOp(const QString &op);
QString normOp(const QString &op);

// True for rectangle/ellipse/triangle/star/pen leaves that are visible,
// not masks, and carry a non-empty silhouette.
bool isCombinableNode(const QVariantMap &node);

// True for group maps carrying a live boolean op.
bool isBooleanGroupMap(const QVariantMap &node);
// All boolean groups under nodes (any depth, top-first).
QList<QVariantMap> booleanGroupsIn(const QVariantList &nodes);
// Leaf uids under a group map (any depth).
QList<int> descendantLeafUids(const QVariantMap &group);

} // namespace ShapePath

// QML bridge: stateless invokables over snapshot maps. No scene access,
// no file IO; preview calls these to draw the combined silhouette.
class ShapePathHelper : public QObject
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit ShapePathHelper(QObject *parent = nullptr);

    Q_INVOKABLE QString nodeSvg(const QVariantMap &node);
    Q_INVOKABLE QString combineSvg(const QVariantList &nodes, const QString &op);
    Q_INVOKABLE QRectF combineBounds(const QVariantList &nodes, const QString &op);
    Q_INVOKABLE bool canCombineNodes(const QVariantList &nodes);
    Q_INVOKABLE bool isOp(const QString &op);
};
