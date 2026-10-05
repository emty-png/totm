#include "VideoExporter.h"

#include "AnimSampler.h"
#include "AppPaths.h"
#include "EffectPainter.h"
#include "FramePaint.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QAtomicInteger>
#include <QPainter>
#include <QPainterPath>
#include <QProcess>
#include <QStandardPaths>
#include <QThread>
#include <QtMath>

#include <algorithm>

namespace {

// Output sizes are resolved here; frame content comes from AnimSampler so
// export and canvas preview share one sampling path.
using namespace Anims;

// Render cap: 1800s at 120fps would be 216k frames (multi-TB temp at 4K,
// hours of encode). 108k covers 30min at 60fps / 15min at 120fps.
constexpr int kMaxTotalFrames = 108000;

// Fixed landscape masters per quality. Scene aspect is letterboxed on
// sceneColor to keep output predictable across scene sizes.
bool resolveQuality(const QString &quality, int &w, int &h) {
    const QString q = quality.trimmed().toLower();
    if (q == QLatin1String("sd") || q == QLatin1String("480p")) {
        w = 854;
        h = 480;
        return true;
    }
    if (q == QLatin1String("4k") || q == QLatin1String("uhd") || q == QLatin1String("2160p")) {
        w = 3840;
        h = 2160;
        return true;
    }
    w = 1920;
    h = 1080;
    return q == QLatin1String("hd") || q == QLatin1String("1080p") || q == QLatin1String("720p");
}

// Sampling lives in AnimSampler; only the quality table stays here.

// Audible audio slice for one timeline clip: source file plus the
// trimmed read window and its composition delay, all in seconds.
// Volume is linear 0..1 (muted forces 0); fades ride seconds.
// rate is the footage playback rate (1 for timeline clips); take is
// composition seconds while the file read is take*rate. loopFile
// requests -stream_loop for looping footage.
struct AudioInput {
    QString path;
    double seek = 0.0;
    double take = 0.0;
    double delay = 0.0;
    double volume = 1.0;
    double fadeIn = 0.0;
    double fadeOut = 0.0;
    bool muted = false;
    double rate = 1.0;
    bool loopFile = false;
};

// Fast fail-open probe: true when ffmpeg sees an audio stream.
// Missing/undecodable files return false so the filter graph never
// references a stream that does not exist ([i:a] would fail the render).
bool fileHasAudioTrack(const QString &path, const QString &ffmpeg) {
    if (path.isEmpty() || ffmpeg.isEmpty())
        return false;
    QProcess proc;
    proc.start(ffmpeg, {QStringLiteral("-hide_banner"), QStringLiteral("-i"), path});
    if (!proc.waitForFinished(8000))
        return false;
    const QString err = QString::fromLocal8Bit(proc.readAllStandardError());
    return err.contains(QStringLiteral("Audio:"));
}

QString resolveBlobPath(const QString &name, const QString &audioDir, const QString &videoDir, bool preferVideo) {
    if (name.isEmpty())
        return {};
    if (name.contains(QLatin1Char('/')) || name.contains(QLatin1Char('\\'))) {
        if (!QFile::exists(name))
            return {};
        const QString suf = QFileInfo(name).suffix().toLower();
        if (!AppPaths::audioExtensions().contains(suf) && !AppPaths::videoExtensions().contains(suf))
            return {};
        return name;
    }
    if (name.contains(QStringLiteral("..")))
        return {};
    const QString first = (preferVideo ? videoDir : audioDir) + QStringLiteral("/") + name;
    if (QFile::exists(first))
        return first;
    const QString second = (preferVideo ? audioDir : videoDir) + QStringLiteral("/") + name;
    if (QFile::exists(second))
        return second;
    return {};
}

// Native video sound (opt-in via the export checkbox): one slice per
// visible, unmuted video leaf. Window math mirrors ShapeItem.wantTime
// (start/offset/rate, loop modulo). Animated hide is ignored in v1
// (static visible only); Video time clips are ignored (legacy math).
void collectVideoSound(const QVariantMap &scene, double duration, QList<AudioInput> &out, const QString &ffmpeg,
    const QString &audioDir, const QString &videoDir) {
    QList<QVariantList> nodeStack;
    QList<bool> visStack;
    nodeStack.append(scene.value(QStringLiteral("nodes")).toList());
    visStack.append(true);
    while (!nodeStack.isEmpty()) {
        const QVariantList nodes = nodeStack.takeLast();
        const bool parentVisible = visStack.takeLast();
        for (const QVariant &nv : nodes) {
            const QVariantMap n = nv.toMap();
            if (n.value(QStringLiteral("kind")).toString() == QLatin1String("group")) {
                const bool vis = n.value(QStringLiteral("visible"), true).toBool();
                nodeStack.append(n.value(QStringLiteral("children")).toList());
                visStack.append(parentVisible && vis);
                continue;
            }
            const QString t = n.value(QStringLiteral("type")).toString();
            const QString st = n.value(QStringLiteral("shapeType")).toString();
            if (t != QLatin1String("video") && st != QLatin1String("video"))
                continue;
            if (!parentVisible || n.value(QStringLiteral("visible"), true).toBool() == false)
                continue;
            if (n.value(QStringLiteral("isMask"), false).toBool())
                continue;
            if (n.value(QStringLiteral("videoMuted"), false).toBool())
                continue;
            const QString src = n.value(QStringLiteral("videoSource")).toString();
            if (src.isEmpty())
                continue;
            const QString path = resolveBlobPath(src, audioDir, videoDir, true);
            if (path.isEmpty())
                continue;
            if (!fileHasAudioTrack(path, ffmpeg))
                continue;
            const double startComp = qMax(0.0, n.value(QStringLiteral("videoStart"), 0.0).toDouble());
            if (startComp >= duration)
                continue;
            double rate = n.value(QStringLiteral("playbackRate"), 1.0).toDouble();
            if (!(rate > 0.0))
                rate = 1.0;
            rate = qBound(0.25, rate, 4.0);
            const double seekFile = qMax(0.0, n.value(QStringLiteral("videoOffset"), 0.0).toDouble());
            const double fileDur = qMax(0.0, n.value(QStringLiteral("videoDuration"), 0.0).toDouble());
            const bool loop = n.value(QStringLiteral("videoLoop"), true).toBool() && fileDur > 0.05;
            double takeComp = duration - startComp;
            if (fileDur > 0.05) {
                if (seekFile >= fileDur)
                    continue;
                if (!loop) {
                    const double maxComp = (fileDur - seekFile) / rate;
                    if (maxComp <= 0.02)
                        continue;
                    takeComp = qMin(takeComp, maxComp);
                }
            } else {
                // Unknown length free-runs like preview (no loop math).
            }
            if (takeComp <= 0.02)
                continue;
            AudioInput in;
            in.path = path;
            in.seek = seekFile;
            in.take = takeComp;
            in.delay = startComp;
            in.volume = qBound(0.0, n.value(QStringLiteral("videoVolume"), 1.0).toDouble(), 1.0);
            in.fadeIn = 0.0;
            in.fadeOut = 0.0;
            in.muted = false;
            in.rate = rate;
            in.loopFile = loop;
            out.append(in);
        }
    }
}

// Timeline audio resolved against the render duration (same trim rule
// as the canvas preview: intersect with [0, duration]). Missing blobs
// are skipped so one lost file never fails the whole render.
// Detached video sound shares the stored video blob in videos/ (legacy
// absolute paths still feed ffmpeg directly, which extracts their track).
// When includeVideoSound is set, native video leaves mix in too (see
// collectVideoSound); GIF callers pass false (silent by design).
QList<AudioInput> collectAudio(const QVariantMap &scene, double duration, bool includeVideoSound, const QString &ffmpeg) {
    QList<AudioInput> out;
    const QVariantMap audio = scene.value(QStringLiteral("audio")).toMap();
    const QVariantList clips = audio.value(QStringLiteral("clips")).toList();
    const QString base = AppPaths::totmBaseDir();
    const QString dir = base + QStringLiteral("/audio");
    const QString vdir = base + QStringLiteral("/videos");
    for (const QVariant &cv : clips) {
        const QVariantMap c = cv.toMap();
        const QString name = c.value(QStringLiteral("source")).toString();
        if (name.isEmpty())
            continue;
        // Legacy absolute paths (detached sound from old designs) feed
        // directly; ffmpeg reads their audio track. Blob names resolve
        // under audio/, then videos/ for detached video sound.
        const QString path = resolveBlobPath(name, dir, vdir, false);
        if (path.isEmpty())
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
        in.rate = 1.0;
        in.loopFile = false;
        out.append(in);
    }
    if (includeVideoSound)
        collectVideoSound(scene, duration, out, ffmpeg, dir, vdir);
    return out;
}

// atempo chain for one playback rate (0.25..4): single filter covers
// 0.5..2, wider rates chain (4 = 2*2, 0.25 = 0.5*0.5). Empty when ~1.
QString atempoChain(double rate) {
    if (rate > 0.999 && rate < 1.001)
        return {};
    double r = qBound(0.25, rate, 4.0);
    QStringList parts;
    while (r > 2.0) {
        parts.append(QStringLiteral("atempo=2.000"));
        r /= 2.0;
    }
    while (r < 0.5) {
        parts.append(QStringLiteral("atempo=0.500"));
        r /= 0.5;
    }
    parts.append(QStringLiteral("atempo=%1").arg(QString::number(r, 'f', 3)));
    return parts.join(QStringLiteral(","));
}

// Filter graph shaping each input (tempo, volume, fades) then delaying
// it to its timeline start and mixing down to one stereo track. Fades
// run before the delay so their times stay clip-relative (0..take);
// both are fit inside the take. normalize=0 keeps bed levels intact;
// overlapping clips can clip instead of ducking (no per-clip volume
// in v1, so there is nothing to preserve headroom for).
QString audioFilter(const QList<AudioInput> &inputs) {
    QStringList mixed;
    for (int i = 0; i < inputs.size(); ++i) {
        const AudioInput &in = inputs.at(i);
        const int ms = qMax(0, qRound(in.delay * 1000.0));
        QString chain = QStringLiteral("[%1:a]aresample=44100,aformat=channel_layouts=stereo").arg(i + 1);
        const QString tempo = atempoChain(in.rate);
        if (!tempo.isEmpty())
            chain += QStringLiteral(",") + tempo;
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
void resolvePerformance(const QString &performance, QString &preset, int &crf) {
    const QString p = performance.trimmed().toLower();
    if (p == QLatin1String("slow")) {
        preset = QStringLiteral("medium");
        crf = 16;
        return;
    }
    if (p == QLatin1String("fast")) {
        preset = QStringLiteral("superfast");
        crf = 20;
        return;
    }
    preset = QStringLiteral("veryfast");
    crf = 18;
}
// Maps performance choice to VP9 speed + quality. VP9 CRF runs 0..63
// (lower is better); cpu-used 1..4 trades encode time for compression.
void resolveWebmEffort(const QString &performance, int &cpuUsed, int &crf) {
    const QString p = performance.trimmed().toLower();
    if (p == QLatin1String("slow")) {
        cpuUsed = 1;
        crf = 28;
        return;
    }
    if (p == QLatin1String("fast")) {
        cpuUsed = 4;
        crf = 34;
        return;
    }
    cpuUsed = 2;
    crf = 31;
}
// Container coercion: only the picker's own options are real, everything
// else falls back to mp4 so corrupt callers can't break the pipe.
QString normalizeFormat(const QString &format) {
    const QString f = format.trimmed().toLower();
    if (f == QLatin1String("webm") || f == QLatin1String("gif"))
        return f;
    return QStringLiteral("mp4");
}
QString suffixForFormat(const QString &format) {
    if (format == QLatin1String("webm"))
        return QStringLiteral(".webm");
    if (format == QLatin1String("gif"))
        return QStringLiteral(".gif");
    return QStringLiteral(".mp4");
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
    RenderThread(QVariantMap scene, int outW, int outH, int fps, QString preset, int crf,
        QString tempPath, QString format, int vp9Cpu, int vp9Crf, bool includeVideoSound, QObject *parent = nullptr)
        : QThread(parent)
        , m_scene(std::move(scene))
        , m_outW(outW)
        , m_outH(outH)
        , m_fps(fps)
        , m_preset(std::move(preset))
        , m_crf(crf)
        , m_tempPath(std::move(tempPath))
        , m_format(std::move(format))
        , m_vp9Cpu(vp9Cpu)
        , m_vp9Crf(vp9Crf)
        , m_includeVideoSound(includeVideoSound) {}

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
        const double duration = qBound(0.5, anim.value(QStringLiteral("duration"), 4.0).toDouble(), 1800.0);
        const int total = qMax(1, qRound(duration * m_fps));
        if (total > kMaxTotalFrames) {
            emit renderError(tr("Too long to export (frame cap exceeded). Shorten the timeline or lower fps."));
            return;
        }

        // Ancestor visibility + masks resolve inside
        // FramePaint::paintLeaves per frame (collects leaves itself).

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
        // GIF is silent by design (no audio inputs at all); no clips
        // keeps the historical video-only path untouched. Native video
        // sound mixes in only when the export checkbox opts in.
        const bool isGif = m_format == QStringLiteral("gif");
        const bool isWebm = m_format == QStringLiteral("webm");
        const QList<AudioInput> audio = isGif ? QList<AudioInput>() : collectAudio(m_scene, duration, m_includeVideoSound, ffmpeg);
        QProcess proc;
        QStringList encArgs = {QStringLiteral("-y"), QStringLiteral("-f"), QStringLiteral("rawvideo"),
            QStringLiteral("-pix_fmt"), QStringLiteral("rgba"), QStringLiteral("-s"),
            QStringLiteral("%1x%2").arg(m_outW).arg(m_outH), QStringLiteral("-r"), QString::number(m_fps),
            QStringLiteral("-i"), QStringLiteral("-")};
        for (const AudioInput &in : audio) {
            // File read is take*rate (tempo shrinks it back to take in
            // the filter); looping footage infinite-loops the input.
            const double fileTake = in.take * qBound(0.25, in.rate, 4.0);
            if (in.loopFile)
                encArgs += {QStringLiteral("-stream_loop"), QStringLiteral("-1")};
            encArgs += {QStringLiteral("-ss"), QString::number(in.seek, 'f', 3), QStringLiteral("-t"),
                QString::number(fileTake, 'f', 3), QStringLiteral("-i"), in.path};
        }
        if (isGif) {
            // Single-pass palette: split the stream, build a 256-color
            // palette on the fly and dither into it. Two-pass palettegen
            // would need the whole file up front, which a live pipe
            // never has. -loop 0 loops forever, the GIF default people
            // expect from a motion tool. -f gif is explicit: a bare
            // "gif" token would parse as a second output URL.
            encArgs += {QStringLiteral("-loop"), QStringLiteral("0"), QStringLiteral("-vf"),
                QStringLiteral("split[s0][s1];[s0]palettegen=max_colors=256[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5"),
                QStringLiteral("-f"), QStringLiteral("gif"), m_tempPath};
        } else {
            // WebM rides Opus, mp4 rides AAC; both trim/mix identically.
            const QString audioCodec = isWebm ? QStringLiteral("libopus") : QStringLiteral("aac");
            const QString audioRate = isWebm ? QStringLiteral("128k") : QStringLiteral("160k");
            if (audio.isEmpty()) {
                encArgs += {QStringLiteral("-an"), QStringLiteral("-c:v")};
            } else {
                // No -shortest: audio is trimmed to <= duration, so the mix
                // never outruns the video. -shortest would truncate the video
                // to a short effect and close the pipe mid-render (broken pipe).
                encArgs += {QStringLiteral("-filter_complex"), audioFilter(audio), QStringLiteral("-map"),
                    QStringLiteral("0:v"), QStringLiteral("-map"), QStringLiteral("[a]"), QStringLiteral("-c:a"),
                    audioCodec, QStringLiteral("-b:a"), audioRate, QStringLiteral("-c:v")};
            }
            if (isWebm) {
                // -b:v 0 selects constant-quality mode; -deadline good
                // keeps encodes near realtime without tanking quality.
                encArgs += {QStringLiteral("libvpx-vp9"), QStringLiteral("-pix_fmt"),
                    QStringLiteral("yuv420p"), QStringLiteral("-b:v"), QStringLiteral("0"),
                    QStringLiteral("-crf"), QString::number(m_vp9Crf), QStringLiteral("-cpu-used"),
                    QString::number(m_vp9Cpu), QStringLiteral("-deadline"), QStringLiteral("good"),
                    QStringLiteral("-row-mt"), QStringLiteral("1"), QStringLiteral("-threads"),
                    QString::number(encThreads), m_tempPath};
            } else {
                encArgs += {QStringLiteral("libx264"), QStringLiteral("-pix_fmt"), QStringLiteral("yuv420p"),
                    QStringLiteral("-crf"), QString::number(m_crf), QStringLiteral("-preset"), m_preset,
                    QStringLiteral("-threads"), QString::number(encThreads), QStringLiteral("-movflags"),
                    QStringLiteral("+faststart"), m_tempPath};
            }
        }
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
            // A half-started child outlives this scope otherwise (same
            // Destroyed-while-running warning as the timeout paths).
            proc.kill();
            proc.waitForFinished(5000);
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
            // Sample at frame midpoints over (0, duration]: frame 0 reads
            // what used to be frame 1, so the static base instant at t=0
            // never lands in the file (thumbnailers grab the first frame).
            // Frame count and duration are unchanged; the tail clamps.
            const double t = qMin(duration, (double(frame) + 1.5) / m_fps);

            // Sampled from AnimSampler; see its header for the QML parity contract.
            const QList<QVariantMap> work = sampleFrame(m_scene, t);

            if (img.size() != QSize(m_outW, m_outH) || img.format() != QImage::Format_RGBA8888)
                img = QImage(m_outW, m_outH, QImage::Format_RGBA8888);
            img.fill(sceneColor);
            QPainter pt(&img);
            pt.setRenderHints(QPainter::Antialiasing | QPainter::TextAntialiasing | QPainter::SmoothPixmapTransform);
            // Mask-aware, bottom-first (work is top-first).
            FramePaint::paintLeaves(pt, img, work, m_scene, ox, oy, scale, Effects::grainFrameNo(t));
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
                // Bounded pipe waits (500ms polls, 60s cap) keep cancel
                // responsive under ffmpeg backpressure. The cap is
                // generous on purpose: a slow box on x264-slow at 4K can
                // stall a 33MB frame for many seconds per poll.
                if (left > 0 && !proc.waitForBytesWritten(500)) {
                    waitedMs += 500;
                    if (waitedMs > 60000) {
                        failMsg = tr("Timed out writing to ffmpeg.");
                        ok = false;
                        break;
                    }
                }
            }
            if (!ok)
                break;
            // Throttle the producer to encoder speed. QProcess.write()
            // only moves bytes into a RAM buffer, so without this a fast
            // painter outruns a slow encoder (4K software x264) and the
            // queue grows a full frame per iteration until OOM (~33MB per
            // 4K frame: ~9GB queued by frame ~280). Capping the queue at
            // ~2 frames bounds memory to ~100MB at 4K while keeping
            // pipeline overlap. Bounded 500ms polls keep Cancel
            // responsive, same pattern as the pipe waits above.
            if (proc.bytesToWrite() > frameBytes * 2) {
                qint64 waitedThrottleMs = 0;
                while (proc.bytesToWrite() > frameBytes * 2) {
                    if (m_cancelled.loadRelaxed()) {
                        cancelAndOut();
                        return;
                    }
                    if (!proc.waitForBytesWritten(500)) {
                        waitedThrottleMs += 500;
                        if (waitedThrottleMs > 60000) {
                            failMsg = tr("Timed out writing to ffmpeg.");
                            ok = false;
                            break;
                        }
                    }
                }
                if (!ok)
                    break;
            }
            if (!emittedOnce || emitT.elapsed() >= 100 || frame + 1 == total) {
                emittedOnce = true;
                emitT.restart();
                emit frameProgress(frame + 1, total);
            }
        }

        proc.closeWriteChannel();
        // Bounded finish wait with live cancel, same pattern as the pipe
        // (500ms polls, 60s cap): draining delayed frames plus the
        // faststart rewrite runs long on slow disks/encoders.
        bool finished = false;
        for (int i = 0; i < 120; ++i) {
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
            // Wait out the kill: destroying a live QProcess warns
            // ("Destroyed while process is still running") and can
            // orphan the encoder.
            proc.kill();
            proc.waitForFinished(5000);
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

    QVariantMap m_scene;
    int m_outW = 1920, m_outH = 1080, m_fps = 30;
    QString m_preset = QStringLiteral("veryfast");
    int m_crf = 18;
    QString m_tempPath;
    QString m_format = QStringLiteral("mp4");
    int m_vp9Cpu = 2;
    int m_vp9Crf = 31;
    bool m_includeVideoSound = false;
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
    for (const QString &f : tmp.entryList({QStringLiteral("totm-export-*.mp4"),
                 QStringLiteral("totm-export-*.webm"), QStringLiteral("totm-export-*.gif")},
             QDir::Files))
        QFile::remove(tmp.filePath(f));
}

VideoExporter::~VideoExporter() {
    // Bounded cooperative shutdown only: the worker polls cancel every
    // frame and during pipe/finish waits, so it normally joins fast.
    // Never terminate(): killing mid-QPainter corrupts the heap.
    // The thread deletes itself via deleteLater on finished.
    if (!m_thread.isNull() && m_thread->isRunning()) {
        m_thread->requestCancel();
        m_thread->wait(8000);
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
QString VideoExporter::format() const { return m_format; }

QString VideoExporter::ffmpegPath() {
#ifdef Q_OS_WIN
    QString found = QStandardPaths::findExecutable(QStringLiteral("ffmpeg.exe"));
    if (!found.isEmpty())
        return found;
#endif
    return QStandardPaths::findExecutable(QStringLiteral("ffmpeg"));
}

bool VideoExporter::startExport(const QVariantMap &scene, const QString &quality, int fps,
    const QString &performance, const QString &designName, const QString &format, bool includeVideoSound) {
    if (m_rendering || (!m_thread.isNull() && m_thread->isRunning())) {
        setLastError(tr("Already rendering. Wait or cancel first."));
        return false;
    }
    if (scene.isEmpty() || !scene.contains(QStringLiteral("nodes"))) {
        setLastError(tr("Nothing to export."));
        return false;
    }
    int outW = 1920, outH = 1080;
    resolveQuality(quality, outW, outH);
    // Frame rates: 30/60 plus 120 for high-refresh footage. GIF stays
    // capped at 60 (120fps GIFs would be absurd); the popup guards the
    // picker, this coerces anything else so corrupt callers stay safe.
    if (fps != 60 && fps != 120)
        fps = 30;
    const QString outFormat = normalizeFormat(format);
    if (outFormat == QLatin1String("gif") && fps > 60)
        fps = 60;
    QString preset;
    int crf = 18;
    resolvePerformance(performance, preset, crf);
    int vp9Cpu = 2, vp9Crf = 31;
    resolveWebmEffort(performance, vp9Cpu, vp9Crf);
    const QVariantMap anim = scene.value(QStringLiteral("anim")).toMap();
    const double duration = qBound(0.5, anim.value(QStringLiteral("duration"), 4.0).toDouble(), 1800.0);
    const int total = qMax(1, qRound(duration * fps));
    if (total > kMaxTotalFrames) {
        setLastError(tr("Too long to export. Shorten the timeline or lower fps."));
        return false;
    }

    if (ffmpegPath().isEmpty()) {
        setLastError(ffmpegMissingMessage());
        return false;
    }
    if (!m_tempPath.isEmpty())
        QFile::remove(m_tempPath);
    m_tempPath.clear();
    const QString temp = QDir::temp().filePath(
        QStringLiteral("totm-export-%1-%2%3").arg(QCoreApplication::applicationPid()).arg(QDateTime::currentMSecsSinceEpoch()).arg(suffixForFormat(outFormat)));
    QFile::remove(temp);

    clearError();
    // Progress title format: "Rendering <design> 4k60 MP4". Effort is
    // omitted; see the completion log.
    QString shortQ = quality.trimmed().toLower();
    if (shortQ != QLatin1String("sd") && shortQ != QLatin1String("4k"))
        shortQ = QStringLiteral("hd");
    QString name = designName.trimmed();
    if (name.isEmpty())
        name = tr("Untitled");
    m_format = outFormat;
    m_qualityLabel = QStringLiteral("Rendering %1 %2%3 %4").arg(name).arg(shortQ).arg(fps).arg(outFormat.toUpper());
    m_currentFrame = 0;
    m_totalFrames = total;
    setRendering(true);
    emit finishedChanged();
    emit progressChanged();

    auto *thread = new RenderThread(scene, outW, outH, fps, preset, crf, temp, outFormat, vp9Cpu, vp9Crf, includeVideoSound && outFormat != QStringLiteral("gif"));
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
    if (!m_rendering || m_thread.isNull())
        return;
    m_thread->requestCancel();
}

namespace {
// Resolved destination with the container suffix appended when missing.
// Delegates to AppPaths so export/save probes share one suffix rule.
QString saveLocalPath(const QUrl &destination, const QString &suffix)
{
    return AppPaths::resolveLocalFileWithSuffix(destination, suffix);
}
} // namespace

bool VideoExporter::saveAs(const QUrl &destination, bool overwrite) {
    if (m_tempPath.isEmpty() || !QFile::exists(m_tempPath)) {
        setLastError(tr("No finished render to save."));
        return false;
    }
    const QString local = saveLocalPath(destination, suffixForFormat(m_format));
    if (local.isEmpty()) {
        setLastError(tr("Pick a file to save to."));
        return false;
    }
    if (!overwrite && QFile::exists(local)) {
        setLastError(tr("“%1” already exists. Confirm to replace it.").arg(QFileInfo(local).fileName()));
        return false;
    }
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

bool VideoExporter::destinationExists(const QUrl &destination) const {
    const QString local = saveLocalPath(destination, suffixForFormat(m_format));
    return !local.isEmpty() && QFile::exists(local);
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
    // Clear only our tracked thread; QPointer auto-nulls if the
    // QThread object was already deleted via deleteLater.
    m_thread.clear();
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
