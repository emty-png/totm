#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// PluginStore: QML-only plugin registry with permission-gated file URLs.
//
// Ownership: all plugin discovery, manifest validation, and grant
// persistence live here. Plugin QML must never read files directly; it
// loads UI through pluginFileUrl() and stores state via get/setValue().
// Storage: <AppData>/totm/plugins/<id>/manifest.json + main.qml per
//   plugin (folder drop-in), grants + per-plugin KV in
//   <AppData>/totm/plugins.json (atomic QSaveFile, corrupt archived).
// Threading: main thread only. scan() is synchronous and cheap (a few
// small JSON + import scans).
// Failure model: invalid manifests disable that plugin with lastError set;
// one bad plugin never blocks the rest. Errors surface via lastError.
// Binding model: pluginList/pendingPlugin are wholesale snapshots for
// Repeater/Loader use; changes emit pluginsChanged/pendingChanged.
// Sandbox: static import + identifier scan rejects Dialogs,
// StandardPaths, Multimedia, XHR/fetch, WorkerScript, LocalStorage, and
// direct LibraryStore/VideoExporter/SettingsStore access so plugins go
// through the gated PluginStore API. Remote transport is additionally
// denied engine-wide (see PluginNetworkGuard), so dodging the text scan
// still cannot exfiltrate or fetch remote code.
struct PluginManifest {
    QString id;
    QString name;
    QString version;
    QString author;
    QString description;
    QString entry = QStringLiteral("main.qml");
    QString tier = QStringLiteral("standard");
    QVariantList toolbarTools;
    QVariantList designSections;
    QVariantList canvasOverlays;
    QString fullOverlay;
    QStringList permissions;
    QVariantMap permissionReasons;
};

class PluginStore : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // Each row: {id, name, version, author, description, tier, enabled,
    // granted:[...], requested:[...], error, hasToolbar, hasSections,
    // hasOverlay, hasFullOverlay}.
    Q_PROPERTY(QVariantList pluginList READ pluginList NOTIFY pluginsChanged)
    // Pending approval: {id, name, version, author, description,
    // requested:[{id, title, reason}], granted:[...]} or {} when none.
    Q_PROPERTY(QVariantMap pendingPlugin READ pendingPlugin NOTIFY pendingChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    static PluginStore *create(QQmlEngine *engine, QJSEngine *scriptEngine);
    explicit PluginStore(QObject *parent = nullptr);

    QVariantList pluginList() const;
    QVariantMap pendingPlugin() const;
    QString lastError() const;
    Q_INVOKABLE void clearError();

    // Discovery. Scans <AppData>/totm/plugins/*/manifest.json, validates,
    // and queues the first new plugin for approval. Safe to call often.
    Q_INVOKABLE void scan();
    Q_INVOKABLE bool hasPlugin(const QString &id) const;
    Q_INVOKABLE QVariantMap plugin(const QString &id) const;
    // Folder drop-in location, created on demand. Shown in the manager
    // empty state so users know where to copy plugin folders.
    Q_INVOKABLE QString pluginsDir();

    // Lifecycle. New plugins start disabled until granted via the
    // permission popup. setEnabled(true) on a plugin with missing grants
    // reopens approval instead of enabling.
    Q_INVOKABLE bool setEnabled(const QString &id, bool enabled);
    Q_INVOKABLE void requestPermissions(const QString &id);
    // Persist the user's per-permission choice. Empty entries mean denied;
    // the popup warns those may break the plugin.
    Q_INVOKABLE bool grantPending(const QVariantList &granted);
    Q_INVOKABLE void dismissPending();

    // Gating. QML slots and mediated actions must check this first.
    Q_INVOKABLE bool hasPermission(const QString &id, const QString &permission) const;
    // Opens PLUG_IN.html (the maker guide) in the default browser.
    // Looks next to the install first, then beside a dev checkout.
    Q_INVOKABLE bool openGuide();
    // Human-readable permission catalog for the popup:
    // [{id, title, description}].
    Q_INVOKABLE QVariantList permissionCatalog() const;

    // Mediated file URL. Only relative .qml paths inside the plugin dir,
    // no "..", no absolute paths. Returns {} unless the plugin is enabled.
    // QML Loaders must use this, never raw file:// strings.
    Q_INVOKABLE QUrl pluginFileUrl(const QString &id, const QString &relativePath) const;

    // Slot models for Repeaters. Rows: {pluginId, pluginName, path, url}.
    // Only enabled plugins with ui.slots granted (fullOverlay rows need
    // ui.fullOverlay instead).
    Q_INVOKABLE QVariantList toolbarTools() const;
    Q_INVOKABLE QVariantList designSections() const;
    Q_INVOKABLE QVariantList canvasOverlays() const;
    Q_INVOKABLE QVariantList fullOverlays() const;

    // Scoped per-plugin KV storage (1MB cap per plugin). Lives in
    // plugins.json so plugins never touch QSettings or the filesystem.
    Q_INVOKABLE QVariant getValue(const QString &id, const QString &key, const QVariant &fallback = {}) const;
    Q_INVOKABLE bool setValue(const QString &id, const QString &key, const QVariant &value);
    Q_INVOKABLE bool removeValue(const QString &id, const QString &key);

    // Mediated media picks. Plugins never see file paths or dialogs:
    // requestImage/requestAudio emits pickRequested(pluginId, kind), the
    // host picker (PluginFilePicker) opens its own trusted FileDialog,
    // imports via LibraryStore, and hands back only the stored blob name
    // through commitPick -> picked(pluginId, kind, name). The plugin then
    // resolves display URLs via imageUrlFor/audioUrlFor, which only work
    // for names it picked itself. kind is "image" or "audio".
    Q_INVOKABLE bool requestImage(const QString &id);
    Q_INVOKABLE bool requestAudio(const QString &id);
    // Host only: record a finished pick. Returns false unless the plugin
    // is enabled with the matching images.use/audio.use grant.
    Q_INVOKABLE bool commitPick(const QString &id, const QString &kind, const QString &storedName);
    Q_INVOKABLE QUrl imageUrlFor(const QString &id, const QString &name) const;
    Q_INVOKABLE QUrl audioUrlFor(const QString &id, const QString &name) const;
    Q_INVOKABLE QVariantMap imageInfoFor(const QString &id, const QString &name) const;

    // Export suggestions (export.hook). A plugin may propose quality/fps;
    // the quality popup surfaces the first one with an Apply button. The
    // plugin never drives the exporter itself.
    Q_INVOKABLE bool suggestExport(const QString &id, const QString &quality, int fps);
    // {} when none. Row: {pluginId, pluginName, quality, fps}.
    Q_INVOKABLE QVariantMap exportSuggestion(const QString &id) const;
    Q_INVOKABLE bool clearExportSuggestion(const QString &id);

signals:
    void pluginsChanged();
    void pendingChanged();
    void lastErrorChanged();
    void pickRequested(const QString &pluginId, const QString &kind);
    void picked(const QString &pluginId, const QString &kind, const QString &storedName);

private:
    void load();
    bool persist();
    void rebuild();
    void setLastError(const QString &message);
    void setPending(const QVariantMap &pending);
    QString pluginsPath() const;
    QString statePath() const;
    bool isValidId(const QString &id) const;
    bool isSafeRelativeQml(const QString &path) const;
    // Static sandbox scan of one plugin's QML files. False + message on
    // forbidden imports or direct backend access.
    bool checkSandbox(const QString &dir, const PluginManifest &manifest, QString *error) const;
    bool checkOneQml(const QString &filePath, QString *error) const;
    QVariantMap manifestToRow(const PluginManifest &manifest, const QString &error) const;
    QVariantMap buildPending(const PluginManifest &manifest) const;
    int findManifest(const QString &id) const;
    // Library blob dir shared with LibraryStore (<libraryDir>/images or
    // /audio). Duplicated here (not coupled) so plugins resolve display
    // URLs without touching LibraryStore or raw paths.
    QString blobDir(const QString &kind) const;
    bool isSafeBlobName(const QString &name) const;
    bool canUseBlobs(const QString &id, const QString &kind) const;
    QStringList pickedBlobs(const QString &id, const QString &kind) const;

    QList<PluginManifest> m_manifests;
    // Persisted per plugin id: {enabled:bool, granted:[...]}.
    QVariantMap m_states;
    // Persisted per plugin id: {key:value}.
    QVariantMap m_storage;
    QVariantList m_pluginList;
    QVariantMap m_pending;
    QString m_lastError;
    QFileSystemWatcher m_watcher;
    bool m_loaded = false;
};
