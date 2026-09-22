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
    QVariantMap styleMap;
    styleMap[QStringLiteral("fills")] = m_fills;
    styleMap[QStringLiteral("strokes")] = m_strokes;
    styleMap[QStringLiteral("radius")] = m_radius;
    styleMap[QStringLiteral("penFill")] = m_penFill;
    styleMap[QStringLiteral("strokeCap")] = m_strokeCap;
    styleMap[QStringLiteral("strokeJoin")] = m_strokeJoin;
    Effects::Style st = Effects::Style::fromMap(styleMap);
    Effects::PathOpts opts;
    opts.cornerRadii = m_cornerRadii;
    opts.points = m_points;
    opts.independentCorners = m_independentCorners;
    opts.pathData = m_pathData;
    opts.ox = m_nodeX;
    opts.oy = m_nodeY;
    const QList<Effects::Shadow> sh = Effects::Shadow::listFrom(m_shadows);
    const Effects::Blur lb = Effects::Blur::fromMap(m_layerBlur);
    const QList<Effects::Glow> gl = Effects::Glow::listFrom(m_glows);
    // Effected text paints the glyph stack (same code export calls, so
    // preview matches video); plain text stays on the GPU QML branch.
    if (m_shapeType == QStringLiteral("text")) {
        const Effects::TextOpts text = Effects::TextOpts::fromMap(m_textStyle);
        Effects::paintTextLeaf(painter, QRectF(m_pad, m_pad, m_boxW, m_boxH), text, st, sh, gl, lb,
            1.0, &m_masks);
        return;
    }
    // Stacked: outer shadows -> outer glows -> fill -> inners -> stroke,
    // then layer-blur mixes the whole stack. Blurred rasters memoize in
    // m_masks (same pixels, skipped recompute); export passes null.
    Effects::paintLeaf(painter, m_shapeType, QRectF(m_pad, m_pad, m_boxW, m_boxH), opts, st, sh, gl, lb,
        1.0, &m_masks);
}

void EffectItem::updatePad()
{
    QVariantMap styleMap;
    styleMap[QStringLiteral("fills")] = m_fills;
    styleMap[QStringLiteral("strokes")] = m_strokes;
    const Effects::Style st = Effects::Style::fromMap(styleMap);
    double next = Effects::effectPad(Effects::Shadow::listFrom(m_shadows),
        Effects::Glow::listFrom(m_glows), Effects::Blur::fromMap(m_layerBlur), st.strokes);
    // Miter spikes can overshoot the round-cap bounds the pad assumes,
    // so effected pens hold at least one max stroke width of margin.
    if (m_shapeType == QStringLiteral("pen") && m_strokeJoin == QStringLiteral("miter") && st.maxStrokeWidth() > 0)
        next = qMax(next, st.maxStrokeWidth());
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
    m_masks.clear();
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
    m_masks.clear();
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
    m_masks.clear();
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
    m_masks.clear();
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
    m_masks.clear();
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
    m_masks.clear();
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
    m_masks.clear();
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
    m_masks.clear();
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
    // Pen paths resolve against the origin; every other kind ignores it
    // in paint, so its moves ride the parent transform with no repaint.
    if (m_shapeType != QStringLiteral("pen"))
        return;
    m_masks.clear();
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
    if (m_shapeType != QStringLiteral("pen"))
        return;
    m_masks.clear();
    emit shapeChanged();
    update();
}

QVariantList EffectItem::fills() const
{
    return m_fills;
}

void EffectItem::setFills(const QVariantList &v)
{
    m_fills = v;
    emit fillChanged();
    updatePad();
    update();
}

QVariantList EffectItem::strokes() const
{
    return m_strokes;
}

void EffectItem::setStrokes(const QVariantList &v)
{
    m_strokes = v;
    m_masks.clear();
    emit strokeChanged();
    updatePad();
    // updatePad only schedules when the pad itself changed; content
    // changes (e.g. same-width swaps) still need a repaint.
    update();
}

bool EffectItem::penFill() const
{
    return m_penFill;
}

void EffectItem::setPenFill(bool v)
{
    if (m_penFill == v)
        return;
    m_penFill = v;
    emit fillChanged();
    update();
}

QString EffectItem::strokeCap() const
{
    return m_strokeCap;
}

void EffectItem::setStrokeCap(const QString &v)
{
    if (m_strokeCap == v)
        return;
    m_strokeCap = v;
    // Caps reshape the silhouette, so cached blur rasters drop.
    m_masks.clear();
    emit strokeChanged();
    update();
}

QString EffectItem::strokeJoin() const
{
    return m_strokeJoin;
}

void EffectItem::setStrokeJoin(const QString &v)
{
    if (m_strokeJoin == v)
        return;
    m_strokeJoin = v;
    m_masks.clear();
    emit strokeChanged();
    updatePad();
    update();
}

QVariantList EffectItem::shadows() const
{
    return m_shadows;
}

void EffectItem::setShadows(const QVariantList &v)
{
    m_shadows = v;
    emit shadowChanged();
    updatePad();
    // Same as setStrokeWidth: pad-equal changes (flipping inner/outer
    // or recoloring at fixed blur) must still repaint.
    update();
}

QVariantMap EffectItem::layerBlur() const
{
    return m_layerBlur;
}

void EffectItem::setLayerBlur(const QVariantMap &v)
{
    m_layerBlur = v;
    emit blurChanged();
    updatePad();
    update();
}

QVariantMap EffectItem::backgroundBlur() const
{
    return m_backgroundBlur;
}

void EffectItem::setBackgroundBlur(const QVariantMap &v)
{
    // Backdrop sampling lives in QML/export; stored here so pad and
    // repaints stay in sync when the effect switches.
    m_backgroundBlur = v;
    emit blurChanged();
    update();
}

QVariantList EffectItem::glows() const
{
    return m_glows;
}

void EffectItem::setGlows(const QVariantList &v)
{
    m_glows = v;
    emit glowChanged();
    updatePad();
    // Pad-equal changes (recoloring at fixed blur) must still repaint.
    update();
}

QVariantMap EffectItem::textStyle() const
{
    return m_textStyle;
}

void EffectItem::setTextStyle(const QVariantMap &v)
{
    m_textStyle = v;
    // Layout inputs feed the cached glyph rasters, so any change drops
    // them; color-only edits never reach this map.
    m_masks.clear();
    emit textChanged();
    update();
}

double EffectItem::pad() const
{
    return m_pad;
}
