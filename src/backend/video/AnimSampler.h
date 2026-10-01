#pragma once

#include <QList>
#include <QMap>
#include <QPointF>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

// AnimSampler: QtCore-only animation sampling for export.
//
// Ownership: easing, motion-path measuring and keyed interpolation live
// here once (easeValue/samplePath/maskKeysAt/genericKeysAt) and QML
// preview delegates through AnimBridge, so preview and export match by
// construction. Per-preset overlay math is still mirrored with
// DocAnimSample.qml (presetOverlay): when adding a preset, update both
// sides together.
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

// Production path helpers (additive; samplePath above stays the legacy
// fast path so old clips sample bit-identical). remapPathProgress folds
// a path-local repeat count into a 0..1 position progress (per-clip
// traversal repeat, unrelated to the removed clip loop modes);
// adjustPathAngle applies orient offset/flip; followCompensation shifts
// top-left by -R(newRot)*pivot so the selected pivot rides the displayed
// trajectory (base top-left + path offset). (0,0) for legacy top-left.
double remapPathProgress(double prog, const QVariantMap &o);
double adjustPathAngle(double angleDelta, const QVariantMap &o);
// Scene-space correction to add to (base.x + dx, base.y + dy) so the
// selected follow pivot lands on the path. (0,0) for legacy top-left.
QPointF pathFollowComp(const QVariantMap &base, double newRotation, const QVariantMap &o);
// Full production sample: speed select (constant uses linear p, else
// eased e) + repeat remap + arc sample + angle adjust + follow comp.
// Returns invalid when fewer than 2 points ride along.
struct PathSampleEx {
    bool valid = false;
    double dx = 0.0;
    double dy = 0.0;
    double angleDelta = 0.0;
};
PathSampleEx samplePathEx(
    const QVariantList &pts, const QVariantMap &o, const QVariantMap &base, double e, double p);

// Color. parseHex accepts #rgb/#rrggbb (case-insensitive). lerpColor
// interpolates in sRGB and returns {} when either endpoint is invalid.
// parseHexA/lerpColorA additionally accept #aarrggbb and interpolate
// alpha, returning #aarrggbb only when the result is translucent.
bool parseHex(const QString &hex, int &r, int &g, int &b);
QString lerpColor(const QString &from, const QString &to, double t);
bool parseHexA(const QString &hex, int &a, int &r, int &g, int &b);
QString lerpColorA(const QString &from, const QString &to, double t);

// Keyed interpolation core shared with QML preview: AnimBridge
// delegates to these, so there is one implementation instead of a
// ported twin. maskKeysAt covers absolute-geometry mask fields;
// genericKeysAt lerps numbers, lerps hex colors alpha-aware, steps
// bools/strings at the midpoint and carries missing fields. True
// when o["keys"] holds 2+ usable keys, with value holding the
// interpolated fields ("hold" as a target key's easing id freezes
// the segment at the previous key).
bool maskKeysAt(const QVariantMap &o, double p, QVariantMap &value);
bool genericKeysAt(const QVariantMap &o, double p, QVariantMap &value);

// Single-clip overlay for one leaf (mirrors DocAnimSample.presetOverlay).
// base: captureBase row for the leaf (or captureGroupBase row for a
// group style clip). cx/cy: target bounds center in scene px (scale
// anchor). e: eased progress, p: linear progress.
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
// Group style bases keyed by group uid (stacks plus opacity/visibility;
// geometry stays leaf-owned). Mirrors the group rows of captureBase.
QMap<int, QVariantMap> captureGroupBase(const QVariantList &nodes);
// Full frame at time t in seconds: leaves top-first with later clips
// winning per property, except movement x/y which chains from the
// previous end so sequential moves accumulate. Locked leaves are
// returned unmodified. Group-targeted style clips resolve against
// captureGroupBase rows and fold into boolean/frame entries.
QList<QVariantMap> sampleFrame(const QVariantMap &scene, double t);

// Masks (layer masks, one active mask per group). Children are
// top-first: the lowest direct shape child with isMask clips siblings
// above it in the same parent. Masks never paint themselves.
bool isMaskMap(const QVariantMap &m);
// Leaf uid -> mask uids clipping it, walking up the ancestor chain
// (nested masks intersect). Mirrors DocTree.maskUidsForLeaf.
QMap<int, QList<int>> maskMapForWork(const QVariantMap &scene, const QList<QVariantMap> &work);

} // namespace Anims
