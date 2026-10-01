#pragma once

#include <QCache>
#include <QImage>
#include <QQuickPaintedItem>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// BooleanGroupItem: CPU-painted live boolean group. Children stay as
// snapshot maps (see DocClipboard.snapshotNode); the item combines
// them per paint via ShapePath and renders through
// Effects::paintCombinedPath — the same stack export calls, so preview
// matches export by construction. Geometry (x/y/width/height) is owned
// by QML via ShapePathHelper.combineBounds; paint translates world to
// item coords by (-bounds + pad).
class BooleanGroupItem : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QVariantList childMaps READ childMaps WRITE setChildMaps NOTIFY contentChanged)
    Q_PROPERTY(QString boolOp READ boolOp WRITE setBoolOp NOTIFY contentChanged)
    Q_PROPERTY(double boundX READ boundX WRITE setBoundX NOTIFY contentChanged)
    Q_PROPERTY(double boundY READ boundY WRITE setBoundY NOTIFY contentChanged)
    Q_PROPERTY(QVariantList fills READ fills WRITE setFills NOTIFY fillChanged)
    Q_PROPERTY(QVariantList strokes READ strokes WRITE setStrokes NOTIFY strokeChanged)
    Q_PROPERTY(QVariantList shadows READ shadows WRITE setShadows NOTIFY shadowChanged)
    Q_PROPERTY(QVariantMap layerBlur READ layerBlur WRITE setLayerBlur NOTIFY blurChanged)
    Q_PROPERTY(QVariantList glows READ glows WRITE setGlows NOTIFY glowChanged)
    Q_PROPERTY(QVariantMap grain READ grain WRITE setGrain NOTIFY grainChanged)
    Q_PROPERTY(QVariantList masks READ masks WRITE setMasks NOTIFY contentChanged)
    Q_PROPERTY(int targetUid READ targetUid WRITE setTargetUid NOTIFY grainChanged)
    Q_PROPERTY(int grainFrame READ grainFrame WRITE setGrainFrame NOTIFY grainChanged)
    Q_PROPERTY(double pad READ pad NOTIFY padChanged)

public:
    explicit BooleanGroupItem(QQuickItem *parent = nullptr);

    void paint(QPainter *painter) override;

    QVariantList childMaps() const;
    void setChildMaps(const QVariantList &v);
    QString boolOp() const;
    void setBoolOp(const QString &v);
    double boundX() const;
    void setBoundX(double v);
    double boundY() const;
    void setBoundY(double v);
    QVariantList fills() const;
    void setFills(const QVariantList &v);
    QVariantList strokes() const;
    void setStrokes(const QVariantList &v);
    QVariantList shadows() const;
    void setShadows(const QVariantList &v);
    QVariantMap layerBlur() const;
    void setLayerBlur(const QVariantMap &v);
    QVariantList glows() const;
    void setGlows(const QVariantList &v);
    QVariantMap grain() const;
    void setGrain(const QVariantMap &v);
    QVariantList masks() const;
    void setMasks(const QVariantList &v);
    int targetUid() const;
    void setTargetUid(int v);
    int grainFrame() const;
    void setGrainFrame(int v);
    double pad() const;

signals:
    void contentChanged();
    void fillChanged();
    void strokeChanged();
    void shadowChanged();
    void blurChanged();
    void glowChanged();
    void grainChanged();
    void padChanged();

private:
    void updatePad();

    QVariantList m_childMaps;
    QString m_boolOp = QStringLiteral("union");
    double m_boundX = 0.0;
    double m_boundY = 0.0;
    QVariantList m_fills;
    QVariantList m_strokes;
    QVariantList m_shadows;
    QVariantMap m_layerBlur;
    QVariantList m_glows;
    QVariantMap m_grain;
    // Group-level mask maps (same preview-map shape MaskLeafItem takes):
    // empty means unmasked (fast direct paint below).
    QVariantList m_masks;
    int m_targetUid = -1;
    int m_grainFrame = 0;
    double m_pad = 0.0;
};
