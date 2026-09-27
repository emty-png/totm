#pragma once

#include <QQuickPaintedItem>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// ImageEffectItem: CPU-painted image leaf for the canvas preview,
// sharing FramePaint with video/component export so preview matches
// export by construction.
//
// The QML image path (ShapeItem imageRoot: Rectangle + MultiEffect
// repeaters) re-implements inner bands with a thresholded inverted
// mask, giving a hard rectangular ring with the wrong falloff versus
// the smooth continuous-alpha DestinationOut band export paints.
// Outer blur kernels differ too (MultiEffect gaussian vs 3-pass box).
// This item forwards to FramePaint::paintLeaf (image branch), which
// already handles outer/inner shadows+glows, layer blur, grain,
// strokes, EXIF and missing-blob tiles.
//
// One instance per effected image; plain images keep the fast GPU
// QML branch. Background blur stays on the QML backdrop rig (the CPU
// leaf disables it so the dummy frame is never sampled). The item is
// bigger than the box by pad() on every side; the image paints at
// (pad,pad). Flip/rotation ride the QML transform like EffectItem.
class ImageEffectItem : public QQuickPaintedItem {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(double boxW READ boxW WRITE setBoxW NOTIFY shapeChanged)
    Q_PROPERTY(double boxH READ boxH WRITE setBoxH NOTIFY shapeChanged)
    Q_PROPERTY(double radius READ radius WRITE setRadius NOTIFY shapeChanged)
    Q_PROPERTY(QString imageSource READ imageSource WRITE setImageSource NOTIFY shapeChanged)
    Q_PROPERTY(QVariantList shadows READ shadows WRITE setShadows NOTIFY effectChanged)
    Q_PROPERTY(QVariantList glows READ glows WRITE setGlows NOTIFY effectChanged)
    Q_PROPERTY(QVariantMap layerBlur READ layerBlur WRITE setLayerBlur NOTIFY effectChanged)
    Q_PROPERTY(QVariantMap grain READ grain WRITE setGrain NOTIFY effectChanged)
    Q_PROPERTY(QVariantList strokes READ strokes WRITE setStrokes NOTIFY effectChanged)
    Q_PROPERTY(int uid READ uid WRITE setUid NOTIFY effectChanged)
    Q_PROPERTY(int frameNo READ frameNo WRITE setFrameNo NOTIFY effectChanged)
    Q_PROPERTY(double pad READ pad NOTIFY padChanged)

public:
    explicit ImageEffectItem(QQuickItem *parent = nullptr);

    void paint(QPainter *painter) override;

    double boxW() const;
    void setBoxW(double v);
    double boxH() const;
    void setBoxH(double v);
    double radius() const;
    void setRadius(double v);
    QString imageSource() const;
    void setImageSource(const QString &v);
    QVariantList shadows() const;
    void setShadows(const QVariantList &v);
    QVariantList glows() const;
    void setGlows(const QVariantList &v);
    QVariantMap layerBlur() const;
    void setLayerBlur(const QVariantMap &v);
    QVariantMap grain() const;
    void setGrain(const QVariantMap &v);
    QVariantList strokes() const;
    void setStrokes(const QVariantList &v);
    int uid() const;
    void setUid(int v);
    int frameNo() const;
    void setFrameNo(int v);
    double pad() const;

signals:
    void shapeChanged();
    void effectChanged();
    void padChanged();

private:
    void updatePad();

    double m_boxW = 10.0;
    double m_boxH = 10.0;
    double m_radius = 0.0;
    QString m_imageSource;
    QVariantList m_shadows;
    QVariantList m_glows;
    QVariantMap m_layerBlur;
    QVariantMap m_grain;
    QVariantList m_strokes;
    int m_uid = -1;
    int m_frameNo = 0;
    double m_pad = 0.0;
};
