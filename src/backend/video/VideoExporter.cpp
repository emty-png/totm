#include "VideoExporter.h"

#include "AnimSampler.h"
#include "EffectPainter.h"

#include <QAbstractTextDocumentLayout>
#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFont>
#include <QImage>
#include <QImageReader>
#include <QAtomicInteger>
#include <QPainter>
#include <QPainterPath>
#include <QPainterPathStroker>
#include <QPalette>
#include <QProcess>
#include <QStandardPaths>
#include <QSvgRenderer>
#include <QTextCursor>
#include <QTextDocument>
#include <QTextOption>
#include <QThread>
#include <QtMath>

#include <algorithm>

namespace {

// Output sizes are resolved here; frame content comes from AnimSampler so
// export and canvas preview share one sampling path.
using namespace Anims;

// Fixed landscape masters per quality. Scene aspect is letterboxed on
// sceneColor to keep output predictable across scene sizes.
bool resolveQuality(const QString &quality, int &w, int &h, QString &label) {
    const QString q = quality.trimmed().toLower();
    if (q == QLatin1String("sd") || q == QLatin1String("480p")) {
        w = 854;
        h = 480;
        label = QStringLiteral("SD · 480p");
        return true;
    }
    if (q == QLatin1String("4k") || q == QLatin1String("uhd") || q == QLatin1String("2160p")) {
        w = 3840;
        h = 2160;
        label = QStringLiteral("4K · 2160p");
        return true;
    }
    w = 1920;
    h = 1080;
    label = QStringLiteral("HD · 1080p");
    return q == QLatin1String("hd") || q == QLatin1String("1080p") || q == QLatin1String("720p");
}

// Sampling lives in AnimSampler; only the quality table stays here.

// Audible audio slice for one timeline clip: source file plus the
// trimmed read window and its composition delay, all in seconds.
// Volume is linear 0..1 (muted forces 0); fades ride seconds.
struct AudioInput {
    QString path;
    double seek = 0.0;
    double take = 0.0;
    double delay = 0.0;
    double volume = 1.0;
    double fadeIn = 0.0;
    double fadeOut = 0.0;
    bool muted = false;
};

// Timeline audio resolved against the render duration (same trim rule
// as the canvas preview: intersect with [0, duration]). Missing blobs
// are skipped so one lost file never fails the whole render.
QList<AudioInput> collectAudio(const QVariantMap &scene, double duration) {
    QList<AudioInput> out;
    const QVariantMap audio = scene.value(QStringLiteral("audio")).toMap();
    const QVariantList clips = audio.value(QStringLiteral("clips")).toList();
    QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (dir.isEmpty())
        dir = QDir::homePath() + QStringLiteral("/.totm");
    if (!dir.endsWith(QStringLiteral("/totm"), Qt::CaseInsensitive))
        dir += QStringLiteral("/totm");
    dir += QStringLiteral("/audio");
    for (const QVariant &cv : clips) {
        const QVariantMap c = cv.toMap();
        const QString name = c.value(QStringLiteral("source")).toString();
        if (name.isEmpty() || name.contains(QLatin1Char('/')) || name.contains(QLatin1Char('\\'))
            || name.contains(QStringLiteral("..")))
            continue;
        const QString path = dir + QStringLiteral("/") + name;
        if (!QFile::exists(path))
            continue;
        const double start = qMax(0.0, c.value(QStringLiteral("t0"), 0.0).toDouble());
        const double offset = qMax(0.0, c.value(QStringLiteral("offset"), 0.0).toDouble());
        const double end = qMin(c.value(QStringLiteral("t0"), 0.0).toDouble() + qMax(0.0, c.value(QStringLiteral("duration"), 0.0).toDouble()), duration);
        if (end - start <= 0.02)
            continue;
        AudioInput in;
        in.path = path;
        in.seek = offset;
        in.take = end - start;
        in.delay = start;
        in.muted = c.value(QStringLiteral("muted"), false).toBool();
        in.volume = in.muted ? 0.0 : qBound(0.0, c.value(QStringLiteral("volume"), 1.0).toDouble(), 1.0);
        in.fadeIn = qMax(0.0, c.value(QStringLiteral("fadeIn"), 0.0).toDouble());
        in.fadeOut = qMax(0.0, c.value(QStringLiteral("fadeOut"), 0.0).toDouble());
        out.append(in);
    }
    return out;
}

// Filter graph shaping each input (volume, fades) then delaying it to
// its timeline start and mixing down to one stereo track. Fades run
// before the delay so their times stay clip-relative (0..take); both
// are fit inside the take. normalize=0 keeps bed levels intact;
// overlapping clips can clip instead of ducking (no per-clip volume
// in v1, so there is nothing to preserve headroom for).
QString audioFilter(const QList<AudioInput> &inputs) {
    QStringList mixed;
    for (int i = 0; i < inputs.size(); ++i) {
        const AudioInput &in = inputs.at(i);
        const int ms = qMax(0, qRound(in.delay * 1000.0));
        QString chain = QStringLiteral("[%1:a]aresample=44100,aformat=channel_layouts=stereo").arg(i + 1);
        if (in.volume < 0.999)
            chain += QStringLiteral(",volume=%1").arg(QString::number(in.volume, 'f', 3));
        const double fi = qMin(qMax(0.0, in.fadeIn), qMax(0.001, in.take));
        const double fo = qMin(qMax(0.0, in.fadeOut), qMax(0.001, in.take - fi));
        if (fi > 0.001)
            chain += QStringLiteral(",afade=t=in:st=0:d=%1").arg(QString::number(fi, 'f', 3));
        if (fo > 0.001)
            chain += QStringLiteral(",afade=t=out:st=%1:d=%2")
                         .arg(QString::number(qMax(0.0, in.take - fo), 'f', 3))
                         .arg(QString::number(fo, 'f', 3));
        mixed.append(chain + QStringLiteral(",adelay=%1|%1[a%2]").arg(ms).arg(i));
    }
    QStringList labels;
    for (int i = 0; i < inputs.size(); ++i)
        labels.append(QStringLiteral("[a%1]").arg(i));
    return mixed.join(QStringLiteral(";"))
        + QStringLiteral(";")
        + labels.join(QString())
        + QStringLiteral("amix=inputs=%1:duration=longest:dropout_transition=0:normalize=0[a]").arg(inputs.size());
}

} // namespace

namespace {
// Maps performance choice to x264 preset + CRF. Unknown values fall back
// to normal. Thread capping is independent; see run().
void resolvePerformance(const QString &performance, QString &preset, int &crf, QString &label) {
    const QString p = performance.trimmed().toLower();
    if (p == QLatin1String("slow")) {
        preset = QStringLiteral("medium");
        crf = 16;
        label = QStringLiteral("Slow");
        return;
    }
    if (p == QLatin1String("fast")) {
        preset = QStringLiteral("superfast");
        crf = 20;
        label = QStringLiteral("Fast");
        return;
    }
    preset = QStringLiteral("veryfast");
    crf = 18;
    label = QStringLiteral("Normal");
}
// User-facing install hint per OS when no ffmpeg binary is on PATH.
QString ffmpegMissingMessage() {
#if defined(Q_OS_WIN)
    return QCoreApplication::translate("VideoExporter",
        "ffmpeg not found. Download it from https://www.gyan.dev/ffmpeg/builds/, add it to PATH, then export again.");
#elif defined(Q_OS_MACOS)
    return QCoreApplication::translate("VideoExporter",
        "ffmpeg not found. Install it with 'brew install ffmpeg', then export again.");
#else
    return QCoreApplication::translate("VideoExporter",
        "ffmpeg not found. Install it (sudo pacman -S ffmpeg / sudo apt install ffmpeg), then export again.");
#endif
}
} // namespace

// RenderThread: sample, rasterize and pipe frames to ffmpeg.
// Runs fully in run(). Cancellation is an atomic flag polled per frame;
// the main thread never touches the QProcess.
class VideoExporter::RenderThread : public QThread {
    Q_OBJECT
public:
    RenderThread(QVariantMap scene, int outW, int outH, int fps, QString preset, int crf, QString effort,
        QString tempPath, QObject *parent = nullptr)
        : QThread(parent)
        , m_scene(std::move(scene))
        , m_outW(outW)
        , m_outH(outH)
        , m_fps(fps)
        , m_preset(std::move(preset))
        , m_crf(crf)
        , m_effort(std::move(effort))
        , m_tempPath(std::move(tempPath)) {}

    void requestCancel() { m_cancelled.storeRelaxed(1); }

signals:
    void frameProgress(int current, int total);
    void renderDone(QString tempPath);
    void renderError(QString message);
    void renderCancelled();

protected:
    void run() override {
        const double sceneW = qMax(1.0, m_scene.value(QStringLiteral("sceneWidth"), 1920).toDouble());
        const double sceneH = qMax(1.0, m_scene.value(QStringLiteral("sceneHeight"), 1080).toDouble());
        const QColor sceneColor(str(m_scene, "sceneColor", QStringLiteral("#ffffff")));
        const QVariantMap anim = m_scene.value(QStringLiteral("anim")).toMap();
        const double duration = qBound(0.5, anim.value(QStringLiteral("duration"), 4.0).toDouble(), 60.0);
        const int total = qMax(1, qRound(duration * m_fps));

        // Ancestor visibility comes from the snapshot so hidden subtrees
        // are skipped before rasterization.
        const QList<Leaf> leaves = collectLeaves(m_scene);
        QMap<int, int> leafIndex;
        for (int i = 0; i < leaves.size(); ++i) {
            const int uid = leaves.at(i).map.value(QStringLiteral("uid"), -1).toInt();
            if (uid >= 0)
                leafIndex[uid] = i;
        }

        const QString ffmpeg = VideoExporter::ffmpegPath();
        if (ffmpeg.isEmpty()) {
            emit renderError(ffmpegMissingMessage());
            return;
        }

        // Cap encoder threads: libx264 auto (~cores) starves the UI
        // thread on weak machines, which stalls Cancel and input.
        const int encThreads = qBound(2, QThread::idealThreadCount() / 2, 6);
        // Timeline audio rides as extra inputs, each trimmed to its
        // audible window and delayed to its start, then mixed down.
        // No clips keeps the historical video-only path untouched.
        const QList<AudioInput> audio = collectAudio(m_scene, duration);
        QProcess proc;
        QStringList encArgs = {QStringLiteral("-y"), QStringLiteral("-f"), QStringLiteral("rawvideo"),
            QStringLiteral("-pix_fmt"), QStringLiteral("rgba"), QStringLiteral("-s"),
            QStringLiteral("%1x%2").arg(m_outW).arg(m_outH), QStringLiteral("-r"), QString::number(m_fps),
            QStringLiteral("-i"), QStringLiteral("-")};
        for (const AudioInput &in : audio) {
            encArgs += {QStringLiteral("-ss"), QString::number(in.seek, 'f', 3), QStringLiteral("-t"),
                QString::number(in.take, 'f', 3), QStringLiteral("-i"), in.path};
        }
        if (audio.isEmpty()) {
            encArgs += {QStringLiteral("-an"), QStringLiteral("-c:v")};
        } else {
            // No -shortest: audio is trimmed to <= duration, so the mix
            // never outruns the video. -shortest would truncate the video
            // to a short effect and close the pipe mid-render (broken pipe).
            encArgs += {QStringLiteral("-filter_complex"), audioFilter(audio), QStringLiteral("-map"),
                QStringLiteral("0:v"), QStringLiteral("-map"), QStringLiteral("[a]"), QStringLiteral("-c:a"),
                QStringLiteral("aac"), QStringLiteral("-b:a"), QStringLiteral("160k"), QStringLiteral("-c:v")};
        }
        encArgs += {QStringLiteral("libx264"), QStringLiteral("-pix_fmt"), QStringLiteral("yuv420p"),
            QStringLiteral("-crf"), QString::number(m_crf), QStringLiteral("-preset"), m_preset,
            QStringLiteral("-threads"), QString::number(encThreads), QStringLiteral("-movflags"),
            QStringLiteral("+faststart"), m_tempPath};
#if defined(Q_OS_UNIX)
        // Thread priority does not propagate to the encoder process, so
        // nice it separately. Falls back to a direct spawn without nice.
        if (!QStandardPaths::findExecutable(QStringLiteral("nice")).isEmpty()) {
            proc.setProgram(QStringLiteral("nice"));
            proc.setArguments(QStringList{QStringLiteral("-n"), QStringLiteral("10"), ffmpeg} + encArgs);
        } else {
            proc.setProgram(ffmpeg);
            proc.setArguments(encArgs);
        }
#else
        proc.setProgram(ffmpeg);
        proc.setArguments(encArgs);
#endif
        proc.start();
        if (!proc.waitForStarted(10000)) {
            emit renderError(tr("Could not start ffmpeg."));
            return;
        }

        const double scale = qMin(double(m_outW) / sceneW, double(m_outH) / sceneH);
        const double ox = (m_outW - sceneW * scale) / 2.0;
        const double oy = (m_outH - sceneH * scale) / 2.0;
        const qint64 frameBytes = qint64(m_outW) * m_outH * 4;
        bool ok = true;
        QString failMsg;

        // Progress is throttled to ~10Hz; per-frame rebinds add UI churn
        // with no visible gain.
        QElapsedTimer emitT;
        emitT.start();
        bool emittedOnce = false;
        // Single reusable frame buffer; per-frame 4K allocs are ~119GB of
        // allocator traffic over a 60fps minute.
        QImage img;
        auto cancelAndOut = [&] {
            proc.kill();
            proc.waitForFinished(5000);
            QFile::remove(m_tempPath);
            emit renderCancelled();
        };

        for (int frame = 0; frame < total; ++frame) {
            if (m_cancelled.loadRelaxed()) {
                cancelAndOut();
                return;
            }
            const double t = qMin(duration, double(frame) / m_fps);

            // Sampled from AnimSampler; see its header for the QML parity contract.
            const QList<QVariantMap> work = sampleFrame(m_scene, t);

            if (img.size() != QSize(m_outW, m_outH) || img.format() != QImage::Format_RGBA8888)
                img = QImage(m_outW, m_outH, QImage::Format_RGBA8888);
            img.fill(sceneColor);
            QPainter pt(&img);
            pt.setRenderHints(QPainter::Antialiasing | QPainter::TextAntialiasing | QPainter::SmoothPixmapTransform);
            // Leaf list is top-first; paint bottom-first.
            for (int li = work.size() - 1; li >= 0; --li) {
                const QVariantMap m = work[li];
                const int uid = m.value(QStringLiteral("uid"), -1).toInt();
                const int srcIdx = leafIndex.value(uid, -1);
                const bool ancVis = srcIdx >= 0 ? leaves.at(srcIdx).ancestorsVisible : true;
                if (!ancVis || !m.value(QStringLiteral("visible"), true).toBool())
                    continue;
                paintLeaf(pt, img, m, ox, oy, scale, Effects::grainFrameNo(t));
            }
            pt.end();

            const char *bits = reinterpret_cast<const char *>(img.constBits());
            qint64 left = frameBytes, off = 0;
            qint64 waitedMs = 0;
            while (left > 0) {
                if (m_cancelled.loadRelaxed()) {
                    cancelAndOut();
                    return;
                }
                const qint64 wrote = proc.write(bits + off, left);
                if (wrote < 0) {
                    failMsg = tr("ffmpeg stopped accepting frames (%1).").arg(proc.errorString());
                    ok = false;
                    break;
                }
                off += wrote;
                left -= wrote;
                // Bounded pipe waits (500ms polls, 30s cap) keep cancel
                // responsive under ffmpeg backpressure.
                if (left > 0 && !proc.waitForBytesWritten(500)) {
                    waitedMs += 500;
                    if (waitedMs > 30000) {
                        failMsg = tr("Timed out writing to ffmpeg.");
                        ok = false;
                        break;
                    }
                }
            }
            if (!ok)
                break;
            if (!emittedOnce || emitT.elapsed() >= 100 || frame + 1 == total) {
                emittedOnce = true;
                emitT.restart();
                emit frameProgress(frame + 1, total);
            }
        }

        proc.closeWriteChannel();
        // Bounded finish wait with live cancel, same pattern as the pipe.
        bool finished = false;
        for (int i = 0; i < 60; ++i) {
            if (proc.waitForFinished(500)) {
                finished = true;
                break;
            }
            if (m_cancelled.loadRelaxed()) {
                cancelAndOut();
                return;
            }
        }
        if (!finished) {
            proc.kill();
            QFile::remove(m_tempPath);
            emit renderError(failMsg.isEmpty() ? tr("ffmpeg timed out.") : failMsg);
            return;
        }
        if (!ok || proc.exitCode() != 0) {
            QFile::remove(m_tempPath);
            const QString err = QString::fromLocal8Bit(proc.readAllStandardError()).trimmed();
            emit renderError(failMsg.isEmpty()
                    ? (err.isEmpty() ? tr("ffmpeg failed.") : err.split(QLatin1Char('\n')).last())
                    : failMsg);
            return;
        }
        emit renderDone(m_tempPath);
    }

    static void paintLeaf(QPainter &pt, QImage &frame, const QVariantMap &m, double ox, double oy, double scale,
        int frameNo) {
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
        const QColor fill(str(m, "fill", QStringLiteral("#d9d9d9")));
        const QColor stroke(str(m, "stroke", QStringLiteral("#000000")));
        const double sw = qMax(0.0, num(m, "strokeWidth") * scale);
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
            // gradient fill, outline ring and whole-stack layer blur,
            // identical to the canvas preview by construction.
            paintText(pt, m, x, y, w, h, scale, fill, shadows, glows, layerBlur,
                useGrain ? grain : Effects::Grain(), uid, frameNo);
            pt.restore();
            return;
        }

        if (shapeType == QLatin1String("image")) {
            if (useBackground)
                paintBackdropBlur(pt, frame, x, y, w, h, backgroundBlur.radius * scale, backgroundBlur.opacity);
            paintImage(pt, m, x, y, w, h, scale, stroke, sw, layerBlur, glows,
                useGrain ? grain : Effects::Grain(), uid, frameNo);
            pt.restore();
            return;
        }

        // Vector shapes share the CPU engine with canvas preview
        // (EffectItem), so export matches preview by construction.
        // Background blur composites here (backdrop is the frame so far);
        // layer blur rides inside paintLeaf. Text keeps its painter.
        if (useBackground)
            paintBackdropBlur(pt, frame, x, y, w, h, backgroundBlur.radius * scale, backgroundBlur.opacity);
        Effects::paintLeaf(&pt, shapeType, QRectF(x, y, w, h), Effects::PathOpts::fromMap(m),
            Effects::Style::fromMap(m), shadows, glows, layerBlur, scale);
        // Grain sits over fill and stroke on every kind (preview layers
        // its tile the same way, under the same leaf opacity).
        if (useGrain) {
            Effects::paintGrainPath(&pt,
                Effects::outlinePath(shapeType, QRectF(x, y, w, h), Effects::PathOpts::fromMap(m),
                    Effects::Style::fromMap(m), scale),
                sw, QRectF(x, y, w, h), grain, uid, frameNo, scale);
        }
        pt.restore();
    }

    // Frosted-glass backdrop: blur the already-painted frame under the
    // bbox and composite by opacity. Caller holds the leaf transform;
    // coordinates are output px. v1 confines to the bbox (shape-masked
    // in a follow-up); rect panels (the common case) are already exact.
    static void paintBackdropBlur(QPainter &pt, QImage &frame, double x, double y, double w, double h,
        double radius, double opacity)
    {
        if (radius <= 0.01 || opacity <= 0.001)
            return;
        const double margin = qMin(128.0, radius * 2.0);
        const QRect srcRect(qMax(0, qRound(x - margin)), qMax(0, qRound(y - margin)),
            qRound(w + margin * 2.0), qRound(h + margin * 2.0));
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
        pt.drawImage(QRectF(x, y, w, h), piece);
        pt.restore();
    }

    // Image via stored blob (mirrors ShapeItem stretch). Missing blobs
    // paint a neutral box so broken imports never vanish silently.
    static QString exportImagesDir() {
        QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
        if (dir.isEmpty())
            dir = QDir::homePath() + QStringLiteral("/.totm");
        if (!dir.endsWith(QStringLiteral("/totm"), Qt::CaseInsensitive))
            dir += QStringLiteral("/totm");
        return dir + QStringLiteral("/images");
    }

    static QImage loadExportImage(const QString &name, int targetW, int targetH) {
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

    static void paintImage(QPainter &pt, const QVariantMap &m, double x, double y, double w, double h, double s,
        const QColor &stroke, double sw, const Effects::Blur &layerBlur = Effects::Blur(),
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
        if (sw > 0.01) {
            QPen pen(stroke, sw, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
            pt.setPen(pen);
            pt.setBrush(Qt::NoBrush);
            pt.drawPath(clip);
        }
        // Grain over pixels and stroke (preview tiles the same way).
        if (grain.enabled && grain.amount > 0.001)
            Effects::paintGrainPath(&pt, clip, sw, QRectF(x, y, w, h), grain, uid, frameNo, s);
    }

    // Outer image glow: the clip silhouette dilated by spread, blurred,
    // tinted, drawn under the raster.
    static void paintImageGlow(QPainter &pt, const QPainterPath &clip, const Effects::Glow &glow, double s) {
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
    static void paintImageGlowInner(QPainter &pt, const QPainterPath &clip, const Effects::Glow &glow, double s) {
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

    // Text through the shared glyph-stack painter (mirrors the canvas
    // EffectItem branch): outer/inner shadows and glows, gradient fill,
    // outline ring, whole-stack layer blur. Grain stays glyph-confined
    // like the preview overlay.
    static void paintText(QPainter &pt, const QVariantMap &m, double x, double y, double w, double h, double s,
        const QColor &fill, const QList<Effects::Shadow> &shadows = QList<Effects::Shadow>(),
        const QList<Effects::Glow> &glows = QList<Effects::Glow>(),
        const Effects::Blur &layerBlur = Effects::Blur(), const Effects::Grain &grain = Effects::Grain(),
        int uid = -1, int frameNo = 0) {
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
        tm[QStringLiteral("outlinePx")] = num(m, "strokeWidth") > 0.0 ? 1.0 : 0.0;
        const Effects::TextOpts text = Effects::TextOpts::fromMap(tm);
        Effects::Style st;
        st.fill = fill;
        st.fillType = str(m, "fillType", QStringLiteral("solid"));
        st.fillGradient = m.value(QStringLiteral("fillGradient")).toMap();
        st.stroke = QColor(str(m, "stroke", QStringLiteral("#000000")));
        st.strokeWidth = num(m, "strokeWidth") > 0.0 ? 1.0 : 0.0;
        Effects::paintTextLeaf(&pt, QRectF(x, y, w, h), text, st, shadows, glows, layerBlur, s, nullptr);
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

    QVariantMap m_scene;
    int m_outW = 1920, m_outH = 1080, m_fps = 30;
    QString m_preset = QStringLiteral("veryfast");
    int m_crf = 18;
    QString m_effort = QStringLiteral("Normal");
    QString m_tempPath;
    QAtomicInteger<int> m_cancelled{0};
};

#include "VideoExporter.moc"

VideoExporter *VideoExporter::create(QQmlEngine *engine, QJSEngine *scriptEngine) {
    Q_UNUSED(scriptEngine);
    auto *store = new VideoExporter(engine);
    QJSEngine::setObjectOwnership(store, QJSEngine::CppOwnership);
    return store;
}

VideoExporter::VideoExporter(QObject *parent)
    : QObject(parent) {
    // Remove temps orphaned by crashes or quit-without-save runs.
    const QDir tmp = QDir::temp();
    for (const QString &f : tmp.entryList({QStringLiteral("totm-export-*.mp4")}, QDir::Files))
        QFile::remove(tmp.filePath(f));
}

VideoExporter::~VideoExporter() {
    // Bounded shutdown: the worker polls cancel every frame and during
    // pipe/finish waits, so it normally joins fast. Terminate is a last
    // resort; ffmpeg then exits once the pipe breaks.
    if (m_thread && m_thread->isRunning()) {
        m_thread->requestCancel();
        if (!m_thread->wait(8000))
            m_thread->terminate();
        m_thread->wait(2000);
    }
}

bool VideoExporter::rendering() const { return m_rendering; }
float VideoExporter::progress() const {
    return m_totalFrames > 0 ? float(m_currentFrame) / float(m_totalFrames) : 0.0f;
}
int VideoExporter::currentFrame() const { return m_currentFrame; }
int VideoExporter::totalFrames() const { return m_totalFrames; }
QString VideoExporter::qualityLabel() const { return m_qualityLabel; }
QString VideoExporter::tempPath() const { return m_tempPath; }
QString VideoExporter::lastError() const { return m_lastError; }

QString VideoExporter::ffmpegPath() {
#ifdef Q_OS_WIN
    QString found = QStandardPaths::findExecutable(QStringLiteral("ffmpeg.exe"));
    if (!found.isEmpty())
        return found;
#endif
    return QStandardPaths::findExecutable(QStringLiteral("ffmpeg"));
}

bool VideoExporter::startExport(const QVariantMap &scene, const QString &quality, int fps,
    const QString &performance, const QString &designName) {
    if (m_rendering) {
        setLastError(tr("Already rendering. Wait or cancel first."));
        return false;
    }
    if (scene.isEmpty() || !scene.contains(QStringLiteral("nodes"))) {
        setLastError(tr("Nothing to export."));
        return false;
    }
    int outW = 1920, outH = 1080;
    QString resolvedLabel;
    resolveQuality(quality, outW, outH, resolvedLabel);
    Q_UNUSED(resolvedLabel); // Dimensions drive the render; the title uses shortQ below.
    if (fps != 60)
        fps = 30;
    QString preset;
    int crf = 18;
    QString perfLabel;
    resolvePerformance(performance, preset, crf, perfLabel);
    const QVariantMap anim = scene.value(QStringLiteral("anim")).toMap();
    const double duration = qBound(0.5, anim.value(QStringLiteral("duration"), 4.0).toDouble(), 60.0);
    const int total = qMax(1, qRound(duration * fps));

    if (ffmpegPath().isEmpty()) {
        setLastError(ffmpegMissingMessage());
        return false;
    }
    if (!m_tempPath.isEmpty())
        QFile::remove(m_tempPath);
    m_tempPath.clear();
    const QString temp = QDir::temp().filePath(
        QStringLiteral("totm-export-%1-%2.mp4").arg(QCoreApplication::applicationPid()).arg(QDateTime::currentMSecsSinceEpoch()));
    QFile::remove(temp);

    clearError();
    // Progress title format: "Rendering <design> 4k60". Effort is omitted;
    // see the completion log.
    QString shortQ = quality.trimmed().toLower();
    if (shortQ != QLatin1String("sd") && shortQ != QLatin1String("4k"))
        shortQ = QStringLiteral("hd");
    QString name = designName.trimmed();
    if (name.isEmpty())
        name = tr("Untitled");
    m_qualityLabel = QStringLiteral("Rendering %1 %2%3").arg(name).arg(shortQ).arg(fps);
    m_currentFrame = 0;
    m_totalFrames = total;
    setRendering(true);
    emit progressChanged();

    auto *thread = new RenderThread(scene, outW, outH, fps, preset, crf, perfLabel, temp);
    m_thread = thread;
    connect(thread, &RenderThread::frameProgress, this, [this](int cur, int total) {
        m_currentFrame = cur;
        m_totalFrames = total;
        emit progressChanged();
    });
    connect(thread, &RenderThread::renderDone, this, [this](const QString &path) { onWorkerFinished(path, {}, false); });
    connect(thread, &RenderThread::renderError, this, [this](const QString &msg) { onWorkerFinished({}, msg, false); });
    connect(thread, &RenderThread::renderCancelled, this, [this]() { onWorkerFinished({}, {}, true); });
    connect(thread, &QThread::finished, thread, &QObject::deleteLater);
    // Low priority so the UI thread wins scheduling during renders.
    thread->start(QThread::LowPriority);
    return true;
}

void VideoExporter::cancel() {
    if (!m_rendering || !m_thread)
        return;
    m_thread->requestCancel();
}

bool VideoExporter::saveAs(const QUrl &destination) {
    if (m_tempPath.isEmpty() || !QFile::exists(m_tempPath)) {
        setLastError(tr("No finished render to save."));
        return false;
    }
    QString local = destination.isLocalFile() ? destination.toLocalFile() : destination.toString();
    if (local.isEmpty()) {
        setLastError(tr("Pick a file to save to."));
        return false;
    }
    if (!local.endsWith(QStringLiteral(".mp4"), Qt::CaseInsensitive))
        local += QStringLiteral(".mp4");
    if (QFile::exists(local) && !QFile::remove(local)) {
        setLastError(tr("Could not overwrite the chosen file."));
        return false;
    }
    if (!QFile::copy(m_tempPath, local)) {
        setLastError(tr("Could not save there. Try another folder."));
        return false;
    }
    return true;
}

void VideoExporter::clearError() {
    if (m_lastError.isEmpty())
        return;
    m_lastError.clear();
    emit lastErrorChanged();
}

void VideoExporter::setRendering(bool rendering) {
    if (m_rendering == rendering)
        return;
    m_rendering = rendering;
    emit renderingChanged();
}

void VideoExporter::setLastError(const QString &message) {
    if (m_lastError == message)
        return;
    m_lastError = message;
    emit lastErrorChanged();
}

void VideoExporter::onWorkerFinished(const QString &tempPath, const QString &error, bool wasCancelled) {
    m_thread = nullptr;
    m_currentFrame = wasCancelled ? 0 : m_currentFrame;
    setRendering(false);
    if (wasCancelled) {
        m_tempPath.clear();
        m_currentFrame = 0;
        m_totalFrames = 0;
        emit finishedChanged();
        emit progressChanged();
        emit cancelled();
        return;
    }
    if (!error.isEmpty()) {
        m_tempPath.clear();
        setLastError(error);
        emit finishedChanged();
        emit progressChanged();
        emit failed();
        return;
    }
    m_tempPath = tempPath;
    emit finishedChanged();
    emit progressChanged();
    emit succeeded();
}
