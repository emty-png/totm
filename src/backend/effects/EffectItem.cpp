#include "EffectItem.h"

#include "EffectPainter.h"

EffectItem::EffectItem(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
    setFillColor(Qt::transparent);
    setRenderTarget(QQuickPaintedItem::Image);
}

void EffectItem::paint(QPainter *painter)
{
    if (!painter || m_boxW <= 0 || m_boxH <= 0)
        return;
    painter->setRenderHint(QPainter::Antialiasing, true);
    Effects::Style st;
    st.fill = m_fill;
    st.fillType = m_fillType;
    st.fillGradient = m_fillGradient;
    st.stroke = m_stroke;
    st.strokeType = m_strokeType;
    st.strokeGradient = m_strokeGradient;
    st.strokeWidth = m_strokeWidth;
    st.radius = m_radius;
    Effects::PathOpts opts;
    opts.cornerRadii = m_cornerRadii;
    opts.points = m_points;
    opts.independentCorners = m_independentCorners;
    opts.pathData = m_pathData;
    opts.ox = m_nodeX;
    opts.oy = m_nodeY;
    const Effects::Shadow sh = Effects::Shadow::fromMap(m_shadow);
    Effects::paintLeaf(painter, m_shapeType, QRectF(m_pad, m_pad, m_boxW, m_boxH), opts, st, sh, 1.0);
}

void EffectItem::updatePad()
{
    const double next = Effects::shadowPad(Effects::Shadow::fromMap(m_shadow), m_strokeWidth);
    if (qFuzzyCompare(m_pad, next))
        return;
    m_pad = next;
    emit padChanged();
    update();
}

QString EffectItem::shapeType() const
{
    return m_shapeType;
}

void EffectItem::setShapeType(const QString &v)
{
    if (m_shapeType == v)
        return;
    m_shapeType = v;
    emit shapeChanged();
    update();
}

double EffectItem::boxW() const
{
    return m_boxW;
}

void EffectItem::setBoxW(double v)
{
    if (qFuzzyCompare(m_boxW, v))
        return;
    m_boxW = v;
    emit shapeChanged();
    update();
}

double EffectItem::boxH() const
{
    return m_boxH;
}

void EffectItem::setBoxH(double v)
{
    if (qFuzzyCompare(m_boxH, v))
        return;
    m_boxH = v;
    emit shapeChanged();
    update();
}

double EffectItem::radius() const
{
    return m_radius;
}

void EffectItem::setRadius(double v)
{
    if (qFuzzyCompare(m_radius, v))
        return;
    m_radius = v;
    emit shapeChanged();
    update();
}

bool EffectItem::independentCorners() const
{
    return m_independentCorners;
}

void EffectItem::setIndependentCorners(bool v)
{
    if (m_independentCorners == v)
        return;
    m_independentCorners = v;
    emit shapeChanged();
    update();
}

QVariantList EffectItem::cornerRadii() const
{
    return m_cornerRadii;
}

void EffectItem::setCornerRadii(const QVariantList &v)
{
    m_cornerRadii = v;
    emit shapeChanged();
    update();
}

int EffectItem::points() const
{
    return m_points;
}

void EffectItem::setPoints(int v)
{
    if (m_points == v)
        return;
    m_points = v;
    emit shapeChanged();
    update();
}

QVariantList EffectItem::pathData() const
{
    return m_pathData;
}

void EffectItem::setPathData(const QVariantList &v)
{
    m_pathData = v;
    emit shapeChanged();
    update();
}

double EffectItem::nodeX() const
{
    return m_nodeX;
}

void EffectItem::setNodeX(double v)
{
    if (qFuzzyCompare(m_nodeX, v))
        return;
    m_nodeX = v;
    emit shapeChanged();
    update();
}

double EffectItem::nodeY() const
{
    return m_nodeY;
}

void EffectItem::setNodeY(double v)
{
    if (qFuzzyCompare(m_nodeY, v))
        return;
    m_nodeY = v;
    emit shapeChanged();
    update();
}

QColor EffectItem::fill() const
{
    return m_fill;
}

void EffectItem::setFill(const QColor &v)
{
    if (m_fill == v)
        return;
    m_fill = v;
    emit fillChanged();
    update();
}

QString EffectItem::fillType() const
{
    return m_fillType;
}

void EffectItem::setFillType(const QString &v)
{
    if (m_fillType == v)
        return;
    m_fillType = v;
    emit fillChanged();
    update();
}

QVariantMap EffectItem::fillGradient() const
{
    return m_fillGradient;
}

void EffectItem::setFillGradient(const QVariantMap &v)
{
    m_fillGradient = v;
    emit fillChanged();
    update();
}

QColor EffectItem::stroke() const
{
    return m_stroke;
}

void EffectItem::setStroke(const QColor &v)
{
    if (m_stroke == v)
        return;
    m_stroke = v;
    emit strokeChanged();
    update();
}

QString EffectItem::strokeType() const
{
    return m_strokeType;
}

void EffectItem::setStrokeType(const QString &v)
{
    if (m_strokeType == v)
        return;
    m_strokeType = v;
    emit strokeChanged();
    update();
}

QVariantMap EffectItem::strokeGradient() const
{
    return m_strokeGradient;
}

void EffectItem::setStrokeGradient(const QVariantMap &v)
{
    m_strokeGradient = v;
    emit strokeChanged();
    update();
}

double EffectItem::strokeWidth() const
{
    return m_strokeWidth;
}

void EffectItem::setStrokeWidth(double v)
{
    if (qFuzzyCompare(m_strokeWidth, v))
        return;
    m_strokeWidth = v;
    emit strokeChanged();
    updatePad();
    // updatePad only schedules when the pad itself changed; content
    // changes (e.g. same-width swaps) still need a repaint.
    update();
}

QVariantMap EffectItem::shadow() const
{
    return m_shadow;
}

void EffectItem::setShadow(const QVariantMap &v)
{
    m_shadow = v;
    emit shadowChanged();
    updatePad();
    // Same as setStrokeWidth: pad-equal changes (flipping inner/outer
    // or recoloring at fixed blur) must still repaint.
    update();
}

double EffectItem::pad() const
{
    return m_pad;
}
