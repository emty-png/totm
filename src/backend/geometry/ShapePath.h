#pragma once

#include <QObject>
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

// Single node silhouette in world coords. Returns empty when the node is
// not a combinable vector (text/image/mask/empty pen).
QPainterPath nodeToWorldPath(const QVariantMap &node);

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
