#pragma once

#include <QCache>
#include <QColor>
#include <QImage>
#include <QQuickPaintedItem>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// EffectItem: CPU-painted vector shape for gradient fills/strokes and
// outer shadows the stock QML items cannot express (ShapePath has
// fillGradient only, Rectangle borders stay solid, MultiEffect has no
// spread). Paints through Effects::paintLeaf, the same code export will
// call from P3, so preview matches video by construction. Covers
// rectangle/ellipse/triangle/star/pen; text and images stay on the GPU
// path. The item is bigger than the shape by pad() on every side (shadow
// blur never clips); the shape paints at (pad,pad). One instance per
// effected shape; plain shapes keep the fast GPU items.
// Blurred silhouette/cutter rasters memoize in m_masks (same pixels,
// skipped blur recompute); geometry edits clear it, style and effect
// edits keep it so stacked siblings reuse each other's rasters.
class EffectItem : public QQuickPaintedItem {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString shapeType READ shapeType WRITE setShapeType NOTIFY shapeChanged)
    Q_PROPERTY(double boxW READ boxW WRITE setBoxW NOTIFY shapeChanged)
    Q_PROPERTY(double boxH READ boxH WRITE setBoxH NOTIFY shapeChanged)
    Q_PROPERTY(double radius READ radius WRITE setRadius NOTIFY shapeChanged)
    Q_PROPERTY(bool independentCorners READ independentCorners WRITE setIndependentCorners NOTIFY shapeChanged)
    Q_PROPERTY(QVariantList cornerRadii READ cornerRadii WRITE setCornerRadii NOTIFY shapeChanged)
    Q_PROPERTY(int points READ points WRITE setPoints NOTIFY shapeChanged)
    Q_PROPERTY(QVariantList pathData READ pathData WRITE setPathData NOTIFY shapeChanged)
    Q_PROPERTY(double nodeX READ nodeX WRITE setNodeX NOTIFY shapeChanged)
    Q_PROPERTY(double nodeY READ nodeY WRITE setNodeY NOTIFY shapeChanged)
    Q_PROPERTY(QColor fill READ fill WRITE setFill NOTIFY fillChanged)
    Q_PROPERTY(QString fillType READ fillType WRITE setFillType NOTIFY fillChanged)
    Q_PROPERTY(QVariantMap fillGradient READ fillGradient WRITE setFillGradient NOTIFY fillChanged)
    Q_PROPERTY(QColor stroke READ stroke WRITE setStroke NOTIFY strokeChanged)
    Q_PROPERTY(QString strokeType READ strokeType WRITE setStrokeType NOTIFY strokeChanged)
    Q_PROPERTY(QVariantMap strokeGradient READ strokeGradient WRITE setStrokeGradient NOTIFY strokeChanged)
    Q_PROPERTY(double strokeWidth READ strokeWidth WRITE setStrokeWidth NOTIFY strokeChanged)
    Q_PROPERTY(QVariantList shadows READ shadows WRITE setShadows NOTIFY shadowChanged)
    Q_PROPERTY(QVariantMap layerBlur READ layerBlur WRITE setLayerBlur NOTIFY blurChanged)
    Q_PROPERTY(QVariantMap backgroundBlur READ backgroundBlur WRITE setBackgroundBlur NOTIFY blurChanged)
    Q_PROPERTY(QVariantList glows READ glows WRITE setGlows NOTIFY glowChanged)
    Q_PROPERTY(double pad READ pad NOTIFY padChanged)

public:
    explicit EffectItem(QQuickItem *parent = nullptr);

    void paint(QPainter *painter) override;

    QString shapeType() const;
    void setShapeType(const QString &v);
    double boxW() const;
    void setBoxW(double v);
    double boxH() const;
    void setBoxH(double v);
    double radius() const;
    void setRadius(double v);
    bool independentCorners() const;
    void setIndependentCorners(bool v);
    QVariantList cornerRadii() const;
    void setCornerRadii(const QVariantList &v);
    int points() const;
    void setPoints(int v);
    QVariantList pathData() const;
    void setPathData(const QVariantList &v);
    double nodeX() const;
    void setNodeX(double v);
    double nodeY() const;
    void setNodeY(double v);
    QColor fill() const;
    void setFill(const QColor &v);
    QString fillType() const;
    void setFillType(const QString &v);
    QVariantMap fillGradient() const;
    void setFillGradient(const QVariantMap &v);
    QColor stroke() const;
    void setStroke(const QColor &v);
    QString strokeType() const;
    void setStrokeType(const QString &v);
    QVariantMap strokeGradient() const;
    void setStrokeGradient(const QVariantMap &v);
    double strokeWidth() const;
    void setStrokeWidth(double v);
    QVariantList shadows() const;
    void setShadows(const QVariantList &v);
    QVariantMap layerBlur() const;
    void setLayerBlur(const QVariantMap &v);
    QVariantMap backgroundBlur() const;
    void setBackgroundBlur(const QVariantMap &v);
    QVariantList glows() const;
    void setGlows(const QVariantList &v);
    double pad() const;

signals:
    void shapeChanged();
    void fillChanged();
    void strokeChanged();
    void shadowChanged();
    void blurChanged();
    void glowChanged();
    void padChanged();

private:
    void updatePad();

    QString m_shapeType = QStringLiteral("rectangle");
    double m_boxW = 10.0;
    double m_boxH = 10.0;
    double m_radius = 0.0;
    bool m_independentCorners = false;
    QVariantList m_cornerRadii;
    int m_points = 5;
    QVariantList m_pathData;
    double m_nodeX = 0.0;
    double m_nodeY = 0.0;
    QColor m_fill = QColor(QStringLiteral("#d9d9d9"));
    QString m_fillType = QStringLiteral("solid");
    QVariantMap m_fillGradient;
    QColor m_stroke = QColor(QStringLiteral("#000000"));
    QString m_strokeType = QStringLiteral("solid");
    QVariantMap m_strokeGradient;
    double m_strokeWidth = 0.0;
    QVariantList m_shadows;
    QVariantMap m_layerBlur;
    QVariantMap m_backgroundBlur;
    QVariantList m_glows;
    double m_pad = 0.0;
    QCache<QByteArray, QImage> m_masks{16 * 1024 * 1024};
};
