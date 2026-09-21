#pragma once

#include <QMap>
#include <QString>
#include <QVariantList>
#include <QVector>

// AudioPeaks: zoom-adaptive waveform magnitudes for timeline lanes.
//
// Ownership: pure helpers plus a memoizing instance held by
// LibraryStore (audio blobs never move under a name, so dense peaks
// cache by blob name for the process lifetime).
// Source: decodes with system ffmpeg (mono 8kHz f32le); missing
// binaries, missing blobs and decode failures all yield an empty
// list so lanes fall back to the plain bar.
// Storage: one `<blob>.peaks` sidecar per blob in the audio dir
// (magic + source size + rate + dense floats, atomic write). Blobs
// are uuid-named and content-immutable, so a size match validates;
// mismatches re-decode. .totm bundles never pack sidecars (derivable,
// recomputed lazily) and the orphan sweep owns their lifecycle.
// Threading: main thread only; a worst-case decode (60s file) reads
// under 2MB and memoizes, so lane paints stay cheap.
class AudioPeaks {
public:
    // Magnitudes 0..1 over [offsetSec, offsetSec + windowSec] of the
    // file, downsampled to exactly `buckets` entries (clamped
    // 1..2048). Empty when anything is unknown or undecodable.
    QVariantList peaksFor(const QString &audioDir, const QString &name, int buckets, double offsetSec,
        double windowSec);

private:
    struct Dense {
        double sampleRate = 8000.0;
        qint64 fileSize = 0;
        QVector<float> peak;
    };

    static int denseBuckets() { return 2048; }
    static QString sidecarFor(const QString &audioDir, const QString &name);
    static bool isSafeName(const QString &name);
    static QString ffmpegPath();

    bool denseFor(const QString &audioDir, const QString &name, Dense &out);
    bool loadSidecar(const QString &path, qint64 fileSize, Dense &out) const;
    bool saveSidecar(const QString &path, qint64 fileSize, const Dense &dense) const;
    bool decodeDense(const QString &path, qint64 fileSize, Dense &out) const;

    QMap<QString, Dense> m_cache;
};
