#pragma once

#include <QString>
#include <QVariantList>

// SvgPaint: vector still-frame export sharing the PNG path's scene
// handling.
//
// Ownership: scene flattening (collectLeaves + sampleFrame at t=0)
// mirrors FramePaint::renderNodes, so selection, visibility and base
// values agree with PNG by construction. Geometry reuses
// Effects::outlinePath, so vector silhouettes match the canvas exactly.
// Paint is vector-native (path/text/image elements with userSpaceOnUse
// gradients). Effects ride along as per-leaf SVG filters in the PNG
// stack order: outer shadows/glows under the shape (spread via
// morphology), inner bands above the fill, whole-stack layer blur
// mixed by opacity, silhouette-confined grain. Mapping is approximate
// (box radii as sigma/2, turbulence instead of hashed dots).
// Background blur has no standalone-SVG equivalent (no backdrop to
// sample), so it is skipped, never failed.
namespace SvgPaint {

// Renders top-level node snapshots (groups included) to a standalone
// SVG document (UTF-8 text). Top-level visibility is forced on like
// the PNG path; nested visibility stays authored. Null string +
// *error on empty input or nothing visible.
QString renderNodes(const QVariantList &topNodes, QString *error = nullptr);

} // namespace SvgPaint
