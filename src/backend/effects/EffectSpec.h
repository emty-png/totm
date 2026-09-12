#pragma once

#include <QColor>
#include <QPointF>
#include <QRectF>
#include <QVariant>
#include <QVariantMap>

// EffectSpec: shared gradient conventions for the CPU paint path.
//
// Ownership: pure helpers, no QObject. Preview (EffectItem) and export
// (VideoExporter) both build through here so pixels match by construction.
// Angle degrees: 0 = left->right, 90 = top->bottom, clockwise in y-down
// coords. Endpoints span the bbox projection so opposite edges land on
// pos 0/1 exactly. v1 is 2-stop linear only.
namespace Effects {

inline QColor colorFrom(const QVariant &v, const QColor &fallback)
{
    if (v.typeId() == QMetaType::QColor)
        return v.value<QColor>();
    const QColor c(v.toString());
    return c.isValid() ? c : fallback;
}

struct GradientStop {
    QColor color = QColor(QStringLiteral("#000000"));
    double pos = 0.0;
};

struct LinearSpec {
    double angle = 90.0;
    GradientStop stops[2] = {{QColor(QStringLiteral("#000000")), 0.0}, {QColor(QStringLiteral("#ffffff")), 1.0}};
    bool valid = false;
};

// Normalized 2-stop spec. Missing/invalid input falls back to
// black->white at 90deg so converts and old scenes always paint.
inline LinearSpec linearFrom(const QVariantMap &grad)
{
    LinearSpec out;
    bool ok = false;
    const double a = grad.value(QStringLiteral("angle")).toDouble(&ok);
    out.angle = ok ? a : 90.0;
    const QVariantList raw = grad.value(QStringLiteral("stops")).toList();
    for (int i = 0; i < 2; ++i) {
        const QVariantMap s = raw.size() > i ? raw.at(i).toMap() : QVariantMap();
        const QColor fallback = i == 0 ? QColor(QStringLiteral("#000000")) : QColor(QStringLiteral("#ffffff"));
        out.stops[i].color = colorFrom(s.value(QStringLiteral("color")), fallback);
        bool pok = false;
        const double p = s.value(QStringLiteral("pos"), i).toDouble(&pok);
        out.stops[i].pos = pok ? qBound(0.0, p, 1.0) : double(i);
    }
    out.valid = true;
    return out;
}

inline void gradientEndpoints(const QRectF &box, double angle, QPointF *p0, QPointF *p1)
{
    const double rad = angle * 3.141592653589793 / 180.0;
    const double vx = qCos(rad);
    const double vy = qSin(rad);
    const double cx = box.x() + box.width() / 2.0;
    const double cy = box.y() + box.height() / 2.0;
    const double half = (qAbs(box.width() * vx) + qAbs(box.height() * vy)) / 2.0;
    if (p0)
        *p0 = QPointF(cx - vx * half, cy - vy * half);
    if (p1)
        *p1 = QPointF(cx + vx * half, cy + vy * half);
}

} // namespace Effects
