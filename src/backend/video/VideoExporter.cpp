#include "VideoExporter.h"

#include "AnimSampler.h"

#include <QAbstractTextDocumentLayout>
#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFont>
#include <QImage>
#include <QImageReader>
#include <QAtomicInteger>
#include <QPainter>
#include <QPainterPath>
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

        // Stage timers for the completion summary log.
        QElapsedTimer totalT;
        totalT.start();
        qint64 msSample = 0, msRaster = 0, msWrite = 0;
        // Progress is throttled to ~10Hz; per-frame rebinds add UI churn
        // with no visible gain.
        QElapsedTimer emitT;
        emitT.start();
        bool emittedOnce = false;
        // Single reusable frame buffer; per-frame 4K allocs are ~119GB of
        // allocator traffic over a 60fps minute.
        QImage img;
        QElapsedTimer stageT;
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
            stageT.start();
            const QList<QVariantMap> work = sampleFrame(m_scene, t);
            msSample += stageT.elapsed();

            stageT.start();
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
                paintLeaf(pt, m, ox, oy, scale);
            }
            pt.end();
            msRaster += stageT.elapsed();

            stageT.start();
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
            msWrite += stageT.elapsed();
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
        // Completion summary: frames, wall time and stage split for perf work.
        qInfo().nospace() << "export: " << total << " frames " << m_outW << 'x' << m_outH << " @" << m_fps
                          << "fps in " << totalT.elapsed() << "ms (sample " << msSample << "ms, raster " << msRaster
                          << "ms, pipe " << msWrite << "ms, enc-threads " << encThreads << ", " << m_effort << ' '
                          << m_preset << "/crf" << m_crf << ')';
        emit renderDone(m_tempPath);
    }

    static void paintLeaf(QPainter &pt, const QVariantMap &m, double ox, double oy, double scale) {
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

        pt.save();
        pt.setOpacity(opacity);
        pt.translate(cx, cy);
        pt.rotate(num(m, "rotation"));
        pt.scale(m.value(QStringLiteral("flipH")).toBool() ? -1.0 : 1.0,
            m.value(QStringLiteral("flipV")).toBool() ? -1.0 : 1.0);
        pt.translate(-cx, -cy);

        if (shapeType == QLatin1String("text")) {
            paintText(pt, m, x, y, w, h, scale, fill);
            pt.restore();
            return;
        }

        if (shapeType == QLatin1String("image")) {
            paintImage(pt, m, x, y, w, h, scale, stroke, sw);
            pt.restore();
            return;
        }

        QPainterPath path;
        if (shapeType == QLatin1String("rectangle") && !m.value(QStringLiteral("independentCorners")).toBool()) {
            const double r = qMax(0.0, num(m, "radius") * scale);
            if (r <= 0.01) {
                pt.fillRect(QRectF(x, y, w, h), fill);
                if (sw > 0.01) {
                    QPen pen(stroke, sw, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
                    pt.setPen(pen);
                    pt.setBrush(Qt::NoBrush);
                    pt.drawRect(QRectF(x + sw / 2, y + sw / 2, w - sw, h - sw));
                }
                pt.restore();
                return;
            }
            // Parity: QML Rectangle borders paint inside the bounds, so
            // inset the path by half the stroke.
            QRectF box(x, y, w, h);
            double r2 = r;
            if (sw > 0.01 && w > sw && h > sw) {
                const double inset = sw / 2.0;
                box.adjust(inset, inset, -inset, -inset);
                r2 = qMax(0.0, r - inset);
            }
            // Parity: oversized radii collapse to a capsule in QML; clamp
            // identically since addRoundedRect warps past half-size.
            r2 = qMin(r2, qMin(box.width(), box.height()) / 2.0);
            path.addRoundedRect(box, r2, r2);
        } else if (shapeType == QLatin1String("ellipse")) {
            path.addEllipse(QRectF(x, y, w, h));
        } else if (shapeType == QLatin1String("rectangle")) {
            path = rectPath(m, x, y, w, h, scale);
        } else if (shapeType == QLatin1String("triangle") || shapeType == QLatin1String("star")) {
            path = roundedPolyPath(m, x, y, w, h, scale);
        } else if (shapeType == QLatin1String("pen")) {
            path = penPath(m, ox, oy, scale);
        } else {
            pt.fillRect(QRectF(x, y, w, h), fill);
            pt.restore();
            return;
        }
        pt.fillPath(path, fill);
        if (sw > 0.01) {
            QPen pen(stroke, sw, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
            pt.setPen(pen);
            pt.setBrush(Qt::NoBrush);
            pt.drawPath(path);
        }
        pt.restore();
    }

    // Per-corner rounded rect (mirrors ShapeGeometry.rectPath).
    static QPainterPath rectPath(const QVariantMap &m, double x, double y, double w, double h, double s) {
        const QVariantList src = m.value(QStringLiteral("cornerRadii")).toList();
        double r[4] = {0, 0, 0, 0};
        for (int i = 0; i < 4; ++i)
            r[i] = i < src.size() ? qMax(0.0, src.at(i).toDouble() * s) : 0.0;
        double cap = qMin(w / 2.0, h / 2.0);
        for (int k = 0; k < 4; ++k)
            r[k] = qMin(r[k], cap);
        const double lens[4] = {w, h, w, h};
        for (int e = 0; e < 4; ++e) {
            const int a = e, b = (e + 1) % 4;
            const double sum = r[a] + r[b];
            if (lens[e] > 0 && sum > lens[e]) {
                r[a] *= lens[e] / sum;
                r[b] *= lens[e] / sum;
            }
        }
        QPainterPath d;
        d.moveTo(x + r[0], y);
        d.lineTo(x + w - r[1], y);
        if (r[1] > 0)
            d.quadTo(x + w, y, x + w, y + r[1]);
        else
            d.lineTo(x + w, y);
        d.lineTo(x + w, y + h - r[2]);
        if (r[2] > 0)
            d.quadTo(x + w, y + h, x + w - r[2], y + h);
        else
            d.lineTo(x + w, y + h);
        d.lineTo(x + r[3], y + h);
        if (r[3] > 0)
            d.quadTo(x, y + h, x, y + h - r[3]);
        else
            d.lineTo(x, y + h);
        d.lineTo(x, y + r[0]);
        if (r[0] > 0)
            d.quadTo(x, y, x + r[0], y);
        else
            d.lineTo(x, y);
        d.closeSubpath();
        return d;
    }

    static QList<QPointF> cornerPoints(const QVariantMap &m, double w, double h) {
        const QString shapeType = str(m, "type", str(m, "shapeType"));
        QList<QPointF> pts;
        if (shapeType == QLatin1String("triangle")) {
            pts << QPointF(w / 2, 0) << QPointF(w, h) << QPointF(0, h);
            return pts;
        }
        const int n = qBound(3, m.value(QStringLiteral("points"), 5).toInt(), 12);
        const double cx = w / 2.0, cy = h / 2.0;
        for (int k = 0; k < n * 2; ++k) {
            const double a = -M_PI / 2.0 + k * M_PI / n;
            const double rr = (k % 2 == 0) ? 1.0 : 0.4;
            pts << QPointF(cx + w / 2 * rr * qCos(a), cy + h / 2 * rr * qSin(a));
        }
        return pts;
    }

    // Closed polygon with per-vertex rounding (mirrors ShapeGeometry.roundedPoly).
    static QPainterPath roundedPolyPath(const QVariantMap &m, double x, double y, double w, double h, double s) {
        const QString shapeType = str(m, "type", str(m, "shapeType"));
        const bool tipsOnly = shapeType == QLatin1String("star");
        const QList<QPointF> local = cornerPoints(m, w / s, h / s);
        QList<QPointF> pts;
        for (const QPointF &p : local)
            pts << QPointF(x + p.x() * s, y + p.y() * s);
        const int n = pts.size();
        const double uniform = qMax(0.0, num(m, "radius") * s);
        const QVariantList arr = m.value(QStringLiteral("cornerRadii")).toList();
        QList<double> cut;
        for (int i = 0; i < n; ++i) {
            double want = -1;
            if (m.value(QStringLiteral("independentCorners")).toBool()) {
                if (shapeType == QLatin1String("star")) {
                    if (i % 2 == 1)
                        want = 0;
                    else {
                        const int tip = i / 2;
                        want = tip < arr.size() ? qMax(0.0, arr.at(tip).toDouble() * s) : 0.0;
                    }
                } else {
                    want = i < arr.size() ? qMax(0.0, arr.at(i).toDouble() * s) : 0.0;
                }
            }
            double r = want >= 0 ? want : uniform;
            if (r <= 0 || (tipsOnly && i % 2 == 1 && !m.value(QStringLiteral("independentCorners")).toBool())) {
                cut << 0.0;
                continue;
            }
            const QPointF pv = pts[(i - 1 + n) % n], v = pts[i], nx = pts[(i + 1) % n];
            const double l1 = qHypot(v.x() - pv.x(), v.y() - pv.y());
            const double l2 = qHypot(nx.x() - v.x(), nx.y() - v.y());
            cut << (l1 <= 0 || l2 <= 0 ? 0.0 : std::min({r, l1, l2}));
        }
        for (int e = 0; e < n; ++e) {
            const int f = e, g = (e + 1) % n;
            const double len = qHypot(pts[g].x() - pts[f].x(), pts[g].y() - pts[f].y());
            const double sum = cut[f] + cut[g];
            if (len > 0 && sum > len) {
                cut[f] *= len / sum;
                cut[g] *= len / sum;
            }
        }
        QPainterPath d;
        for (int j = 0; j < n; ++j) {
            const QPointF q = pts[(j - 1 + n) % n], v = pts[j], e = pts[(j + 1) % n];
            const double m1 = qHypot(v.x() - q.x(), v.y() - q.y());
            const double m2 = qHypot(e.x() - v.x(), e.y() - v.y());
            QPointF a = v, b = v;
            if (cut[j] > 0 && m1 > 0 && m2 > 0) {
                a = QPointF(v.x() - (v.x() - q.x()) / m1 * cut[j], v.y() - (v.y() - q.y()) / m1 * cut[j]);
                b = QPointF(v.x() + (e.x() - v.x()) / m2 * cut[j], v.y() + (e.y() - v.y()) / m2 * cut[j]);
            }
            if (j == 0)
                d.moveTo(a);
            else
                d.lineTo(a);
            if (cut[j] > 0)
                d.quadTo(v, b);
        }
        d.closeSubpath();
        return d;
    }

    // Pen subpaths in absolute content coords (mirrors ShapeGeometry.penPath).
    static QPainterPath penPath(const QVariantMap &m, double ox, double oy, double s) {
        QPainterPath d;
        bool first = true;
        for (const QVariant &sv : m.value(QStringLiteral("pathData")).toList()) {
            const QVariantMap sub = sv.toMap();
            const QVariantList raw = sub.value(QStringLiteral("pts")).toList();
            if (raw.isEmpty())
                continue;
            const auto X = [&](double v) { return ox + v * s; };
            const QVariantMap p0 = raw.first().toMap();
            d.moveTo(X(num(p0, "x")), oy + num(p0, "y") * s);
            first = false;
            for (int i = 1; i < raw.size(); ++i) {
                const QVariantMap a = raw.at(i - 1).toMap(), b = raw.at(i).toMap();
                const bool aS = a.value(QStringLiteral("smooth")).toBool();
                const bool bS = b.value(QStringLiteral("smooth")).toBool();
                const double bx = X(num(b, "x")), by = oy + num(b, "y") * s;
                if (!aS && !bS) {
                    d.lineTo(bx, by);
                    continue;
                }
                const double ax = X(num(a, "x")), ay = oy + num(a, "y") * s;
                const double c1x = aS ? X(num(a, "outX", num(a, "x"))) : ax;
                const double c1y = aS ? oy + num(a, "outY", num(a, "y")) * s : ay;
                const double c2x = bS ? X(num(b, "inX", num(b, "x"))) : bx;
                const double c2y = bS ? oy + num(b, "inY", num(b, "y")) * s : by;
                d.cubicTo(c1x, c1y, c2x, c2y, bx, by);
            }
            if (sub.value(QStringLiteral("closed")).toBool() && raw.size() > 1) {
                const QVariantMap a = raw.last().toMap(), b = raw.first().toMap();
                const bool aS = a.value(QStringLiteral("smooth")).toBool();
                const bool bS = b.value(QStringLiteral("smooth")).toBool();
                const double bx = X(num(b, "x")), by = oy + num(b, "y") * s;
                if (!aS && !bS) {
                    d.lineTo(bx, by);
                } else {
                    const double ax = X(num(a, "x")), ay = oy + num(a, "y") * s;
                    const double c1x = aS ? X(num(a, "outX", num(a, "x"))) : ax;
                    const double c1y = aS ? oy + num(a, "outY", num(a, "y")) * s : ay;
                    const double c2x = bS ? X(num(b, "inX", num(b, "x"))) : bx;
                    const double c2y = bS ? oy + num(b, "inY", num(b, "y")) * s : by;
                    d.cubicTo(c1x, c1y, c2x, c2y, bx, by);
                }
                d.closeSubpath();
            }
            Q_UNUSED(first);
        }
        return d;
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
        const QColor &stroke, double sw) {
        const QString name = str(m, "imageSource", str(m, "image", QString()));
        const double r = qMin(qMax(0.0, num(m, "radius") * s), qMin(w, h) / 2.0);
        QPainterPath clip;
        if (r > 0.01)
            clip.addRoundedRect(QRectF(x, y, w, h), r, r);
        else
            clip.addRect(QRectF(x, y, w, h));
        const QImage img = loadExportImage(name, qMax(1, qRound(w)), qMax(1, qRound(h)));
        if (img.isNull()) {
            pt.fillPath(clip, QColor(QStringLiteral("#d9d9d9")));
        } else {
            pt.save();
            pt.setClipPath(clip, Qt::IntersectClip);
            pt.drawImage(QRectF(x, y, w, h), img);
            pt.restore();
        }
        if (sw > 0.01) {
            QPen pen(stroke, sw, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
            pt.setPen(pen);
            pt.setBrush(Qt::NoBrush);
            pt.drawPath(clip);
        }
    }

    // Text via QTextDocument (mirrors TextGlyphs). Outline uses a 1px
    // content-space hairline; line height follows the
    // natural-unless-overridden rule.
    static void paintText(QPainter &pt, const QVariantMap &m, double x, double y, double w, double h, double s, const QColor &fill) {
        QTextDocument doc;
        doc.setPlainText(str(m, "textContent"));
        const double px = qMax(1.0, num(m, "fontSize", 16.0) * s);
        QFont font(str(m, "fontFamily", QStringLiteral("Inter")));
        font.setPixelSize(qRound(px));
        font.setWeight(QFont::Weight(qBound(100, m.value(QStringLiteral("fontWeight"), 400).toInt(), 900)));
        const double spacingPct = num(m, "letterSpacing");
        if (!qFuzzyIsNull(spacingPct))
            font.setLetterSpacing(QFont::AbsoluteSpacing, num(m, "fontSize", 16.0) * s * spacingPct / 100.0);
        doc.setDefaultFont(font);
        QTextCursor cur(&doc);
        cur.select(QTextCursor::Document);
        QTextCharFormat fmt;
        fmt.setForeground(fill);
        if (num(m, "strokeWidth") > 0.0)
            fmt.setTextOutline(QPen(QColor(str(m, "stroke", QStringLiteral("#000000"))), qMax(0.5, s)));
        cur.mergeCharFormat(fmt);
        if (!m.value(QStringLiteral("lineHeightAuto"), true).toBool()) {
            QTextBlockFormat bf;
            bf.setLineHeight(qMax(0.5, num(m, "lineHeight", 1.2) * px), QTextBlockFormat::FixedHeight);
            cur.mergeBlockFormat(bf);
        }
        QTextOption opt;
        const QString ha = str(m, "hAlign", QStringLiteral("left"));
        opt.setAlignment(ha == QLatin1String("center") ? Qt::AlignHCenter
            : ha == QLatin1String("right")             ? Qt::AlignRight
            : ha == QLatin1String("justify")           ? Qt::AlignJustify
                                                      : Qt::AlignLeft);
        opt.setWrapMode(m.value(QStringLiteral("autoSize"), true).toBool() ? QTextOption::NoWrap : QTextOption::WordWrap);
        doc.setDefaultTextOption(opt);
        const bool autoSize = m.value(QStringLiteral("autoSize"), true).toBool();
        if (!autoSize)
            doc.setTextWidth(w);
        QTextOption::WrapMode unused = opt.wrapMode();
        Q_UNUSED(unused);
        QSizeF ds = doc.size();
        double dy = 0.0;
        if (!autoSize) {
            const QString va = str(m, "vAlign", QStringLiteral("top"));
            if (va == QLatin1String("middle"))
                dy = qMax(0.0, (h - ds.height()) / 2.0);
            else if (va == QLatin1String("bottom"))
                dy = qMax(0.0, h - ds.height());
        }
        pt.save();
        pt.translate(x, y + dy);
        QAbstractTextDocumentLayout::PaintContext ctx;
        ctx.palette.setColor(QPalette::Text, fill);
        // Fixed boxes clip like the canvas; auto-size boxes grow freely.
        if (!autoSize)
            pt.setClipRect(QRectF(0, 0, w, h));
        doc.documentLayout()->draw(&pt, ctx);
        pt.restore();
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
