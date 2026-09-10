#pragma once

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

class LibraryStore : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // QML snapshots. workspaceList rows: {workspaceId, name, isDefault,
    // createdAt, designCount}. designList rows: {designId, workspaceId,
    // name, createdAt, updatedAt, starred, scene}.
    Q_PROPERTY(QVariantList workspaceList READ workspaceList NOTIFY libraryChanged)
    Q_PROPERTY(QVariantList designList READ designList NOTIFY libraryChanged)
    Q_PROPERTY(QString defaultWorkspaceId READ defaultWorkspaceId NOTIFY libraryChanged)
    Q_PROPERTY(QString libraryPath READ libraryPath CONSTANT)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    static LibraryStore *create(QQmlEngine *engine, QJSEngine *scriptEngine);
    explicit LibraryStore(QObject *parent = nullptr);

    Q_INVOKABLE void clearError();
    QVariantList workspaceList() const;
    QVariantList designList() const;
    QString defaultWorkspaceId() const;
    QString libraryPath() const;
    QString lastError() const;

    // Workspaces. Names are trimmed to 120 chars with fallback applied.
    // deleteWorkspace rejects the Default workspace and re-homes its
    // designs to Default instead of deleting them.
    Q_INVOKABLE QString createWorkspace(const QString &name);
    Q_INVOKABLE bool renameWorkspace(const QString &id, const QString &name);
    Q_INVOKABLE bool deleteWorkspace(const QString &id);

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
    Q_INVOKABLE bool hasImage(const QString &name) const;
    Q_INVOKABLE quint64 imagesDiskUsage() const;
    Q_INVOKABLE int imageCount() const;

    // Audio blobs. Same sidecar pattern as images: files copied into
    // <libraryDir>/audio/, clips store the file name only. Import
    // allowlist is MP3/WAV/OGG/FLAC; anything else is rejected loudly.
    Q_INVOKABLE QString importAudio(const QUrl &source);
    Q_INVOKABLE QUrl audioUrl(const QString &name) const;
    Q_INVOKABLE bool hasAudio(const QString &name) const;
    Q_INVOKABLE quint64 audioDiskUsage() const;
    Q_INVOKABLE int audioCount() const;

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
    // Delete audio blobs no scene references. Startup only, same
    // reasoning as the image sweep.
    void sweepOrphanAudio();
    // Audio blob directory (<libraryDir>/audio). Created on demand.
    QString audioDir() const;
    // Stored file name guard: uuid + safe suffix, no separators.
    bool isSafeAudioName(const QString &name) const;
    // Image blob directory (<libraryDir>/images). Created on demand.
    QString imagesDir() const;
    // Stored file name guard: uuid + safe suffix, no separators.
    bool isSafeImageName(const QString &name) const;

    QList<WorkspaceEntry> m_workspaceEntries;
    QList<DesignEntry> m_designEntries;
    QVariantList m_workspaceList;
    QVariantList m_designList;
    QString m_defaultWorkspaceId;
    QString m_lastError;
    // Held for the process lifetime; warns on contention, last-writer-wins.
    QLockFile m_lock;
    bool m_loaded = false;
};
