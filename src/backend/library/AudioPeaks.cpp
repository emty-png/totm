#include "AudioPeaks.h"

#include <QDataStream>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QSaveFile>
#include <QStandardPaths>
#include <QtMath>

namespace {
constexpr int kRate = 8000;
constexpr int kMaxBuckets = 2048;
constexpr int kDecodeTimeoutMs = 30000;
constexpr char kMagic[] = "TOTMPEAKS1";
} // namespace

QVariantList AudioPeaks::peaksFor(
    const QString &audioDir, const QString &name, int buckets, double offsetSec, double windowSec) {
    QVariantList empty;
    if (!isSafeName(name) || audioDir.isEmpty())
        return empty;
    if (buckets <= 0 || !qIsFinite(offsetSec) || !qIsFinite(windowSec) || windowSec <= 0.0)
        return empty;
    buckets = qBound(1, buckets, kMaxBuckets);
    Dense dense;
    if (!denseFor(audioDir, name, dense) || dense.peak.isEmpty() || dense.sampleRate <= 0.0)
        return empty;
    const double fileDur = double(dense.peak.size()) / dense.sampleRate;
    const double start = qMax(0.0, offsetSec);
    if (start >= fileDur)
        return empty;
    const double take = qMin(windowSec, fileDur - start);
    const int i0 = qBound(0, int(start / fileDur * dense.peak.size()), dense.peak.size() - 1);
    const int i1 = qBound(i0 + 1, int((start + take) / fileDur * dense.peak.size() + 0.5), dense.peak.size());
    QVariantList out;
    out.reserve(buckets);
    for (int b = 0; b < buckets; ++b) {
        const int lo = i0 + (i1 - i0) * b / buckets;
        const int hi = i0 + (i1 - i0) * (b + 1) / buckets;
        // RMS energy, not max: a max over dozens of dense buckets
        // saturates at 1.0 on loud masters and draws flat full-height
        // bars. RMS keeps beats and quiet passages visibly apart.
        double sum = 0.0;
        int cnt = 0;
        for (int i = lo; i < hi && i < dense.peak.size(); ++i) {
            const double v = dense.peak.at(i);
            sum += v * v;
            cnt++;
        }
        out.append(cnt > 0 ? qSqrt(sum / cnt) : 0.0);
    }
    // Normalize to the visible window's own max: one loud transient
    // elsewhere in the file must not dwarf the whole clip into a
    // flatline. Relative dynamics inside the window are preserved;
    // true silence (max 0) stays flat.
    double winMax = 0.0;
    for (const QVariant &v : out)
        winMax = qMax(winMax, v.toDouble());
    if (winMax > 0.0) {
        for (QVariant &v : out)
            v = qBound(0.0, v.toDouble() / winMax, 1.0);
    }
    return out;
}

bool AudioPeaks::denseFor(const QString &audioDir, const QString &name, Dense &out) {
    if (m_cache.contains(name)) {
        out = m_cache.value(name);
        return !out.peak.isEmpty();
    }
    const QString path = audioDir + QStringLiteral("/") + name;
    const qint64 size = QFileInfo(path).size();
    if (size <= 0 || !QFile::exists(path))
        return false;
    Dense dense;
    if (!loadSidecar(sidecarFor(audioDir, name), size, dense)) {
        if (!decodeDense(path, size, dense))
            return false;
        saveSidecar(sidecarFor(audioDir, name), size, dense);
    }
    if (dense.peak.isEmpty())
        return false;
    m_cache.insert(name, dense);
    out = dense;
    return true;
}

QString AudioPeaks::sidecarFor(const QString &audioDir, const QString &name) {
    return audioDir + QStringLiteral("/") + name + QStringLiteral(".peaks");
}

bool AudioPeaks::isSafeName(const QString &name) {
    if (name.isEmpty() || name.contains(QLatin1Char('/')) || name.contains(QLatin1Char('\\'))
        || name.contains(QStringLiteral("..")))
        return false;
    const int dot = name.lastIndexOf(QLatin1Char('.'));
    return dot > 0 && dot < name.size() - 1;
}

QString AudioPeaks::ffmpegPath() {
#ifdef Q_OS_WIN
    QString found = QStandardPaths::findExecutable(QStringLiteral("ffmpeg.exe"));
    if (!found.isEmpty())
        return found;
#endif
    return QStandardPaths::findExecutable(QStringLiteral("ffmpeg"));
}

bool AudioPeaks::loadSidecar(const QString &path, qint64 fileSize, Dense &out) const {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return false;
    QDataStream in(&f);
    in.setVersion(QDataStream::Qt_6_0);
    QByteArray magic;
    qint64 storedSize = 0;
    double rate = 0.0;
    quint32 count = 0;
    in >> magic >> storedSize >> rate;
    if (magic != QByteArray(kMagic) || storedSize != fileSize || !(rate > 0.0))
        return false;
    in >> count;
    if (count != quint32(denseBuckets()))
        return false;
    QVector<float> peak;
    peak.reserve(int(count));
    for (quint32 i = 0; i < count; ++i) {
        float v = 0.0f;
        in >> v;
        if (in.status() != QDataStream::Ok || !(v >= 0.0f) || !(v <= 1.0f))
            return false;
        peak.append(v);
    }
    if (in.status() != QDataStream::Ok)
        return false;
    out.sampleRate = rate;
    out.fileSize = storedSize;
    out.peak = peak;
    return true;
}

bool AudioPeaks::saveSidecar(const QString &path, qint64 fileSize, const Dense &dense) const {
    if (dense.peak.size() != denseBuckets() || !(dense.sampleRate > 0.0))
        return false;
    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly))
        return false;
    QDataStream out(&f);
    out.setVersion(QDataStream::Qt_6_0);
    out << QByteArray(kMagic) << fileSize << dense.sampleRate << quint32(dense.peak.size());
    for (float v : dense.peak)
        out << v;
    return f.commit();
}

bool AudioPeaks::decodeDense(const QString &path, qint64 fileSize, Dense &out) const {
    const QString ffmpeg = ffmpegPath();
    if (ffmpeg.isEmpty())
        return false;
    QProcess proc;
    proc.start(ffmpeg,
        {QStringLiteral("-v"), QStringLiteral("error"), QStringLiteral("-i"), path, QStringLiteral("-ac"),
            QStringLiteral("1"), QStringLiteral("-ar"), QString::number(kRate),
            // Decode at most 30min: lanes only show composition windows
            // (<= 60s) and an unbounded pipe would stall/OOM the UI
            // thread on hour-long files. Clips past the cap stay flat.
            QStringLiteral("-t"), QStringLiteral("1800"), QStringLiteral("-f"), QStringLiteral("f32le"),
            QStringLiteral("-")});
    if (!proc.waitForStarted(10000))
        return false;
    // Pump stdout while decoding: readAll-after-finish deadlocks once
    // output exceeds the pipe buffer, freezing the UI thread.
    QByteArray raw;
    QElapsedTimer watch;
    watch.start();
    while (proc.state() != QProcess::NotRunning) {
        if (watch.elapsed() > kDecodeTimeoutMs) {
            proc.kill();
            proc.waitForFinished(5000);
            return false;
        }
        proc.waitForReadyRead(250);
        raw += proc.readAllStandardOutput();
    }
    raw += proc.readAllStandardOutput();
    if (proc.exitCode() != 0)
        return false;
    // 64-bit counts: a 140s file holds 1.1M samples and
    // total * buckets overflows 32-bit int (the select-audio crash).
    const qsizetype total = raw.size() / 4;
    if (total <= 0)
        return false;
    const float *samples = reinterpret_cast<const float *>(raw.constData());
    QVector<float> peak;
    peak.reserve(denseBuckets());
    float fileMax = 0.0f;
    for (int b = 0; b < denseBuckets(); ++b) {
        // Fractional edges keep every bucket uniformly wide; a
        // truncated per-bucket count would starve early buckets and
        // leave the last one holding the whole remainder.
        const qsizetype lo = total * b / denseBuckets();
        const qsizetype hi = total * (b + 1) / denseBuckets();
        float m = 0.0f;
        for (qsizetype i = lo; i < hi; ++i) {
            const float v = samples[i];
            if (!qIsFinite(v))
                continue;
            m = qMax(m, qAbs(v));
        }
        peak.append(m);
        fileMax = qMax(fileMax, m);
    }
    // Normalize to the file max so quiet recordings still draw a
    // legible wave; pure silence stays flat at zero.
    if (fileMax > 0.0f) {
        for (float &v : peak)
            v = qBound(0.0f, v / fileMax, 1.0f);
    }
    // Buckets per second of source audio: slicing maps clip
    // offset/duration onto the dense array through this rate.
    out.sampleRate = double(denseBuckets()) / (double(total) / kRate);
    out.fileSize = fileSize;
    out.peak = peak;
    return true;
}
