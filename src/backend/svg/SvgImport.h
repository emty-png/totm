#pragma once

#include <QString>
#include <QVariantMap>

// SvgImport: SVG file -> editable pen data (mirror of the export-side
// SvgPaint unit). Parses drawable elements (path, rect, circle,
// ellipse, line, polyline, polygon, use, text) with transforms, solid
// paints and linearGradient paints (objectBoundingBox and
// userSpaceOnUse vectors map to the bbox-relative angle model;
// gradientTransform applies to the endpoints; href chains resolve;
// multi-stop ramps sample at pos 0/1) into the pen [{closed, pts}]
// shape the canvas, export and animation paths already consume.
// Radial gradients degrade to their first stop as solid; filters,
// clips, masks and patterns are skipped: unconvertible files report
// ok=false so callers can fall back to image-blob placement.
namespace SvgImport {

// {ok, error, width, height, paths:[{pathData, fill, penFill, stroke,
// strokeWidth, strokeCap, strokeJoin}]}. Geometry is normalized to a
// width/height box at the origin, uniformly scaled down to maxSize like
// the image stamp clamp (never scaled up).
QVariantMap importFile(const QString &localPath, double maxSize);

} // namespace SvgImport
