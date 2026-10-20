#include "MaskLeafItem.h"

#include "FramePaint.h"

#include <QPainter>
#include <QTransform>
#include <QtMath>

MaskLeafItem::MaskLeafItem(QQuickItem *parent)
    : QQuickPaintedItem(parent) {
    setAntialiasing(true);
    setSmooth(true);
    setFillColor(Qt::transparent);
}

void MaskLeafItem::paint(QPainter *painter) {
    if (!painter)
        return;
    const QVariantMap leaf = m_leaf;
    if (leaf.isEmpty())
        return;
    if (leaf.value(QStringLiteral("isMask"), false).toBool())
        return;
    if (!leaf.value(QStringLiteral("visible"), true).toBool())
        return;
    const double opacity = leaf.value(QStringLiteral("opacity"), 1.0).toDouble();
    if (!(opacity > 0.001))
        return;
    const double w = leaf.value(QStringLiteral("w"), 0.0).toDouble();
    const double h = leaf.value(QStringLiteral("h"), 0.0).toDouble();
    if (!(w > 0 && h > 0))
        return;
    // Device-scale preview like EffectItem: the backing is scene*zoom and
    // Qt pre-scales this painter. Bake mask silhouettes and the leaf layer
    // at backing res (scale=ds) and composite 1:1 under identity so zoom
    // never stretches a 1x raster.
    qreal ds = 1.0;
    if (painter->device() && width() > 0.0 && height() > 0.0) {
        const qreal sx = qreal(painter->device()->width()) / qreal(width());
        const qreal sy = qreal(painter->device()->height()) / qreal(height());
        ds = qMin(sx, sy);
    }
    if (!(ds > 0.04) || !(ds < 32.0) || !qIsFinite(ds))
        ds = 1.0;
    ds = qBound(0.05, ds, 4.0);
    // Allocate only the actual, budgeted QQuickPaintedItem backing. Rebuilding
    // this from width * ds can exceed a capped backing on one axis.
    const QSize size = painter->device()
        ? QSize(qMax(1, painter->device()->width()), qMax(1, painter->device()->height()))
        : QSize(qMax(1, qRound(width() * ds)), qMax(1, qRound(height() * ds)));
    if (size.isEmpty())
        return;

    // Active masks: visible maps only (opacity 0 still masks: the
    // silhouette carries near-zero alpha and hides, like export).
    QList<QVariantMap> active;
    for (const QVariant &v : m_masks) {
        const QVariantMap mm = v.toMap();
        if (mm.isEmpty())
            continue;
        if (mm.value(QStringLiteral("isMask"), false).toBool() == false) {
            // Tolerate callers passing unresolved entries: only real
            // mask maps cut. Non-mask entries are skipped, never paint.
            continue;
        }
        if (!mm.value(QStringLiteral("visible"), true).toBool())
            continue;
        active.append(mm);
    }
    if (active.isEmpty())
        return;

    QImage combined;
    for (const QVariantMap &mm : active) {
        const QImage mi = FramePaint::maskSilhouette(mm, 0.0, 0.0, ds, size);
        if (mi.isNull())
            return;
        if (combined.isNull()) {
            combined = mi.copy();
        } else {
            QPainter cp(&combined);
            cp.setCompositionMode(QPainter::CompositionMode_DestinationIn);
            cp.drawImage(0, 0, mi);
            cp.end();
        }
    }
    if (combined.isNull())
        return;

    QImage layer(size, QImage::Format_ARGB32_Premultiplied);
    layer.fill(Qt::transparent);
    {
        QPainter lp(&layer);
        lp.setRenderHints(QPainter::Antialiasing | QPainter::TextAntialiasing | QPainter::SmoothPixmapTransform);
        // Backdrop blur inside masks samples the temp (transparent),
        // not the scene behind: same documented v1 limitation as export.
        FramePaint::paintLeaf(lp, layer, leaf, 0.0, 0.0, ds, m_frameNo);
    }
    {
        QPainter ap(&layer);
        ap.setCompositionMode(QPainter::CompositionMode_DestinationIn);
        ap.drawImage(0, 0, combined);
    }
    painter->save();
    painter->setTransform(QTransform());
    painter->drawImage(0, 0, layer);
    painter->restore();
}

QVariantMap MaskLeafItem::leaf() const {
    return m_leaf;
}

void MaskLeafItem::setLeaf(const QVariantMap &v) {
    if (m_leaf == v)
        return;
    m_leaf = v;
    emit contentChanged();
    update();
}

QVariantList MaskLeafItem::masks() const {
    return m_masks;
}

void MaskLeafItem::setMasks(const QVariantList &v) {
    if (m_masks == v)
        return;
    m_masks = v;
    emit contentChanged();
    update();
}

int MaskLeafItem::frameNo() const {
    return m_frameNo;
}

void MaskLeafItem::setFrameNo(int v) {
    if (m_frameNo == v)
        return;
    m_frameNo = v;
    // Grain shimmer is the only frame-dependent input: static or
    // grain-free leaves must not repaint at 60Hz during playback.
    bool grainOn = false;
    const QVariant g = m_leaf.value(QStringLiteral("grain"));
    if (g.isValid()) {
        const QVariantMap gm = g.toMap();
        if (!gm.isEmpty())
            grainOn = gm.value(QStringLiteral("enabled"), false).toBool()
                && gm.value(QStringLiteral("amount"), 0.0).toDouble() > 0.001;
    }
    if (!grainOn)
        return;
    emit contentChanged();
    update();
}
