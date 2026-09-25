#include "FramePaint.h"

#include "AnimSampler.h"
#include "EffectPainter.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QImageReader>
#include <QPainterPathStroker>
#include <QStandardPaths>
#include <QSvgRenderer>
#include <QtMath>

namespace FramePaint {

using namespace Anims;

namespace {

// Image via stored blob (mirrors ShapeItem stretch). Missing blobs
// paint a neutral box so broken imports never vanish silently.
QString exportImagesDir() {
    QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (dir.isEmpty())
        dir = QDir::homePath() + QStringLiteral("/.totm");
    if (!dir.endsWith(QStringLiteral("/totm"), Qt::CaseInsensitive))
        dir += QStringLiteral("/totm");
    return dir + QStringLiteral("/images");
}

QImage loadExportImage(const QString &name, int targetW, int targetH) {
    if (name.isEmpty() || name.contains(QLatin1Char('/')) || name.contains(QLatin1Char('\\'))
        || name.contains(QStringLiteral("..")))
        return {};
    const QString path = exportImagesDir() + QStringLiteral("/") + name;
    if (!QFile::exists(path))
        return {};
    if (name.endsWith(QStringLiteral(".svg"), Qt::CaseInsensitive)) {
        QSvgRenderer renderer(path);
        if (!renderer.isValid())
            return {};
        const int w = qMax(1, targetW), h = qMax(1, targetH);
        QImage img(w, h, QImage::Format_ARGB32_Premultiplied);
        img.fill(Qt::transparent);
        QPainter p(&img);
        renderer.render(&p, QRectF(0, 0, w, h));
        return img;
    }
    QImageReader reader(path);
    reader.setAutoTransform(true);
    return reader.read();
}

// Frosted-glass backdrop: blur the already-painted frame under the
// bbox and composite by opacity. Caller holds the leaf transform;
// coordinates are output px. The tile is clipped to the shape
// silhouette (empty path = whole bbox, for images which fill it):
// bbox corners outside rounded/star/pen/rotated shapes would else
// land as blurred pixels past the fill with a hard seam, and the
// canvas preview already masks the same way via its rigMask.
void paintBackdropBlur(QPainter &pt, QImage &frame, double x, double y, double w, double h, double radius,
    double opacity, const QPainterPath &clip = QPainterPath()) {
    if (radius <= 0.01 || opacity <= 0.001)
        return;
    const double margin = qMin(128.0, radius * 2.0);
    const QRect srcRect(qMax(0, qRound(x - margin)), qMax(0, qRound(y - margin)), qRound(w + margin * 2.0),
        qRound(h + margin * 2.0));
    const QRect bounded = srcRect.intersected(frame.rect());
    if (bounded.isEmpty())
        return;
    QImage cut = frame.copy(bounded);
    QImage blurred = cut.copy();
    Effects::blurImage(blurred, radius);
    Effects::mixBlurred(cut, blurred, qBound(0.0, opacity, 1.0));
    // Only the bbox portion lands on the shape; the margin fed the blur.
    const QPoint dstTopLeft(qRound(x), qRound(y));
    const QPoint srcOffset(dstTopLeft - bounded.topLeft());
    QImage piece = cut.copy(QRect(srcOffset, QSize(qRound(w), qRound(h))));
    // World transform is active (rotation/flip): map through it so
    // the blurred tile registers under the shape fill.
    pt.save();
    pt.setOpacity(1.0);
    if (!clip.isEmpty())
        pt.setClipPath(clip, Qt::IntersectClip);
    pt.drawImage(QRectF(x, y, w, h), piece);
    pt.restore();
}

// Outer image glow: the clip silhouette dilated by spread, blurred,
// tinted, drawn under the raster.
void paintImageGlow(QPainter &pt, const QPainterPath &clip, const Effects::Glow &glow, double s) {
    QPainterPath silhouette = clip;
    if (glow.spread * s > 0.01) {
        QPainterPathStroker stroker;
        stroker.setWidth(glow.spread * 2.0 * s);
        stroker.setCapStyle(Qt::RoundCap);
        stroker.setJoinStyle(Qt::RoundJoin);
        silhouette = stroker.createStroke(clip).united(clip);
    }
    const double m = glow.blur * s * 2.0 + 1.0;
    QRectF area = silhouette.boundingRect();
    area.adjust(-m, -m, m, m);
    QImage mask(qMax(1, qRound(area.width())), qMax(1, qRound(area.height())), QImage::Format_ARGB32_Premultiplied);
    mask.fill(0);
    {
        QPainter mp(&mask);
        mp.setRenderHint(QPainter::Antialiasing, true);
        mp.translate(-area.topLeft());
        mp.fillPath(silhouette, Qt::black);
    }
    Effects::blurImage(mask, glow.blur * s);
    {
        QPainter mp(&mask);
        mp.setCompositionMode(QPainter::CompositionMode_SourceIn);
        mp.fillRect(mask.rect(), glow.color);
    }
    pt.drawImage(area.topLeft(), mask);
}

// Inner image glow: tinted clip with the blurred eroded copy cut out,
// leaving the halo band at the inside edges (above the pixels).
void paintImageGlowInner(QPainter &pt, const QPainterPath &clip, const Effects::Glow &glow, double s) {
    QPainterPath eroded = clip;
    if (glow.spread * s > 0.01) {
        QPainterPathStroker stroker;
        stroker.setWidth(glow.spread * 2.0 * s);
        stroker.setCapStyle(Qt::RoundCap);
        stroker.setJoinStyle(Qt::RoundJoin);
        eroded = clip.subtracted(stroker.createStroke(clip));
    }
    const double m = glow.blur * s * 2.0 + 1.0;
    QRectF area = clip.boundingRect();
    area.adjust(-m, -m, m, m);
    const QSize size(qMax(1, qRound(area.width())), qMax(1, qRound(area.height())));
    QImage cutter(size, QImage::Format_ARGB32_Premultiplied);
    cutter.fill(0);
    {
        QPainter mp(&cutter);
        mp.setRenderHint(QPainter::Antialiasing, true);
        mp.translate(-area.topLeft());
        mp.fillPath(eroded, Qt::black);
    }
    Effects::blurImage(cutter, glow.blur * s);
    QImage mask(size, QImage::Format_ARGB32_Premultiplied);
    mask.fill(0);
    {
        QPainter mp(&mask);
        mp.setRenderHint(QPainter::Antialiasing, true);
        mp.translate(-area.topLeft());
        mp.fillPath(clip, glow.color);
        mp.setCompositionMode(QPainter::CompositionMode_DestinationOut);
        mp.resetTransform();
        mp.drawImage(0, 0, cutter);
    }
    pt.drawImage(area.topLeft(), mask);
}

void paintImage(QPainter &pt, const QVariantMap &m, double x, double y, double w, double h, double s,
    const QList<Effects::StrokeEntry> &strokes, const Effects::Blur &layerBlur = Effects::Blur(),
    const QList<Effects::Glow> &glows = QList<Effects::Glow>(), const Effects::Grain &grain = Effects::Grain(),
    int uid = -1, int frameNo = 0) {
    const QString name = str(m, "imageSource", str(m, "image", QString()));
    const double r = qMin(qMax(0.0, num(m, "radius") * s), qMin(w, h) / 2.0);
    QPainterPath clip;
    if (r > 0.01)
        clip.addRoundedRect(QRectF(x, y, w, h), r, r);
    else
        clip.addRect(QRectF(x, y, w, h));
    // Outer glows: bottom-first so index 0 paints topmost.
    for (int i = glows.size() - 1; i >= 0; --i) {
        const Effects::Glow &g = glows.at(i);
        if (g.enabled && !g.inner)
            paintImageGlow(pt, clip, g, s);
    }
    QImage img = loadExportImage(name, qMax(1, qRound(w)), qMax(1, qRound(h)));
    if (img.isNull()) {
        QImage tile(qMax(1, qRound(w)), qMax(1, qRound(h)), QImage::Format_ARGB32_Premultiplied);
        tile.fill(QColor(QStringLiteral("#d9d9d9")));
        img = tile;
    }
    // Layer blur on images: blur the raster then mix by opacity.
    if (layerBlur.enabled && layerBlur.radius > 0.01) {
        QImage blurred = img.copy();
        Effects::blurImage(blurred, layerBlur.radius * s);
        QImage sharp = img.copy();
        Effects::mixBlurred(sharp, blurred, layerBlur.opacity);
        img = sharp;
    }
    pt.save();
    pt.setClipPath(clip, Qt::IntersectClip);
    pt.drawImage(QRectF(x, y, w, h), img);
    pt.restore();
    // Inner glows over the pixels, index 0 topmost.
    for (int i = glows.size() - 1; i >= 0; --i) {
        const Effects::Glow &g = glows.at(i);
        if (g.enabled && g.inner)
            paintImageGlowInner(pt, clip, g, s);
    }
    // Stacked strokes as rect borders, bottom-first so index 0 paints
    // topmost. Position maps to border placement: inside rides the
    // clip edge, center straddles it, outside grows past it.
    double maxSw = 0.0;
    for (int i = strokes.size() - 1; i >= 0; --i) {
        const Effects::StrokeEntry &se = strokes.at(i);
        if (!se.enabled || se.width <= 0.01)
            continue;
        const double sw = se.width * s;
        maxSw = qMax(maxSw, sw);
        QColor sc = se.color;
        sc.setAlphaF(qBound(0.0, sc.alphaF() * se.opacity, 1.0));
        QPen pen(sc, sw, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
        if (!se.dash.isEmpty()) {
            pen.setStyle(Qt::CustomDashLine);
            pen.setDashPattern(se.dash);
        }
        QRectF rect(x, y, w, h);
        if (se.position == QLatin1String("outside"))
            rect.adjust(-sw / 2.0, -sw / 2.0, sw / 2.0, sw / 2.0);
        else if (se.position == QLatin1String("center"))
            rect.adjust(0, 0, 0, 0);
        // inside: default clip rect (border paints inside in Qt).
        pt.setPen(pen);
        pt.setBrush(Qt::NoBrush);
        pt.drawRoundedRect(rect, r, r);
    }
    // Grain over pixels and stroke (preview tiles the same way).
    if (grain.enabled && grain.amount > 0.001)
        Effects::paintGrainPath(&pt, clip, maxSw, QRectF(x, y, w, h), grain, uid, frameNo, s);
}

// Text through the shared glyph-stack painter (mirrors the canvas
// EffectItem branch): outer/inner shadows and glows, stacked fills,
// stacked stroke rings, whole-stack layer blur. Grain stays
// glyph-confined like the preview overlay.
void paintText(QPainter &pt, const QVariantMap &m, double x, double y, double w, double h, double s,
    const Effects::Style &style, const QList<Effects::Shadow> &shadows = QList<Effects::Shadow>(),
    const QList<Effects::Glow> &glows = QList<Effects::Glow>(),
    const Effects::Blur &layerBlur = Effects::Blur(), const Effects::Grain &grain = Effects::Grain(), int uid = -1,
    int frameNo = 0) {
    QVariantMap tm;
    tm[QStringLiteral("content")] = str(m, "textContent");
    tm[QStringLiteral("family")] = str(m, "fontFamily", QStringLiteral("Inter"));
    tm[QStringLiteral("weight")] = m.value(QStringLiteral("fontWeight"), 400).toInt();
    tm[QStringLiteral("size")] = num(m, "fontSize", 16.0);
    tm[QStringLiteral("spacing")] = num(m, "letterSpacing");
    tm[QStringLiteral("halign")] = str(m, "hAlign", QStringLiteral("left"));
    tm[QStringLiteral("valign")] = str(m, "vAlign", QStringLiteral("top"));
    tm[QStringLiteral("autoSize")] = m.value(QStringLiteral("autoSize"), true).toBool();
    tm[QStringLiteral("lineAuto")] = m.value(QStringLiteral("lineHeightAuto"), true).toBool();
    tm[QStringLiteral("leading")] = num(m, "lineHeight", 1.2);
    tm[QStringLiteral("boxW")] = num(m, "w");
    tm[QStringLiteral("boxH")] = num(m, "h");
    tm[QStringLiteral("outlinePx")] = style.maxStrokeWidth() > 0.0 ? style.maxStrokeWidth() : 0.0;
    const Effects::TextOpts text = Effects::TextOpts::fromMap(tm);
    Effects::paintTextLeaf(&pt, QRectF(x, y, w, h), text, style, shadows, glows, layerBlur, s, nullptr);
    // Grain confined to the glyphs: ghost the coverage, keep dots
    // where the ghost is opaque (preview masks its tile the same way).
    if (grain.enabled && grain.amount > 0.001) {
        const QImage ghost = Effects::textGhost(text, w, h, s, false);
        QImage dots = Effects::grainDots(ghost.size(), qMax(1.0, grain.size * s),
            Effects::grainSeed(uid, frameNo), grain.amount);
        {
            QPainter dp(&dots);
            dp.setCompositionMode(QPainter::CompositionMode_DestinationIn);
            dp.drawImage(0, 0, ghost);
        }
        pt.drawImage(QRectF(x, y, w, h), dots);
    }
}

// Effect pad for one sampled leaf in content px: the canvas sizing
// rule (EffectItem::updatePad, miter-pen clause included) so crops
// match the preview silhouette exactly. Images add the glow halo the
// shared pad does not cover (their glow paints outside the clip).
double leafPad(const QVariantMap &m) {
    const QString shapeType = str(m, "type", str(m, "shapeType", QStringLiteral("rectangle")));
    const QList<Effects::Shadow> shadows = Effects::Shadow::listFrom(m.value(QStringLiteral("shadows")).toList());
    const QList<Effects::Glow> glows = Effects::Glow::listFrom(m.value(QStringLiteral("glows")).toList());
    const Effects::Blur layerBlur = Effects::Blur::fromMap(m.value(QStringLiteral("layerBlur")).toMap());
    const Effects::Style st = Effects::Style::fromMap(m);
    double pad = Effects::effectPad(shadows, glows, layerBlur, st.strokes);
    if (shapeType == QLatin1String("pen") && str(m, "strokeJoin", QStringLiteral("round")) == QLatin1String("miter")
        && st.maxStrokeWidth() > 0)
        pad = qMax(pad, st.maxStrokeWidth());
    if (shapeType == QLatin1String("image"))
        pad = qMax(pad, Effects::glowsPad(glows));
    return pad;
}

// Rotated bbox corners (flips never change the box).
QRectF rotatedBox(const QVariantMap &m) {
    const double x = num(m, "x"), y = num(m, "y");
    const double w = num(m, "w"), h = num(m, "h");
    if (w <= 0 || h <= 0)
        return {};
    const double cx = x + w / 2.0, cy = y + h / 2.0;
    const double a = qDegreesToRadians(num(m, "rotation"));
    const double c = qCos(a), s = qSin(a);
    double x0 = 1e18, y0 = 1e18, x1 = -1e18, y1 = -1e18;
    const QPointF corners[4] = {QPointF(x, y), QPointF(x + w, y), QPointF(x + w, y + h), QPointF(x, y + h)};
    for (const QPointF &p : corners) {
        const double dx = p.x() - cx, dy = p.y() - cy;
        x0 = qMin(x0, cx + dx * c - dy * s);
        y0 = qMin(y0, cy + dx * s + dy * c);
        x1 = qMax(x1, cx + dx * c - dy * s);
        y1 = qMax(y1, cy + dx * s + dy * c);
    }
    return QRectF(QPointF(x0, y0), QPointF(x1, y1));
}

} // namespace

void paintLeaf(QPainter &pt, QImage &frame, const QVariantMap &m, double ox, double oy, double scale, int frameNo) {
    const QString shapeType = str(m, "type", str(m, "shapeType", QStringLiteral("rectangle")));
    const double x = ox + num(m, "x") * scale;
    const double y = oy + num(m, "y") * scale;
    const double w = qMax(0.01, num(m, "w") * scale);
    const double h = qMax(0.01, num(m, "h") * scale);
    if (w <= 0 || h <= 0)
        return;
    const double opacity = qBound(0.0, num(m, "opacity", 1.0), 1.0);
    if (opacity <= 0.001)
        return;
    const Effects::Style style = Effects::Style::fromMap(m);
    const double cx = x + w / 2.0, cy = y + h / 2.0;
    const int uid = m.value(QStringLiteral("uid"), -1).toInt();

    const QList<Effects::Shadow> shadows = Effects::Shadow::listFrom(m.value(QStringLiteral("shadows")).toList());
    const Effects::Blur layerBlur = Effects::Blur::fromMap(m.value(QStringLiteral("layerBlur")).toMap());
    const Effects::Blur backgroundBlur = Effects::Blur::fromMap(m.value(QStringLiteral("backgroundBlur")).toMap());
    const QList<Effects::Glow> glows = Effects::Glow::listFrom(m.value(QStringLiteral("glows")).toList());
    const bool useBackground = backgroundBlur.enabled && backgroundBlur.radius > 0.01
        && shapeType != QLatin1String("text");
    const Effects::Grain grain = Effects::Grain::fromMap(m.value(QStringLiteral("grain")).toMap());
    const bool useGrain = grain.enabled && grain.amount > 0.001;

    pt.save();
    pt.setOpacity(opacity);
    pt.translate(cx, cy);
    pt.rotate(num(m, "rotation"));
    pt.scale(m.value(QStringLiteral("flipH")).toBool() ? -1.0 : 1.0,
        m.value(QStringLiteral("flipV")).toBool() ? -1.0 : 1.0);
    pt.translate(-cx, -cy);

    if (shapeType == QLatin1String("text")) {
        // Glyph stack through the shared painter: real inner bands,
        // stacked fills, stroke rings and whole-stack layer blur,
        // identical to the canvas preview by construction.
        paintText(pt, m, x, y, w, h, scale, style, shadows, glows, layerBlur,
            useGrain ? grain : Effects::Grain(), uid, frameNo);
        pt.restore();
        return;
    }

    if (shapeType == QLatin1String("image")) {
        if (useBackground)
            paintBackdropBlur(pt, frame, x, y, w, h, backgroundBlur.radius * scale, backgroundBlur.opacity);
        paintImage(pt, m, x, y, w, h, scale, style.strokes, layerBlur, glows,
            useGrain ? grain : Effects::Grain(), uid, frameNo);
        pt.restore();
        return;
    }

    // Vector shapes share the CPU engine with canvas preview
    // (EffectItem), so export matches preview by construction.
    // Background blur composites here (backdrop is the frame so far);
    // layer blur rides inside paintLeaf. Text keeps its painter.
    if (useBackground) {
        // Masked to the silhouette like the canvas rigMask: the bbox
        // tile alone would leak blurred corners outside rounded,
        // star/pen and rotated shapes with a hard seam.
        const QPainterPath clip = Effects::outlinePath(shapeType, QRectF(x, y, w, h),
            Effects::PathOpts::fromMap(m), Effects::Style::fromMap(m), scale);
        paintBackdropBlur(pt, frame, x, y, w, h, backgroundBlur.radius * scale, backgroundBlur.opacity, clip);
    }
    Effects::paintLeaf(&pt, shapeType, QRectF(x, y, w, h), Effects::PathOpts::fromMap(m),
        Effects::Style::fromMap(m), shadows, glows, layerBlur, scale);
    // Grain sits over fill and stroke on every kind (preview layers
    // its tile the same way, under the same leaf opacity).
    if (useGrain) {
        Effects::paintGrainPath(&pt,
            Effects::outlinePath(shapeType, QRectF(x, y, w, h), Effects::PathOpts::fromMap(m),
                Effects::Style::fromMap(m), scale),
            style.maxStrokeWidth() * scale, QRectF(x, y, w, h), grain, uid, frameNo, scale);
    }
    pt.restore();
}

// White alpha silhouette of one sampled mask leaf in frame coords.
// Vectors use the shared outline path, images a rounded rect, text
// the glyph ghost; feather blurs the edge, invert flips the alpha.
// Only alpha carries meaning (DestinationIn); color stays white.
QImage maskSilhouette(const QVariantMap &mask, double ox, double oy, double scale, const QSize &size) {
    QImage img(size, QImage::Format_ARGB32_Premultiplied);
    img.fill(Qt::transparent);
    const QString shapeType = str(mask, "type", str(mask, "shapeType", QStringLiteral("rectangle")));
    const double x = ox + num(mask, "x") * scale;
    const double y = oy + num(mask, "y") * scale;
    const double w = qMax(0.01, num(mask, "w") * scale);
    const double h = qMax(0.01, num(mask, "h") * scale);
    if (w <= 0 || h <= 0 || size.isEmpty())
        return img;
    const double opacity = qBound(0.0, num(mask, "opacity", 1.0), 1.0);
    if (opacity <= 0.001)
        return img;
    const double cx = x + w / 2.0, cy = y + h / 2.0;
    QPainter pt(&img);
    pt.setRenderHints(QPainter::Antialiasing | QPainter::TextAntialiasing | QPainter::SmoothPixmapTransform);
    pt.setOpacity(opacity);
    pt.translate(cx, cy);
    pt.rotate(num(mask, "rotation"));
    pt.scale(mask.value(QStringLiteral("flipH")).toBool() ? -1.0 : 1.0,
        mask.value(QStringLiteral("flipV")).toBool() ? -1.0 : 1.0);
    pt.translate(-cx, -cy);
    pt.setPen(Qt::NoPen);
    pt.setBrush(Qt::white);
    if (shapeType == QLatin1String("text")) {
        QVariantMap tm;
        tm[QStringLiteral("content")] = str(mask, "textContent");
        tm[QStringLiteral("family")] = str(mask, "fontFamily", QStringLiteral("Inter"));
        tm[QStringLiteral("weight")] = mask.value(QStringLiteral("fontWeight"), 400).toInt();
        tm[QStringLiteral("size")] = num(mask, "fontSize", 16.0);
        tm[QStringLiteral("spacing")] = num(mask, "letterSpacing");
        tm[QStringLiteral("halign")] = str(mask, "hAlign", QStringLiteral("left"));
        tm[QStringLiteral("valign")] = str(mask, "valign", QStringLiteral("top"));
        tm[QStringLiteral("autoSize")] = mask.value(QStringLiteral("autoSize"), true).toBool();
        tm[QStringLiteral("lineAuto")] = mask.value(QStringLiteral("lineHeightAuto"), true).toBool();
        tm[QStringLiteral("leading")] = num(mask, "lineHeight", 1.2);
        tm[QStringLiteral("boxW")] = num(mask, "w");
        tm[QStringLiteral("boxH")] = num(mask, "h");
        tm[QStringLiteral("outlinePx")] = 0.0;
        const Effects::TextOpts text = Effects::TextOpts::fromMap(tm);
        const QImage ghost = Effects::textGhost(text, w, h, scale, false);
        if (!ghost.isNull())
            pt.drawImage(QRectF(x, y, w, h), ghost);
        else
            pt.drawRect(QRectF(x, y, w, h));
    } else if (shapeType == QLatin1String("image")) {
        const double r = qMin(qMax(0.0, num(mask, "radius") * scale), qMin(w, h) / 2.0);
        if (r > 0.01)
            pt.drawRoundedRect(QRectF(x, y, w, h), r, r);
        else
            pt.drawRect(QRectF(x, y, w, h));
    } else {
        const QPainterPath path = Effects::outlinePath(shapeType, QRectF(x, y, w, h),
            Effects::PathOpts::fromMap(mask), Effects::Style::fromMap(mask), scale);
        if (!path.isEmpty())
            pt.fillPath(path, Qt::white);
        else
            pt.drawRect(QRectF(x, y, w, h));
    }
    pt.end();
    const double feather = qMax(0.0, num(mask, "maskFeather")) * scale;
    if (feather > 0.01)
        Effects::blurImage(img, feather);
    if (mask.value(QStringLiteral("maskInverted"), false).toBool()) {
        QImage inv(size, QImage::Format_ARGB32_Premultiplied);
        inv.fill(Qt::white);
        QPainter ip(&inv);
        ip.setCompositionMode(QPainter::CompositionMode_DestinationOut);
        ip.drawImage(0, 0, img);
        ip.end();
        return inv;
    }
    return img;
}

void paintLeaves(QPainter &pt, QImage &frame, const QList<QVariantMap> &work, const QVariantMap &scene,
    double ox, double oy, double scale, int frameNo) {
    const QList<Leaf> leaves = collectLeaves(scene);
    QMap<int, int> leafIndex;
    for (int i = 0; i < leaves.size(); ++i) {
        const int uid = leaves.at(i).map.value(QStringLiteral("uid"), -1).toInt();
        if (uid >= 0)
            leafIndex[uid] = i;
    }
    QMap<int, QVariantMap> workByUid;
    for (const QVariantMap &m : work) {
        const int uid = m.value(QStringLiteral("uid"), -1).toInt();
        if (uid >= 0)
            workByUid[uid] = m;
    }
    const QMap<int, QList<int>> maskMap = maskMapForWork(scene, work);
    QMap<int, QImage> maskCache;
    QImage layer;
    for (int li = work.size() - 1; li >= 0; --li) {
        const QVariantMap m = work.at(li);
        const int uid = m.value(QStringLiteral("uid"), -1).toInt();
        if (m.value(QStringLiteral("isMask"), false).toBool())
            continue;
        const int srcIdx = leafIndex.value(uid, -1);
        const bool ancVis = srcIdx >= 0 ? leaves.at(srcIdx).ancestorsVisible : true;
        if (!ancVis || !m.value(QStringLiteral("visible"), true).toBool())
            continue;
        if (qBound(0.0, Anims::num(m, "opacity", 1.0), 1.0) <= 0.001)
            continue;
        QList<int> active;
        for (int mid : maskMap.value(uid)) {
            const QVariantMap mm = workByUid.value(mid);
            if (mm.isEmpty())
                continue;
            if (!mm.value(QStringLiteral("visible"), true).toBool())
                continue;
            const int mSrc = leafIndex.value(mid, -1);
            if (mSrc >= 0 && !leaves.at(mSrc).ancestorsVisible)
                continue;
            active.append(mid);
        }
        if (active.isEmpty()) {
            paintLeaf(pt, frame, m, ox, oy, scale, frameNo);
            continue;
        }
        QImage combined;
        for (int mid : active) {
            if (!maskCache.contains(mid))
                maskCache[mid] = maskSilhouette(workByUid.value(mid), ox, oy, scale, frame.size());
            const QImage &mi = maskCache[mid];
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
            continue;
        if (layer.size() != frame.size() || layer.format() != QImage::Format_ARGB32_Premultiplied)
            layer = QImage(frame.size(), QImage::Format_ARGB32_Premultiplied);
        layer.fill(Qt::transparent);
        {
            QPainter lp(&layer);
            lp.setRenderHints(QPainter::Antialiasing | QPainter::TextAntialiasing | QPainter::SmoothPixmapTransform);
            // Backdrop blur inside masks samples the temp (transparent),
            // not the frame behind: documented v1 limitation, rare combo.
            paintLeaf(lp, layer, m, ox, oy, scale, frameNo);
        }
        {
            QPainter ap(&layer);
            ap.setCompositionMode(QPainter::CompositionMode_DestinationIn);
            ap.drawImage(0, 0, combined);
        }
        pt.drawImage(0, 0, layer);
    }
}

QRectF selectionBounds(const QList<QVariantMap> &work, double scale) {
    QRectF bounds;
    for (const QVariantMap &m : work) {
        if (m.value(QStringLiteral("isMask"), false).toBool())
            continue;
        if (!m.value(QStringLiteral("visible"), true).toBool())
            continue;
        if (qBound(0.0, num(m, "opacity", 1.0), 1.0) <= 0.001)
            continue;
        QRectF box = rotatedBox(m);
        if (box.isEmpty())
            continue;
        // Pads are content px (same basis as EffectItem at scale 1).
        box.adjust(-leafPad(m), -leafPad(m), leafPad(m), leafPad(m));
        bounds = bounds.united(box);
    }
    if (bounds.isEmpty())
        return {};
    // Device coverage: aligned rect so AA edges never clip a pixel.
    return QRectF(bounds.topLeft() * scale, bounds.size() * scale).normalized().toAlignedRect();
}

QImage renderNodes(const QVariantList &topNodes, double scale, int frameNo, QString *error) {
    auto fail = [&](const QString &message) {
        if (error)
            *error = message;
        return QImage();
    };
    if (topNodes.isEmpty())
        return fail(QCoreApplication::translate("FramePaint", "Nothing selected to export."));
    if (!(scale > 0))
        return fail(QCoreApplication::translate("FramePaint", "Export scale must be positive."));
    QVariantMap subset;
    QVariantList nodes;
    for (const QVariant &v : topNodes) {
        QVariantMap n = v.toMap();
        if (n.isEmpty())
            continue;
        // Explicit selection exports even when hidden; nested
        // visibility stays authored (collectLeaves ANDs ancestors).
        n[QStringLiteral("visible")] = true;
        nodes.append(n);
    }
    if (nodes.isEmpty())
        return fail(QCoreApplication::translate("FramePaint", "Nothing selected to export."));
    subset[QStringLiteral("nodes")] = nodes;

    // Ancestor visibility comes from the subset so hidden subtrees
    // are skipped before rasterization (same rule as video frames).
    const QList<Leaf> leaves = collectLeaves(subset);
    QMap<int, int> leafIndex;
    for (int i = 0; i < leaves.size(); ++i) {
        const int uid = leaves.at(i).map.value(QStringLiteral("uid"), -1).toInt();
        if (uid >= 0)
            leafIndex[uid] = i;
    }
    // No anim blob rides along, so the frame holds base values.
    const QList<QVariantMap> work = sampleFrame(subset, 0.0);
    QList<QVariantMap> paint;
    paint.reserve(work.size());
    for (const QVariantMap &m : work) {
        if (m.value(QStringLiteral("isMask"), false).toBool())
            continue;
        const int uid = m.value(QStringLiteral("uid"), -1).toInt();
        const int srcIdx = leafIndex.value(uid, -1);
        const bool ancVis = srcIdx >= 0 ? leaves.at(srcIdx).ancestorsVisible : true;
        if (!ancVis || !m.value(QStringLiteral("visible"), true).toBool())
            continue;
        if (qBound(0.0, Anims::num(m, "opacity", 1.0), 1.0) <= 0.001)
            continue;
        paint.append(m);
    }
    if (paint.isEmpty())
        return fail(QCoreApplication::translate("FramePaint", "Nothing visible to export."));

    const QRectF bounds = selectionBounds(paint, scale);
    if (bounds.isEmpty() || bounds.width() < 1 || bounds.height() < 1)
        return fail(QCoreApplication::translate("FramePaint", "Nothing visible to export."));
    constexpr int kMaxSide = 8192;
    if (bounds.width() > kMaxSide || bounds.height() > kMaxSide)
        return fail(QCoreApplication::translate("FramePaint",
            "Selection is too large to export at this scale (over 8192 px on a side)."));

    QImage img(qMax(1, qRound(bounds.width())), qMax(1, qRound(bounds.height())),
        QImage::Format_ARGB32_Premultiplied);
    img.fill(Qt::transparent);
    QPainter pt(&img);
    pt.setRenderHints(QPainter::Antialiasing | QPainter::TextAntialiasing | QPainter::SmoothPixmapTransform);
    // Mask-aware, bottom-first (work is top-first).
    const double ox = -bounds.left(), oy = -bounds.top();
    paintLeaves(pt, img, work, subset, ox, oy, scale, frameNo);
    pt.end();
    return img;
}

} // namespace FramePaint
