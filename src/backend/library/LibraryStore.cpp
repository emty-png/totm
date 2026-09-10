#include "LibraryStore.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QImageReader>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUrl>
#include <QUuid>

namespace {
constexpr int kSchemaVersion = 2;
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
    // Contract: persist only the keys the loader understands. Extra QML
    // keys are dropped; missing keys get defaults so older documents stay
    // readable. The anim map passes through untouched.
    QVariantMap out;
    out[QStringLiteral("version")] = kSchemaVersion;
    out[QStringLiteral("sceneWidth")] = scene.value(QStringLiteral("sceneWidth"), 1920);
    out[QStringLiteral("sceneHeight")] = scene.value(QStringLiteral("sceneHeight"), 1080);
    out[QStringLiteral("sceneColor")] = scene.value(QStringLiteral("sceneColor"), QStringLiteral("#ffffff"));
    out[QStringLiteral("nodes")] = scene.value(QStringLiteral("nodes"), QVariantList());
    out[QStringLiteral("anim")] = scene.value(QStringLiteral("anim"), QVariantMap());
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
    : QObject(parent)
    , m_lock(libraryDir() + QStringLiteral("/totm.lock")) {
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
    // Invariant: designs are never deleted with their workspace.
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
    // New designs own their scene file from birth, so the index never
    // points at a design without durable storage.
    if (!writeDesignFile(entry.id, entry.scene) || !persist()) {
        m_designEntries.removeAt(findDesign(entry.id));
        return {};
    }
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
    // Best effort: a leftover file is swept next boot and never blocks.
    QFile::remove(designsDir() + QStringLiteral("/") + id + QStringLiteral(".json"));
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
    // Scene file first: it is the durable copy, the index only carries
    // the updatedAt stamp and stays small.
    if (!writeDesignFile(designId, m_designEntries.at(at).scene))
        return false;
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

QString LibraryStore::importImage(const QUrl &source) {
    QString local = source.isLocalFile() ? source.toLocalFile() : source.toString();
    if (local.isEmpty()) {
        setLastError(tr("Pick an image file first."));
        return {};
    }
    QFileInfo info(local);
    if (!info.exists() || !info.isFile()) {
        setLastError(tr("Could not read that image file."));
        return {};
    }
    QString suffix = info.suffix().toLower();
    static const QStringList allowed = {QStringLiteral("png"), QStringLiteral("jpg"), QStringLiteral("jpeg"),
        QStringLiteral("webp"), QStringLiteral("gif"), QStringLiteral("svg")};
    if (!allowed.contains(suffix))
        suffix = QStringLiteral("png");
    QDir().mkpath(imagesDir());
    const QString name = newId() + QStringLiteral(".") + suffix;
    const QString dest = imagesDir() + QStringLiteral("/") + name;
    if (!QFile::copy(local, dest)) {
        setLastError(tr("Could not import that image."));
        return {};
    }
    clearError();
    return name;
}

QUrl LibraryStore::imageUrl(const QString &name) const {
    if (!isSafeImageName(name))
        return {};
    const QString path = imagesDir() + QStringLiteral("/") + name;
    if (!QFile::exists(path))
        return {};
    return QUrl::fromLocalFile(path);
}

QVariantMap LibraryStore::imageInfo(const QString &name) const {
    QVariantMap out;
    out[QStringLiteral("name")] = name;
    out[QStringLiteral("width")] = 0;
    out[QStringLiteral("height")] = 0;
    if (!isSafeImageName(name))
        return out;
    const QString path = imagesDir() + QStringLiteral("/") + name;
    if (!QFile::exists(path))
        return out;
    QImageReader reader(path);
    // SVG reports a valid size via the plugin when it carries width/height;
    // icon-only SVGs fall back to a neutral box so clicks still stamp.
    QSize size = reader.size();
    if (!size.isValid() || size.isEmpty()) {
        QImage img(path);
        if (!img.isNull())
            size = img.size();
    }
    if (size.isValid() && !size.isEmpty()) {
        out[QStringLiteral("width")] = size.width();
        out[QStringLiteral("height")] = size.height();
    }
    return out;
}

bool LibraryStore::hasImage(const QString &name) const {
    if (!isSafeImageName(name))
        return false;
    return QFile::exists(imagesDir() + QStringLiteral("/") + name);
}

quint64 LibraryStore::imagesDiskUsage() const {
    quint64 total = 0;
    const QDir dir(imagesDir());
    for (const QFileInfo &info : dir.entryInfoList(QDir::Files))
        total += static_cast<quint64>(info.size());
    return total;
}

int LibraryStore::imageCount() const {
    return QDir(imagesDir()).entryList(QDir::Files).size();
}

QSet<QString> LibraryStore::referencedImages() const {
    QSet<QString> out;
    QList<QVariantList> stack;
    for (const DesignEntry &entry : m_designEntries)
        stack.append(entry.scene.value(QStringLiteral("nodes")).toList());
    while (!stack.isEmpty()) {
        const QVariantList nodes = stack.takeLast();
        for (const QVariant &v : nodes) {
            const QVariantMap n = v.toMap();
            const QString src = n.value(QStringLiteral("imageSource")).toString();
            if (!src.isEmpty())
                out.insert(src);
            if (n.value(QStringLiteral("kind")).toString() == QLatin1String("group"))
                stack.append(n.value(QStringLiteral("children")).toList());
        }
    }
    return out;
}

void LibraryStore::sweepOrphanImages() {
    const QSet<QString> keep = referencedImages();
    const QDir dir(imagesDir());
    for (const QFileInfo &info : dir.entryInfoList(QDir::Files)) {
        if (!keep.contains(info.fileName()))
            QFile::remove(info.absoluteFilePath());
    }
}

void LibraryStore::load() {
    if (m_loaded)
        return;
    m_loaded = true;

    QDir().mkpath(libraryDir());
    // Second-instance guard. Contention only warns; concurrent writers
    // remain last-writer-wins.
    if (!m_lock.lock()) {
        setLastError(tr("Another copy of totm seems to be running; saves may overwrite each other."));
    }

    QFile file(libraryPath());
    if (!file.exists()) {
        installFreshDefault();
        sweepOrphanImages();
        persist();
        rebuild();
        return;
    }
    if (!file.open(QIODevice::ReadOnly)) {
        setLastError(tr("Could not read library: %1").arg(file.errorString()));
        // Invariant: in-memory state stays valid even when disk is not.
        installFreshDefault();
        sweepOrphanImages();
        rebuild();
        return;
    }
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &parseError);
    const QJsonObject root = doc.object();
    // Contract: files we write always carry both arrays. Anything else is
    // treated as foreign and archived, never adopted as empty.
    const bool wrongShape = !root.value(QStringLiteral("workspaces")).isArray()
        || !root.value(QStringLiteral("designs")).isArray();
    if (parseError.error != QJsonParseError::NoError || !doc.isObject() || wrongShape) {
        // Recovery: archive the bad file and start from Default.
        const QString backup = libraryDir() + QStringLiteral("/library.corrupt.%1.json")
                                                   .arg(QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyyMMdd-hhmmss-zzz")));
        file.close();
        if (QFile::rename(libraryPath(), backup)) {
            setLastError(tr("Library was corrupt; archived to %1 and reset.").arg(backup));
        } else {
            setLastError(tr("Library was corrupt and could not be archived; starting fresh."));
        }
        m_workspaceEntries.clear();
        m_designEntries.clear();
        installFreshDefault();
        sweepOrphanImages();
        persist();
        rebuild();
        return;
    } else {
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
            if (entry.id.isEmpty())
                continue;
            entry.scene = readDesignFile(entry.id);
            m_designEntries.append(entry);
        }
        sweepOrphanDesignFiles();
    }

    // Invariants restored on every load: exactly one Default workspace
    // exists; every design points at a known workspace with a valid scene.
    bool healed = false;
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
        healed = true;
    }
    QHash<QString, bool> known;
    for (const WorkspaceEntry &entry : m_workspaceEntries)
        known.insert(entry.id, true);
    for (DesignEntry &entry : m_designEntries) {
        if (!known.contains(entry.workspaceId)) {
            entry.workspaceId = m_defaultWorkspaceId;
            healed = true;
        }
        if (entry.scene.isEmpty()) {
            entry.scene = entryToScene({});
            healed = true;
        }
    }
    // Healed state must persist even without further edits.
    if (healed)
        persist();
    sweepOrphanImages();
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
    // Metadata only: scenes live in designs/<id>.json, so the index
    // stays small no matter how large the library grows.
    for (const DesignEntry &entry : m_designEntries) {
        designs.append(QJsonObject{
            {QStringLiteral("id"), entry.id},
            {QStringLiteral("workspaceId"), entry.workspaceId},
            {QStringLiteral("name"), entry.name},
            {QStringLiteral("createdAt"), entry.createdAt},
            {QStringLiteral("updatedAt"), entry.updatedAt},
            {QStringLiteral("starred"), entry.starred},
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
        // In-memory state already holds the change; rebuild so the view
        // matches instead of showing stale data.
        rebuild();
        return false;
    }
    file.write(doc.toJson(QJsonDocument::Indented));
    if (!file.commit()) {
        setLastError(tr("Could not save library: %1").arg(file.errorString()));
        rebuild();
        return false;
    }
    return true;
}

void LibraryStore::rebuild() {    QHash<QString, int> counts;
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

void LibraryStore::clearError() {
    setLastError(QString());
}

void LibraryStore::installFreshDefault() {
    WorkspaceEntry fallback;
    fallback.id = newId();
    fallback.name = tr("Default");
    fallback.isDefault = true;
    fallback.createdAt = nowIso();
    m_workspaceEntries = {fallback};
    m_defaultWorkspaceId = fallback.id;
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

QString LibraryStore::imagesDir() const {
    return libraryDir() + QStringLiteral("/images");
}

QString LibraryStore::designsDir() const {
    return libraryDir() + QStringLiteral("/designs");
}

bool LibraryStore::writeDesignFile(const QString &id, const QVariantMap &scene) {
    if (id.isEmpty() || id.contains(QLatin1Char('/')) || id.contains(QLatin1Char('\\'))
        || id.contains(QStringLiteral("..")))
        return false;
    QDir().mkpath(designsDir());
    QSaveFile file(designsDir() + QStringLiteral("/") + id + QStringLiteral(".json"));
    if (!file.open(QIODevice::WriteOnly)) {
        setLastError(tr("Could not save design: %1").arg(file.errorString()));
        return false;
    }
    const QJsonDocument doc(QJsonObject{
        {QStringLiteral("version"), kSchemaVersion},
        {QStringLiteral("scene"), QJsonObject::fromVariantMap(entryToScene(scene))},
    });
    file.write(doc.toJson(QJsonDocument::Indented));
    if (!file.commit()) {
        setLastError(tr("Could not save design: %1").arg(file.errorString()));
        return false;
    }
    return true;
}

QVariantMap LibraryStore::readDesignFile(const QString &id) {
    if (id.isEmpty() || id.contains(QLatin1Char('/')) || id.contains(QLatin1Char('\\'))
        || id.contains(QStringLiteral("..")))
        return entryToScene({});
    const QString path = designsDir() + QStringLiteral("/") + id + QStringLiteral(".json");
    QFile file(path);
    if (!file.exists())
        return entryToScene({});
    if (!file.open(QIODevice::ReadOnly)) {
        setLastError(tr("Could not read design; starting it fresh."));
        return entryToScene({});
    }
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &parseError);
    const QJsonObject root = doc.object();
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()
        || !root.value(QStringLiteral("scene")).isObject()) {
        file.close();
        const QString backup = designsDir() + QStringLiteral("/") + id + QStringLiteral(".corrupt.")
            + QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyyMMdd-hhmmss-zzz"))
            + QStringLiteral(".json");
        if (QFile::rename(path, backup))
            setLastError(tr("A design was corrupt; archived and started fresh."));
        else
            setLastError(tr("A design was corrupt and could not be archived; started fresh."));
        return entryToScene({});
    }
    return entryToScene(root.value(QStringLiteral("scene")).toObject().toVariantMap());
}

void LibraryStore::sweepOrphanDesignFiles() {
    QHash<QString, bool> known;
    for (const DesignEntry &entry : m_designEntries)
        known.insert(entry.id, true);
    const QDir dir(designsDir());
    for (const QString &file : dir.entryList({QStringLiteral("*.json")}, QDir::Files)) {
        // Corrupt archives (<id>.corrupt.<ts>.json) never match an id
        // and are left alone for the user to inspect.
        if (file.contains(QStringLiteral(".corrupt.")))
            continue;
        const QString id = file.left(file.size() - 5);
        if (!known.contains(id))
            QFile::remove(dir.filePath(file));
    }
}

bool LibraryStore::isSafeImageName(const QString &name) const {
    if (name.isEmpty() || name.contains(QLatin1Char('/')) || name.contains(QLatin1Char('\\'))
        || name.contains(QStringLiteral("..")))
        return false;
    // Stored names are uuid + "." + suffix.
    const int dot = name.lastIndexOf(QLatin1Char('.'));
    return dot > 0 && dot < name.size() - 1;
}
