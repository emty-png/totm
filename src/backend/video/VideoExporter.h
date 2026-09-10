#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QUrl>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// VideoExporter: scene snapshot to mp4 via a system ffmpeg binary.
//
// Ownership: QML snapshots the scene and calls startExport; this class owns
// the worker thread, the ffmpeg process and the temp file. QML performs no
// file IO except via saveAs after a native Save dialog.
// Pipeline: worker thread samples with AnimSampler, rasterizes with
// QPainter, and streams raw RGBA to ffmpeg stdin. Progress streams via
// progressChanged; completion via succeeded/failed/cancelled.
// Threading: startExport/cancel/saveAs run on the main thread. Rendering
// happens on a low-priority RenderThread; cancel is an atomic flag polled
// per frame and during pipe/finish waits, so no blocking call exceeds 500ms.
// Temp lifecycle: render writes totm-export-*.mp4 in the OS temp dir.
// Cancel/failure deletes the partial; saveAs copies the finished file to
// the user destination. Orphaned temps are swept at construction.
class VideoExporter : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool rendering READ rendering NOTIFY renderingChanged)
    Q_PROPERTY(float progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(int currentFrame READ currentFrame NOTIFY progressChanged)
    Q_PROPERTY(int totalFrames READ totalFrames NOTIFY progressChanged)
    Q_PROPERTY(QString qualityLabel READ qualityLabel NOTIFY progressChanged)
    Q_PROPERTY(QString tempPath READ tempPath NOTIFY finishedChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    static VideoExporter *create(QQmlEngine *engine, QJSEngine *scriptEngine);
    explicit VideoExporter(QObject *parent = nullptr);
    ~VideoExporter() override;

    bool rendering() const;
    float progress() const;
    int currentFrame() const;
    int totalFrames() const;
    QString qualityLabel() const;
    QString tempPath() const;
    QString lastError() const;

    // Starts a render. quality: "sd"|"hd"|"4k" (default hd); fps: 30|60
    // (other values coerce to 30); performance: "slow"|"normal"|"fast".
    // qualityLabel reads "Rendering <design> <quality><fps>". Returns false
    // when already rendering, the scene is empty, or ffmpeg is missing.
    Q_INVOKABLE bool startExport(const QVariantMap &scene, const QString &quality, int fps,
        const QString &performance, const QString &designName);
    // Requests cancellation; the worker deletes the partial and emits cancelled().
    Q_INVOKABLE void cancel();
    // Copies the finished temp file to destination (appends .mp4 when
    // missing). Returns false when no finished render exists.
    Q_INVOKABLE bool saveAs(const QUrl &destination);
    Q_INVOKABLE void clearError();
    // Empty when no ffmpeg binary is on PATH.
    Q_INVOKABLE static QString ffmpegPath();

signals:
    void renderingChanged();
    void progressChanged();
    void finishedChanged();
    void lastErrorChanged();
    void succeeded();
    void failed();
    void cancelled();

private:
    void setRendering(bool rendering);
    void setProgress(int current, int total);
    void setLastError(const QString &message);
    void onWorkerFinished(const QString &tempPath, const QString &error, bool wasCancelled);

    bool m_rendering = false;
    int m_currentFrame = 0;
    int m_totalFrames = 0;
    QString m_qualityLabel;
    QString m_tempPath;
    QString m_lastError;

    class RenderThread;
    RenderThread *m_thread = nullptr;
};
