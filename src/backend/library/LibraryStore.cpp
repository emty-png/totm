#include "LibraryStore.h"

#include "AppPaths.h"
#include "SvgImport.h"

#include <QCache>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFontDatabase>
#include <QClipboard>
#include <QGuiApplication>
#include <QMimeData>
#include <QImage>
#include <QImageReader>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDesktopServices>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUrl>
#include <QUuid>
#include <functional>

namespace {
constexpr int kSchemaVersion = 3;
constexpr int kMaxNameLength = 120;
// .totm import cap: blobs allow 100MB image/audio + 1GB video; base64
// inflates ~4/3. 1.5GiB covers a maxed-out design without letting a
// malicious file OOM the app via readAll() before per-blob checks.
constexpr qint64 kMaxImportBytes = qint64(1536) * 1024 * 1024;

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

QString sanitizeStem(const QString &raw) {
    QString safe;
    safe.reserve(raw.size());
    for (QChar c : raw) {
        const uint u = c.unicode();
        if ((u >= 'a' && u <= 'z') || (u >= 'A' && u <= 'Z') || (u >= '0' && u <= '9') || c == u'-' || c == u'_')
            safe.append(c);
        else
            safe.append(u'_');
    }
    return safe;
}

QString thumbsDir() {
    return AppPaths::totmBaseDir() + QStringLiteral("/thumbs");
}

void sweepThumbPrefix(const QString &prefix) {
    const QString safe = sanitizeStem(prefix);
    const QString dir = thumbsDir();
    for (const QString &f : QDir(dir).entryList(QDir::Files)) {
        if (f.startsWith(safe + QStringLiteral("_")) && f.endsWith(QStringLiteral(".png")))
            QFile::remove(dir + QStringLiteral("/") + f);
    }
}

QSet<QString> collectNodeStringRefs(QList<QVariantList> stack, const QString &key) {
    QSet<QString> out;
    while (!stack.isEmpty()) {
        const QVariantList nodes = stack.takeLast();
        for (const QVariant &v : nodes) {
            const QVariantMap n = v.toMap();
            const QString src = n.value(key).toString();
            if (!src.isEmpty())
                out.insert(src);
            if (n.value(QStringLiteral("kind")).toString() == QLatin1String("group"))
                stack.append(n.value(QStringLiteral("children")).toList());
        }
    }
    return out;
}

// Font families used by text leaves (groups recursed, sorted). Runs
// carry no family (per-run bold/italic/color only), so the leaf
// fontFamily value is the whole story.
QStringList collectFontFamilies(const QVariantList &roots) {
    QSet<QString> out;
    QList<QVariantList> stack;
    stack.append(roots);
    while (!stack.isEmpty()) {
        const QVariantList nodes = stack.takeLast();
        for (const QVariant &v : nodes) {
            const QVariantMap n = v.toMap();
            if (n.value(QStringLiteral("kind")).toString() == QLatin1String("group")) {
                stack.append(n.value(QStringLiteral("children")).toList());
                continue;
            }
            const QString t = n.value(QStringLiteral("type")).toString();
            const QString st = n.value(QStringLiteral("shapeType")).toString();
            if (t != QLatin1String("text") && st != QLatin1String("text"))
                continue;
            const QString f = n.value(QStringLiteral("fontFamily"), QStringLiteral("Inter")).toString().trimmed();
            if (!f.isEmpty())
                out.insert(f);
        }
    }
    QStringList sorted = out.values();
    sorted.sort(Qt::CaseInsensitive);
    return sorted;
}

// Families unavailable on this device (case-insensitive). Bundled
// Inter resolves once main.cpp registers it; user fonts resolve once
// SettingsStore loads them — so a hit here means the receiving
// device (or viewer) likely substitutes too.
QStringList unavailableFonts(const QStringList &families) {
    const QStringList installed = QFontDatabase::families();
    QStringList missing;
    for (const QString &f : families) {
        bool ok = false;
        for (const QString &have : installed) {
            if (have.compare(f, Qt::CaseInsensitive) == 0) {
                ok = true;
                break;
            }
        }
        // Dedupe case-insensitively ("Foo" + "foo" warn once).
        if (!ok && !missing.contains(f, Qt::CaseInsensitive))
            missing.append(f);
    }
    return missing;
}

// Scene schema version carried by entryToScene output (0 when absent
// or unparseable: legacy files predate the field). Readers accept
// anything <= kSchemaVersion; foreign files above it are refused at
// the import gate below, own-library files load best-effort so a
// downgrade never nukes the library at startup.
int sceneVersion(const QVariantMap &scene) {
    bool ok = false;
    const int v = scene.value(QStringLiteral("version"), 0).toInt(&ok);
    return ok && v > 0 ? v : 0;
}

// Resolved .totm destination: delegates to AppPaths so the write and
// the QML overwrite probe share one suffix rule.
QString exportLocalPath(const QUrl &destination) {
    return AppPaths::resolveLocalFileWithSuffix(destination, QStringLiteral(".totm"));
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
    out[QStringLiteral("audio")] = scene.value(QStringLiteral("audio"), QVariantMap());
    return out;
}

QVariantMap entryToAsset(const QVariantMap &payload) {
    // Contract: assets carry detached node snapshots plus optional anim
    // clips targeting those nodes. Extra keys are dropped.
    QVariantMap out;
    out[QStringLiteral("version")] = kSchemaVersion;
    out[QStringLiteral("nodes")] = payload.value(QStringLiteral("nodes"), QVariantList());
    out[QStringLiteral("clips")] = payload.value(QStringLiteral("clips"), QVariantList());
    return out;
}

QVariantMap entryToShader(const QVariantMap &payload) {
    // Contract: shader assets carry presetId + vertex/fragment source +
    // uniform defaults. Extra keys are dropped; missing keys get safe
    // defaults so older payloads stay readable.
    // presetId "custom" marks from-scratch/imported GLSL: vertex +
    // fragment carry the live sources, basePreset is the CPU-export
    // fallback ("" = keep base paint), sourceKind is
    // preset|scratch|import, originFile the imported file name (""
    // otherwise).
    QVariantMap out;
    out[QStringLiteral("version")] = kSchemaVersion;
    out[QStringLiteral("presetId")] = payload.value(QStringLiteral("presetId"), QStringLiteral("plasma")).toString();
    out[QStringLiteral("vertex")] = payload.value(QStringLiteral("vertex"), QString()).toString();
    out[QStringLiteral("fragment")] = payload.value(QStringLiteral("fragment"), QString()).toString();
    out[QStringLiteral("uniforms")] = payload.value(QStringLiteral("uniforms"), QVariantMap());
    out[QStringLiteral("basePreset")] = payload.value(QStringLiteral("basePreset"),
        payload.value(QStringLiteral("presetId"), QStringLiteral("plasma"))).toString();
    const QString kind = payload.value(QStringLiteral("sourceKind")).toString();
    out[QStringLiteral("sourceKind")]
        = (kind == QStringLiteral("scratch") || kind == QStringLiteral("import")) ? kind : QStringLiteral("preset");
    out[QStringLiteral("originFile")] = payload.value(QStringLiteral("originFile"), QString()).toString().left(128);
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

QVariantList LibraryStore::assetList() const {
    return m_assetList;
}

QVariantList LibraryStore::shaderList() const {
    return m_shaderList;
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

bool LibraryStore::deleteWorkspaceAndDesigns(const QString &id) {
    const int at = findWorkspace(id);
    if (at < 0 || m_workspaceEntries.at(at).isDefault)
        return false;
    // Collect-then-remove so index math stays simple; scene files are
    // best-effort (a leftover is swept next boot and never blocks).
    QList<QString> doomed;
    for (const DesignEntry &design : m_designEntries) {
        if (design.workspaceId == id)
            doomed.append(design.id);
    }
    for (const QString &designId : doomed) {
        const int dat = findDesign(designId);
        if (dat >= 0)
            m_designEntries.removeAt(dat);
        QFile::remove(designsDir() + QStringLiteral("/") + designId + QStringLiteral(".json"));
    }
    m_workspaceEntries.removeAt(at);
    if (!persist())
        return false;
    rebuild();
    return true;
}

bool LibraryStore::moveWorkspace(const QString &id, int toIndex) {
    const int from = findWorkspace(id);
    if (from < 0 || m_workspaceEntries.isEmpty())
        return false;
    const int clamped = qBound(0, toIndex, m_workspaceEntries.size() - 1);
    if (clamped == from)
        return true;
    WorkspaceEntry entry = m_workspaceEntries.takeAt(from);
    m_workspaceEntries.insert(clamped, entry);
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
    // Drop cached home-grid thumbnails (stale stamps sweep on render).
    sweepThumbPrefix(id);
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
    if (!AppPaths::imageExtensions().contains(suffix)) {
        setLastError(tr("That image type is not supported (png, jpg, jpeg, webp, gif, svg)."));
        return {};
    }
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

QStringList LibraryStore::clipboardFileUrls() const
{
    const QClipboard *cb = QGuiApplication::clipboard();
    if (!cb)
        return {};
    const QMimeData *md = cb->mimeData();
    if (!md || !md->hasUrls())
        return {};
    QStringList out;
    for (const QUrl &u : md->urls()) {
        if (u.isLocalFile())
            out.append(u.toLocalFile());
    }
    return out;
}

bool LibraryStore::clipboardHasImage() const
{
    const QClipboard *cb = QGuiApplication::clipboard();
    return cb && cb->mimeData() && cb->mimeData()->hasImage();
}

QString LibraryStore::pasteClipboardImage()
{
    const QClipboard *cb = QGuiApplication::clipboard();
    const QImage img = cb ? cb->image() : QImage();
    if (img.isNull()) {
        setLastError(tr("The clipboard holds no image."));
        return {};
    }
    QDir().mkpath(imagesDir());
    const QString name = newId() + QStringLiteral(".png");
    if (!img.save(imagesDir() + QStringLiteral("/") + name, "PNG")) {
        setLastError(tr("Could not import that image."));
        return {};
    }
    clearError();
    return name;
}

QVariantMap LibraryStore::importSvgVectors(const QUrl &source)
{
    QVariantMap out;
    out[QStringLiteral("ok")] = false;
    const QString local = source.isLocalFile() ? source.toLocalFile() : source.toString();
    if (local.isEmpty() || QFileInfo(local).suffix().toLower() != QStringLiteral("svg")) {
        out[QStringLiteral("error")] = tr("Pick an SVG file first.");
        return out;
    }
    // Same stamp clamp as the image flow: a poster-sized SVG never
    // covers the scene; drags can still stretch larger.
    QVariantMap parsed = SvgImport::importFile(local, 800.0);
    if (!parsed.value(QStringLiteral("ok")).toBool()) {
        out[QStringLiteral("error")] = parsed.value(QStringLiteral("error"));
        return out;
    }
    clearError();
    return parsed;
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
    QList<QVariantList> roots;
    for (const DesignEntry &entry : m_designEntries)
        roots.append(entry.scene.value(QStringLiteral("nodes")).toList());
    for (const AssetEntry &entry : m_assetEntries)
        roots.append(entry.payload.value(QStringLiteral("nodes")).toList());
    return collectNodeStringRefs(roots, QStringLiteral("imageSource"));
}

void LibraryStore::sweepOrphanImages() {
    const QSet<QString> keep = referencedImages();
    const QDir dir(imagesDir());
    for (const QFileInfo &info : dir.entryInfoList(QDir::Files)) {
        if (!keep.contains(info.fileName()))
            QFile::remove(info.absoluteFilePath());
    }
}

QString LibraryStore::importAudio(const QUrl &source) {
    QString local = source.isLocalFile() ? source.toLocalFile() : source.toString();
    if (local.isEmpty()) {
        setLastError(tr("Pick an audio file first."));
        return {};
    }
    QFileInfo info(local);
    if (!info.exists() || !info.isFile()) {
        setLastError(tr("Could not read that audio file."));
        return {};
    }
    const QString suffix = info.suffix().toLower();
    if (!AppPaths::audioExtensions().contains(suffix)) {
        setLastError(tr("That audio type is not supported (mp3, wav, ogg, flac)."));
        return {};
    }
    QDir().mkpath(audioDir());
    const QString name = newId() + QStringLiteral(".") + suffix;
    const QString dest = audioDir() + QStringLiteral("/") + name;
    if (!QFile::copy(local, dest)) {
        setLastError(tr("Could not import that audio file."));
        return {};
    }
    clearError();
    return name;
}

QUrl LibraryStore::audioUrl(const QString &name) const {
    if (name.isEmpty())
        return {};
    const QString resolved = resolveAudioFile(name);
    if (resolved.isEmpty())
        return {};
    return QUrl::fromLocalFile(resolved);
}

bool LibraryStore::hasAudio(const QString &name) const {
    if (name.isEmpty())
        return false;
    return !resolveAudioFile(name).isEmpty();
}

quint64 LibraryStore::audioDiskUsage() const {
    quint64 total = 0;
    const QDir dir(audioDir());
    for (const QFileInfo &info : dir.entryInfoList(QDir::Files))
        total += static_cast<quint64>(info.size());
    return total;
}

int LibraryStore::audioCount() const {
    // Peaks sidecars (<blob>.peaks) share the dir but are not clips.
    int n = 0;
    for (const QString &f : QDir(audioDir()).entryList(QDir::Files)) {
        if (f.endsWith(QStringLiteral(".peaks"), Qt::CaseInsensitive))
            continue;
        if (isSafeAudioName(f))
            n++;
    }
    return n;
}

QVariantList LibraryStore::audioPeaks(const QString &name, int buckets, double offset, double window) {
    if (name.isEmpty())
        return {};
    // Legacy absolute paths (detached video sound from old designs)
    // decode straight from the file with a memory-only cache; blob
    // names use the sidecar path (audio/ blobs in audio/, video blobs
    // in videos/ so detached sound keeps its waveform).
    if (name.contains(QLatin1Char('/')) || name.contains(QLatin1Char('\\'))) {
        if (!QFile::exists(name))
            return {};
        return m_peaks.peaksForAbsolute(name, buckets, offset, window);
    }
    if (!isSafeAudioName(name) && !isSafeVideoName(name))
        return {};
    const QString audioPath = audioDir() + QStringLiteral("/") + name;
    if (QFile::exists(audioPath))
        return m_peaks.peaksFor(audioDir(), name, buckets, offset, window);
    const QString videoPath = videosDir() + QStringLiteral("/") + name;
    if (QFile::exists(videoPath))
        return m_peaks.peaksFor(videosDir(), name, buckets, offset, window);
    return {};
}

QString LibraryStore::importVideo(const QUrl &source) {
    QString local = source.isLocalFile() ? source.toLocalFile() : source.toString();
    if (local.isEmpty()) {
        setLastError(tr("Pick a video file first."));
        return {};
    }
    QFileInfo info(local);
    if (!info.exists() || !info.isFile()) {
        setLastError(tr("Could not read that video file."));
        return {};
    }
    static const QStringList allowed = {QStringLiteral("mp4"), QStringLiteral("webm"),
        QStringLiteral("mov"), QStringLiteral("m4v"), QStringLiteral("mkv")};
    const QString suffix = info.suffix().toLower();
    if (!allowed.contains(suffix)) {
        setLastError(tr("That video type is not supported (mp4, webm, mov, m4v, mkv)."));
        return {};
    }
    QDir().mkpath(videosDir());
    const QString name = newId() + QStringLiteral(".") + suffix;
    const QString dest = videosDir() + QStringLiteral("/") + name;
    if (!QFile::copy(local, dest)) {
        setLastError(tr("Could not import that video."));
        return {};
    }
    clearError();
    return name;
}

QString LibraryStore::normalizeVideoPath(const QUrl &source) {
    // Legacy entry point: now copies into videos/ like images/audio so
    // deleting the original never breaks the design. Returns the stored
    // blob name (callers probe/resolve it via videoProbe/videoUrl).
    return importVideo(source);
}

QUrl LibraryStore::videoUrl(const QString &ref) const {
    const QString resolved = resolveVideoFile(ref);
    if (resolved.isEmpty())
        return {};
    return QUrl::fromLocalFile(resolved);
}

bool LibraryStore::hasVideo(const QString &ref) const {
    return !resolveVideoFile(ref).isEmpty();
}

bool LibraryStore::revealVideo(const QString &ref) const {
    const QString resolved = resolveVideoFile(ref);
    QString dir;
    if (!resolved.isEmpty()) {
        dir = QFileInfo(resolved).absolutePath();
    } else if (!ref.isEmpty()) {
        // Missing legacy path: best effort on its old folder.
        const QFileInfo info(ref);
        if (!info.absolutePath().isEmpty())
            dir = info.absolutePath();
    }
    if (dir.isEmpty() || !QDir(dir).exists())
        dir = QStandardPaths::writableLocation(QStandardPaths::MoviesLocation);
    if (dir.isEmpty() || !QDir(dir).exists())
        return false;
    return QDesktopServices::openUrl(QUrl::fromLocalFile(dir));
}

quint64 LibraryStore::videosDiskUsage() const {
    quint64 total = 0;
    const QDir dir(videosDir());
    for (const QFileInfo &info : dir.entryInfoList(QDir::Files))
        total += static_cast<quint64>(info.size());
    return total;
}

int LibraryStore::videoCount() const {
    int n = 0;
    for (const QString &f : QDir(videosDir()).entryList(QDir::Files)) {
        if (f.endsWith(QStringLiteral(".peaks"), Qt::CaseInsensitive))
            continue;
        if (isSafeVideoName(f))
            n++;
    }
    return n;
}

int LibraryStore::linkedVideoCount(const QString &id) const {
    const int at = findDesign(id);
    if (at < 0)
        return 0;
    int count = 0;
    QList<QVariantList> stack;
    stack.append(m_designEntries.at(at).scene.value(QStringLiteral("nodes")).toList());
    while (!stack.isEmpty()) {
        const QVariantList nodes = stack.takeLast();
        for (const QVariant &v : nodes) {
            const QVariantMap n = v.toMap();
            if (n.value(QStringLiteral("kind")).toString() == QLatin1String("group")) {
                stack.append(n.value(QStringLiteral("children")).toList());
                continue;
            }
            const QString t = n.value(QStringLiteral("type")).toString();
            const QString st = n.value(QStringLiteral("shapeType")).toString();
            if (t != QLatin1String("video") && st != QLatin1String("video"))
                continue;
            const QString src = n.value(QStringLiteral("videoSource")).toString();
            if (src.isEmpty())
                continue;
            // Stored blobs are packed into .totm; only legacy absolute
            // paths count as linked (old designs until re-imported).
            if (src.contains(QLatin1Char('/')) || src.contains(QLatin1Char('\\')))
                count++;
        }
    }
    return count;
}

QVariantMap LibraryStore::videoProbe(const QString &ref) const {
    QVariantMap out;
    out[QStringLiteral("ok")] = false;
    out[QStringLiteral("duration")] = 0.0;
    out[QStringLiteral("width")] = 0;
    out[QStringLiteral("height")] = 0;
    out[QStringLiteral("hasAudio")] = false;
    if (ref.isEmpty())
        return out;
    const QString resolved = resolveVideoFile(ref);
    if (resolved.isEmpty())
        return out;
    // Missing files bypass the cache (no spawn, instant return) so a
    // restored file probes fresh on the next pass instead of sticking
    // to a cached failure.
    QFileInfo info(resolved);
    if (!info.exists() || !info.isFile())
        return out;
    // Memoized per content generation: placement, panel, timeline and
    // relink probes share one ffmpeg spawn; edits bust the key.
    const QString key = resolved + QLatin1Char('@')
        + QString::number(info.lastModified().toMSecsSinceEpoch()) + QLatin1Char('@')
        + QString::number(info.size());
    if (QVariantMap *hit = m_videoProbes.object(key))
        return *hit;
    auto cached = [&](const QVariantMap &r) {
        m_videoProbes.insert(key, new QVariantMap(r));
        return r;
    };
    const QString ffmpeg = AppPaths::findFfmpeg();
    if (ffmpeg.isEmpty())
        return cached(out);
    QProcess proc;
    proc.start(ffmpeg, {QStringLiteral("-hide_banner"), QStringLiteral("-i"), resolved});
    if (!proc.waitForFinished(8000))
        return cached(out);
    // One stderr dump carries everything: Duration line plus per-stream
    // descriptors. Labels print in English regardless of locale.
    const QString err = QString::fromLocal8Bit(proc.readAllStandardError());
    static const QRegularExpression durRe(QStringLiteral("Duration:\\s*(\\d+):(\\d+):([\\d.]+)"));
    const QRegularExpressionMatch durMatch = durRe.match(err);
    if (!durMatch.hasMatch())
        return cached(out);
    const double secs = durMatch.captured(1).toDouble() * 3600.0 + durMatch.captured(2).toDouble() * 60.0
        + durMatch.captured(3).toDouble();
    if (!(secs > 0.0))
        return cached(out);
    static const QRegularExpression videoRe(QStringLiteral("Stream[^\\n]*?Video:[^\\n]*?(\\d{2,5})x(\\d{2,5})"));
    const QRegularExpressionMatch videoMatch = videoRe.match(err);
    if (!videoMatch.hasMatch())
        return cached(out);
    out[QStringLiteral("ok")] = true;
    out[QStringLiteral("duration")] = secs;
    out[QStringLiteral("width")] = videoMatch.captured(1).toInt();
    out[QStringLiteral("height")] = videoMatch.captured(2).toInt();
    out[QStringLiteral("hasAudio")] = err.contains(QStringLiteral("Audio:"));
    return cached(out);
}

bool LibraryStore::exportDesign(const QString &id, const QUrl &destination, bool overwrite) {
    const int at = findDesign(id);
    if (at < 0) {
        setLastError(tr("Design not found."));
        return false;
    }
    const QString local = exportLocalPath(destination);
    if (local.isEmpty()) {
        setLastError(tr("Pick a destination file first."));
        return false;
    }
    if (!overwrite && QFile::exists(local)) {
        setLastError(tr("“%1” already exists. Confirm to replace it.").arg(QFileInfo(local).fileName()));
        return false;
    }
    const QVariantMap scene = entryToScene(m_designEntries.at(at).scene);
    // Referenced blobs for this scene only (groups included). Videos
    // include node sources plus audio clips pointing at video blobs
    // (detached sound shares the video file). Legacy absolute video
    // paths are packed too when the file still exists, so old designs
    // export self-contained and re-import as blobs.
    QSet<QString> images;
    QSet<QString> videoRefs;
    QSet<QString> shaderRefs;
    QList<QVariantList> stack;
    stack.append(scene.value(QStringLiteral("nodes")).toList());
    while (!stack.isEmpty()) {
        const QVariantList nodes = stack.takeLast();
        for (const QVariant &v : nodes) {
            const QVariantMap n = v.toMap();
            const QString src = n.value(QStringLiteral("imageSource")).toString();
            if (!src.isEmpty())
                images.insert(src);
            const QString vsrc = n.value(QStringLiteral("videoSource")).toString();
            if (!vsrc.isEmpty())
                videoRefs.insert(vsrc);
            const QString sid = n.value(QStringLiteral("shaderId")).toString();
            if (!sid.isEmpty() && !sid.startsWith(QLatin1String("preset:")))
                shaderRefs.insert(sid);
            if (n.value(QStringLiteral("kind")).toString() == QLatin1String("group"))
                stack.append(n.value(QStringLiteral("children")).toList());
        }
    }
    QSet<QString> audios;
    const QVariantMap audio = scene.value(QStringLiteral("audio")).toMap();
    for (const QVariant &v : audio.value(QStringLiteral("clips")).toList()) {
        const QString src = v.toMap().value(QStringLiteral("source")).toString();
        if (src.isEmpty())
            continue;
        audios.insert(src);
        // Detached video sound rides on the video blob: pack it with the
        // videos so the clip survives the round-trip even when no video
        // node references the file anymore. Suffix-gated (the name
        // guards are loose dotted names): audio-suffixed clips stay
        // audio-owned for counting.
        const QString asuf = src.section(QLatin1Char('.'), -1).toLower();
        if (!src.contains(QLatin1Char('/')) && !src.contains(QLatin1Char('\\'))
            && AppPaths::videoExtensions().contains(asuf))
            videoRefs.insert(src);
    }
    // Unpacked blobs are skipped so one lost file never blocks sharing;
    // per-kind counts ride the warning channel (see below).
    int skippedImages = 0, skippedAudios = 0, skippedVideos = 0;
    QJsonObject imageBlobs;
    for (const QString &name : images) {
        if (!isSafeImageName(name)) {
            ++skippedImages;
            continue;
        }
        QFile f(imagesDir() + QStringLiteral("/") + name);
        if (!f.open(QIODevice::ReadOnly)) {
            ++skippedImages;
            continue;
        }
        const QByteArray raw = f.readAll();
        if (!raw.isEmpty())
            imageBlobs[name] = QString::fromLatin1(raw.toBase64());
        else
            ++skippedImages;
    }
    QJsonObject audioBlobs;
    for (const QString &name : audios) {
        if (!isSafeAudioName(name)) {
            ++skippedAudios;
            continue;
        }
        // Video blobs referenced by audio clips live in videos/, not
        // audio/ — they are packed (and counted) with the videos below.
        // Suffix-gated like the collector above: audio-suffixed names
        // stay audio-owned here.
        const QString asuf = name.section(QLatin1Char('.'), -1).toLower();
        if (AppPaths::videoExtensions().contains(asuf) && !name.contains(QLatin1Char('/')) && !name.contains(QLatin1Char('\\')))
            continue;
        QFile f(audioDir() + QStringLiteral("/") + name);
        if (!f.open(QIODevice::ReadOnly)) {
            ++skippedAudios;
            continue;
        }
        const QByteArray raw = f.readAll();
        if (!raw.isEmpty())
            audioBlobs[name] = QString::fromLatin1(raw.toBase64());
        else
            ++skippedAudios;
    }
    QJsonObject videoBlobs;
    const QSet<QString> &videoOk = AppPaths::videoExtensions();
    for (const QString &ref : videoRefs) {
        QString filePath;
        QString suffix;
        if (isSafeVideoName(ref)) {
            suffix = ref.section(QLatin1Char('.'), -1).toLower();
            if (!videoOk.contains(suffix)) {
                ++skippedVideos;
                continue;
            }
            filePath = videosDir() + QStringLiteral("/") + ref;
        } else if (ref.contains(QLatin1Char('/')) || ref.contains(QLatin1Char('\\'))) {
            // Legacy absolute path: pack by content so the import lands
            // as a stored blob.
            suffix = ref.section(QLatin1Char('.'), -1).toLower();
            if (!videoOk.contains(suffix)) {
                ++skippedVideos;
                continue;
            }
            if (!QFile::exists(ref)) {
                ++skippedVideos;
                continue;
            }
            filePath = ref;
        } else {
            ++skippedVideos;
            continue;
        }
        QFile vf(filePath);
        if (!vf.open(QIODevice::ReadOnly)) {
            ++skippedVideos;
            continue;
        }
        const QByteArray raw = vf.readAll();
        if (!raw.isEmpty())
            videoBlobs[ref] = QString::fromLatin1(raw.toBase64());
        else
            ++skippedVideos;
    }
    // Custom shader assets referenced by nodes: pack name+payload so the
    // design stays self-contained. Preset ids need no packing.
    QJsonObject shaderBlobs;
    int skippedShaders = 0;
    for (const QString &sid : shaderRefs) {
        const int sat = findShader(sid);
        if (sat < 0) {
            ++skippedShaders;
            continue;
        }
        const ShaderEntry &se = m_shaderEntries.at(sat);
        QJsonObject obj;
        obj[QStringLiteral("name")] = se.name;
        obj[QStringLiteral("payload")] = QJsonObject::fromVariantMap(se.payload);
        shaderBlobs[sid] = obj;
    }
    const QJsonObject root{
        {QStringLiteral("app"), QStringLiteral("totm")},
        {QStringLiteral("kind"), QStringLiteral("totm-design")},
        {QStringLiteral("version"), kSchemaVersion},
        {QStringLiteral("name"), m_designEntries.at(at).name},
        {QStringLiteral("scene"), QJsonObject::fromVariantMap(scene)},
        {QStringLiteral("blobs"), QJsonObject{
                                      {QStringLiteral("images"), imageBlobs},
                                      {QStringLiteral("audio"), audioBlobs},
                                      {QStringLiteral("videos"), videoBlobs},
                                      {QStringLiteral("shaders"), shaderBlobs},
                                  }},
    };
    QSaveFile out(local);
    if (!out.open(QIODevice::WriteOnly)) {
        setLastError(tr("Could not write that file: %1").arg(out.errorString()));
        return false;
    }
    out.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    if (!out.commit()) {
        setLastError(tr("Could not write that file: %1").arg(out.errorString()));
        return false;
    }
    // Degraded success still reports: missing blobs show as placeholders
    // on import, and unembedded fonts substitute on foreign devices.
    QStringList warnings;
    if (skippedImages + skippedAudios + skippedVideos > 0) {
        QStringList parts;
        if (skippedImages > 0)
            parts.append(tr("%n image(s)", "", skippedImages));
        if (skippedAudios > 0)
            parts.append(tr("%n audio file(s)", "", skippedAudios));
        if (skippedVideos > 0)
            parts.append(tr("%n video(s)", "", skippedVideos));
        warnings.append(tr("Shared without %1 — missing on this device. Placeholders show on import.").arg(parts.join(QStringLiteral(", "))));
    }
    if (skippedShaders > 0)
        warnings.append(tr("%n shader(s) missing on this device — importing nodes fall back to Plasma.", "", skippedShaders));
    const QStringList missingFonts = unavailableFonts(collectFontFamilies(scene.value(QStringLiteral("nodes")).toList()));
    if (!missingFonts.isEmpty())
        warnings.append(tr("Fonts not embedded (%1) — install them on the receiving device or text may substitute.").arg(missingFonts.join(QStringLiteral(", "))));
    clearError();
    if (!warnings.isEmpty())
        setLastWarning(warnings.join(QStringLiteral(" ")));
    return true;
}

bool LibraryStore::exportDestinationExists(const QUrl &destination) const {
    const QString local = exportLocalPath(destination);
    return !local.isEmpty() && QFile::exists(local);
}

QString LibraryStore::importDesign(const QString &workspaceId, const QUrl &source) {
    QString local = source.isLocalFile() ? source.toLocalFile() : source.toString();
    if (local.isEmpty()) {
        setLastError(tr("Pick a .totm file first."));
        return {};
    }
    QFile f(local);
    if (!f.open(QIODevice::ReadOnly)) {
        setLastError(tr("Could not read that file."));
        return {};
    }
    if (f.size() > kMaxImportBytes) {
        setLastError(tr("That file is too large to import."));
        return {};
    }
    const QByteArray rawJson = f.readAll();
    if (rawJson.size() > kMaxImportBytes) {
        setLastError(tr("That file is too large to import."));
        return {};
    }
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(rawJson, &parseError);
    const QJsonObject root = doc.object();
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()
        || root.value(QStringLiteral("app")).toString() != QLatin1String("totm")
        || root.value(QStringLiteral("kind")).toString() != QLatin1String("totm-design")
        || !root.value(QStringLiteral("scene")).isObject()) {
        setLastError(tr("That file is not a totm design."));
        return {};
    }
    // Forward-compat gate: scenes above our schema may carry fields we
    // would silently drop or misread, so refuse with an update hint
    // instead of importing a corrupted-looking design. Own-library
    // files bypass this (readDesignFile loads best-effort) so a
    // downgrade never nukes the library at startup.
    const QVariantMap rawScene = root.value(QStringLiteral("scene")).toObject().toVariantMap();
    if (sceneVersion(rawScene) > kSchemaVersion) {
        setLastError(tr("That design was made by a newer totm (scene v%1) — update to open it.").arg(sceneVersion(rawScene)));
        return {};
    }
    const QString target = findWorkspace(workspaceId) >= 0 ? workspaceId : m_defaultWorkspaceId;
    QVariantMap scene = entryToScene(rawScene);
    const QJsonObject blobs = root.value(QStringLiteral("blobs")).toObject();
    const QJsonObject imageBlobs = blobs.value(QStringLiteral("images")).toObject();
    const QJsonObject audioBlobs = blobs.value(QStringLiteral("audio")).toObject();
    const QJsonObject videoBlobs = blobs.value(QStringLiteral("videos")).toObject();
    const QSet<QString> &imageOk = AppPaths::imageExtensions();
    const QSet<QString> &audioOk = AppPaths::audioExtensions();
    const QSet<QString> &videoOk = AppPaths::videoExtensions();
    // Remap helper: store each referenced blob under a fresh uuid name so
    // imports never collide with library files. Missing/invalid blobs
    // keep their refs (canvas shows the neutral placeholder, export
    // skips them) instead of failing the whole import; per-kind miss
    // counts ride the warning channel (see below).
    int missingImages = 0, missingAudios = 0, missingVideos = 0;
    QHash<QString, QString> imageMap;
    {
        QSet<QString> refs;
        QList<QVariantList> stack;
        stack.append(scene.value(QStringLiteral("nodes")).toList());
        while (!stack.isEmpty()) {
            const QVariantList nodes = stack.takeLast();
            for (const QVariant &v : nodes) {
                const QVariantMap n = v.toMap();
                const QString src = n.value(QStringLiteral("imageSource")).toString();
                if (!src.isEmpty())
                    refs.insert(src);
                if (n.value(QStringLiteral("kind")).toString() == QLatin1String("group"))
                    stack.append(n.value(QStringLiteral("children")).toList());
            }
        }
        QDir().mkpath(imagesDir());
        for (const QString &ref : refs) {
            const QString b64 = imageBlobs.value(ref).toString();
            if (b64.isEmpty()) {
                ++missingImages;
                continue;
            }
            const QByteArray raw = QByteArray::fromBase64(b64.toLatin1());
            if (raw.isEmpty() || raw.size() > 100 * 1024 * 1024) {
                ++missingImages;
                continue;
            }
            QString suffix = ref.section(QLatin1Char('.'), -1).toLower();
            if (!imageOk.contains(suffix))
                suffix = QStringLiteral("png");
            const QString fresh = newId() + QStringLiteral(".") + suffix;
            QFile out(imagesDir() + QStringLiteral("/") + fresh);
            if (!out.open(QIODevice::WriteOnly) || out.write(raw) != raw.size()) {
                ++missingImages;
                continue;
            }
            imageMap.insert(ref, fresh);
        }
        if (!imageMap.isEmpty()) {
            std::function<void(QVariantList &)> rewrite = [&](QVariantList &nodes) {
                for (int i = 0; i < nodes.size(); ++i) {
                    QVariantMap n = nodes.at(i).toMap();
                    const QString src = n.value(QStringLiteral("imageSource")).toString();
                    if (!src.isEmpty() && imageMap.contains(src))
                        n[QStringLiteral("imageSource")] = imageMap.value(src);
                    if (n.value(QStringLiteral("kind")).toString() == QLatin1String("group")) {
                        QVariantList kids = n.value(QStringLiteral("children")).toList();
                        rewrite(kids);
                        n[QStringLiteral("children")] = kids;
                    }
                    nodes[i] = n;
                }
            };
            QVariantList nodes = scene.value(QStringLiteral("nodes")).toList();
            rewrite(nodes);
            scene[QStringLiteral("nodes")] = nodes;
        }
    }
    {
        QVariantMap audio = scene.value(QStringLiteral("audio")).toMap();
        QVariantList clips = audio.value(QStringLiteral("clips")).toList();
        bool changed = false;
        QDir().mkpath(audioDir());
        for (int i = 0; i < clips.size(); ++i) {
            QVariantMap c = clips.at(i).toMap();
            const QString ref = c.value(QStringLiteral("source")).toString();
            if (ref.isEmpty())
                continue;
            // Video blobs referenced by detached-sound clips are remapped
            // with the videos below; skip them here so they are not
            // duplicated into audio/ under an audio suffix.
            if (!ref.contains(QLatin1Char('/')) && !ref.contains(QLatin1Char('\\'))
                && videoBlobs.contains(ref))
                continue;
            const QString b64 = audioBlobs.value(ref).toString();
            if (b64.isEmpty()) {
                ++missingAudios;
                continue;
            }
            const QByteArray raw = QByteArray::fromBase64(b64.toLatin1());
            if (raw.isEmpty() || raw.size() > 100 * 1024 * 1024) {
                ++missingAudios;
                continue;
            }
            QString suffix = ref.section(QLatin1Char('.'), -1).toLower();
            if (!audioOk.contains(suffix)) {
                ++missingAudios;
                continue;
            }
            const QString fresh = newId() + QStringLiteral(".") + suffix;
            QFile out(audioDir() + QStringLiteral("/") + fresh);
            if (!out.open(QIODevice::WriteOnly) || out.write(raw) != raw.size()) {
                ++missingAudios;
                continue;
            }
            c[QStringLiteral("source")] = fresh;
            clips[i] = c;
            changed = true;
        }
        if (changed) {
            audio[QStringLiteral("clips")] = clips;
            scene[QStringLiteral("audio")] = audio;
        }
    }
    {
        // Video blobs: node sources plus detached-sound clips sharing the
        // video file. Each lands under a fresh uuid name in videos/; both
        // node refs and matching audio clip sources are remapped so the
        // design plays offline. Videos allow up to 1GB per blob (footage
        // dwarfs the 100MB image/audio cap).
        QSet<QString> refs;
        QList<QVariantList> stack;
        stack.append(scene.value(QStringLiteral("nodes")).toList());
        while (!stack.isEmpty()) {
            const QVariantList nodes = stack.takeLast();
            for (const QVariant &v : nodes) {
                const QVariantMap n = v.toMap();
                const QString src = n.value(QStringLiteral("videoSource")).toString();
                if (!src.isEmpty())
                    refs.insert(src);
                if (n.value(QStringLiteral("kind")).toString() == QLatin1String("group"))
                    stack.append(n.value(QStringLiteral("children")).toList());
            }
        }
        QVariantMap audio = scene.value(QStringLiteral("audio")).toMap();
        QVariantList clips = audio.value(QStringLiteral("clips")).toList();
        for (const QVariant &v : clips) {
            const QString src = v.toMap().value(QStringLiteral("source")).toString();
            if (!src.isEmpty() && videoBlobs.contains(src))
                refs.insert(src);
        }
        QHash<QString, QString> videoMap;
        QDir().mkpath(videosDir());
        for (const QString &ref : refs) {
            const QString b64 = videoBlobs.value(ref).toString();
            if (b64.isEmpty()) {
                ++missingVideos;
                continue;
            }
            const QByteArray raw = QByteArray::fromBase64(b64.toLatin1());
            if (raw.isEmpty() || raw.size() > 1024LL * 1024 * 1024) {
                ++missingVideos;
                continue;
            }
            QString suffix = ref.section(QLatin1Char('.'), -1).toLower();
            if (!videoOk.contains(suffix)) {
                ++missingVideos;
                continue;
            }
            const QString fresh = newId() + QStringLiteral(".") + suffix;
            QFile out(videosDir() + QStringLiteral("/") + fresh);
            if (!out.open(QIODevice::WriteOnly) || out.write(raw) != raw.size()) {
                ++missingVideos;
                continue;
            }
            videoMap.insert(ref, fresh);
        }
        if (!videoMap.isEmpty()) {
            std::function<void(QVariantList &)> rewrite = [&](QVariantList &nodes) {
                for (int i = 0; i < nodes.size(); ++i) {
                    QVariantMap n = nodes.at(i).toMap();
                    const QString src = n.value(QStringLiteral("videoSource")).toString();
                    if (!src.isEmpty() && videoMap.contains(src))
                        n[QStringLiteral("videoSource")] = videoMap.value(src);
                    if (n.value(QStringLiteral("kind")).toString() == QLatin1String("group")) {
                        QVariantList kids = n.value(QStringLiteral("children")).toList();
                        rewrite(kids);
                        n[QStringLiteral("children")] = kids;
                    }
                    nodes[i] = n;
                }
            };
            QVariantList nodes = scene.value(QStringLiteral("nodes")).toList();
            rewrite(nodes);
            scene[QStringLiteral("nodes")] = nodes;
            bool clipsChanged = false;
            for (int i = 0; i < clips.size(); ++i) {
                QVariantMap c = clips.at(i).toMap();
                const QString src = c.value(QStringLiteral("source")).toString();
                if (!src.isEmpty() && videoMap.contains(src)) {
                    c[QStringLiteral("source")] = videoMap.value(src);
                    clips[i] = c;
                    clipsChanged = true;
                }
            }
            if (clipsChanged) {
                audio[QStringLiteral("clips")] = clips;
                scene[QStringLiteral("audio")] = audio;
            }
        }
    }
    int missingShaders = 0;
    {
        const QJsonObject shaderBlobs = blobs.value(QStringLiteral("shaders")).toObject();
        QSet<QString> refs;
        QList<QVariantList> stack;
        stack.append(scene.value(QStringLiteral("nodes")).toList());
        while (!stack.isEmpty()) {
            const QVariantList nodes = stack.takeLast();
            for (const QVariant &v : nodes) {
                const QVariantMap n = v.toMap();
                const QString sid = n.value(QStringLiteral("shaderId")).toString();
                if (!sid.isEmpty() && !sid.startsWith(QLatin1String("preset:")))
                    refs.insert(sid);
                if (n.value(QStringLiteral("kind")).toString() == QLatin1String("group"))
                    stack.append(n.value(QStringLiteral("children")).toList());
            }
        }
        QHash<QString, QString> shaderMap;
        for (const QString &ref : refs) {
            const QJsonObject obj = shaderBlobs.value(ref).toObject();
            if (obj.isEmpty() || !obj.value(QStringLiteral("payload")).isObject()) {
                // Already have it locally (same library re-import)? Keep id.
                if (findShader(ref) >= 0)
                    continue;
                ++missingShaders;
                continue;
            }
            ShaderEntry se;
            se.id = newId();
            se.name = trimmedName(obj.value(QStringLiteral("name")).toString(), tr("Imported shader"));
            se.createdAt = nowIso();
            se.updatedAt = se.createdAt;
            se.payload = entryToShader(obj.value(QStringLiteral("payload")).toObject().toVariantMap());
            m_shaderEntries.prepend(se);
            if (!writeShaderFile(se.id, se.payload)) {
                m_shaderEntries.removeAt(findShader(se.id));
                ++missingShaders;
                continue;
            }
            shaderMap.insert(ref, se.id);
        }
        if (!shaderMap.isEmpty()) {
            std::function<void(QVariantList &)> rewrite = [&](QVariantList &nodes) {
                for (int i = 0; i < nodes.size(); ++i) {
                    QVariantMap n = nodes.at(i).toMap();
                    const QString sid = n.value(QStringLiteral("shaderId")).toString();
                    if (!sid.isEmpty() && shaderMap.contains(sid))
                        n[QStringLiteral("shaderId")] = shaderMap.value(sid);
                    if (n.value(QStringLiteral("kind")).toString() == QLatin1String("group")) {
                        QVariantList kids = n.value(QStringLiteral("children")).toList();
                        rewrite(kids);
                        n[QStringLiteral("children")] = kids;
                    }
                    nodes[i] = n;
                }
            };
            QVariantList nodes = scene.value(QStringLiteral("nodes")).toList();
            rewrite(nodes);
            scene[QStringLiteral("nodes")] = nodes;
            persist();
            rebuild();
        }
    }
    DesignEntry entry;
    entry.id = newId();
    entry.workspaceId = target;
    entry.name = trimmedName(root.value(QStringLiteral("name")).toString(), tr("Imported"));
    entry.createdAt = nowIso();
    entry.updatedAt = entry.createdAt;
    entry.scene = entryToScene(scene);
    m_designEntries.prepend(entry);
    if (!writeDesignFile(entry.id, entry.scene) || !persist()) {
        m_designEntries.removeAt(findDesign(entry.id));
        return {};
    }
    rebuild();
    // Degraded success still reports: unmapped refs render as
    // placeholders, and fonts missing here substitute on canvas.
    QStringList warnings;
    if (missingImages + missingAudios + missingVideos > 0) {
        QStringList parts;
        if (missingImages > 0)
            parts.append(tr("%n image(s)", "", missingImages));
        if (missingAudios > 0)
            parts.append(tr("%n audio file(s)", "", missingAudios));
        if (missingVideos > 0)
            parts.append(tr("%n video(s)", "", missingVideos));
        warnings.append(tr("Imported with %1 placeholder(s) — files missing from the bundle (%2).").arg(missingImages + missingAudios + missingVideos).arg(parts.join(QStringLiteral(", "))));
    }
    if (missingShaders > 0)
        warnings.append(tr("%n shader(s) missing from the bundle — affected nodes fall back to Plasma.", "", missingShaders));
    const QStringList missingFonts = unavailableFonts(collectFontFamilies(scene.value(QStringLiteral("nodes")).toList()));
    if (!missingFonts.isEmpty())
        warnings.append(tr("Fonts not installed here (%1) — text may substitute.").arg(missingFonts.join(QStringLiteral(", "))));
    clearError();
    if (!warnings.isEmpty())
        setLastWarning(warnings.join(QStringLiteral(" ")));
    return entry.id;
}

QString LibraryStore::createAsset(const QString &name, const QVariantMap &payload) {
    const QVariantList nodes = payload.value(QStringLiteral("nodes")).toList();
    if (nodes.isEmpty())
        return {};
    AssetEntry entry;
    entry.id = newId();
    entry.name = trimmedName(name, tr("Untitled asset"));
    entry.createdAt = nowIso();
    entry.updatedAt = entry.createdAt;
    entry.payload = entryToAsset(payload);
    m_assetEntries.prepend(entry);
    if (!writeAssetFile(entry.id, entry.payload) || !persist()) {
        m_assetEntries.removeAt(findAsset(entry.id));
        return {};
    }
    rebuild();
    clearError();
    return entry.id;
}

bool LibraryStore::renameAsset(const QString &id, const QString &name) {
    const int at = findAsset(id);
    if (at < 0)
        return false;
    const QString next = trimmedName(name, m_assetEntries.at(at).name);
    if (next == m_assetEntries.at(at).name)
        return true;
    m_assetEntries[at].name = next;
    m_assetEntries[at].updatedAt = nowIso();
    if (!persist())
        return false;
    rebuild();
    return true;
}

bool LibraryStore::deleteAsset(const QString &id) {
    const int at = findAsset(id);
    if (at < 0)
        return false;
    m_assetEntries.removeAt(at);
    QFile::remove(assetsDir() + QStringLiteral("/") + id + QStringLiteral(".json"));
    // Drop cached asset thumbnails (stale stamps sweep on render).
    sweepThumbPrefix(QStringLiteral("asset-") + id);
    if (!persist())
        return false;
    rebuild();
    return true;
}

QVariantMap LibraryStore::loadAsset(const QString &id) const {
    const int at = findAsset(id);
    if (at < 0)
        return {};
    return m_assetEntries.at(at).payload;
}

bool LibraryStore::hasAsset(const QString &id) const {
    return findAsset(id) >= 0;
}

QString LibraryStore::createShader(const QString &name, const QVariantMap &payload) {
    ShaderEntry entry;
    entry.id = newId();
    entry.name = trimmedName(name, tr("Untitled shader"));
    entry.createdAt = nowIso();
    entry.updatedAt = entry.createdAt;
    entry.payload = entryToShader(payload);
    m_shaderEntries.prepend(entry);
    if (!writeShaderFile(entry.id, entry.payload) || !persist()) {
        m_shaderEntries.removeAt(findShader(entry.id));
        return {};
    }
    rebuild();
    clearError();
    return entry.id;
}

bool LibraryStore::renameShader(const QString &id, const QString &name) {
    const int at = findShader(id);
    if (at < 0)
        return false;
    const QString next = trimmedName(name, m_shaderEntries.at(at).name);
    if (next == m_shaderEntries.at(at).name)
        return true;
    m_shaderEntries[at].name = next;
    m_shaderEntries[at].updatedAt = nowIso();
    if (!persist())
        return false;
    rebuild();
    return true;
}

bool LibraryStore::deleteShader(const QString &id) {
    const int at = findShader(id);
    if (at < 0)
        return false;
    m_shaderEntries.removeAt(at);
    QFile::remove(shadersDir() + QStringLiteral("/") + id + QStringLiteral(".json"));
    if (!persist())
        return false;
    rebuild();
    return true;
}

QVariantMap LibraryStore::loadShader(const QString &id) const {
    const int at = findShader(id);
    if (at < 0)
        return {};
    return m_shaderEntries.at(at).payload;
}

bool LibraryStore::hasShader(const QString &id) const {
    return findShader(id) >= 0;
}

QVariantMap LibraryStore::shader(const QString &id) const {
    const int at = findShader(id);
    if (at < 0)
        return {};
    const ShaderEntry &entry = m_shaderEntries.at(at);
    return {{QStringLiteral("id"), entry.id}, {QStringLiteral("name"), entry.name},
        {QStringLiteral("createdAt"), entry.createdAt}, {QStringLiteral("updatedAt"), entry.updatedAt},
        {QStringLiteral("payload"), entry.payload}};
}

QSet<QString> LibraryStore::referencedAudio() const {
    QSet<QString> out;
    for (const DesignEntry &entry : m_designEntries) {
        const QVariantMap audio = entry.scene.value(QStringLiteral("audio")).toMap();
        for (const QVariant &v : audio.value(QStringLiteral("clips")).toList()) {
            const QString src = v.toMap().value(QStringLiteral("source")).toString();
            if (!src.isEmpty())
                out.insert(src);
        }
    }
    return out;
}

void LibraryStore::sweepOrphanAudio() {
    const QSet<QString> keep = referencedAudio();
    const QDir dir(audioDir());
    for (const QFileInfo &info : dir.entryInfoList(QDir::Files)) {
        const QString f = info.fileName();
        if (keep.contains(f))
            continue;
        // Sidecars live only while their blob does.
        if (f.endsWith(QStringLiteral(".peaks")) && keep.contains(f.left(f.size() - 6)))
            continue;
        QFile::remove(info.absoluteFilePath());
    }
}

QSet<QString> LibraryStore::referencedVideos() const {
    QSet<QString> out;
    QList<QVariantList> roots;
    for (const DesignEntry &entry : m_designEntries) {
        roots.append(entry.scene.value(QStringLiteral("nodes")).toList());
        const QVariantMap audio = entry.scene.value(QStringLiteral("audio")).toMap();
        for (const QVariant &v : audio.value(QStringLiteral("clips")).toList()) {
            const QString src = v.toMap().value(QStringLiteral("source")).toString();
            if (!src.isEmpty() && isSafeVideoName(src))
                out.insert(src);
        }
    }
    for (const AssetEntry &entry : m_assetEntries)
        roots.append(entry.payload.value(QStringLiteral("nodes")).toList());
    const QSet<QString> nodes = collectNodeStringRefs(roots, QStringLiteral("videoSource"));
    for (const QString &s : nodes) {
        if (isSafeVideoName(s))
            out.insert(s);
    }
    return out;
}

void LibraryStore::sweepOrphanVideos() {
    const QSet<QString> keep = referencedVideos();
    const QDir dir(videosDir());
    for (const QFileInfo &info : dir.entryInfoList(QDir::Files)) {
        const QString f = info.fileName();
        if (keep.contains(f))
            continue;
        if (f.endsWith(QStringLiteral(".peaks")) && keep.contains(f.left(f.size() - 6)))
            continue;
        QFile::remove(info.absoluteFilePath());
    }
}

void LibraryStore::load() {
    if (m_loaded)
        return;
    m_loaded = true;

    QDir().mkpath(libraryDir());
    // Second-instance guard. Contention only warns; concurrent writers
    // remain last-writer-wins. Sweeps are lock-gated below so a second
    // instance never deletes the first instance's in-memory-only blobs.
    m_hasLock = m_lock.lock();
    if (!m_hasLock) {
        setLastError(tr("Another copy of totm seems to be running; saves may overwrite each other."));
    }

    QFile file(libraryPath());
    if (!file.exists()) {
        installFreshDefault();
        if (m_hasLock) {
            sweepOrphanImages();
            sweepOrphanAudio();
            sweepOrphanVideos();
        }
        persist();
        rebuild();
        return;
    }
    if (!file.open(QIODevice::ReadOnly)) {
        setLastError(tr("Could not read library: %1").arg(file.errorString()));
        // Invariant: in-memory state stays valid even when disk is not.
        installFreshDefault();
        if (m_hasLock) {
            sweepOrphanImages();
            sweepOrphanAudio();
            sweepOrphanVideos();
        }
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
        m_assetEntries.clear();
        m_shaderEntries.clear();
        installFreshDefault();
        if (m_hasLock) {
            sweepOrphanImages();
            sweepOrphanAudio();
            sweepOrphanVideos();
        }
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
        m_assetEntries.clear();
        // Assets are optional: libraries written before assets existed
        // carry no key and load as empty without migration.
        if (root.value(QStringLiteral("assets")).isArray()) {
            for (const QJsonValue &value : root.value(QStringLiteral("assets")).toArray()) {
                const QJsonObject item = value.toObject();
                AssetEntry entry;
                entry.id = item.value(QStringLiteral("id")).toString();
                entry.name = item.value(QStringLiteral("name")).toString();
                entry.createdAt = item.value(QStringLiteral("createdAt")).toString();
                entry.updatedAt = item.value(QStringLiteral("updatedAt")).toString();
                if (entry.id.isEmpty())
                    continue;
                entry.payload = readAssetFile(entry.id);
                m_assetEntries.append(entry);
            }
        }
        m_shaderEntries.clear();
        // Shader assets are optional like component assets.
        if (root.value(QStringLiteral("shaders")).isArray()) {
            for (const QJsonValue &value : root.value(QStringLiteral("shaders")).toArray()) {
                const QJsonObject item = value.toObject();
                ShaderEntry entry;
                entry.id = item.value(QStringLiteral("id")).toString();
                entry.name = item.value(QStringLiteral("name")).toString();
                entry.createdAt = item.value(QStringLiteral("createdAt")).toString();
                entry.updatedAt = item.value(QStringLiteral("updatedAt")).toString();
                if (entry.id.isEmpty())
                    continue;
                entry.payload = readShaderFile(entry.id);
                m_shaderEntries.append(entry);
            }
        }
        if (m_hasLock) {
            sweepOrphanDesignFiles();
            sweepOrphanAssetFiles();
            sweepOrphanShaderFiles();
        }
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
    if (m_hasLock) {
        sweepOrphanImages();
        sweepOrphanAudio();
        sweepOrphanVideos();
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
    QJsonArray assets;
    // Metadata only: payloads live in assets/<id>.json.
    for (const AssetEntry &entry : m_assetEntries) {
        assets.append(QJsonObject{
            {QStringLiteral("id"), entry.id},
            {QStringLiteral("name"), entry.name},
            {QStringLiteral("createdAt"), entry.createdAt},
            {QStringLiteral("updatedAt"), entry.updatedAt},
        });
    }
    QJsonArray shaders;
    // Metadata only: payloads live in shaders/<id>.json.
    for (const ShaderEntry &entry : m_shaderEntries) {
        shaders.append(QJsonObject{
            {QStringLiteral("id"), entry.id},
            {QStringLiteral("name"), entry.name},
            {QStringLiteral("createdAt"), entry.createdAt},
            {QStringLiteral("updatedAt"), entry.updatedAt},
        });
    }
    const QJsonDocument doc(QJsonObject{
        {QStringLiteral("version"), kSchemaVersion},
        {QStringLiteral("workspaces"), workspaces},
        {QStringLiteral("designs"), designs},
        {QStringLiteral("assets"), assets},
        {QStringLiteral("shaders"), shaders},
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
    QVariantList assets;
    for (const AssetEntry &entry : m_assetEntries) {
        assets.append(QVariantMap{
            {QStringLiteral("assetId"), entry.id},
            {QStringLiteral("name"), entry.name},
            {QStringLiteral("createdAt"), entry.createdAt},
            {QStringLiteral("updatedAt"), entry.updatedAt},
            {QStringLiteral("payload"), entry.payload},
        });
    }
    QVariantList shaders;
    for (const ShaderEntry &entry : m_shaderEntries) {
        shaders.append(QVariantMap{
            {QStringLiteral("shaderId"), entry.id},
            {QStringLiteral("name"), entry.name},
            {QStringLiteral("createdAt"), entry.createdAt},
            {QStringLiteral("updatedAt"), entry.updatedAt},
            {QStringLiteral("payload"), entry.payload},
        });
    }
    m_workspaceList = workspaces;
    m_designList = designs;
    m_assetList = assets;
    m_shaderList = shaders;
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
    setLastWarning(QString());
}

QString LibraryStore::lastWarning() const {
    return m_lastWarning;
}

void LibraryStore::setLastWarning(const QString &message) {
    if (m_lastWarning == message)
        return;
    m_lastWarning = message;
    emit lastWarningChanged();
}

void LibraryStore::flagUnsupportedFiles(int count, const QString &detail) {
    if (count <= 0)
        return;
    const QString names = detail.trimmed().isEmpty() ? tr("unknown") : detail.trimmed();
    const QString msg = tr("%n file(s) skipped — unsupported type (%1). Supported: png, jpg, webp, gif, svg, mp4, webm, mov, m4v, mkv.", "", count).arg(names);
    if (!m_lastError.isEmpty())
        setLastError(m_lastError + QStringLiteral(" ") + msg);
    else
        setLastError(msg);
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

int LibraryStore::findAsset(const QString &id) const {
    for (int i = 0; i < m_assetEntries.size(); ++i) {
        if (m_assetEntries.at(i).id == id)
            return i;
    }
    return -1;
}

int LibraryStore::findShader(const QString &id) const {
    for (int i = 0; i < m_shaderEntries.size(); ++i) {
        if (m_shaderEntries.at(i).id == id)
            return i;
    }
    return -1;
}

QString LibraryStore::shadersDir() const {
    return libraryDir() + QStringLiteral("/shaders");
}

bool LibraryStore::writeShaderFile(const QString &id, const QVariantMap &payload) {
    if (id.isEmpty() || id.contains(QLatin1Char('/')) || id.contains(QLatin1Char('\\'))
        || id.contains(QStringLiteral("..")))
        return false;
    QDir().mkpath(shadersDir());
    QSaveFile file(shadersDir() + QStringLiteral("/") + id + QStringLiteral(".json"));
    if (!file.open(QIODevice::WriteOnly)) {
        setLastError(tr("Could not save shader: %1").arg(file.errorString()));
        return false;
    }
    const QJsonDocument doc(QJsonObject{
        {QStringLiteral("version"), kSchemaVersion},
        {QStringLiteral("payload"), QJsonObject::fromVariantMap(entryToShader(payload))},
    });
    file.write(doc.toJson(QJsonDocument::Indented));
    if (!file.commit()) {
        setLastError(tr("Could not save shader: %1").arg(file.errorString()));
        return false;
    }
    return true;
}

QVariantMap LibraryStore::readShaderFile(const QString &id) {
    if (id.isEmpty() || id.contains(QLatin1Char('/')) || id.contains(QLatin1Char('\\'))
        || id.contains(QStringLiteral("..")))
        return entryToShader({});
    const QString path = shadersDir() + QStringLiteral("/") + id + QStringLiteral(".json");
    QFile file(path);
    if (!file.exists())
        return entryToShader({});
    if (!file.open(QIODevice::ReadOnly)) {
        setLastError(tr("Could not read shader; starting it fresh."));
        return entryToShader({});
    }
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &parseError);
    const QJsonObject root = doc.object();
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()
        || !root.value(QStringLiteral("payload")).isObject()) {
        file.close();
        const QString backup = shadersDir() + QStringLiteral("/") + id + QStringLiteral(".corrupt.")
            + QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyyMMdd-hhmmss-zzz"))
            + QStringLiteral(".json");
        if (QFile::rename(path, backup))
            setLastError(tr("A shader was corrupt; archived and started fresh."));
        else
            setLastError(tr("A shader was corrupt and could not be archived; started fresh."));
        return entryToShader({});
    }
    return entryToShader(root.value(QStringLiteral("payload")).toObject().toVariantMap());
}

void LibraryStore::sweepOrphanShaderFiles() {
    QHash<QString, bool> known;
    for (const ShaderEntry &entry : m_shaderEntries)
        known.insert(entry.id, true);
    const QDir dir(shadersDir());
    for (const QString &f : dir.entryList({QStringLiteral("*.json")}, QDir::Files)) {
        if (f.contains(QStringLiteral(".corrupt.")))
            continue;
        const QString id = f.left(f.size() - 5);
        if (!known.contains(id))
            QFile::remove(dir.filePath(f));
    }
}

QString LibraryStore::assetsDir() const {
    return libraryDir() + QStringLiteral("/assets");
}

bool LibraryStore::writeAssetFile(const QString &id, const QVariantMap &payload) {
    if (id.isEmpty() || id.contains(QLatin1Char('/')) || id.contains(QLatin1Char('\\'))
        || id.contains(QStringLiteral("..")))
        return false;
    QDir().mkpath(assetsDir());
    QSaveFile file(assetsDir() + QStringLiteral("/") + id + QStringLiteral(".json"));
    if (!file.open(QIODevice::WriteOnly)) {
        setLastError(tr("Could not save asset: %1").arg(file.errorString()));
        return false;
    }
    const QJsonDocument doc(QJsonObject{
        {QStringLiteral("version"), kSchemaVersion},
        {QStringLiteral("payload"), QJsonObject::fromVariantMap(entryToAsset(payload))},
    });
    file.write(doc.toJson(QJsonDocument::Indented));
    if (!file.commit()) {
        setLastError(tr("Could not save asset: %1").arg(file.errorString()));
        return false;
    }
    return true;
}

QVariantMap LibraryStore::readAssetFile(const QString &id) {
    if (id.isEmpty() || id.contains(QLatin1Char('/')) || id.contains(QLatin1Char('\\'))
        || id.contains(QStringLiteral("..")))
        return entryToAsset({});
    const QString path = assetsDir() + QStringLiteral("/") + id + QStringLiteral(".json");
    QFile file(path);
    if (!file.exists())
        return entryToAsset({});
    if (!file.open(QIODevice::ReadOnly)) {
        setLastError(tr("Could not read asset; starting it fresh."));
        return entryToAsset({});
    }
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &parseError);
    const QJsonObject root = doc.object();
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()
        || !root.value(QStringLiteral("payload")).isObject()) {
        file.close();
        const QString backup = assetsDir() + QStringLiteral("/") + id + QStringLiteral(".corrupt.")
            + QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyyMMdd-hhmmss-zzz"))
            + QStringLiteral(".json");
        if (QFile::rename(path, backup))
            setLastError(tr("An asset was corrupt; archived and started fresh."));
        else
            setLastError(tr("An asset was corrupt and could not be archived; started fresh."));
        return entryToAsset({});
    }
    return entryToAsset(root.value(QStringLiteral("payload")).toObject().toVariantMap());
}

void LibraryStore::sweepOrphanAssetFiles() {
    QHash<QString, bool> known;
    for (const AssetEntry &entry : m_assetEntries)
        known.insert(entry.id, true);
    const QDir dir(assetsDir());
    for (const QString &file : dir.entryList({QStringLiteral("*.json")}, QDir::Files)) {
        if (file.contains(QStringLiteral(".corrupt.")))
            continue;
        const QString id = file.left(file.size() - 5);
        if (!known.contains(id))
            QFile::remove(dir.filePath(file));
    }
}

QSet<QString> LibraryStore::referencedAssetImages() const {
    QList<QVariantList> roots;
    for (const AssetEntry &entry : m_assetEntries)
        roots.append(entry.payload.value(QStringLiteral("nodes")).toList());
    return collectNodeStringRefs(roots, QStringLiteral("imageSource"));
}

QSet<QString> LibraryStore::referencedAssetVideos() const {
    QList<QVariantList> roots;
    for (const AssetEntry &entry : m_assetEntries)
        roots.append(entry.payload.value(QStringLiteral("nodes")).toList());
    const QSet<QString> all = collectNodeStringRefs(roots, QStringLiteral("videoSource"));
    QSet<QString> out;
    for (const QString &s : all) {
        if (isSafeVideoName(s))
            out.insert(s);
    }
    return out;
}

QString LibraryStore::libraryDir() const {
    return AppPaths::totmBaseDir();
}

QString LibraryStore::imagesDir() const {
    return libraryDir() + QStringLiteral("/images");
}

QString LibraryStore::designsDir() const {
    return libraryDir() + QStringLiteral("/designs");
}

QString LibraryStore::audioDir() const {
    return libraryDir() + QStringLiteral("/audio");
}

QString LibraryStore::videosDir() const {
    return libraryDir() + QStringLiteral("/videos");
}

bool LibraryStore::isSafeVideoName(const QString &name) const {
    if (name.isEmpty() || name.contains(QLatin1Char('/')) || name.contains(QLatin1Char('\\'))
        || name.contains(QStringLiteral("..")))
        return false;
    const int dot = name.lastIndexOf(QLatin1Char('.'));
    return dot > 0 && dot < name.size() - 1;
}

QString LibraryStore::resolveVideoFile(const QString &ref) const {
    if (ref.isEmpty())
        return {};
    if (isSafeVideoName(ref)) {
        const QString blob = videosDir() + QStringLiteral("/") + ref;
        if (QFile::exists(blob))
            return blob;
        return {};
    }
    // Legacy absolute path: honor only while the file still exists.
    if (ref.contains(QLatin1Char('/')) || ref.contains(QLatin1Char('\\'))) {
        if (QFile::exists(ref))
            return ref;
    }
    return {};
}

QString LibraryStore::resolveAudioFile(const QString &ref) const {
    if (ref.isEmpty())
        return {};
    if (ref.contains(QLatin1Char('/')) || ref.contains(QLatin1Char('\\'))) {
        if (QFile::exists(ref))
            return ref;
        return {};
    }
    if (isSafeAudioName(ref)) {
        const QString blob = audioDir() + QStringLiteral("/") + ref;
        if (QFile::exists(blob))
            return blob;
    }
    // Detached video sound shares the video blob in videos/.
    if (isSafeVideoName(ref)) {
        const QString blob = videosDir() + QStringLiteral("/") + ref;
        if (QFile::exists(blob))
            return blob;
    }
    return {};
}

bool LibraryStore::isSafeAudioName(const QString &name) const {
    if (name.isEmpty() || name.contains(QLatin1Char('/')) || name.contains(QLatin1Char('\\'))
        || name.contains(QStringLiteral("..")))
        return false;
    const int dot = name.lastIndexOf(QLatin1Char('.'));
    return dot > 0 && dot < name.size() - 1;
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
