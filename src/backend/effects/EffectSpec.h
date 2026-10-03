#pragma once

#include <QColor>
#include <QPointF>
#include <QRectF>
#include <QVariant>
#include <QVariantMap>
#include <QVector>

#include <algorithm>

// EffectSpec: shared gradient conventions for the CPU paint path.
//
// Ownership: pure helpers, no QObject. Preview (EffectItem) and export
// (VideoExporter) both build through here so pixels match by construction.
// Angle degrees: 0 = left->right, 90 = top->bottom, clockwise in y-down
// coords. Endpoints span the bbox projection so opposite edges land on
// pos 0/1 exactly. v2 is N-stop linear (2..8 stops, sorted by pos).
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
    QVector<GradientStop> stops = { { QColor(QStringLiteral("#000000")), 0.0 },
        { QColor(QStringLiteral("#ffffff")), 1.0 } };
    bool valid = false;
};

// Normalized N-stop spec (2..8 stops, sorted by pos). Missing/invalid
// input falls back to black->white at 90deg so converts and old scenes
// always paint. Extra stops past 8 resample by index (endpoints kept)
// so coverage survives the cap; single-stop input pads to two.
inline LinearSpec linearFrom(const QVariantMap &grad)
{
    LinearSpec out;
    bool ok = false;
    const double a = grad.value(QStringLiteral("angle")).toDouble(&ok);
    out.angle = ok ? a : 90.0;
    const QVariantList raw = grad.value(QStringLiteral("stops")).toList();
    QVector<GradientStop> parsed;
    parsed.reserve(qMin(raw.size(), 64) > 0 ? qMin(raw.size(), 64) : 2);
    for (int i = 0; i < raw.size(); ++i) {
        const QVariantMap s = raw.at(i).toMap();
        const QColor fallback = parsed.isEmpty() ? QColor(QStringLiteral("#000000"))
                                                 : QColor(QStringLiteral("#ffffff"));
        const QColor c = colorFrom(s.value(QStringLiteral("color")), fallback);
        double usePos = -1.0;
        if (s.contains(QStringLiteral("pos"))) {
            bool pok = false;
            const double p = s.value(QStringLiteral("pos")).toDouble(&pok);
            if (pok)
                usePos = qBound(0.0, p, 1.0);
        }
        parsed.append({ c, usePos });
    }
    // Fill missing positions evenly across 0..1.
    const int n = parsed.size();
    for (int i = 0; i < n; ++i) {
        if (parsed[i].pos < -0.5)
            parsed[i].pos = n <= 1 ? double(i) : double(i) / double(qMax(1, n - 1));
    }
    while (parsed.size() < 2) {
        const QColor fb = parsed.isEmpty() ? QColor(QStringLiteral("#000000")) : QColor(QStringLiteral("#ffffff"));
        const double pp = parsed.isEmpty() ? 0.0 : 1.0;
        parsed.append({ fb, pp });
    }
    std::sort(parsed.begin(), parsed.end(), [](const GradientStop &a, const GradientStop &b) {
        return a.pos < b.pos;
    });
    // Resample when over cap: pick 8 evenly by sorted index so the
    // 0..1 coverage survives instead of dropping the tail.
    if (parsed.size() > 8) {
        QVector<GradientStop> sampled;
        sampled.reserve(8);
        const int m = parsed.size();
        for (int k = 0; k < 8; ++k)
            sampled.append(parsed.at(qRound(k * (m - 1) / 7.0)));
        parsed = sampled;
    }
    // Clamp after sort so endpoints land exactly on 0/1 when close.
    for (auto &s : parsed)
        s.pos = qBound(0.0, s.pos, 1.0);
    out.stops = parsed;
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
