#include "VideoExporter.h"

#include "AnimSampler.h"
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
    RenderThread(QVariantMap scene, int outW, int outH, int fps, QString preset, int crf, QString effort,
        QString tempPath, QString format, int vp9Cpu, int vp9Crf, QObject *parent = nullptr)
        : QThread(parent)
        , m_scene(std::move(scene))
        , m_outW(outW)
        , m_outH(outH)
        , m_fps(fps)
        , m_preset(std::move(preset))
        , m_crf(crf)
        , m_effort(std::move(effort))
        , m_tempPath(std::move(tempPath))
        , m_format(std::move(format))
        , m_vp9Cpu(vp9Cpu)
        , m_vp9Crf(vp9Crf) {}

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
        // GIF is silent by design (no audio inputs at all); no clips
        // keeps the historical video-only path untouched.
        const bool isGif = m_format == QStringLiteral("gif");
        const bool isWebm = m_format == QStringLiteral("webm");
        const QList<AudioInput> audio = isGif ? QList<AudioInput>() : collectAudio(m_scene, duration);
        QProcess proc;
        QStringList encArgs = {QStringLiteral("-y"), QStringLiteral("-f"), QStringLiteral("rawvideo"),
            QStringLiteral("-pix_fmt"), QStringLiteral("rgba"), QStringLiteral("-s"),
            QStringLiteral("%1x%2").arg(m_outW).arg(m_outH), QStringLiteral("-r"), QString::number(m_fps),
            QStringLiteral("-i"), QStringLiteral("-")};
        for (const AudioInput &in : audio) {
            encArgs += {QStringLiteral("-ss"), QString::number(in.seek, 'f', 3), QStringLiteral("-t"),
                QString::number(in.take, 'f', 3), QStringLiteral("-i"), in.path};
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
                FramePaint::paintLeaf(pt, img, m, ox, oy, scale, Effects::grainFrameNo(t));
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
    QString m_effort = QStringLiteral("Normal");
    QString m_tempPath;
    QString m_format = QStringLiteral("mp4");
    int m_vp9Cpu = 2;
    int m_vp9Crf = 31;
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
    const QString &performance, const QString &designName, const QString &format) {
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
    const QString outFormat = normalizeFormat(format);
    QString preset;
    int crf = 18;
    QString perfLabel;
    resolvePerformance(performance, preset, crf, perfLabel);
    int vp9Cpu = 2, vp9Crf = 31;
    resolveWebmEffort(performance, vp9Cpu, vp9Crf);
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

    auto *thread = new RenderThread(scene, outW, outH, fps, preset, crf, perfLabel, temp, outFormat, vp9Cpu, vp9Crf);
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

namespace {
// Resolved destination with the container suffix appended when missing
// ("" when no usable path). Shared by the write and the QML overwrite
// probe so the two can never disagree on the target file.
QString saveLocalPath(const QUrl &destination, const QString &suffix)
{
    QString local = destination.isLocalFile() ? destination.toLocalFile() : destination.toString();
    if (local.isEmpty()) {
        return {};
    }
    if (!local.endsWith(suffix, Qt::CaseInsensitive)) {
        local += suffix;
    }
    return local;
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
