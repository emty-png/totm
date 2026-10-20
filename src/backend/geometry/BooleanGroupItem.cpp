#include "BooleanGroupItem.h"

#include "EffectPainter.h"
#include "FramePaint.h"
#include "ShapePath.h"

#include <QImage>
#include <QPainter>
#include <QTransform>
#include <QtMath>

BooleanGroupItem::BooleanGroupItem(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
    setSmooth(true);
    setFillColor(Qt::transparent);
    setRenderTarget(QQuickPaintedItem::Image);
}

void BooleanGroupItem::paint(QPainter *painter)
{
    if (!painter || m_childMaps.size() < 1)
        return;
    painter->setRenderHint(QPainter::Antialiasing, true);
    // Device-scale preview like EffectItem: bake combined silhouette and
    // all blur rasters at backing res so zoom never stretches a 1x cache.
    qreal ds = 1.0;
    if (painter->device() && width() > 0.0 && height() > 0.0) {
        const qreal sx = qreal(painter->device()->width()) / qreal(width());
        const qreal sy = qreal(painter->device()->height()) / qreal(height());
        ds = qMin(sx, sy);
    }
    if (!(ds > 0.04) || !(ds < 32.0) || !qIsFinite(ds))
        ds = 1.0;
    ds = qBound(0.05, ds, 8.0);
    QList<QPainterPath> paths;
    paths.reserve(m_childMaps.size());
    for (const QVariant &v : m_childMaps)
        paths << ShapePath::nodeToWorldPath(v.toMap());
    const QPainterPath combined = ShapePath::combinePaths(m_boolOp, paths);
    if (combined.isEmpty())
        return;
    // Device-space path/bounds: scale the logical combination once so the
    // painter (identity below) and every cached raster share screen res.
    const QPainterPath dpath = QTransform::fromScale(ds, ds).map(combined);
    const QRectF dbounds = dpath.boundingRect();

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
        painter->setTransform(QTransform());
        painter->translate(-m_boundX * ds + m_pad * ds, -m_boundY * ds + m_pad * ds);
        Effects::paintCombinedPath(painter, dpath, dbounds, st, sh, gl, lb, ds);
        const Effects::Grain grDirect = Effects::Grain::fromMap(m_grain);
        if (grDirect.enabled && grDirect.amount > 0.001)
            Effects::paintGrainPath(painter, dpath, st.maxStrokeWidth(), dbounds, grDirect, m_targetUid,
                m_grainFrame, ds);
        painter->restore();
        return;
    }
    const QSize tileSize = painter->device()
        ? QSize(qMax(1, painter->device()->width()), qMax(1, painter->device()->height()))
        : QSize(qMax(1, qRound(width() * ds)), qMax(1, qRound(height() * ds)));
    QImage tile(tileSize, QImage::Format_ARGB32_Premultiplied);
    if (tile.isNull())
        return;
    tile.fill(Qt::transparent);
    {
        QPainter tp(&tile);
        tp.setRenderHint(QPainter::Antialiasing, true);
        tp.save();
        tp.translate(-m_boundX * ds + m_pad * ds, -m_boundY * ds + m_pad * ds);
        Effects::paintCombinedPath(&tp, dpath, dbounds, st, sh, gl, lb, ds);
        const Effects::Grain gr = Effects::Grain::fromMap(m_grain);
        if (gr.enabled && gr.amount > 0.001)
            Effects::paintGrainPath(&tp, dpath, st.maxStrokeWidth(), dbounds, gr, m_targetUid, m_grainFrame, ds);
        tp.restore();
    }
    // Mask silhouettes in device coords (same scale as the tile).
    QImage masked;
    for (const QVariant &v : m_masks) {
        const QImage mi = FramePaint::maskSilhouette(
            v.toMap(), -m_boundX * ds + m_pad * ds, -m_boundY * ds + m_pad * ds, ds, tile.size());
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
    painter->save();
    painter->setTransform(QTransform());
    painter->drawImage(0, 0, tile);
    painter->restore();
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
