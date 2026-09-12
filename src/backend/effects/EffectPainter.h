#pragma once

#include <QColor>
#include <QList>
#include <QPainter>
#include <QPainterPath>
#include <QPointF>
#include <QRectF>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

// EffectPainter: CPU shape rendering shared by preview (EffectItem) and,
// from P3, export (VideoExporter). One code path paints gradients and
// outer shadows everywhere, so preview matches video by construction.
// Stock QML items cannot do this (ShapePath has fillGradient only,
// Rectangle borders stay solid, MultiEffect has no spread).
namespace Effects {

// Fill/stroke paint: solid colors or 2-stop linear gradients.
struct Style {
    QColor fill = QColor(QStringLiteral("#d9d9d9"));
    QString fillType = QStringLiteral("solid");
    QVariantMap fillGradient;
    QColor stroke = QColor(QStringLiteral("#000000"));
    QString strokeType = QStringLiteral("solid");
    QVariantMap strokeGradient;
    double strokeWidth = 0.0;
    double radius = 0.0;

    static Style fromMap(const QVariantMap &m);
};

// Geometry options for vector paths. cornerRadii/points mirror
// ShapeGeometry; pathData holds pen subpaths in absolute content coords
// with ox/oy as the node origin (paint subtracts it, like the canvas).
struct PathOpts {
    QVariantList cornerRadii;
    int points = 5;
    bool independentCorners = false;
    QVariantList pathData;
    double ox = 0.0;
    double oy = 0.0;

    static PathOpts fromMap(const QVariantMap &m);
};

// Single outer shadow. Color alpha carries opacity; spread dilates the
// silhouette before blur. inner paints the same shadow inside the shape
// (Figma order: above fill, below stroke). Plain data so clips stay
// backend-readable.
struct Shadow {
    bool enabled = false;
    bool inner = false;
    QColor color = QColor(0, 0, 0, 128);
    double x = 0.0;
    double y = 4.0;
    double blur = 8.0;
    double spread = 0.0;

    static Shadow fromMap(const QVariantMap &m);
};

// Vector outline for rectangle/ellipse/triangle/star/pen in paint coords.
// box is the shape bbox; pen points resolve against ox/oy then land on box.

// Full leaf: shadow composite under the shape. scale maps content px to
// device px for blur/offset fidelity (preview passes 1, export its ratio).
void paintLeaf(QPainter *pt, const QString &kind, const QRectF &box, const PathOpts &opts,
    const Style &st, const Shadow &sh, double scale);

// Texture pad so blurs/offsets never clip: caller sizes the item
// box+2*pad and paints the shape at (pad,pad). Zero when shadow is off
// (strokes paint inside, like the QML Rectangle branch).
double shadowPad(const Shadow &sh, double strokeWidth);

} // namespace Effects
