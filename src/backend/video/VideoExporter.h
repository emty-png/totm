#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QUrl>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// Video export for totm: renders the scene snapshot (the same plain
// document the canvas previews) to mp4 via a system ffmpeg binary.
//
// Flow: QML snapshots fresh on every Export click (doc.snapshotScene,
// which rebases preview frames), calls startExport(scene, quality, fps,
// performance).
// Frames render in a worker thread with QPainter (ports of DocEasing,
// DocPathSample, DocAnimSample and ShapeGeometry) and stream as raw RGBA
// to ffmpeg's stdin. Progress streams live; cancel kills the encode and
// deletes the partial. On success QML opens a native Save dialog and
// calls saveAs(dest) to copy the temp file out (no QML-side file IO).
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

    // performance: "slow" | "normal" | "fast" (x264 preset + CRF).
    // qualityLabel reads "Rendering <design> <quality><fps>" (hd30).
    Q_INVOKABLE bool startExport(const QVariantMap &scene, const QString &quality, int fps,
        const QString &performance, const QString &designName);
    Q_INVOKABLE void cancel();
    // Copies the finished temp file to the user's chosen destination.
    Q_INVOKABLE bool saveAs(const QUrl &destination);
    Q_INVOKABLE void clearError();
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
