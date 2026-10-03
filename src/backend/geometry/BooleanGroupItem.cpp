#include "BooleanGroupItem.h"

#include "EffectPainter.h"
#include "FramePaint.h"
#include "ShapePath.h"

#include <QImage>
#include <QPainter>

BooleanGroupItem::BooleanGroupItem(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
    setFillColor(Qt::transparent);
    setRenderTarget(QQuickPaintedItem::Image);
}

void BooleanGroupItem::paint(QPainter *painter)
{
    if (!painter || m_childMaps.size() < 1)
        return;
    painter->setRenderHint(QPainter::Antialiasing, true);
    QList<QPainterPath> paths;
    paths.reserve(m_childMaps.size());
    for (const QVariant &v : m_childMaps)
        paths << ShapePath::nodeToWorldPath(v.toMap());
    const QPainterPath combined = ShapePath::combinePaths(m_boolOp, paths);
    if (combined.isEmpty())
        return;
    const QRectF bounds = combined.boundingRect();

    QVariantMap styleMap;
    styleMap[QStringLiteral("fills")] = m_fills;
    styleMap[QStringLiteral("strokes")] = m_strokes;
    styleMap[QStringLiteral("penFill")] = true;
    const Effects::Style st = Effects::Style::fromMap(styleMap);
    const QList<Effects::Shadow> sh = Effects::Shadow::listFrom(m_shadows);
    const Effects::Blur lb = Effects::Blur::fromMap(m_layerBlur);
    const QList<Effects::Glow> gl = Effects::Glow::listFrom(m_glows);

    // Unmasked groups keep the direct fast path; masked groups
    // composite offscreen (same DestinationIn rule as MaskLeafItem).
    if (m_masks.isEmpty()) {
        painter->save();
        painter->translate(-m_boundX + m_pad, -m_boundY + m_pad);
        Effects::paintCombinedPath(painter, combined, bounds, st, sh, gl, lb, 1.0);
        const Effects::Grain grDirect = Effects::Grain::fromMap(m_grain);
        if (grDirect.enabled && grDirect.amount > 0.001)
            Effects::paintGrainPath(painter, combined, st.maxStrokeWidth(), bounds, grDirect, m_targetUid,
                m_grainFrame, 1.0);
        painter->restore();
        return;
    }
    QImage tile(int(width()), int(height()), QImage::Format_ARGB32_Premultiplied);
    if (tile.isNull())
        return;
    tile.fill(Qt::transparent);
    {
        QPainter tp(&tile);
        tp.setRenderHint(QPainter::Antialiasing, true);
        tp.save();
        tp.translate(-m_boundX + m_pad, -m_boundY + m_pad);
        Effects::paintCombinedPath(&tp, combined, bounds, st, sh, gl, lb, 1.0);
        const Effects::Grain gr = Effects::Grain::fromMap(m_grain);
        if (gr.enabled && gr.amount > 0.001)
            Effects::paintGrainPath(&tp, combined, st.maxStrokeWidth(), bounds, gr, m_targetUid, m_grainFrame, 1.0);
        tp.restore();
    }
    // Mask silhouettes in item coords (content px at scale 1, like the
    // tile): same maskSilhouette the masked-leaf preview uses.
    QImage masked;
    for (const QVariant &v : m_masks) {
        const QImage mi = FramePaint::maskSilhouette(
            v.toMap(), -m_boundX + m_pad, -m_boundY + m_pad, 1.0, tile.size());
        if (mi.isNull())
            continue;
        if (masked.isNull()) {
            masked = mi.copy();
        } else {
            QPainter cp(&masked);
            cp.setCompositionMode(QPainter::CompositionMode_DestinationIn);
            cp.drawImage(0, 0, mi);
            cp.end();
        }
    }
    if (!masked.isNull()) {
        QPainter ap(&tile);
        ap.setCompositionMode(QPainter::CompositionMode_DestinationIn);
        ap.drawImage(0, 0, masked);
        ap.end();
    }
    painter->drawImage(0, 0, tile);
}

void BooleanGroupItem::updatePad()
{
    QVariantMap styleMap;
    styleMap[QStringLiteral("fills")] = m_fills;
    styleMap[QStringLiteral("strokes")] = m_strokes;
    const Effects::Style st = Effects::Style::fromMap(styleMap);
    const double next = Effects::effectPad(Effects::Shadow::listFrom(m_shadows),
        Effects::Glow::listFrom(m_glows), Effects::Blur::fromMap(m_layerBlur), st.strokes);
    if (qFuzzyCompare(m_pad, next))
        return;
    m_pad = next;
    emit padChanged();
    update();
}

QVariantList BooleanGroupItem::childMaps() const
{
    return m_childMaps;
}

void BooleanGroupItem::setChildMaps(const QVariantList &v)
{
    if (m_childMaps == v)
        return;
    m_childMaps = v;
    emit contentChanged();
    update();
}

QString BooleanGroupItem::boolOp() const
{
    return m_boolOp;
}

void BooleanGroupItem::setBoolOp(const QString &v)
{
    if (m_boolOp == v)
        return;
    m_boolOp = v;
    emit contentChanged();
    update();
}

double BooleanGroupItem::boundX() const
{
    return m_boundX;
}

void BooleanGroupItem::setBoundX(double v)
{
    if (qFuzzyCompare(m_boundX, v))
        return;
    m_boundX = v;
    emit contentChanged();
    update();
}

double BooleanGroupItem::boundY() const
{
    return m_boundY;
}

void BooleanGroupItem::setBoundY(double v)
{
    if (qFuzzyCompare(m_boundY, v))
        return;
    m_boundY = v;
    emit contentChanged();
    update();
}

QVariantList BooleanGroupItem::fills() const
{
    return m_fills;
}

void BooleanGroupItem::setFills(const QVariantList &v)
{
    if (m_fills == v)
        return;
    m_fills = v;
    emit fillChanged();
    update();
}

QVariantList BooleanGroupItem::strokes() const
{
    return m_strokes;
}

void BooleanGroupItem::setStrokes(const QVariantList &v)
{
    if (m_strokes == v)
        return;
    m_strokes = v;
    emit strokeChanged();
    updatePad();
    update();
}

QVariantList BooleanGroupItem::shadows() const
{
    return m_shadows;
}

void BooleanGroupItem::setShadows(const QVariantList &v)
{
    if (m_shadows == v)
        return;
    m_shadows = v;
    emit shadowChanged();
    updatePad();
    update();
}

QVariantMap BooleanGroupItem::layerBlur() const
{
    return m_layerBlur;
}

void BooleanGroupItem::setLayerBlur(const QVariantMap &v)
{
    if (m_layerBlur == v)
        return;
    m_layerBlur = v;
    emit blurChanged();
    updatePad();
    update();
}

QVariantList BooleanGroupItem::glows() const
{
    return m_glows;
}

void BooleanGroupItem::setGlows(const QVariantList &v)
{
    if (m_glows == v)
        return;
    m_glows = v;
    emit glowChanged();
    updatePad();
    update();
}

QVariantMap BooleanGroupItem::grain() const
{
    return m_grain;
}

void BooleanGroupItem::setGrain(const QVariantMap &v)
{
    if (m_grain == v)
        return;
    m_grain = v;
    emit grainChanged();
    update();
}

QVariantList BooleanGroupItem::masks() const
{
    return m_masks;
}

void BooleanGroupItem::setMasks(const QVariantList &v)
{
    if (m_masks == v)
        return;
    m_masks = v;
    emit contentChanged();
    update();
}

int BooleanGroupItem::targetUid() const
{
    return m_targetUid;
}

void BooleanGroupItem::setTargetUid(int v)
{
    if (m_targetUid == v)
        return;
    m_targetUid = v;
    emit grainChanged();
    update();
}

int BooleanGroupItem::grainFrame() const
{
    return m_grainFrame;
}

void BooleanGroupItem::setGrainFrame(int v)
{
    if (m_grainFrame == v)
        return;
    m_grainFrame = v;
    emit grainChanged();
    update();
}

double BooleanGroupItem::pad() const
{
    return m_pad;
}
