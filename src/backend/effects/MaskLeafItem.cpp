#include "MaskLeafItem.h"

#include "FramePaint.h"

#include <QPainter>

MaskLeafItem::MaskLeafItem(QQuickItem *parent)
    : QQuickPaintedItem(parent) {
    setAntialiasing(true);
    setSmooth(true);
    setMipmap(true);
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
    const QSize size(qMax(1, qRound(width())), qMax(1, qRound(height())));
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
        const QImage mi = FramePaint::maskSilhouette(mm, 0.0, 0.0, 1.0, size);
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
        FramePaint::paintLeaf(lp, layer, leaf, 0.0, 0.0, 1.0, m_frameNo);
    }
    {
        QPainter ap(&layer);
        ap.setCompositionMode(QPainter::CompositionMode_DestinationIn);
        ap.drawImage(0, 0, combined);
    }
    painter->drawImage(QRectF(0, 0, width(), height()), layer);
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
    emit contentChanged();
    update();
}
