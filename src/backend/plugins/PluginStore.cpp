#include "PluginStore.h"

#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>

namespace {
constexpr int kStateVersion = 1;
constexpr int kMaxIdLength = 64;
constexpr qint64 kMaxStorageBytes = 1024 * 1024;

QStringList kKnownPermissions = {
    QStringLiteral("doc.read"),
    QStringLiteral("doc.write"),
    QStringLiteral("library.read"),
    QStringLiteral("library.write"),
    QStringLiteral("images.use"),
    QStringLiteral("audio.use"),
    QStringLiteral("settings.read"),
    QStringLiteral("export.hook"),
    QStringLiteral("ui.slots"),
    QStringLiteral("ui.fullOverlay"),
    QStringLiteral("plugin.storage"),
};

QStringList kDefaultPermissions = {
    QStringLiteral("doc.read"),
    QStringLiteral("plugin.storage"),
    QStringLiteral("ui.slots"),
};

QVariantMap permissionMeta(const QString &id) {
    // Titles stay short for popup rows; descriptions explain the risk.
    static const QHash<QString, QVariantMap> catalog = {
        {QStringLiteral("doc.read"), {{"title", QObject::tr("Read canvas")}, {"description", QObject::tr("See selection, nodes and scene properties.")}}},
        {QStringLiteral("doc.write"), {{"title", QObject::tr("Edit canvas")}, {"description", QObject::tr("Move, add or restyle shapes. Undo still applies.")}}},
        {QStringLiteral("library.read"), {{"title", QObject::tr("Read library")}, {"description", QObject::tr("List workspaces and designs, load scenes.")}}},
        {QStringLiteral("library.write"), {{"title", QObject::tr("Modify library")}, {"description", QObject::tr("Create, rename or save designs. Can overwrite work.")}}},
        {QStringLiteral("images.use"), {{"title", QObject::tr("Use images")}, {"description", QObject::tr("Ask you to pick images; never sees file paths.")}}},
        {QStringLiteral("audio.use"), {{"title", QObject::tr("Use audio")}, {"description", QObject::tr("Ask you to pick audio; never sees file paths.")}}},
        {QStringLiteral("settings.read"), {{"title", QObject::tr("Read theme")}, {"description", QObject::tr("Follow dark/light theme only.")}}},
        {QStringLiteral("export.hook"), {{"title", QObject::tr("Suggest export")}, {"description", QObject::tr("Suggest quality/fps; cannot run ffmpeg itself.")}}},
        {QStringLiteral("ui.slots"), {{"title", QObject::tr("Add UI sections")}, {"description", QObject::tr("Add toolbar buttons and panel sections.")}}},
        {QStringLiteral("ui.fullOverlay"), {{"title", QObject::tr("Full overlay")}, {"description", QObject::tr("Draw over the whole editor. May break on updates.")}}},
        {QStringLiteral("plugin.storage"), {{"title", QObject::tr("Save settings")}, {"description", QObject::tr("Remember its own small settings inside the app.")}}},
    };
    QVariantMap meta = catalog.value(id);
    if (meta.isEmpty())
        meta = {{"title", id}, {"description", QObject::tr("App capability.")}};
    meta[QStringLiteral("id")] = id;
    return meta;
}

QStringList toStringList(const QVariantList &list) {
    QStringList out;
    for (const QVariant &v : list)
        out.append(v.toString());
    return out;
}

qint64 storageBytes(const QVariantMap &storage) {
    return QJsonDocument(QJsonObject::fromVariantMap(storage)).toJson(QJsonDocument::Compact).size();
}
} // namespace

PluginStore *PluginStore::create(QQmlEngine *engine, QJSEngine *scriptEngine) {
    Q_UNUSED(scriptEngine);
    auto *store = new PluginStore(engine);
    QJSEngine::setObjectOwnership(store, QJSEngine::CppOwnership);
    return store;
}

PluginStore::PluginStore(QObject *parent)
    : QObject(parent) {
    load();
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this](const QString &) {
        scan();
    });
}

QVariantList PluginStore::pluginList() const {
    return m_pluginList;
}

QVariantMap PluginStore::pendingPlugin() const {
    return m_pending;
}

QString PluginStore::lastError() const {
    return m_lastError;
}

void PluginStore::clearError() {
    setLastError(QString());
}

void PluginStore::scan() {
    QDir().mkpath(pluginsPath());
    if (!m_watcher.directories().contains(pluginsPath()))
        m_watcher.addPath(pluginsPath());

    QList<PluginManifest> found;
    const QDir dir(pluginsPath());
    for (const QFileInfo &info : dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        const QString manifestPath = info.absoluteFilePath() + QStringLiteral("/manifest.json");
        QFile file(manifestPath);
        if (!file.exists())
            continue;
        if (!file.open(QIODevice::ReadOnly))
            continue;
        QJsonParseError parseError;
        const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &parseError);
        const QJsonObject root = doc.object();
        if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
            setLastError(tr("Plugin \"%1\" has a broken manifest; skipped.").arg(info.fileName()));
            continue;
        }
        PluginManifest manifest;
        manifest.id = root.value(QStringLiteral("id")).toString().trimmed();
        manifest.name = root.value(QStringLiteral("name")).toString().trimmed();
        manifest.version = root.value(QStringLiteral("version")).toString().trimmed();
        manifest.author = root.value(QStringLiteral("author")).toString().trimmed();
        manifest.description = root.value(QStringLiteral("description")).toString().trimmed();
        manifest.entry = root.value(QStringLiteral("entry")).toString().trimmed();
        if (manifest.entry.isEmpty())
            manifest.entry = QStringLiteral("main.qml");
        manifest.tier = root.value(QStringLiteral("tier")).toString().trimmed();
        if (manifest.tier.isEmpty())
            manifest.tier = QStringLiteral("standard");

        const QJsonObject contributions = root.value(QStringLiteral("contributions")).toObject();
        for (const QVariant &v : contributions.value(QStringLiteral("toolbarTools")).toArray().toVariantList())
            manifest.toolbarTools.append(v.toString());
        for (const QVariant &v : contributions.value(QStringLiteral("designSections")).toArray().toVariantList())
            manifest.designSections.append(v.toString());
        for (const QVariant &v : contributions.value(QStringLiteral("canvasOverlays")).toArray().toVariantList())
            manifest.canvasOverlays.append(v.toString());
        manifest.fullOverlay = contributions.value(QStringLiteral("fullOverlay")).toString().trimmed();

        for (const QVariant &v : root.value(QStringLiteral("permissions")).toArray().toVariantList())
            manifest.permissions.append(v.toString().trimmed());
        manifest.permissionReasons = root.value(QStringLiteral("permissionReasons")).toObject().toVariantMap();

        // Contract: manifests must identify the plugin and stay inside
        // their own folder. Anything else is disabled, never half-loaded.
        QString error;
        if (!isValidId(manifest.id) || manifest.id != info.fileName()) {
            error = tr("Folder \"%1\" must match a valid plugin id.").arg(info.fileName());
        } else if (manifest.name.isEmpty()) {
            error = tr("Plugin \"%1\" needs a name.").arg(manifest.id);
        } else if (manifest.tier != QStringLiteral("standard") && manifest.tier != QStringLiteral("advanced")) {
            error = tr("Plugin \"%1\" has an unknown tier.").arg(manifest.id);
        } else if (!isSafeRelativeQml(manifest.entry)
            || !QFile::exists(info.absoluteFilePath() + QStringLiteral("/") + manifest.entry)) {
            error = tr("Plugin \"%1\" entry is missing.").arg(manifest.id);
        } else {
            for (const QString &perm : manifest.permissions) {
                if (!kKnownPermissions.contains(perm)) {
                    error = tr("Plugin \"%1\" asks for unknown permission \"%2\".").arg(manifest.id, perm);
                    break;
                }
            }
        }
        if (error.isEmpty() && !manifest.fullOverlay.isEmpty()
            && (manifest.tier != QStringLiteral("advanced")
                || !manifest.permissions.contains(QStringLiteral("ui.fullOverlay")))) {
            error = tr("Plugin \"%1\" full overlay needs the advanced tier and permission.").arg(manifest.id);
        }
        if (error.isEmpty()) {
            QStringList allFiles = {manifest.entry};
            for (const QVariant &v : manifest.toolbarTools)
                allFiles.append(v.toString());
            for (const QVariant &v : manifest.designSections)
                allFiles.append(v.toString());
            for (const QVariant &v : manifest.canvasOverlays)
                allFiles.append(v.toString());
            if (!manifest.fullOverlay.isEmpty())
                allFiles.append(manifest.fullOverlay);
            for (const QString &rel : allFiles) {
                if (!isSafeRelativeQml(rel)
                    || !QFile::exists(info.absoluteFilePath() + QStringLiteral("/") + rel)) {
                    error = tr("Plugin \"%1\" file \"%2\" is missing.").arg(manifest.id, rel);
                    break;
                }
            }
        }
        if (error.isEmpty() && !checkSandbox(info.absoluteFilePath(), manifest, &error)) {
            // checkSandbox explains which import or identifier is forbidden.
        }
        if (!error.isEmpty()) {
            PluginManifest broken;
            broken.id = isValidId(manifest.id) ? manifest.id : info.fileName();
            broken.name = manifest.name.isEmpty() ? broken.id : manifest.name;
            broken.description = manifest.description;
            broken.tier = manifest.tier.isEmpty() ? QStringLiteral("standard") : manifest.tier;
            found.append(broken);
            // Remember the error on the row; keep scanning the rest.
            m_states[broken.id + QStringLiteral(".error")] = error;
            setLastError(error);
            continue;
        }
        m_states.remove(manifest.id + QStringLiteral(".error"));
        found.append(manifest);
    }

    m_manifests = found;
    // New plugins start disabled; the first scan queues approval so the
    // user sees exactly what each plugin wants before it can run.
    bool healed = false;
    for (const PluginManifest &manifest : m_manifests) {
        if (!m_states.contains(manifest.id)) {
            m_states[manifest.id] = QVariantMap{
                {QStringLiteral("enabled"), false},
                {QStringLiteral("granted"), QVariantList()},
                {QStringLiteral("seen"), true},
            };
            healed = true;
            if (m_pending.isEmpty())
                setPending(buildPending(manifest));
        }
    }
    if (healed)
        persist();
    rebuild();
}

bool PluginStore::hasPlugin(const QString &id) const {
    return findManifest(id) >= 0;
}

QVariantMap PluginStore::plugin(const QString &id) const {
    for (const QVariant &row : m_pluginList) {
        if (row.toMap().value(QStringLiteral("id")).toString() == id)
            return row.toMap();
    }
    return {};
}

bool PluginStore::setEnabled(const QString &id, bool enabled) {
    const int at = findManifest(id);
    if (at < 0)
        return false;
    QVariantMap state = m_states.value(id).toMap();
    if (enabled) {
        // Enabling with missing grants reopens approval instead of
        // silently running with less than requested.
        const QStringList granted = toStringList(state.value(QStringLiteral("granted")).toList());
        const QStringList requested = m_manifests.at(at).permissions;
        bool missing = false;
        for (const QString &perm : requested) {
            if (!granted.contains(perm)) {
                missing = true;
                break;
            }
        }
        if (missing) {
            requestPermissions(id);
            return true;
        }
    }
    state[QStringLiteral("enabled")] = enabled;
    m_states[id] = state;
    if (!persist())
        return false;
    rebuild();
    return true;
}

void PluginStore::requestPermissions(const QString &id) {
    const int at = findManifest(id);
    if (at < 0)
        return;
    setPending(buildPending(m_manifests.at(at)));
}

bool PluginStore::grantPending(const QVariantList &granted) {
    const QString id = m_pending.value(QStringLiteral("id")).toString();
    if (id.isEmpty() || findManifest(id) < 0)
        return false;
    const QStringList requested = m_manifests.at(findManifest(id)).permissions;
    QStringList kept;
    for (const QVariant &v : granted) {
        const QString perm = v.toString();
        if (requested.contains(perm) && kKnownPermissions.contains(perm) && !kept.contains(perm))
            kept.append(perm);
    }
    QVariantMap state = m_states.value(id).toMap();
    state[QStringLiteral("granted")] = QVariantList(kept.begin(), kept.end());
    state[QStringLiteral("enabled")] = true;
    m_states[id] = state;
    setPending({});
    if (!persist())
        return false;
    rebuild();
    return true;
}

void PluginStore::dismissPending() {
    setPending({});
}

bool PluginStore::hasPermission(const QString &id, const QString &permission) const {
    const QVariantMap state = m_states.value(id).toMap();
    if (!state.value(QStringLiteral("enabled"), false).toBool())
        return false;
    return toStringList(state.value(QStringLiteral("granted")).toList()).contains(permission);
}

bool PluginStore::openGuide() {
    // Candidates: installed doc dir beside the binary first, then the
    // file in a dev checkout (build/<preset>/src -> src/docs).
    const QString exeDir = QCoreApplication::applicationDirPath();
    const QStringList candidates = {
        exeDir + QStringLiteral("/../share/doc/totm/PLUG_IN.html"),
        exeDir + QStringLiteral("/../Resources/PLUG_IN.html"),
        exeDir + QStringLiteral("/../../../src/docs/PLUG_IN.html"),
    };
    for (const QString &candidate : candidates) {
        const QString path = QDir::cleanPath(candidate);
        if (QFile::exists(path))
            return QDesktopServices::openUrl(QUrl::fromLocalFile(path));
    }
    setLastError(tr("Could not find PLUG_IN.html next to the install."));
    return false;
}

QVariantList PluginStore::permissionCatalog() const {
    QVariantList out;
    for (const QString &id : kKnownPermissions)
        out.append(permissionMeta(id));
    return out;
}

QUrl PluginStore::pluginFileUrl(const QString &id, const QString &relativePath) const {
    const int at = findManifest(id);
    if (at < 0 || !isSafeRelativeQml(relativePath))
        return {};
    const QVariantMap state = m_states.value(id).toMap();
    if (!state.value(QStringLiteral("enabled"), false).toBool())
        return {};
    const QString full = pluginsPath() + QStringLiteral("/") + id + QStringLiteral("/") + relativePath;
    if (!QFile::exists(full))
        return {};
    return QUrl::fromLocalFile(full);
}

QVariantList PluginStore::toolbarTools() const {
    QVariantList out;
    for (const PluginManifest &manifest : m_manifests) {
        if (!hasPermission(manifest.id, QStringLiteral("ui.slots")))
            continue;
        for (const QVariant &v : manifest.toolbarTools) {
            const QString rel = v.toString();
            const QUrl url = pluginFileUrl(manifest.id, rel);
            if (url.isEmpty())
                continue;
            out.append(QVariantMap{
                {QStringLiteral("pluginId"), manifest.id},
                {QStringLiteral("pluginName"), manifest.name},
                {QStringLiteral("path"), rel},
                {QStringLiteral("url"), url},
            });
        }
    }
    return out;
}

QVariantList PluginStore::designSections() const {
    QVariantList out;
    for (const PluginManifest &manifest : m_manifests) {
        if (!hasPermission(manifest.id, QStringLiteral("ui.slots")))
            continue;
        for (const QVariant &v : manifest.designSections) {
            const QString rel = v.toString();
            const QUrl url = pluginFileUrl(manifest.id, rel);
            if (url.isEmpty())
                continue;
            out.append(QVariantMap{
                {QStringLiteral("pluginId"), manifest.id},
                {QStringLiteral("pluginName"), manifest.name},
                {QStringLiteral("path"), rel},
                {QStringLiteral("url"), url},
            });
        }
    }
    return out;
}

QVariantList PluginStore::canvasOverlays() const {
    QVariantList out;
    for (const PluginManifest &manifest : m_manifests) {
        if (!hasPermission(manifest.id, QStringLiteral("ui.slots")))
            continue;
        for (const QVariant &v : manifest.canvasOverlays) {
            const QString rel = v.toString();
            const QUrl url = pluginFileUrl(manifest.id, rel);
            if (url.isEmpty())
                continue;
            out.append(QVariantMap{
                {QStringLiteral("pluginId"), manifest.id},
                {QStringLiteral("pluginName"), manifest.name},
                {QStringLiteral("path"), rel},
                {QStringLiteral("url"), url},
            });
        }
    }
    return out;
}

QVariantList PluginStore::fullOverlays() const {
    QVariantList out;
    for (const PluginManifest &manifest : m_manifests) {
        if (manifest.fullOverlay.isEmpty()
            || !hasPermission(manifest.id, QStringLiteral("ui.fullOverlay")))
            continue;
        const QUrl url = pluginFileUrl(manifest.id, manifest.fullOverlay);
        if (url.isEmpty())
            continue;
        out.append(QVariantMap{
            {QStringLiteral("pluginId"), manifest.id},
            {QStringLiteral("pluginName"), manifest.name},
            {QStringLiteral("path"), manifest.fullOverlay},
            {QStringLiteral("url"), url},
        });
    }
    return out;
}

QVariant PluginStore::getValue(const QString &id, const QString &key, const QVariant &fallback) const {
    if (findManifest(id) < 0 || key.isEmpty() || key.contains(QLatin1Char('/')))
        return fallback;
    return m_storage.value(id).toMap().value(key, fallback);
}

bool PluginStore::setValue(const QString &id, const QString &key, const QVariant &value) {
    if (findManifest(id) < 0 || key.isEmpty() || key.contains(QLatin1Char('/')) || key.size() > 120)
        return false;
    if (!hasPermission(id, QStringLiteral("plugin.storage")))
        return false;
    QVariantMap scoped = m_storage.value(id).toMap();
    scoped[key] = value;
    QVariantMap next = m_storage;
    next[id] = scoped;
    if (storageBytes(next) > kMaxStorageBytes) {
        setLastError(tr("Plugin \"%1\" storage is full (1MB).").arg(id));
        return false;
    }
    m_storage = next;
    return persist();
}

bool PluginStore::removeValue(const QString &id, const QString &key) {
    if (findManifest(id) < 0)
        return false;
    QVariantMap scoped = m_storage.value(id).toMap();
    if (!scoped.contains(key))
        return true;
    scoped.remove(key);
    m_storage[id] = scoped;
    return persist();
}

void PluginStore::load() {
    if (m_loaded)
        return;
    m_loaded = true;
    QDir().mkpath(pluginsPath());
    QFile file(statePath());
    if (!file.exists()) {
        scan();
        return;
    }
    if (!file.open(QIODevice::ReadOnly)) {
        setLastError(tr("Could not read plugins: %1").arg(file.errorString()));
        scan();
        return;
    }
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &parseError);
    const QJsonObject root = doc.object();
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()
        || !root.value(QStringLiteral("plugins")).isObject()) {
        file.close();
        const QString backup = pluginsPath() + QStringLiteral("/../plugins.corrupt.")
            + QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyyMMdd-hhmmss-zzz")) + QStringLiteral(".json");
        if (QFile::rename(statePath(), backup))
            setLastError(tr("Plugin settings were corrupt; archived and reset."));
        else
            setLastError(tr("Plugin settings were corrupt and could not be archived; reset."));
        scan();
        return;
    }
    m_states = root.value(QStringLiteral("plugins")).toObject().toVariantMap();
    m_storage = root.value(QStringLiteral("storage")).toObject().toVariantMap();
    scan();
}

bool PluginStore::persist() {
    QSaveFile file(statePath());
    if (!file.open(QIODevice::WriteOnly)) {
        setLastError(tr("Could not save plugins: %1").arg(file.errorString()));
        return false;
    }
    const QJsonDocument doc(QJsonObject{
        {QStringLiteral("version"), kStateVersion},
        {QStringLiteral("plugins"), QJsonObject::fromVariantMap(m_states)},
        {QStringLiteral("storage"), QJsonObject::fromVariantMap(m_storage)},
    });
    file.write(doc.toJson(QJsonDocument::Indented));
    if (!file.commit()) {
        setLastError(tr("Could not save plugins: %1").arg(file.errorString()));
        return false;
    }
    return true;
}

void PluginStore::rebuild() {
    QVariantList rows;
    for (const PluginManifest &manifest : m_manifests)
        rows.append(manifestToRow(manifest, m_states.value(manifest.id + QStringLiteral(".error")).toString()));
    m_pluginList = rows;
    emit pluginsChanged();
}

void PluginStore::setLastError(const QString &message) {
    if (m_lastError == message)
        return;
    m_lastError = message;
    emit lastErrorChanged();
}

void PluginStore::setPending(const QVariantMap &pending) {
    m_pending = pending;
    emit pendingChanged();
}

QString PluginStore::pluginsDir() {
    QDir().mkpath(pluginsPath());
    return pluginsPath();
}

QString PluginStore::pluginsPath() const {
    QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (dir.isEmpty())
        dir = QDir::homePath() + QStringLiteral("/.totm");
    if (!dir.endsWith(QStringLiteral("/totm"), Qt::CaseInsensitive))
        dir += QStringLiteral("/totm");
    return dir + QStringLiteral("/plugins");
}

QString PluginStore::statePath() const {
    QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (dir.isEmpty())
        dir = QDir::homePath() + QStringLiteral("/.totm");
    if (!dir.endsWith(QStringLiteral("/totm"), Qt::CaseInsensitive))
        dir += QStringLiteral("/totm");
    return dir + QStringLiteral("/plugins.json");
}

bool PluginStore::isValidId(const QString &id) const {
    if (id.isEmpty() || id.size() > kMaxIdLength)
        return false;
    static const QRegularExpression valid(QStringLiteral("^[a-z0-9][a-z0-9._-]*$"));
    return valid.match(id.toLower()).hasMatch() && !id.contains(QStringLiteral(".."));
}

bool PluginStore::isSafeRelativeQml(const QString &path) const {
    if (path.isEmpty() || !path.endsWith(QStringLiteral(".qml"), Qt::CaseInsensitive))
        return false;
    if (path.startsWith(QLatin1Char('/')) || path.contains(QStringLiteral(".."))
        || path.contains(QStringLiteral(":")) || path.contains(QStringLiteral("\\")))
        return false;
    return true;
}

bool PluginStore::checkSandbox(const QString &dir, const PluginManifest &manifest, QString *error) const {
    QStringList files = {manifest.entry};
    for (const QVariant &v : manifest.toolbarTools)
        files.append(v.toString());
    for (const QVariant &v : manifest.designSections)
        files.append(v.toString());
    for (const QVariant &v : manifest.canvasOverlays)
        files.append(v.toString());
    if (!manifest.fullOverlay.isEmpty())
        files.append(manifest.fullOverlay);
    for (const QString &rel : files) {
        if (!checkOneQml(dir + QStringLiteral("/") + rel, error)) {
            *error = tr("Plugin \"%1\": %2").arg(manifest.id, *error);
            return false;
        }
    }
    return true;
}

bool PluginStore::checkOneQml(const QString &filePath, QString *error) const {
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly)) {
        *error = tr("Cannot read \"%1\".").arg(QFileInfo(filePath).fileName());
        return false;
    }
    const QString text = QString::fromUtf8(file.readAll());
    // Allowlist: layout/controls/shapes/effects plus app theme/icons.
    // Dialogs (file pickers), StandardPaths, and Multimedia would let a
    // plugin reach outside the app, so they stay host-mediated.
    static const QRegularExpression importRe(QStringLiteral("^\\s*import\\s+(\\S+)"), QRegularExpression::MultilineOption);
    auto it = importRe.globalMatch(text);
    while (it.hasNext()) {
        const QString module = it.next().captured(1);
        const bool allowed = module == QStringLiteral("QtQuick") || module == QStringLiteral("QtQuick.Layouts")
            || module == QStringLiteral("QtQuick.Controls") || module == QStringLiteral("QtQuick.Shapes")
            || module == QStringLiteral("QtQuick.Effects") || module == QStringLiteral("Totm");
        if (!allowed) {
            *error = tr("Forbidden import \"%1\". Allowed: QtQuick, Layouts, Controls, Shapes, Effects, Totm.").arg(module);
            return false;
        }
    }
    // Direct backend access bypasses permission gates; plugins must use
    // PluginStore.hasPermission/pluginFileUrl/get/setValue instead.
    const QStringList forbidden = {
        QStringLiteral("LibraryStore"),
        QStringLiteral("VideoExporter"),
        QStringLiteral("SettingsStore"),
        QStringLiteral("FileDialog"),
        QStringLiteral("FolderDialog"),
        QStringLiteral("StandardPaths"),
        QStringLiteral("MediaPlayer"),
        QStringLiteral("XMLHttpRequest"),
        QStringLiteral("WorkerScript"),
        QStringLiteral("LocalStorage"),
        QStringLiteral("Qt.createQmlObject"),
        QStringLiteral("Qt.openUrlExternally"),
    };
    for (const QString &token : forbidden) {
        if (text.contains(token)) {
            *error = tr("Forbidden \"%1\" — use the PluginStore API so permissions apply.").arg(token);
            return false;
        }
    }
    return true;
}

QVariantMap PluginStore::manifestToRow(const PluginManifest &manifest, const QString &error) const {
    // Broken rows carry an error and no contributions; surface them
    // disabled so one bad plugin never blocks the rest.
    if (!error.isEmpty()) {
        return QVariantMap{
            {QStringLiteral("id"), manifest.id},
            {QStringLiteral("name"), manifest.name},
            {QStringLiteral("version"), manifest.version},
            {QStringLiteral("author"), QString()},
            {QStringLiteral("description"), manifest.description},
            {QStringLiteral("tier"), manifest.tier},
            {QStringLiteral("enabled"), false},
            {QStringLiteral("granted"), QVariantList()},
            {QStringLiteral("requested"), QVariantList()},
            {QStringLiteral("missing"), QVariantList()},
            {QStringLiteral("error"), error},
            {QStringLiteral("hasToolbar"), false},
            {QStringLiteral("hasSections"), false},
            {QStringLiteral("hasOverlay"), false},
            {QStringLiteral("hasFullOverlay"), false},
        };
    }
    const QVariantMap state = m_states.value(manifest.id).toMap();
    const QStringList granted = toStringList(state.value(QStringLiteral("granted")).toList());
    const QStringList requested = manifest.permissions;
    QStringList missing;
    for (const QString &perm : requested) {
        if (!granted.contains(perm))
            missing.append(perm);
    }
    return QVariantMap{
        {QStringLiteral("id"), manifest.id},
        {QStringLiteral("name"), manifest.name},
        {QStringLiteral("version"), manifest.version},
        {QStringLiteral("author"), manifest.author},
        {QStringLiteral("description"), manifest.description},
        {QStringLiteral("tier"), manifest.tier},
        {QStringLiteral("enabled"), state.value(QStringLiteral("enabled"), false).toBool()},
        {QStringLiteral("granted"), QVariantList(granted.begin(), granted.end())},
        {QStringLiteral("requested"), QVariantList(requested.begin(), requested.end())},
        {QStringLiteral("missing"), QVariantList(missing.begin(), missing.end())},
        {QStringLiteral("error"), error},
        {QStringLiteral("hasToolbar"), !manifest.toolbarTools.isEmpty()},
        {QStringLiteral("hasSections"), !manifest.designSections.isEmpty()},
        {QStringLiteral("hasOverlay"), !manifest.canvasOverlays.isEmpty()},
        {QStringLiteral("hasFullOverlay"), !manifest.fullOverlay.isEmpty()},
    };
}

QVariantMap PluginStore::buildPending(const PluginManifest &manifest) const {
    QVariantList requested;
    const QVariantMap state = m_states.value(manifest.id).toMap();
    const QStringList granted = toStringList(state.value(QStringLiteral("granted")).toList());
    for (const QString &perm : manifest.permissions) {
        QVariantMap meta = permissionMeta(perm);
        meta[QStringLiteral("reason")] = manifest.permissionReasons.value(perm, meta.value(QStringLiteral("description")));
        meta[QStringLiteral("granted")] = granted.isEmpty() ? true : granted.contains(perm);
        requested.append(meta);
    }
    // Empty-grant default is all-on so one tap installs; unticking shows
    // the may-break warning in the popup.
    if (requested.isEmpty()) {
        for (const QString &perm : kDefaultPermissions) {
            QVariantMap meta = permissionMeta(perm);
            meta[QStringLiteral("reason")] = manifest.permissionReasons.value(perm, meta.value(QStringLiteral("description")));
            meta[QStringLiteral("granted")] = true;
            requested.append(meta);
        }
    }
    return QVariantMap{
        {QStringLiteral("id"), manifest.id},
        {QStringLiteral("name"), manifest.name},
        {QStringLiteral("version"), manifest.version},
        {QStringLiteral("author"), manifest.author},
        {QStringLiteral("description"), manifest.description},
        {QStringLiteral("tier"), manifest.tier},
        {QStringLiteral("requested"), requested},
    };
}

int PluginStore::findManifest(const QString &id) const {
    for (int i = 0; i < m_manifests.size(); ++i) {
        if (m_manifests.at(i).id == id)
            return i;
    }
    return -1;
}

bool PluginStore::requestImage(const QString &id) {
    if (!canUseBlobs(id, QStringLiteral("image"))) {
        setLastError(tr("Plugin \"%1\" needs the images permission to pick images.").arg(id));
        return false;
    }
    emit pickRequested(id, QStringLiteral("image"));
    return true;
}

bool PluginStore::requestAudio(const QString &id) {
    if (!canUseBlobs(id, QStringLiteral("audio"))) {
        setLastError(tr("Plugin \"%1\" needs the audio permission to pick audio.").arg(id));
        return false;
    }
    emit pickRequested(id, QStringLiteral("audio"));
    return true;
}

bool PluginStore::commitPick(const QString &id, const QString &kind, const QString &storedName) {
    // Host only, but re-validated: the name must be a safe blob the host
    // just imported, and the plugin must still hold the grant.
    if ((kind != QStringLiteral("image") && kind != QStringLiteral("audio")) || !isSafeBlobName(storedName))
        return false;
    if (!canUseBlobs(id, kind))
        return false;
    if (!QFile::exists(blobDir(kind) + QStringLiteral("/") + storedName))
        return false;
    QStringList names = pickedBlobs(id, kind);
    if (!names.contains(storedName)) {
        names.append(storedName);
        QVariantMap state = m_states.value(id).toMap();
        state[kind == QStringLiteral("image") ? QStringLiteral("images") : QStringLiteral("audio")] = QVariantList(names.begin(), names.end());
        m_states[id] = state;
        if (!persist())
            return false;
    }
    emit picked(id, kind, storedName);
    return true;
}

QUrl PluginStore::imageUrlFor(const QString &id, const QString &name) const {
    if (!canUseBlobs(id, QStringLiteral("image")) || !pickedBlobs(id, QStringLiteral("image")).contains(name))
        return {};
    const QString path = blobDir(QStringLiteral("image")) + QStringLiteral("/") + name;
    if (!QFile::exists(path))
        return {};
    return QUrl::fromLocalFile(path);
}

QUrl PluginStore::audioUrlFor(const QString &id, const QString &name) const {
    if (!canUseBlobs(id, QStringLiteral("audio")) || !pickedBlobs(id, QStringLiteral("audio")).contains(name))
        return {};
    const QString path = blobDir(QStringLiteral("audio")) + QStringLiteral("/") + name;
    if (!QFile::exists(path))
        return {};
    return QUrl::fromLocalFile(path);
}

QVariantMap PluginStore::imageInfoFor(const QString &id, const QString &name) const {
    QVariantMap out{{QStringLiteral("name"), name}, {QStringLiteral("width"), 0}, {QStringLiteral("height"), 0}};
    if (imageUrlFor(id, name).isEmpty())
        return out;
    QImageReader reader(blobDir(QStringLiteral("image")) + QStringLiteral("/") + name);
    const QSize size = reader.size();
    if (size.isValid()) {
        out[QStringLiteral("width")] = size.width();
        out[QStringLiteral("height")] = size.height();
    }
    return out;
}

bool PluginStore::suggestExport(const QString &id, const QString &quality, int fps) {
    if (findManifest(id) < 0 || !hasPermission(id, QStringLiteral("export.hook")))
        return false;
    // Contract: only the popup's own options are suggestible, so Apply
    // always maps onto a real choice.
    if (quality != QStringLiteral("sd") && quality != QStringLiteral("hd") && quality != QStringLiteral("4k"))
        return false;
    if (fps != 30 && fps != 60)
        return false;
    QVariantMap state = m_states.value(id).toMap();
    state[QStringLiteral("exportQuality")] = quality;
    state[QStringLiteral("exportFps")] = fps;
    m_states[id] = state;
    if (!persist())
        return false;
    rebuild();
    return true;
}

QVariantMap PluginStore::exportSuggestion(const QString &id) const {
    if (findManifest(id) < 0 || !hasPermission(id, QStringLiteral("export.hook")))
        return {};
    const QVariantMap state = m_states.value(id).toMap();
    const QString quality = state.value(QStringLiteral("exportQuality")).toString();
    const int fps = state.value(QStringLiteral("exportFps"), 0).toInt();
    if (quality.isEmpty() || (fps != 30 && fps != 60))
        return {};
    const QVariantMap row = plugin(id);
    return QVariantMap{
        {QStringLiteral("pluginId"), id},
        {QStringLiteral("pluginName"), row.value(QStringLiteral("name"), id)},
        {QStringLiteral("quality"), quality},
        {QStringLiteral("fps"), fps},
    };
}

bool PluginStore::clearExportSuggestion(const QString &id) {
    if (findManifest(id) < 0)
        return false;
    QVariantMap state = m_states.value(id).toMap();
    if (!state.contains(QStringLiteral("exportQuality")))
        return true;
    state.remove(QStringLiteral("exportQuality"));
    state.remove(QStringLiteral("exportFps"));
    m_states[id] = state;
    if (!persist())
        return false;
    rebuild();
    return true;
}

QString PluginStore::blobDir(const QString &kind) const {
    // Mirrors LibraryStore's images/audio layout without coupling to it.
    QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (dir.isEmpty())
        dir = QDir::homePath() + QStringLiteral("/.totm");
    if (!dir.endsWith(QStringLiteral("/totm"), Qt::CaseInsensitive))
        dir += QStringLiteral("/totm");
    return dir + (kind == QStringLiteral("image") ? QStringLiteral("/images") : QStringLiteral("/audio"));
}

bool PluginStore::isSafeBlobName(const QString &name) const {
    if (name.isEmpty() || name.contains(QLatin1Char('/')) || name.contains(QLatin1Char('\\'))
        || name.contains(QStringLiteral("..")))
        return false;
    const int dot = name.lastIndexOf(QLatin1Char('.'));
    return dot > 0 && dot < name.size() - 1;
}

bool PluginStore::canUseBlobs(const QString &id, const QString &kind) const {
    if (findManifest(id) < 0)
        return false;
    return hasPermission(id, kind == QStringLiteral("image") ? QStringLiteral("images.use") : QStringLiteral("audio.use"));
}

QStringList PluginStore::pickedBlobs(const QString &id, const QString &kind) const {
    const QVariantMap state = m_states.value(id).toMap();
    return toStringList(state.value(kind == QStringLiteral("image") ? QStringLiteral("images") : QStringLiteral("audio")).toList());
}
