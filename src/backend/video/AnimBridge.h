#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// AnimBridge: QML entry point to the shared animation-sampling math.
//
// Ownership: stateless app-wide singleton (QML_ELEMENT + QML_SINGLETON,
// same pattern as CursorStore). Created on first QML reference.
// Threading: main thread only (QML preview); export workers keep calling
// Anims:: directly.
// Contract: every function delegates to the Anims:: implementation in
// AnimSampler, so QML preview and video export run one codebase instead
// of ported twins. easeValue covers DocEasing, samplePath covers
// DocPathSample, mask/genericKeysAt cover DocAnimSample keyed clips.
// Per-preset overlay branches stay mirrored with DocAnimSample (see
// AnimSampler.h); only the interpolation core is unified here.
class AnimBridge : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    static AnimBridge *create(QQmlEngine *engine, QJSEngine *scriptEngine);
    explicit AnimBridge(QObject *parent = nullptr);

    // Eased progress for an easing id + custom bezier at t in [0, 1].
    Q_INVOKABLE double easeValue(const QString &id, const QVariantList &bezier, double t);
    // Keyed mask values over options["keys"] at clip-local p in [0, 1].
    // Invalid QVariant when fewer than 2 keys ride along.
    Q_INVOKABLE QVariant maskKeysAt(const QVariantMap &options, double p);
    // Generic keyed values. Invalid QVariant when fewer than 2 keys.
    Q_INVOKABLE QVariant genericKeysAt(const QVariantMap &options, double p);
    // Motion-path sample by arc length: {valid, dx, dy, angleDelta}.
    // Invalid QVariant when fewer than 2 points ride along.
    Q_INVOKABLE QVariant samplePath(const QVariantList &pts, bool closed, double e);
};
