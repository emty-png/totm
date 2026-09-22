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
#include <QVector>

#include <cstdint>

// EffectPainter: CPU shape rendering shared by preview (EffectItem) and,
// from P3, export (VideoExporter). One code path paints gradients and
// outer shadows everywhere, so preview matches video by construction.
// Stock QML items cannot do this (ShapePath has fillGradient only,
// Rectangle borders stay solid, MultiEffect has no spread).
namespace Effects {

// Fill/stroke paint: stacked entries (Figma-style, index 0 topmost).
// Each fill is solid or 2-stop linear with its own opacity (final
// alpha = color alpha * opacity); each stroke adds width, dash pair,
// position (center/inside/outside) and opacity. penFill toggles the
// path fill (pen line-art); strokeCap/strokeJoin stay per-shape.
struct FillEntry {
    bool enabled = true;
    QColor color = QColor(QStringLiteral("#d9d9d9"));
    QString type = QStringLiteral("solid");
    QVariantMap gradient;
    double opacity = 1.0;

    static FillEntry fromMap(const QVariantMap &m);
    static QList<FillEntry> listFrom(const QVariantList &l, const QVariantMap &legacy);
};

struct StrokeEntry {
    bool enabled = true;
    QColor color = QColor(QStringLiteral("#000000"));
    QString type = QStringLiteral("solid");
    QVariantMap gradient;
    double width = 0.0;
    // Dash pair in stroke-width units ([dash, gap]); empty paints solid.
    // Both entries must be positive, otherwise the stroke stays solid.
    QVector<qreal> dash;
    QString position = QStringLiteral("center");
    double opacity = 1.0;

    static StrokeEntry fromMap(const QVariantMap &m);
    static QList<StrokeEntry> listFrom(const QVariantList &l, const QVariantMap &legacy);
};

struct Style {
    QList<FillEntry> fills;
    QList<StrokeEntry> strokes;
    double radius = 0.0;
    bool penFill = true;
    QString strokeCap = QStringLiteral("round");
    QString strokeJoin = QStringLiteral("round");

    static Style fromMap(const QVariantMap &m);
    // Max enabled stroke width (for pads/geometry); 0 when none.
    double maxStrokeWidth() const;
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

// Dash pair in stroke-width units ([dash, gap]); empty paints solid.
// Both entries must be positive, otherwise the stroke stays solid.
QVector<qreal> dashFrom(const QVariant &v);
void applyDashToPen(QPen &pen, const QVector<qreal> &dash);

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

// Text layout for the glyph raster path. Content-space values straight
// off the node (like PathOpts); the painter scales by `scale`.
// autoSize boxes grow with content, fixed boxes wrap and clip; vAlign
// parks fixed boxes top/middle/bottom. Plain data, backend-readable.
struct TextOpts {
    QString content;
    QString family = QStringLiteral("Inter");
    int weight = 400;
    double size = 16.0;
    double spacingPct = 0.0;
    QString halign = QStringLiteral("left");
    QString valign = QStringLiteral("top");
    bool autoSize = true;
    bool lineAuto = true;
    double leading = 1.2;
    double boxW = 10.0;
    double boxH = 10.0;
    double outlinePx = 1.0;

    static TextOpts fromMap(const QVariantMap &m);
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
// White glyph coverage for one text box (fill silhouette plus the
// outline ring unioned in when outlinePx > 0), laid out by the shared
// QTextDocument builder so preview and export shape glyphs alike.
// Device px throughout (already scaled); clips fixed boxes like the
// canvas, lets auto-size boxes overflow like the canvas.
QImage textGhost(const TextOpts &text, double w, double h, double scale, bool withOutline);
// Effected text leaf: outer shadows/glows under the glyphs, fill (solid
// or linear across the box), real inner bands, stroke ring on top, then
// layer-blur mixes the whole stack. Same fixed order as vectors; grain
// stays a separate overlay on both sides. maskCache memoizes blurred
// rasters (null recomputes, same pixels).
void paintTextLeaf(QPainter *pt, const QRectF &box, const TextOpts &text, const Style &st,
    const QList<Shadow> &shadows, const QList<Glow> &glows, const Blur &layerBlur, double scale,
    QCache<QByteArray, QImage> *maskCache = nullptr);
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
// box+2*pad and paints the shape at (pad,pad). Includes the outer
// half of center/outside strokes (inside strokes need no room).
double shadowPad(const Shadow &sh, double strokeWidth);
double shadowsPad(const QList<Shadow> &shadows, double strokeWidth);
// Layer-blur pad (blur radius spreads beyond the bbox).
double blurPad(const Blur &b);
// Glow pad (spread plus blur halo, centered so no offset term).
double glowPad(const Glow &g);
double glowsPad(const QList<Glow> &glows);
double strokesPad(const QList<StrokeEntry> &strokes);
// Combined pad for single-effect shapes (max of active branches).
double effectPad(const Shadow &sh, const Blur &b, double strokeWidth);
double effectPad(const Shadow &sh, const Blur &b, const Glow &g, double strokeWidth);
double effectPad(const QList<Shadow> &shadows, const QList<Glow> &glows, const Blur &b,
    double strokeWidth);
double effectPad(const QList<Shadow> &shadows, const QList<Glow> &glows, const Blur &b,
    const QList<StrokeEntry> &strokes);

} // namespace Effects
