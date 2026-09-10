#pragma once

#include <QList>
#include <QMap>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

// Shared animation sampler: QtCore-only port of DocEasing.qml,
// DocPathSample.qml and the sampling half of DocAnimSample.qml
// (presetOverlay, per-clip evaluation, writeback). VideoExporter renders
// from this; the conformance harness diffs it against the real QML.
namespace Anims {

double num(const QVariantMap &m, const char *key, double fallback = 0.0);
QString str(const QVariantMap &m, const char *key, const QString &fallback = QString());

double cubicBezier(double x1, double y1, double x2, double y2, double x);
double easeValue(const QString &id, const QVariantList &bezier, double t);

struct PathSample {
    bool valid = false;
    double dx = 0.0;
    double dy = 0.0;
    double angleDelta = 0.0;
};
PathSample samplePath(const QVariantList &pts, bool closed, double e);

bool parseHex(const QString &hex, int &r, int &g, int &b);
QString lerpColor(const QString &from, const QString &to, double t);

// One clip's overlay for a single leaf (DocAnimSample.presetOverlay).
QVariantMap presetOverlay(const QString &preset, const QString &mode, const QVariantMap &o,
    const QVariantMap &base, double cx, double cy, double e, double p);

// Flattened leaf with static ancestor state (DocTree + DocEffective).
struct Leaf {
    QVariantMap map;
    bool ancestorsVisible = true;
    bool locked = false;
};
QList<Leaf> collectLeaves(const QVariantMap &scene);
// Pre-play values keyed by uid (DocTransport.captureBase).
QMap<int, QVariantMap> captureBase(const QList<Leaf> &leaves);
// Full frame: leaves top-first with overlays written (DocAnimSample
// sampleAnim + applySample over plain maps, locks hold still).
QList<QVariantMap> sampleFrame(const QVariantMap &scene, double t);

} // namespace Anims
