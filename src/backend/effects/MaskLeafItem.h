#pragma once

#include <QQuickPaintedItem>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// MaskLeafItem: CPU preview for one masked leaf, sharing FramePaint
// with video export so preview matches video by construction.
//
// The QML canvas keeps fast GPU items for plain leaves. Masked leaves
// hide their GPU paint (ShapeItem.isMaskedContent) and land here: the
// leaf paints to a temp via FramePaint::paintLeaf, then the mask
// silhouette(s) cut it via DestinationIn, then it composites. One item
// per masked leaf keeps z-order interleaving with unmasked GPU leaves
// (each item carries its leaf's paintDepth).
//
// The item is scene-sized in content coords (lives inside the scaled
// ShapeLayer, so ox=0, oy=0, scale=1). leaf/masks are plain sampled
// maps built in QML from live nodes (same keys as export snapshots).
// frameNo feeds grain so shimmer matches export.
class MaskLeafItem : public QQuickPaintedItem {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QVariantMap leaf READ leaf WRITE setLeaf NOTIFY contentChanged)
    Q_PROPERTY(QVariantList masks READ masks WRITE setMasks NOTIFY contentChanged)
    Q_PROPERTY(int frameNo READ frameNo WRITE setFrameNo NOTIFY contentChanged)

public:
    explicit MaskLeafItem(QQuickItem *parent = nullptr);

    void paint(QPainter *painter) override;

    QVariantMap leaf() const;
    void setLeaf(const QVariantMap &v);
    QVariantList masks() const;
    void setMasks(const QVariantList &v);
    int frameNo() const;
    void setFrameNo(int v);

signals:
    void contentChanged();

private:
    QVariantMap m_leaf;
    QVariantList m_masks;
    int m_frameNo = 0;
};
