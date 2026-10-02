#include "ImageEffectItem.h"

#include "EffectPainter.h"
#include "FramePaint.h"

#include <QPainter>

ImageEffectItem::ImageEffectItem(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
    setFillColor(Qt::transparent);
    setRenderTarget(QQuickPaintedItem::Image);
}

void ImageEffectItem::paint(QPainter *painter)
{
    if (!painter || m_boxW <= 0 || m_boxH <= 0)
        return;
    painter->setRenderHint(QPainter::Antialiasing, true);

    // Leaf map in the same keys export snapshots use. x/y place the box
    // at (pad,pad) inside this padded item; rotation/flip stay on the
    // QML transform (parent Item), so the leaf stays axis-aligned here.
    // Background blur is disabled: the QML backdrop rig samples the live
    // scene behind this item like export samples the frame so far.
    // Video links ride the same item: when videoSource is set the leaf
    // paints the decoded frame (FramePaint video branch), else the image.
    QVariantMap leaf;
    const bool isVideo = !m_videoSource.isEmpty();
    leaf[QStringLiteral("type")] = isVideo ? QStringLiteral("video") : QStringLiteral("image");
    leaf[QStringLiteral("shapeType")] = isVideo ? QStringLiteral("video") : QStringLiteral("image");
    leaf[QStringLiteral("x")] = m_pad;
    leaf[QStringLiteral("y")] = m_pad;
    leaf[QStringLiteral("w")] = m_boxW;
    leaf[QStringLiteral("h")] = m_boxH;
    leaf[QStringLiteral("radius")] = m_radius;
    leaf[QStringLiteral("imageSource")] = m_imageSource;
    leaf[QStringLiteral("image")] = m_imageSource;
    leaf[QStringLiteral("videoSource")] = m_videoSource;
    leaf[QStringLiteral("videoDuration")] = m_videoDuration;
    leaf[QStringLiteral("videoOffset")] = m_videoOffset;
    leaf[QStringLiteral("playbackRate")] = m_playbackRate;
    leaf[QStringLiteral("videoLoop")] = m_videoLoop;
    leaf[QStringLiteral("shadows")] = m_shadows;
    leaf[QStringLiteral("glows")] = m_glows;
    leaf[QStringLiteral("layerBlur")] = m_layerBlur;
    leaf[QStringLiteral("backgroundBlur")] = QVariantMap({{QStringLiteral("enabled"), false}});
    leaf[QStringLiteral("grain")] = m_grain;
    leaf[QStringLiteral("strokes")] = m_strokes;
    leaf[QStringLiteral("fills")] = QVariantList();
    leaf[QStringLiteral("uid")] = m_uid;
    leaf[QStringLiteral("opacity")] = 1.0;
    leaf[QStringLiteral("visible")] = true;
    leaf[QStringLiteral("rotation")] = 0.0;
    leaf[QStringLiteral("flipH")] = false;
    leaf[QStringLiteral("flipV")] = false;

    // Dummy backdrop tile: never sampled (background disabled), but
    // paintLeaf requires a frame reference.
    static QImage s_dummy(1, 1, QImage::Format_ARGB32_Premultiplied);
    s_dummy.fill(Qt::transparent);
    QImage frame = s_dummy;
    FramePaint::paintLeaf(*painter, frame, leaf, 0.0, 0.0, 1.0, m_frameNo);
}

void ImageEffectItem::updatePad()
{
    const QList<Effects::Shadow> shadows = Effects::Shadow::listFrom(m_shadows);
    const QList<Effects::Glow> glows = Effects::Glow::listFrom(m_glows);
    const Effects::Blur lb = Effects::Blur::fromMap(m_layerBlur);
    const Effects::Style st = Effects::Style::fromMap(
        QVariantMap({{QStringLiteral("strokes"), m_strokes}}));
    // Mirrors FramePaint::leafPad image rule: shared pad plus the glow
    // halo the shared pad does not cover for images.
    double next = Effects::effectPad(shadows, glows, lb, st.strokes);
    next = qMax(next, Effects::glowsPad(glows));
    next = qMin(1024.0, qMax(0.0, next));
    if (qFuzzyCompare(m_pad, next))
        return;
    m_pad = next;
    emit padChanged();
    update();
}

double ImageEffectItem::boxW() const
{
    return m_boxW;
}

void ImageEffectItem::setBoxW(double v)
{
    if (qFuzzyCompare(m_boxW, v))
        return;
    m_boxW = v;
    emit shapeChanged();
    update();
}

double ImageEffectItem::boxH() const
{
    return m_boxH;
}

void ImageEffectItem::setBoxH(double v)
{
    if (qFuzzyCompare(m_boxH, v))
        return;
    m_boxH = v;
    emit shapeChanged();
    update();
}

double ImageEffectItem::radius() const
{
    return m_radius;
}

void ImageEffectItem::setRadius(double v)
{
    if (qFuzzyCompare(m_radius, v))
        return;
    m_radius = v;
    emit shapeChanged();
    update();
}

QString ImageEffectItem::imageSource() const
{
    return m_imageSource;
}

void ImageEffectItem::setImageSource(const QString &v)
{
    if (m_imageSource == v)
        return;
    m_imageSource = v;
    emit shapeChanged();
    update();
}

QString ImageEffectItem::videoSource() const
{
    return m_videoSource;
}

void ImageEffectItem::setVideoSource(const QString &v)
{
    if (m_videoSource == v)
        return;
    m_videoSource = v;
    emit shapeChanged();
    update();
}

double ImageEffectItem::videoDuration() const
{
    return m_videoDuration;
}

void ImageEffectItem::setVideoDuration(double v)
{
    const double nv = qMax(0.0, v);
    if (qFuzzyCompare(m_videoDuration, nv))
        return;
    m_videoDuration = nv;
    emit shapeChanged();
    update();
}

double ImageEffectItem::videoOffset() const
{
    return m_videoOffset;
}

void ImageEffectItem::setVideoOffset(double v)
{
    const double nv = qMax(0.0, v);
    if (qFuzzyCompare(m_videoOffset, nv))
        return;
    m_videoOffset = nv;
    emit shapeChanged();
    update();
}

double ImageEffectItem::playbackRate() const
{
    return m_playbackRate;
}

void ImageEffectItem::setPlaybackRate(double v)
{
    double nv = v;
    if (!(nv > 0.0))
        nv = 1.0;
    nv = qBound(0.25, nv, 4.0);
    if (qFuzzyCompare(m_playbackRate, nv))
        return;
    m_playbackRate = nv;
    emit shapeChanged();
    update();
}

bool ImageEffectItem::videoLoop() const
{
    return m_videoLoop;
}

void ImageEffectItem::setVideoLoop(bool v)
{
    if (m_videoLoop == v)
        return;
    m_videoLoop = v;
    emit shapeChanged();
    update();
}

QVariantList ImageEffectItem::shadows() const
{
    return m_shadows;
}

void ImageEffectItem::setShadows(const QVariantList &v)
{
    if (m_shadows == v)
        return;
    m_shadows = v;
    emit effectChanged();
    updatePad();
    update();
}

QVariantList ImageEffectItem::glows() const
{
    return m_glows;
}

void ImageEffectItem::setGlows(const QVariantList &v)
{
    if (m_glows == v)
        return;
    m_glows = v;
    emit effectChanged();
    updatePad();
    update();
}

QVariantMap ImageEffectItem::layerBlur() const
{
    return m_layerBlur;
}

void ImageEffectItem::setLayerBlur(const QVariantMap &v)
{
    if (m_layerBlur == v)
        return;
    m_layerBlur = v;
    emit effectChanged();
    updatePad();
    update();
}

QVariantMap ImageEffectItem::grain() const
{
    return m_grain;
}

void ImageEffectItem::setGrain(const QVariantMap &v)
{
    if (m_grain == v)
        return;
    m_grain = v;
    emit effectChanged();
    update();
}

QVariantList ImageEffectItem::strokes() const
{
    return m_strokes;
}

void ImageEffectItem::setStrokes(const QVariantList &v)
{
    if (m_strokes == v)
        return;
    m_strokes = v;
    emit effectChanged();
    updatePad();
    update();
}

int ImageEffectItem::uid() const
{
    return m_uid;
}

void ImageEffectItem::setUid(int v)
{
    if (m_uid == v)
        return;
    m_uid = v;
    emit effectChanged();
    update();
}

int ImageEffectItem::frameNo() const
{
    return m_frameNo;
}

void ImageEffectItem::setFrameNo(int v)
{
    if (m_frameNo == v)
        return;
    m_frameNo = v;
    // Grain shimmer is the only frame-dependent input.
    bool grainOn = false;
    if (!m_grain.isEmpty())
        grainOn = m_grain.value(QStringLiteral("enabled"), false).toBool()
            && m_grain.value(QStringLiteral("amount"), 0.0).toDouble() > 0.001;
    if (!grainOn)
        return;
    emit effectChanged();
    update();
}

double ImageEffectItem::pad() const
{
    return m_pad;
}
