#pragma once

#include <QCache>
#include <QDateTime>
#include <QLockFile>
#include <QObject>
#include <QQmlEngine>
#include <QSet>
#include <QString>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

#include "AudioPeaks.h"

// LibraryStore: persistent workspace/design library.
//
// Ownership: all file IO lives here. QML must not read/write files
// directly; it calls the Q_INVOKABLE mutators below and binds to the
// snapshot lists.
// Storage: index at <AppData>/totm/library.json plus one file per
//   design at <AppData>/totm/designs/<designId>.json, so an autosave
//   writes a single scene instead of the whole library.
//   library.json: { version, workspaces: [{id, name, isDefault,
//     createdAt}], designs: [{id, workspaceId, name, createdAt,
//     updatedAt, starred}] } (metadata only, never scenes).
//   designs/<id>.json: { version, scene }.
//   scene: { version, sceneWidth, sceneHeight, sceneColor, nodes, anim }
//   Nodes use the QML snapshot shape so restore needs no translation.
//   The anim blob is opaque preset data consumed by the video exporter.
//   In memory each entry keeps its scene mirrored, so snapshots and
//   previews never touch disk; the files are the durable copy.
//   Pre-1.0 cutover, no upgrade path: indexes written by older builds
//   may still carry embedded scenes, which are ignored (those designs
//   load as fresh defaults and the next index write drops the keys).
// Threading: main thread only. All mutators are synchronous.
// Failure model: writes are atomic (QSaveFile). A corrupt file is archived
//   to library.corrupt.<timestamp>.json and replaced with a fresh Default
//   workspace, so startup never blocks on bad disk state. Errors surface
//   via lastError/lastErrorChanged; mutators return false/{} on failure.
// Binding model: workspaceList/designList are plain-list snapshots rebuilt
//   wholesale per change and exposed via libraryChanged for Repeater use.
struct WorkspaceEntry {
    QString id;
    QString name;
    bool isDefault = false;
    QString createdAt;
};

struct DesignEntry {
    QString id;
    QString workspaceId;
    QString name;
    QString createdAt;
    QString updatedAt;
    bool starred = false;
    QVariantMap scene;
};

// Persistent asset (reusable component). Payload is plain data:
// {nodes: [...snapshots...], clips: [...anim clips...]}. Import
// creates detached copies with fresh uids/ids, so assets never alias
// live nodes. Files live in <libraryDir>/assets/<id>.json.
struct AssetEntry {
    QString id;
    QString name;
    QString createdAt;
    QString updatedAt;
    QVariantMap payload;
};

class LibraryStore : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // QML snapshots. workspaceList rows: {workspaceId, name, isDefault,
    // createdAt, designCount}. designList rows: {designId, workspaceId,
    // name, createdAt, updatedAt, starred, scene}. assetList rows:
    // {assetId, name, createdAt, updatedAt, payload}.
    Q_PROPERTY(QVariantList workspaceList READ workspaceList NOTIFY libraryChanged)
    Q_PROPERTY(QVariantList designList READ designList NOTIFY libraryChanged)
    Q_PROPERTY(QVariantList assetList READ assetList NOTIFY libraryChanged)
    Q_PROPERTY(QString defaultWorkspaceId READ defaultWorkspaceId NOTIFY libraryChanged)
    Q_PROPERTY(QString libraryPath READ libraryPath CONSTANT)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    static LibraryStore *create(QQmlEngine *engine, QJSEngine *scriptEngine);
    explicit LibraryStore(QObject *parent = nullptr);

    Q_INVOKABLE void clearError();
    QVariantList workspaceList() const;
    QVariantList designList() const;
    QVariantList assetList() const;
    QString defaultWorkspaceId() const;
    QString libraryPath() const;
    QString lastError() const;

    // Workspaces. Names are trimmed to 120 chars with fallback applied.
    // deleteWorkspace rejects the Default workspace and re-homes its
    // designs to Default instead of deleting them.
    // deleteWorkspaceAndDesigns rejects Default and deletes the
    // workspace together with all designs inside it (scene files
    // removed best-effort). QML closes open tabs first.
    Q_INVOKABLE QString createWorkspace(const QString &name);
    Q_INVOKABLE bool renameWorkspace(const QString &id, const QString &name);
    Q_INVOKABLE bool deleteWorkspace(const QString &id);
    Q_INVOKABLE bool deleteWorkspaceAndDesigns(const QString &id);
    // Reorder: moves the workspace to toIndex (clamped). Order is
    // insertion/persisted array order; Default is not pinned.
    Q_INVOKABLE bool moveWorkspace(const QString &id, int toIndex);

    // Designs. createDesign falls back to the Default workspace when the
    // target is unknown. saveScene normalizes keys via entryToScene and
    // stamps updatedAt. loadScene/design return {} when the id is unknown.
    Q_INVOKABLE QString createDesign(const QString &workspaceId, const QString &name);
    Q_INVOKABLE bool renameDesign(const QString &id, const QString &name);
    Q_INVOKABLE bool deleteDesign(const QString &id);
    Q_INVOKABLE bool moveDesign(const QString &id, const QString &workspaceId);
    Q_INVOKABLE bool setStarred(const QString &id, bool starred);
    Q_INVOKABLE bool toggleStarred(const QString &id);
    Q_INVOKABLE bool saveScene(const QString &designId, const QVariantMap &scene);
    Q_INVOKABLE QVariantMap loadScene(const QString &designId) const;
    Q_INVOKABLE QVariantMap design(const QString &id) const;
    Q_INVOKABLE bool hasDesign(const QString &id) const;
    Q_INVOKABLE int designCount(const QString &workspaceId) const;
    Q_INVOKABLE QString workspaceName(const QString &id) const;
    Q_INVOKABLE bool isDefaultWorkspace(const QString &id) const;

    // Images. Files are copied into <libraryDir>/images/ and nodes store
    // the file name only, so designs stay portable offline.
    // importImage copies a local file and returns its stored name ("" on
    // failure). imageUrl resolves a stored name to a file url for Image
    // sources. imageInfo reports {name, width, height} (0 when unknown).
    // Unreferenced blobs are swept at startup; imagesDiskUsage/imageCount
    // report the live footprint for a future storage UI.
    Q_INVOKABLE QString importImage(const QUrl &source);
    Q_INVOKABLE QUrl imageUrl(const QString &name) const;
    Q_INVOKABLE QVariantMap imageInfo(const QString &name) const;
    // System clipboard reads for drag-drop/paste parity. clipboardFileUrls
    // lists pasted/copied local files ("" entries dropped); clipboardHasImage
    // reports raw pixel data (screenshots, browser copies);
    // pasteClipboardImage stores that pixel data as a PNG blob and returns
    // its name ("" when the clipboard holds no image). Inbound only.
    Q_INVOKABLE QStringList clipboardFileUrls() const;
    Q_INVOKABLE bool clipboardHasImage() const;
    Q_INVOKABLE QString pasteClipboardImage();
    // SVG vector import: parses an .svg file into editable pen data
    // ({ok, error, width, height, paths}) without storing a blob, so
    // icons land as shapes instead of flat images. Unconvertible files
    // report ok=false for the image-blob fallback.
    Q_INVOKABLE QVariantMap importSvgVectors(const QUrl &source);
    Q_INVOKABLE bool hasImage(const QString &name) const;
    Q_INVOKABLE quint64 imagesDiskUsage() const;
    Q_INVOKABLE int imageCount() const;

    // Audio blobs. Same sidecar pattern as images: files copied into
    // <libraryDir>/audio/, clips store the file name only. Import
    // allowlist is MP3/WAV/OGG/FLAC; anything else is rejected loudly.
    // audioPeaks returns 0..1 waveform magnitudes over the clip window
    // (exactly `buckets` entries for zoom-adaptive lanes, [] when
    // unknown); dense peaks decode once via ffmpeg and persist as a
    // `<blob>.peaks` sidecar owned by the orphan sweep, never packed
    // into .totm bundles.
    Q_INVOKABLE QString importAudio(const QUrl &source);
    Q_INVOKABLE QUrl audioUrl(const QString &name) const;
    Q_INVOKABLE bool hasAudio(const QString &name) const;
    Q_INVOKABLE quint64 audioDiskUsage() const;
    Q_INVOKABLE int audioCount() const;
    Q_INVOKABLE QVariantList audioPeaks(const QString &name, int buckets, double offset, double window);

    // Video blobs. Same sidecar pattern as images/audio: files are copied
    // into <libraryDir>/videos/ and nodes store the file name only, so
    // deleting/moving the original never breaks the design. Allowlist is
    // mp4/webm/mov/m4v/mkv (Qt Multimedia + ffmpeg both handle them).
    // importVideo copies a local file and returns its stored name ("" on
    // failure). normalizeVideoPath is the legacy entry point and now
    // copies as well (returns the stored blob name). videoUrl/hasVideo
    // resolve stored names; legacy absolute paths still resolve when the
    // file exists (old designs keep working until re-imported).
    // videoProbe parses a single `ffmpeg -i` stderr dump into {ok,
    // duration, width, height, hasAudio}. videosDiskUsage/videoCount
    // report the live footprint (peaks sidecars excluded from the count).
    Q_INVOKABLE QString importVideo(const QUrl &source);
    Q_INVOKABLE QString normalizeVideoPath(const QUrl &source);
    Q_INVOKABLE QUrl videoUrl(const QString &ref) const;
    Q_INVOKABLE bool hasVideo(const QString &ref) const;
    // Container probe for one stored video (or legacy absolute path):
    // parses a single `ffmpeg -i`
    // stderr dump (no decode, milliseconds) into {ok, duration,
    // width, height, hasAudio}. ok=false when the file is missing,
    // unparseable, or carries no video stream. Backend-independent, so
    // durations match export on every OS (unlike MediaPlayer probing
    // through OS backends). Replaces per-site MediaPlayer probes.
    Q_INVOKABLE QVariantMap videoProbe(const QString &ref) const;
    // Legacy linked-video count for one design's scene (groups included).
    // Only absolute-path refs count; stored blob names are packed into
    // .totm bundles so they never warn. Kept so old designs still warn
    // until their videos are re-imported as blobs.
    Q_INVOKABLE int linkedVideoCount(const QString &id) const;
    // Reveal a stored/legacy video in the OS file manager (folder of the
    // file, or the Movies folder when missing). False when nothing to show.
    Q_INVOKABLE bool revealVideo(const QString &ref) const;
    Q_INVOKABLE quint64 videosDiskUsage() const;
    Q_INVOKABLE int videoCount() const;

    // Project share: single-file .totm bundle (JSON with base64 blobs).
    // exportDesign writes name + normalized scene + referenced
    // image/audio/video blobs; importDesign validates, stores blobs under
    // fresh uuid names with scene refs remapped, creates the design,
    // returns its id ("" on failure with lastError set). QML drives both
    // via FileDialogs.
    // exportDesign refuses an existing destination unless overwrite is
    // set (QML confirms first via exportDestinationExists, which applies
    // the same .totm suffix rule so the probe never drifts from the write).
    Q_INVOKABLE bool exportDesign(
        const QString &id, const QUrl &destination, bool overwrite = false);
    Q_INVOKABLE bool exportDestinationExists(const QUrl &destination) const;
    Q_INVOKABLE QString importDesign(const QString &workspaceId, const QUrl &source);

    // Persistent assets (reusable components). createAsset stores a
    // detached payload {nodes, clips} and returns its id ("" on
    // failure). Payloads are plain snapshot data; import constructs
    // fresh uids/ids so assets never alias live nodes. Blobs stay
    // shared by name in the library dirs; sweeps keep asset refs alive.
    Q_INVOKABLE QString createAsset(const QString &name, const QVariantMap &payload);
    Q_INVOKABLE bool renameAsset(const QString &id, const QString &name);
    Q_INVOKABLE bool deleteAsset(const QString &id);
    Q_INVOKABLE QVariantMap loadAsset(const QString &id) const;
    Q_INVOKABLE bool hasAsset(const QString &id) const;

signals:
    void libraryChanged();
    void lastErrorChanged();

private:
    // load: read-once at construction; self-heals and rebuilds.
    // persist: serialize + atomic write; returns false and rebuilds on error.
    // rebuild: refresh QML snapshots from entries and emit libraryChanged.
    // installFreshDefault: reset entries to a single Default workspace.
    void load();
    bool persist();
    void rebuild();
    void installFreshDefault();
    void setLastError(const QString &message);
    // Linear lookup by id; -1 when absent.
    int findWorkspace(const QString &id) const;
    int findDesign(const QString &id) const;
    int findAsset(const QString &id) const;
    // Per-asset payload directory (<libraryDir>/assets). Created on demand.
    QString assetsDir() const;
    // Atomic write of one asset's payload file. False + lastError on failure.
    bool writeAssetFile(const QString &id, const QVariantMap &payload);
    // Normalized payload for one asset. Missing files yield empty
    // nodes/clips; corrupt files are archived aside like designs.
    QVariantMap readAssetFile(const QString &id);
    // Delete asset files with no matching index entry. Quiet.
    void sweepOrphanAssetFiles();
    // Blob names referenced by any in-memory asset payload, groups included.
    QSet<QString> referencedAssetImages() const;
    QSet<QString> referencedAssetVideos() const;
    // Owning directory for library.json + lock file. Falls back to
    // ~/.totm when the platform location is unavailable.
    QString libraryDir() const;
    // Per-design scene directory (<libraryDir>/designs). Created on demand.
    QString designsDir() const;
    // Atomic write of one design's scene file. False + lastError on failure.
    bool writeDesignFile(const QString &id, const QVariantMap &scene);
    // Normalized scene for one design. Missing files yield defaults; a
    // corrupt file is archived aside and also yields defaults, so one bad
    // design never blocks the rest of the library.
    QVariantMap readDesignFile(const QString &id);
    // Delete design files with no matching index entry (crashed creates,
    // half-finished deletes). Quiet: best effort, no errors surfaced.
    void sweepOrphanDesignFiles();
    // Blob names referenced by any in-memory scene, groups included.
    QSet<QString> referencedImages() const;
    // Delete image blobs no scene references. Startup only: mid-session
    // the app-wide clipboard and per-tab undo can reference blobs no
    // saved scene points at yet, and both are empty at boot.
    void sweepOrphanImages();
    // Blob names referenced by any in-memory scene's audio clips.
    QSet<QString> referencedAudio() const;
    // Blob names referenced by any in-memory scene's video nodes (groups
    // included) plus audio clips pointing at video blobs (detached sound
    // shares the video file, so the sweep must keep it while either side
    // references it).
    QSet<QString> referencedVideos() const;
    // Delete video blobs no scene references (plus their .peaks
    // sidecars, and orphan sidecars whose blob is gone). Startup only,
    // same reasoning as the image sweep.
    void sweepOrphanVideos();
    // Delete audio blobs no scene references (plus their .peaks
    // sidecars, and orphan sidecars whose blob is gone). Startup only,
    // same reasoning as the image sweep.
    void sweepOrphanAudio();
    // Audio blob directory (<libraryDir>/audio). Created on demand.
    QString audioDir() const;
    // Stored file name guard: uuid + safe suffix, no separators.
    bool isSafeAudioName(const QString &name) const;
    // Image blob directory (<libraryDir>/images). Created on demand.
    QString imagesDir() const;
    // Stored file name guard: uuid + safe suffix, no separators.
    bool isSafeImageName(const QString &name) const;
    // Video blob directory (<libraryDir>/videos). Created on demand.
    QString videosDir() const;
    // Stored file name guard: uuid + safe suffix, no separators.
    bool isSafeVideoName(const QString &name) const;
    // Resolve a stored video blob name or legacy absolute path to an
    // absolute filesystem path ("" when missing). Blobs win; absolute
    // paths are honored only when the file still exists.
    QString resolveVideoFile(const QString &ref) const;
    // Resolve an audio clip source to an absolute path: audio/ blobs,
    // then video/ blobs (detached sound shares the video file), then
    // legacy absolute paths. "" when missing.
    QString resolveAudioFile(const QString &ref) const;

    QList<WorkspaceEntry> m_workspaceEntries;
    QList<DesignEntry> m_designEntries;
    QList<AssetEntry> m_assetEntries;
    QVariantList m_workspaceList;
    QVariantList m_designList;
    QVariantList m_assetList;
    QString m_defaultWorkspaceId;
    QString m_lastError;
    // Held for the process lifetime; warns on contention, last-writer-wins.
    QLockFile m_lock;
    bool m_loaded = false;
    // Waveform peaks for timeline lanes (memoized dense decode).
    AudioPeaks m_peaks;
    // Container probes for stored videos (memoized per path + mtime +
    // size, so placement, panel, relink and multi-select re-probes
    // share one ffmpeg spawn instead of one per call site).
    mutable QCache<QString, QVariantMap> m_videoProbes{64};
};
