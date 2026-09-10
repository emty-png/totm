#pragma once

#include <QList>
#include <QMap>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

// AnimSampler: QtCore-only animation sampling for export.
//
// Ownership: C++ port of DocEasing.qml, DocPathSample.qml and the sampling
// half of DocAnimSample.qml (presetOverlay, per-clip evaluation,
// writeback). VideoExporter renders from here so export matches the canvas
// preview. When adding a preset, update both sides together.
// Constraints: no QtGui/QtQuick dependency; operates on plain scene maps.
// Units: positions/sizes in scene px, time in seconds, eased progress e
// and linear progress p both in [0, 1].
namespace Anims {

// Map access with fallback. Returns fallback when the key is missing or
// not convertible.
double num(const QVariantMap &m, const char *key, double fallback = 0.0);
QString str(const QVariantMap &m, const char *key, const QString &fallback = QString());

// Easing. cubicBezier solves y for x in [0, 1] (Newton + bisection
// fallback). easeValue maps an easing id + custom bezier to eased t.
double cubicBezier(double x1, double y1, double x2, double y2, double x);
double easeValue(const QString &id, const QVariantList &bezier, double t);

struct PathSample {
    bool valid = false;
    // Absolute scene-space offset of the path point at progress e.
    double dx = 0.0;
    double dy = 0.0;
    // Rotation delta vs the path start, in degrees, normalized to [-180, 180].
    double angleDelta = 0.0;
};
// Samples a motion path by arc length. pts: [{x, y, smooth, inX/inY,
// outX/outY}]. Invalid when fewer than 2 points.
PathSample samplePath(const QVariantList &pts, bool closed, double e);

// Color. parseHex accepts #rgb/#rrggbb (case-insensitive). lerpColor
// interpolates in sRGB and returns {} when either endpoint is invalid.
bool parseHex(const QString &hex, int &r, int &g, int &b);
QString lerpColor(const QString &from, const QString &to, double t);

// Single-clip overlay for one leaf (mirrors DocAnimSample.presetOverlay).
// base: captureBase row for the leaf. cx/cy: target bounds center in scene
// px (scale anchor). e: eased progress, p: linear progress.
QVariantMap presetOverlay(const QString &preset, const QString &mode, const QVariantMap &o,
    const QVariantMap &base, double cx, double cy, double e, double p);

// Flattened drawable leaf with inherited group state (mirrors DocTree +
// DocEffective). Groups never appear here; see collectLeaves.
struct Leaf {
    QVariantMap map;
    bool ancestorsVisible = true;
    bool locked = false;
};
// Depth-first leaf collection preserving document order (top-first).
QList<Leaf> collectLeaves(const QVariantMap &scene);
// Pre-play values keyed by uid (mirrors DocTransport.captureBase).
QMap<int, QVariantMap> captureBase(const QList<Leaf> &leaves);
// Full frame at time t in seconds: leaves top-first with later clips
// winning per property. Locked leaves are returned unmodified.
QList<QVariantMap> sampleFrame(const QVariantMap &scene, double t);

} // namespace Anims
