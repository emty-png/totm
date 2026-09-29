#include "AnimBridge.h"

#include "AnimSampler.h"

AnimBridge *AnimBridge::create(QQmlEngine *engine, QJSEngine *scriptEngine)
{
    Q_UNUSED(scriptEngine);
    auto *bridge = new AnimBridge(engine);
    QJSEngine::setObjectOwnership(bridge, QJSEngine::CppOwnership);
    return bridge;
}

AnimBridge::AnimBridge(QObject *parent)
    : QObject(parent)
{
}

double AnimBridge::easeValue(const QString &id, const QVariantList &bezier, double t)
{
    return Anims::easeValue(id, bezier, t);
}

QVariant AnimBridge::maskKeysAt(const QVariantMap &options, double p)
{
    QVariantMap value;
    if (!Anims::maskKeysAt(options, p, value))
        return QVariant();
    return value;
}

QVariant AnimBridge::genericKeysAt(const QVariantMap &options, double p)
{
    QVariantMap value;
    if (!Anims::genericKeysAt(options, p, value))
        return QVariant();
    return value;
}

QVariant AnimBridge::samplePath(const QVariantList &pts, bool closed, double e)
{
    const Anims::PathSample s = Anims::samplePath(pts, closed, e);
    if (!s.valid)
        return QVariant();
    QVariantMap out;
    out[QStringLiteral("valid")] = true;
    out[QStringLiteral("dx")] = s.dx;
    out[QStringLiteral("dy")] = s.dy;
    out[QStringLiteral("angleDelta")] = s.angleDelta;
    return out;
}
