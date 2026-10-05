#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// ComponentExporter: Per-component still export.
//
// Ownership: PNG rendering goes through FramePaint (the same raster
// the canvas preview and video export share), SVG through SvgPaint
// (same scene handling, vector-native paint); all file IO lives here.
// QML passes selected-top snapshots plus scales and only picks the
// destination folder; every name, suffix and byte is decided here so
// the plan and the write can never disagree (same rule as the .totm
// probe/write pair).
// Storage: PNG writes one file per (top x scale); SVG is
// resolution-independent so it writes one .svg per top (scales are
// ignored). A single file saves directly, several pack into a stored
// (uncompressed) zip. Stills only: scenes paint at base values, grain
// freezes at the passed frame (PNG; SVG skips raster-only effects).
// Failure model: writes are atomic (QSaveFile). Errors surface via
// lastError; mutators return false/{} on failure.
// Threading: main thread only. All calls are synchronous.
class ComponentExporter : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    // Non-blocking warning from the last export ("" when clean):
    // SVG-excluded videos and unembedded fonts. Failures use lastError.
    Q_PROPERTY(QString lastWarning READ lastWarning NOTIFY lastWarningChanged)

public:
    static ComponentExporter *create(QQmlEngine *engine, QJSEngine *scriptEngine);
    explicit ComponentExporter(QObject *parent = nullptr);

    QString lastError() const;
    Q_INVOKABLE void clearError();
    QString lastWarning() const;

    // Plan for (names x scales): {fileCount, suffix ("png"/"svg"/"zip"),
    // defaultName, files}. PNG names sanitize to layer-safe stems with
    // a @2x/@3x suffix per scale; SVG writes one file per top (scales
    // ignored, no @nx tag). Duplicates gain -1/-2. PNG scales keep
    // 1/2/3 only (anything else is ignored, empty means 1x).
    Q_INVOKABLE QVariantMap planExport(const QStringList &names, const QVariantList &scales,
        const QString &designName, const QString &format = QStringLiteral("png"));
    // Renders and writes the plan. Refuses an existing destination
    // unless overwrite is set (QML confirms first via
    // destinationExists, which applies the same suffix rule).
    // frameNo freezes animated grain on PNG (see Effects::grainFrameNo).
    Q_INVOKABLE bool exportSelection(const QVariantList &topNodes, const QStringList &names,
        const QVariantList &scales, const QString &designName, const QUrl &destination, bool overwrite, int frameNo,
        const QString &format = QStringLiteral("png"));
    Q_INVOKABLE bool destinationExists(const QUrl &destination, const QString &suffix) const;

    // Home-grid thumbnail for one library scene: renders once at tile
    // width through FramePaint (frozen grain, base values) and caches
    // the PNG under <AppData>/totm/thumbs keyed by design id + stamp,
    // returning its file URL ("" when the scene has nothing visible).
    // Cards show a plain Image over the scene-color rect instead of
    // live scene items, so heavy effect stacks cost one tile-scale
    // raster per content change instead of full-res CPU items per
    // rebuild. stamp should change with content (designs pass
    // updatedAt; templates a fixed id). tight renders union bounds
    // (template content fit) instead of the full scene rect.
    Q_INVOKABLE QString thumbnailFile(
        const QVariantMap &scene, const QString &designId, const QString &stamp, int targetW, bool tight);

signals:
    void lastErrorChanged();
    void lastWarningChanged();

private:
    struct Plan {
        QStringList files;
        bool zip = false;
        QString suffix = QStringLiteral("png");
        QString defaultName;
    };
    Plan makePlan(const QStringList &names, const QVariantList &scales, const QString &designName,
        const QString &format) const;
    void setLastError(const QString &message);
    void setLastWarning(const QString &message);

    QString m_lastError;
    QString m_lastWarning;
};
