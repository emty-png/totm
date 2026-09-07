#pragma once

#include <QDateTime>
#include <QLockFile>
#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// On-disk library for totm, part of the future backend layer
// (video rendering will live beside this under src/).
//
// Single-file store: <AppData>/totm/library.json holding workspaces plus
// designs with their scenes embedded. Writes go through QSaveFile so a
// crash can never leave a half-written library behind; a corrupt file is
// moved aside to library.corrupt.<timestamp>.json and we start fresh with
// the indestructible Default workspace.
//
// QML reads plain lists (workspaceList/designList) instead of item
// models: Repeaters bind modelData off them, which stays reactive
// through libraryChanged and never hits delegate-scope quirks.
//
// Schema (version 1):
//   { version, workspaces: [{id, name, isDefault, createdAt}],
//     designs: [{id, workspaceId, name, createdAt, updatedAt, scene}] }
//   scene: { version, sceneWidth, sceneHeight, sceneColor, nodes: [...] }
//   nodes reuse the QML snapshotNode shape so QML can restore them
//   without translation.

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

    // Plain snapshots for Repeaters: [{workspaceId, name, isDefault,
    // createdAt, designCount}] and [{designId, workspaceId, name,
    // createdAt, updatedAt, starred, scene}]. Rebuilt wholesale on
    // every change.
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

    Q_INVOKABLE QString createWorkspace(const QString &name);
    Q_INVOKABLE bool renameWorkspace(const QString &id, const QString &name);
    // Refuses the Default workspace. Designs inside move to Default.
    Q_INVOKABLE bool deleteWorkspace(const QString &id);

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

signals:
    void libraryChanged();
    void lastErrorChanged();

private:
    void load();
    bool persist();
    void rebuild();
    void installFreshDefault();
    void setLastError(const QString &message);
    int findWorkspace(const QString &id) const;
    int findDesign(const QString &id) const;
    QString libraryDir() const;

    QList<WorkspaceEntry> m_workspaceEntries;
    QList<DesignEntry> m_designEntries;
    QVariantList m_workspaceList;
    QVariantList m_designList;
    QString m_defaultWorkspaceId;
    QString m_lastError;
    // Second-instance guard, held for the life of the store.
    QLockFile m_lock;
    bool m_loaded = false;
};
