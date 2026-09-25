#pragma once

#include <QImage>
#include <QPainter>
#include <QRectF>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

// FramePaint: still-frame raster shared by video export and component
// export.
//
// Ownership: the leaf rasterizer (plus its image/backdrop-blur/glyph
// helpers) moved here verbatim from VideoExporter::RenderThread, so
// canvas preview, video frames and component PNGs paint through one
// code path by construction. VideoExporter keeps its thread/ffmpeg
// plumbing and calls paintLeaf; ComponentExporter renders through
// renderNodes. Behavior on existing paths is unchanged.
// Units: node geometry in content px, scale maps content px to device
// px (video passes its letterbox ratio, components their 1x/2x/3x).
namespace FramePaint {

// Single sampled leaf onto pt (frame is the tile for backdrop-blur
// sampling). Transparent-safe: nothing fills the background, the
// caller owns the clear color. frameNo feeds the grain seed so stills
// can match the preview grain (see Effects::grainFrameNo).
void paintLeaf(QPainter &pt, QImage &frame, const QVariantMap &m, double ox, double oy, double scale,
    int frameNo);

// White alpha silhouette of one sampled mask leaf in frame coords.
// Vectors use the shared outline path, images a rounded rect, text
// the glyph ghost; feather blurs the edge, invert flips the alpha.
// Only alpha carries meaning (DestinationIn); color stays white.
QImage maskSilhouette(const QVariantMap &mask, double ox, double oy, double scale, const QSize &size);

// Group-aware leaf pass with Figma/Jitter-style masks. Skips isMask
// leaves, clips masked leaves by their mask silhouette(s) at the same
// frame time. scene is the full hierarchy (for mask lookup), work is
// the sampled top-first leaf list. Paints bottom-first like callers did.
void paintLeaves(QPainter &pt, QImage &frame, const QList<QVariantMap> &work, const QVariantMap &scene,
    double ox, double oy, double scale, int frameNo);

// Union of rotated leaf bboxes expanded by the canvas effect pads
// (mirrors EffectItem::updatePad, including the miter-pen rule), in
// content coords. Empty when no leaf has a positive area.
QRectF selectionBounds(const QList<QVariantMap> &work, double scale);

// Renders top-level node snapshots (groups included) to a transparent
// image at scale. The subset scene carries no anim blob, so leaves
// paint at base values; top-level visibility is forced on (explicit
// selection exports even when hidden), nested visibility stays
// authored. Grain freezes at frameNo. Null image + *error on empty
// input, nothing visible, or over the pixel cap.
QImage renderNodes(const QVariantList &topNodes, double scale, int frameNo, QString *error = nullptr);

} // namespace FramePaint
