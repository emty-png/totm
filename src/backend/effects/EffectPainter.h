#pragma once

#include <QCache>
#include <QColor>
#include <QList>
#include <QImage>
#include <QPainter>
#include <QPainterPath>
#include <QPointF>
#include <QRectF>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

#include <cstdint>

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
// backend-readable. Shadows stack: lists paint index 0 topmost.
struct Shadow {
    bool enabled = false;
    bool inner = false;
    QColor color = QColor(0, 0, 0, 128);
    double x = 0.0;
    double y = 4.0;
    double blur = 8.0;
    double spread = 0.0;

    static Shadow fromMap(const QVariantMap &m);
    static QList<Shadow> listFrom(const QVariantList &l);
};

// Single blur effect (layer or background). radius is px at scale 1,
// opacity 0..1 mixes blurred with sharp (layer) or blurred backdrop
// with original (background). Plain data so clips stay backend-readable.
struct Blur {
    bool enabled = false;
    double radius = 0.0;
    double opacity = 1.0;

    static Blur fromMap(const QVariantMap &m);
};

// Neon glow, outer or inner. Centered (no offset by design): spread
// grows the silhouette, blur softens it, color alpha carries opacity.
// Plain data so clips stay backend-readable. Glows stack like shadows.
struct Glow {
    bool enabled = false;
    bool inner = false;
    QColor color = QColor(0, 255, 255, 204);
    double blur = 16.0;
    double spread = 0.0;

    static Glow fromMap(const QVariantMap &m);
    static QList<Glow> listFrom(const QVariantList &l);
};

// Animated monochrome film grain. amount 0..1 scales dot alpha, size is
// the noise cell in content px. The noise field is a pure function of
// (cell, seed) with seed = grainSeed(uid, frameNo); the QML preview
// implements the identical hash, so preview matches export exactly and
// the grain shimmers per frame while playing, freezing when paused.
// Plain data so clips stay backend-readable.
struct Grain {
    bool enabled = false;
    double amount = 0.5;
    double size = 2.0;

    static Grain fromMap(const QVariantMap &m);
};

// Frames tick at 60Hz on both sides (preview transport seconds and
// export frame times share this rule).
inline int grainFrameNo(double t)
{
    return qMax(0, int(t * 60.0));
}
uint32_t grainSeed(int uid, int frameNo);
uint32_t grainHash(uint32_t cx, uint32_t cy, uint32_t seed);

// Vector outline for rectangle/ellipse/triangle/star/pen in paint coords.
// box is the shape bbox; pen points resolve against ox/oy then land on box.

// Stacked leaf: background blur composites outside (backdrop is the
// frame so far); this paints outer shadows -> outer glows -> fill ->
// inner shadows -> inner glows -> stroke, then layer-blur mixes the
// whole stack. Index 0 paints topmost within its group. scale maps
// content px to device px (preview passes 1, export its ratio).
// maskCache memoizes blurred silhouette/cutter rasters per item (same
// pixels, skipped blur recompute); export passes null and recomputes.
void paintLeaf(QPainter *pt, const QString &kind, const QRectF &box, const PathOpts &opts,
    const Style &st, const QList<Shadow> &shadows, const QList<Glow> &glows, const Blur &layerBlur,
    double scale, QCache<QByteArray, QImage> *maskCache = nullptr);
// Full leaf: shadow composite under the shape. scale maps content px to
// device px for blur/offset fidelity (preview passes 1, export its ratio).
void paintLeaf(QPainter *pt, const QString &kind, const QRectF &box, const PathOpts &opts,
    const Style &st, const Shadow &sh, double scale);
// Layer-blur overload: sharp leaf renders offscreen, blurs by radius,
// then mixes sharp/blurred by opacity (single-effect: shadow is off).
void paintLeaf(QPainter *pt, const QString &kind, const QRectF &box, const PathOpts &opts,
    const Style &st, const Shadow &sh, const Blur &layerBlur, double scale);
// Glow leaf: centered outer/inner glow under/over the fill, then the
// stroke on top. Single-effect: shadow and layer blur stay off.
void paintLeaf(QPainter *pt, const QString &kind, const QRectF &box, const PathOpts &opts,
    const Style &st, const Glow &glow, double scale);

// Separable box blur shared by preview and export (device px radius).
void blurImage(QImage &img, double radius);
// Mix blurred over sharp by opacity 0..1 (premultiplied-safe).
void mixBlurred(QImage &sharp, const QImage &blurred, double opacity);
// Full-coverage monochrome grain tile over px (tile origin = cell
// origin): black/white dots picked by grainHash, alpha scaled by amount.
QImage grainDots(const QSize &px, double cellD, uint32_t seed, double amount);
// Vector outline path in device coords (fill path; stroke straddles it
// for non-plain shapes, like the paint leaves).
QPainterPath outlinePath(const QString &kind, const QRectF &box, const PathOpts &opts, const Style &st,
    double scale);
// Grain confined to clip (stroke unioned in when it sticks out),
// composited over dotBox's top-left. No-op when disabled.
void paintGrainPath(QPainter *pt, const QPainterPath &clip, double strokeWidth, const QRectF &dotBox,
    const Grain &gr, int uid, int frameNo, double scale);

// Texture pad so blurs/offsets never clip: caller sizes the item
// box+2*pad and paints the shape at (pad,pad). Zero when shadow is off
// (strokes paint inside, like the QML Rectangle branch).
double shadowPad(const Shadow &sh, double strokeWidth);
double shadowsPad(const QList<Shadow> &shadows, double strokeWidth);
// Layer-blur pad (blur radius spreads beyond the bbox).
double blurPad(const Blur &b);
// Glow pad (spread plus blur halo, centered so no offset term).
double glowPad(const Glow &g);
double glowsPad(const QList<Glow> &glows);
// Combined pad for single-effect shapes (max of active branches).
double effectPad(const Shadow &sh, const Blur &b, double strokeWidth);
double effectPad(const Shadow &sh, const Blur &b, const Glow &g, double strokeWidth);
double effectPad(const QList<Shadow> &shadows, const QList<Glow> &glows, const Blur &b,
    double strokeWidth);

} // namespace Effects
