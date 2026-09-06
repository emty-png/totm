#include "LibraryStore.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUuid>

namespace {
constexpr int kSchemaVersion = 1;
constexpr int kMaxNameLength = 120;

QString nowIso() {
    return QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
}

QString trimmedName(const QString &raw, const QString &fallback) {
    const QString name = raw.trimmed().left(kMaxNameLength);
    return name.isEmpty() ? fallback : name;
}

QString newId() {
    return QUuid::createUuid().toString(QUuid::WithoutBraces);
}

QVariantMap entryToScene(const QVariantMap &scene) {
    // Scenes arrive from QML as plain maps; normalize the keys we persist
    // so older/newer writers stay readable.
    QVariantMap out;
    out[QStringLiteral("version")] = kSchemaVersion;
    out[QStringLiteral("sceneWidth")] = scene.value(QStringLiteral("sceneWidth"), 1920);
    out[QStringLiteral("sceneHeight")] = scene.value(QStringLiteral("sceneHeight"), 1080);
    out[QStringLiteral("sceneColor")] = scene.value(QStringLiteral("sceneColor"), QStringLiteral("#ffffff"));
    out[QStringLiteral("nodes")] = scene.value(QStringLiteral("nodes"), QVariantList());
    return out;
}
} // namespace

LibraryStore *LibraryStore::create(QQmlEngine *engine, QJSEngine *scriptEngine) {
    Q_UNUSED(scriptEngine);
    auto *store = new LibraryStore(engine);
    QJSEngine::setObjectOwnership(store, QJSEngine::CppOwnership);
    return store;
}

LibraryStore::LibraryStore(QObject *parent)
    : QObject(parent) {
    load();
}

QVariantList LibraryStore::workspaceList() const {
    return m_workspaceList;
}

QVariantList LibraryStore::designList() const {
    return m_designList;
}

QString LibraryStore::defaultWorkspaceId() const {
    return m_defaultWorkspaceId;
}

QString LibraryStore::libraryPath() const {
    return libraryDir() + QStringLiteral("/library.json");
}

QString LibraryStore::lastError() const {
    return m_lastError;
}

QString LibraryStore::createWorkspace(const QString &name) {
    WorkspaceEntry entry;
    entry.id = newId();
    entry.name = trimmedName(name, tr("Untitled workspace"));
    entry.isDefault = false;
    entry.createdAt = nowIso();
    m_workspaceEntries.append(entry);
    if (!persist())
        return {};
    rebuild();
    return entry.id;
}

bool LibraryStore::renameWorkspace(const QString &id, const QString &name) {
    const int at = findWorkspace(id);
    if (at < 0)
        return false;
    const QString next = trimmedName(name, m_workspaceEntries.at(at).name);
    if (next == m_workspaceEntries.at(at).name)
        return true;
    m_workspaceEntries[at].name = next;
    if (!persist())
        return false;
    rebuild();
    return true;
}

bool LibraryStore::deleteWorkspace(const QString &id) {
    const int at = findWorkspace(id);
    if (at < 0 || m_workspaceEntries.at(at).isDefault)
        return false;
    // Designs are never destroyed with their workspace; they move home
    // to Default so a slip of the finger costs nothing.
    for (DesignEntry &design : m_designEntries) {
        if (design.workspaceId == id) {
            design.workspaceId = m_defaultWorkspaceId;
            design.updatedAt = nowIso();
        }
    }
    m_workspaceEntries.removeAt(at);
    if (!persist())
        return false;
    rebuild();
    return true;
}

QString LibraryStore::createDesign(const QString &workspaceId, const QString &name) {
    const QString target = findWorkspace(workspaceId) >= 0 ? workspaceId : m_defaultWorkspaceId;
    DesignEntry entry;
    entry.id = newId();
    entry.workspaceId = target;
    entry.name = trimmedName(name, tr("Untitled"));
    entry.createdAt = nowIso();
    entry.updatedAt = entry.createdAt;
    entry.scene = entryToScene({});
    m_designEntries.prepend(entry);
    if (!persist())
        return {};
    rebuild();
    return entry.id;
}

bool LibraryStore::renameDesign(const QString &id, const QString &name) {
    const int at = findDesign(id);
    if (at < 0)
        return false;
    const QString next = trimmedName(name, m_designEntries.at(at).name);
    if (next == m_designEntries.at(at).name)
        return true;
    m_designEntries[at].name = next;
    m_designEntries[at].updatedAt = nowIso();
    if (!persist())
        return false;
    rebuild();
    return true;
}

bool LibraryStore::deleteDesign(const QString &id) {
    const int at = findDesign(id);
    if (at < 0)
        return false;
    m_designEntries.removeAt(at);
    if (!persist())
        return false;
    rebuild();
    return true;
}

bool LibraryStore::moveDesign(const QString &id, const QString &workspaceId) {
    const int at = findDesign(id);
    if (at < 0 || findWorkspace(workspaceId) < 0)
        return false;
    if (m_designEntries.at(at).workspaceId == workspaceId)
        return true;
    m_designEntries[at].workspaceId = workspaceId;
    m_designEntries[at].updatedAt = nowIso();
    if (!persist())
        return false;
    rebuild();
    return true;
}

bool LibraryStore::setStarred(const QString &id, bool starred) {
    const int at = findDesign(id);
    if (at < 0 || m_designEntries.at(at).starred == starred)
        return at >= 0;
    m_designEntries[at].starred = starred;
    if (!persist())
        return false;
    rebuild();
    return true;
}

bool LibraryStore::toggleStarred(const QString &id) {
    const int at = findDesign(id);
    if (at < 0)
        return false;
    return setStarred(id, !m_designEntries.at(at).starred);
}

bool LibraryStore::saveScene(const QString &designId, const QVariantMap &scene) {
    const int at = findDesign(designId);
    if (at < 0)
        return false;
    m_designEntries[at].scene = entryToScene(scene);
    m_designEntries[at].updatedAt = nowIso();
    if (!persist())
        return false;
    rebuild();
    return true;
}

QVariantMap LibraryStore::loadScene(const QString &designId) const {
    const int at = findDesign(designId);
    if (at < 0)
        return {};
    return m_designEntries.at(at).scene;
}

QVariantMap LibraryStore::design(const QString &id) const {
    const int at = findDesign(id);
    if (at < 0)
        return {};
    const DesignEntry &entry = m_designEntries.at(at);
    return {
        {QStringLiteral("id"), entry.id},
        {QStringLiteral("workspaceId"), entry.workspaceId},
        {QStringLiteral("name"), entry.name},
        {QStringLiteral("createdAt"), entry.createdAt},
        {QStringLiteral("updatedAt"), entry.updatedAt},
        {QStringLiteral("starred"), entry.starred},
        {QStringLiteral("scene"), entry.scene},
    };
}

bool LibraryStore::hasDesign(const QString &id) const {
    return findDesign(id) >= 0;
}

int LibraryStore::designCount(const QString &workspaceId) const {
    int count = 0;
    for (const DesignEntry &entry : m_designEntries) {
        if (entry.workspaceId == workspaceId)
            ++count;
    }
    return count;
}

QString LibraryStore::workspaceName(const QString &id) const {
    const int at = findWorkspace(id);
    return at >= 0 ? m_workspaceEntries.at(at).name : QString();
}

bool LibraryStore::isDefaultWorkspace(const QString &id) const {
    const int at = findWorkspace(id);
    return at >= 0 && m_workspaceEntries.at(at).isDefault;
}

void LibraryStore::load() {
    if (m_loaded)
        return;
    m_loaded = true;

    QDir().mkpath(libraryDir());
    QFile file(libraryPath());
    if (!file.exists()) {
        WorkspaceEntry fallback;
        fallback.id = newId();
        fallback.name = tr("Default");
        fallback.isDefault = true;
        fallback.createdAt = nowIso();
        m_workspaceEntries = {fallback};
        m_defaultWorkspaceId = fallback.id;
        persist();
        rebuild();
        return;
    }
    if (!file.open(QIODevice::ReadOnly)) {
        setLastError(tr("Could not read library: %1").arg(file.errorString()));
        return;
    }
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        // Never strand the user on a corrupt file: archive it and start over.
        const QString backup = libraryDir() + QStringLiteral("/library.corrupt.%1.json")
                                                   .arg(QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyyMMdd-hhmmss")));
        file.close();
        QFile::rename(libraryPath(), backup);
        setLastError(tr("Library was corrupt; archived to %1 and reset.").arg(backup));
        m_workspaceEntries.clear();
        m_designEntries.clear();
    } else {
        const QJsonObject root = doc.object();
        m_workspaceEntries.clear();
        for (const QJsonValue &value : root.value(QStringLiteral("workspaces")).toArray()) {
            const QJsonObject item = value.toObject();
            WorkspaceEntry entry;
            entry.id = item.value(QStringLiteral("id")).toString();
            entry.name = item.value(QStringLiteral("name")).toString();
            entry.isDefault = item.value(QStringLiteral("isDefault")).toBool();
            entry.createdAt = item.value(QStringLiteral("createdAt")).toString();
            if (!entry.id.isEmpty())
                m_workspaceEntries.append(entry);
        }
        m_designEntries.clear();
        for (const QJsonValue &value : root.value(QStringLiteral("designs")).toArray()) {
            const QJsonObject item = value.toObject();
            DesignEntry entry;
            entry.id = item.value(QStringLiteral("id")).toString();
            entry.workspaceId = item.value(QStringLiteral("workspaceId")).toString();
            entry.name = item.value(QStringLiteral("name")).toString();
            entry.createdAt = item.value(QStringLiteral("createdAt")).toString();
            entry.updatedAt = item.value(QStringLiteral("updatedAt")).toString();
            entry.starred = item.value(QStringLiteral("starred")).toBool();
            entry.scene = item.value(QStringLiteral("scene")).toObject().toVariantMap();
            if (!entry.id.isEmpty())
                m_designEntries.append(entry);
        }
    }

    // Self-heal invariants every load: exactly one Default exists, and no
    // design points at a missing workspace.
    bool haveDefault = false;
    for (const WorkspaceEntry &entry : m_workspaceEntries) {
        if (entry.isDefault) {
            m_defaultWorkspaceId = entry.id;
            haveDefault = true;
            break;
        }
    }
    if (!haveDefault) {
        WorkspaceEntry fallback;
        fallback.id = newId();
        fallback.name = tr("Default");
        fallback.isDefault = true;
        fallback.createdAt = nowIso();
        m_workspaceEntries.prepend(fallback);
        m_defaultWorkspaceId = fallback.id;
    }
    QHash<QString, bool> known;
    for (const WorkspaceEntry &entry : m_workspaceEntries)
        known.insert(entry.id, true);
    for (DesignEntry &entry : m_designEntries) {
        if (!known.contains(entry.workspaceId))
            entry.workspaceId = m_defaultWorkspaceId;
        if (entry.scene.isEmpty())
            entry.scene = entryToScene({});
    }
    rebuild();
}

bool LibraryStore::persist() {
    QJsonArray workspaces;
    for (const WorkspaceEntry &entry : m_workspaceEntries) {
        workspaces.append(QJsonObject{
            {QStringLiteral("id"), entry.id},
            {QStringLiteral("name"), entry.name},
            {QStringLiteral("isDefault"), entry.isDefault},
            {QStringLiteral("createdAt"), entry.createdAt},
        });
    }
    QJsonArray designs;
    for (const DesignEntry &entry : m_designEntries) {
        designs.append(QJsonObject{
            {QStringLiteral("id"), entry.id},
            {QStringLiteral("workspaceId"), entry.workspaceId},
            {QStringLiteral("name"), entry.name},
            {QStringLiteral("createdAt"), entry.createdAt},
            {QStringLiteral("updatedAt"), entry.updatedAt},
            {QStringLiteral("starred"), entry.starred},
            {QStringLiteral("scene"), QJsonObject::fromVariantMap(entry.scene)},
        });
    }
    const QJsonDocument doc(QJsonObject{
        {QStringLiteral("version"), kSchemaVersion},
        {QStringLiteral("workspaces"), workspaces},
        {QStringLiteral("designs"), designs},
    });
    QSaveFile file(libraryPath());
    if (!file.open(QIODevice::WriteOnly)) {
        setLastError(tr("Could not save library: %1").arg(file.errorString()));
        return false;
    }
    file.write(doc.toJson(QJsonDocument::Indented));
    if (!file.commit()) {
        setLastError(tr("Could not save library: %1").arg(file.errorString()));
        return false;
    }
    return true;
}

void LibraryStore::rebuild() {
    QHash<QString, int> counts;
    for (const DesignEntry &entry : m_designEntries)
        counts[entry.workspaceId] = counts.value(entry.workspaceId, 0) + 1;
    QVariantList workspaces;
    for (const WorkspaceEntry &entry : m_workspaceEntries) {
        workspaces.append(QVariantMap{
            {QStringLiteral("workspaceId"), entry.id},
            {QStringLiteral("name"), entry.name},
            {QStringLiteral("isDefault"), entry.isDefault},
            {QStringLiteral("createdAt"), entry.createdAt},
            {QStringLiteral("designCount"), counts.value(entry.id, 0)},
        });
    }
    QVariantList designs;
    for (const DesignEntry &entry : m_designEntries) {
        designs.append(QVariantMap{
            {QStringLiteral("designId"), entry.id},
            {QStringLiteral("workspaceId"), entry.workspaceId},
            {QStringLiteral("name"), entry.name},
            {QStringLiteral("createdAt"), entry.createdAt},
            {QStringLiteral("updatedAt"), entry.updatedAt},
            {QStringLiteral("starred"), entry.starred},
            {QStringLiteral("scene"), entry.scene},
        });
    }
    m_workspaceList = workspaces;
    m_designList = designs;
    emit libraryChanged();
}

void LibraryStore::setLastError(const QString &message) {
    if (m_lastError == message)
        return;
    m_lastError = message;
    emit lastErrorChanged();
}

int LibraryStore::findWorkspace(const QString &id) const {
    for (int i = 0; i < m_workspaceEntries.size(); ++i) {
        if (m_workspaceEntries.at(i).id == id)
            return i;
    }
    return -1;
}

int LibraryStore::findDesign(const QString &id) const {
    for (int i = 0; i < m_designEntries.size(); ++i) {
        if (m_designEntries.at(i).id == id)
            return i;
    }
    return -1;
}

QString LibraryStore::libraryDir() const {
    QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (dir.isEmpty())
        dir = QDir::homePath() + QStringLiteral("/.totm");
    if (!dir.endsWith(QStringLiteral("/totm"), Qt::CaseInsensitive))
        dir += QStringLiteral("/totm");
    return dir;
}
