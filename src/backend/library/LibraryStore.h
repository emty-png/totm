#pragma once

#include <QDateTime>
#include <QLockFile>
#include <QObject>
#include <QQmlEngine>
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
// Storage: single JSON document at <AppData>/totm/library.json.
//   { version, workspaces: [{id, name, isDefault, createdAt}],
//     designs: [{id, workspaceId, name, createdAt, updatedAt, starred, scene}] }
//   scene: { version, sceneWidth, sceneHeight, sceneColor, nodes, anim }
//   Nodes use the QML snapshot shape so restore needs no translation.
//   The anim blob is opaque preset data consumed by the video exporter.
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
    Q_INVOKABLE QString importImage(const QUrl &source);
    Q_INVOKABLE QUrl imageUrl(const QString &name) const;
    Q_INVOKABLE QVariantMap imageInfo(const QString &name) const;
    Q_INVOKABLE bool hasImage(const QString &name) const;

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
