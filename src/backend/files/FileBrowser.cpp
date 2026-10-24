#include "FileBrowser.h"

#include <QByteArray>
#include <QCollator>
#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QHash>
#include <QLocale>
#include <QSet>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QUrl>

#include <algorithm>

namespace {
QString localPath(const QUrl &url)
{
    if (url.isEmpty() || !url.isLocalFile()) {
        return {};
    }
    return url.toLocalFile();
}

QString volumeDetail(const QStorageInfo &storage)
{
    if (!storage.isValid() || storage.bytesTotal() <= 0) {
        return {};
    }
    const QLocale locale;
    return QCoreApplication::translate("FileBrowser", "%1 free of %2")
        .arg(locale.formattedDataSize(storage.bytesAvailable(), 1, QLocale::DataSizeTraditionalFormat),
             locale.formattedDataSize(storage.bytesTotal(), 1, QLocale::DataSizeTraditionalFormat));
}

struct Entry {
    QFileInfo info;
    bool isDir = false;
    QString suffix;
};
} // namespace

FileBrowser *FileBrowser::create(QQmlEngine *engine, QJSEngine *scriptEngine)
{
    Q_UNUSED(scriptEngine);
    auto *store = new FileBrowser(engine);
    QJSEngine::setObjectOwnership(store, QJSEngine::CppOwnership);
    return store;
}

FileBrowser::FileBrowser(QObject *parent)
    : QObject(parent)
{
}

QVariantList FileBrowser::places() const
{
    // Well-known user dirs, in sidebar order. Missing ones (e.g. no
    // ~/Desktop on minimal installs) stay out instead of dead links.
    static const QList<QPair<QString, QStandardPaths::StandardLocation>> entries{
        {QStringLiteral("home"), QStandardPaths::HomeLocation},
        {QStringLiteral("desktop"), QStandardPaths::DesktopLocation},
        {QStringLiteral("downloads"), QStandardPaths::DownloadLocation},
        {QStringLiteral("documents"), QStandardPaths::DocumentsLocation},
        {QStringLiteral("music"), QStandardPaths::MusicLocation},
        {QStringLiteral("pictures"), QStandardPaths::PicturesLocation},
        {QStringLiteral("movies"), QStandardPaths::MoviesLocation},
    };
    static const QHash<QString, QString> names{
        {QStringLiteral("home"), tr("Home")},
        {QStringLiteral("desktop"), tr("Desktop")},
        {QStringLiteral("downloads"), tr("Downloads")},
        {QStringLiteral("documents"), tr("Documents")},
        {QStringLiteral("music"), tr("Music")},
        {QStringLiteral("pictures"), tr("Pictures")},
        {QStringLiteral("movies"), tr("Movies")},
    };
    QVariantList out;
    for (const auto &entry : entries) {
        const QString path = QStandardPaths::writableLocation(entry.second);
        if (path.isEmpty() || !QDir(path).exists()) {
            continue;
        }
        out.append(QVariantMap{
            {QStringLiteral("id"), entry.first},
            {QStringLiteral("name"), names.value(entry.first)},
            {QStringLiteral("url"), QUrl::fromLocalFile(path)},
        });
    }
    return out;
}

QVariantList FileBrowser::volumes() const
{
    QVariantList out;
    QSet<QString> seen;

    const auto addVolume = [&out, &seen](const QString &rawPath, const QString &rawName,
                                         const QString &detail) {
        const QString path = QDir::cleanPath(rawPath);
        if (path.isEmpty() || seen.contains(path)) {
            return;
        }
        seen.insert(path);
        QString name = rawName.trimmed();
        if (name.isEmpty()) {
            name = QDir(path).isRoot() ? QDir::toNativeSeparators(path) : QFileInfo(path).fileName();
        }
        if (name.isEmpty()) {
            name = QDir::toNativeSeparators(path);
        }
        while (name.size() > 1 && (name.endsWith(QLatin1Char('/')) || name.endsWith(QLatin1Char('\\')))) {
            name.chop(1);
        }
        out.append(QVariantMap{
            {QStringLiteral("id"), QStringLiteral("volume:") + path},
            {QStringLiteral("name"), name},
            {QStringLiteral("url"), QUrl::fromLocalFile(path)},
            {QStringLiteral("detail"), detail},
        });
    };

#ifdef Q_OS_WIN
    // Drive list is the stable Windows volume source; QStorageInfo fills
    // in the free-space detail.
    const QFileInfoList drives = QDir::drives();
    for (const QFileInfo &drive : drives) {
        const QString path = QDir::cleanPath(drive.absoluteFilePath());
        const QStorageInfo storage(path);
        addVolume(path, QDir::toNativeSeparators(path), volumeDetail(storage));
    }
#else
    for (const QStorageInfo &storage : QStorageInfo::mountedVolumes()) {
        if (!storage.isValid() || !storage.isReady()) {
            continue;
        }
        const QString path = QDir::cleanPath(storage.rootPath());
        if (path.isEmpty()) {
            continue;
        }
#ifdef Q_OS_LINUX
        // Only real block devices and the root filesystem: proc, sysfs,
        // tmpfs, snaps and container overlays are not useful in a picker.
        if (path != QLatin1String("/") && !storage.device().startsWith(QLatin1String("/dev/"))) {
            continue;
        }
        if (path.startsWith(QLatin1String("/snap/"))) {
            continue;
        }
#endif
#ifdef Q_OS_MACOS
        // Show the boot volume and disks mounted under /Volumes; skip
        // APFS internals such as /System/Volumes/Data.
        if (path != QLatin1String("/") && !path.startsWith(QLatin1String("/Volumes/"))) {
            continue;
        }
#endif
        addVolume(path, storage.displayName(), volumeDetail(storage));
    }
    // Some minimal Linux setups omit the root volume from mountedVolumes.
    const QStorageInfo root(QStringLiteral("/"));
    if (root.isValid() && root.isReady()) {
        addVolume(QStringLiteral("/"), root.displayName(), volumeDetail(root));
    }
#endif
    return out;
}

QVariantList FileBrowser::breadcrumbs(const QUrl &folder) const
{
    QVariantList out;
    QString path = QDir::cleanPath(localPath(folder));
    if (path.isEmpty()) {
        return out;
    }
    // Walk up to the root collecting crumbs, then reverse to root-first.
    QStringList chain;
    QDir dir(path);
    while (true) {
        chain.prepend(dir.absolutePath());
        if (dir.isRoot() || !dir.cdUp()) {
            break;
        }
    }
    for (const QString &crumb : chain) {
        // Windows roots are "C:/" (not "/"); show the drive itself.
        const QString name = QDir(crumb).isRoot() ? QDir::cleanPath(crumb) : QFileInfo(crumb).fileName();
        out.append(QVariantMap{
            {QStringLiteral("name"), name.isEmpty() ? crumb : name},
            {QStringLiteral("url"), QUrl::fromLocalFile(crumb)},
        });
    }
    return out;
}

QVariantList FileBrowser::list(const QUrl &folder, const QStringList &suffixes,
                               bool showHidden, const QString &sortKey, bool ascending) const
{
    QVariantList out;
    const QString path = localPath(folder);
    if (path.isEmpty()) {
        return out;
    }
    QDir dir(path);
    if (!dir.isReadable()) {
        return out;
    }
    QSet<QString> wanted;
    for (const QString &suffix : suffixes) {
        const QString clean = suffix.trimmed().toLower();
        if (!clean.isEmpty()) {
            wanted.insert(clean.startsWith(QLatin1Char('.')) ? clean.mid(1) : clean);
        }
    }

    QDir::Filters filters = QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot | QDir::Readable;
    if (showHidden) {
        filters |= QDir::Hidden;
    }
    const QFileInfoList entries = dir.entryInfoList(filters, QDir::NoSort);

    QList<Entry> rows;
    rows.reserve(entries.size());
    for (const QFileInfo &info : entries) {
        const bool isDir = info.isDir();
        const QString suffix = info.suffix().toLower();
        if (!isDir && !wanted.isEmpty() && !wanted.contains(suffix)) {
            continue;
        }
        // Dotfiles on Unix, hidden/system on Windows (desktop.ini etc.).
        // QFileInfo::isHidden covers both; showHidden passes them through.
        if (!showHidden && info.isHidden()) {
            continue;
        }
        rows.append(Entry{info, isDir, suffix});
    }

    QCollator collator;
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    collator.setNumericMode(true);
    const auto byName = [&collator](const Entry &a, const Entry &b) {
        const int primary = collator.compare(a.info.fileName(), b.info.fileName());
        if (primary != 0) {
            return primary;
        }
        return QString::compare(a.info.fileName(), b.info.fileName(), Qt::CaseSensitive);
    };

    const QString key = sortKey.trimmed().toLower();
    std::sort(rows.begin(), rows.end(), [&](const Entry &a, const Entry &b) {
        if (a.isDir != b.isDir) {
            return a.isDir;
        }
        int cmp = 0;
        if (key == QStringLiteral("size")) {
            const qint64 aSize = a.isDir ? 0 : a.info.size();
            const qint64 bSize = b.isDir ? 0 : b.info.size();
            cmp = aSize < bSize ? -1 : aSize > bSize ? 1 : 0;
        } else if (key == QStringLiteral("modified")) {
            const QDateTime aTime = a.info.lastModified();
            const QDateTime bTime = b.info.lastModified();
            cmp = aTime < bTime ? -1 : aTime > bTime ? 1 : 0;
        } else if (key == QStringLiteral("type")) {
            cmp = QString::compare(a.suffix, b.suffix, Qt::CaseInsensitive);
        }
        if (cmp == 0) {
            cmp = byName(a, b);
        }
        return ascending ? cmp < 0 : cmp > 0;
    });

    out.reserve(rows.size());
    for (const Entry &entry : rows) {
        const QFileInfo &info = entry.info;
        out.append(QVariantMap{
            {QStringLiteral("fileName"), info.fileName()},
            {QStringLiteral("url"), QUrl::fromLocalFile(info.absoluteFilePath())},
            {QStringLiteral("isDir"), entry.isDir},
            {QStringLiteral("size"), entry.isDir ? 0 : info.size()},
            {QStringLiteral("modified"), info.lastModified().toString(Qt::ISODate)},
            {QStringLiteral("suffix"), entry.suffix},
        });
    }
    return out;
}

QUrl FileBrowser::parentOf(const QUrl &folder) const
{
    const QString path = QDir::cleanPath(localPath(folder));
    if (path.isEmpty()) {
        return {};
    }
    QDir dir(path);
    if (dir.isRoot() || !dir.cdUp()) {
        // At a filesystem root ("/" or "C:/"): no parent. QML falls back
        // to the places list, which carries drive roots on Windows.
        return {};
    }
    return QUrl::fromLocalFile(dir.absolutePath());
}

bool FileBrowser::isReadable(const QUrl &folder) const
{
    const QString path = localPath(folder);
    if (path.isEmpty()) {
        return false;
    }
    const QFileInfo info(path);
    return info.isDir() && info.isReadable();
}

bool FileBrowser::isWritable(const QUrl &folder) const
{
    const QString path = localPath(folder);
    if (path.isEmpty()) {
        return false;
    }
    const QFileInfo info(path);
    return info.isDir() && info.isWritable();
}

QString FileBrowser::displayPath(const QUrl &folder) const
{
    const QString path = QDir::cleanPath(localPath(folder));
    if (path.isEmpty()) {
        return {};
    }
    return QDir::toNativeSeparators(path);
}

QVariantMap FileBrowser::resolveTarget(const QString &text) const
{
    QVariantMap out{
        {QStringLiteral("ok"), false},
    };
    QString input = text.trimmed();
    if (input.isEmpty()) {
        return out;
    }
    if (input == QStringLiteral("~")) {
        input = QDir::homePath();
    } else if (input.startsWith(QStringLiteral("~/")) || input.startsWith(QStringLiteral("~\\"))) {
        input = QDir::homePath() + input.mid(1);
    }

    const QUrl url = QUrl::fromUserInput(input, QDir::currentPath(), QUrl::AssumeLocalFile);
    if (!url.isLocalFile()) {
        return out;
    }
    const QString path = QDir::cleanPath(url.toLocalFile());
    if (path.isEmpty()) {
        return out;
    }
    const QFileInfo info(path);
    if (info.isDir()) {
        out.insert(QStringLiteral("ok"), true);
        out.insert(QStringLiteral("folder"), QUrl::fromLocalFile(info.absoluteFilePath()));
        out.insert(QStringLiteral("file"), QUrl());
    } else if (info.isFile()) {
        out.insert(QStringLiteral("ok"), true);
        out.insert(QStringLiteral("folder"), QUrl::fromLocalFile(info.absolutePath()));
        out.insert(QStringLiteral("file"), QUrl::fromLocalFile(info.absoluteFilePath()));
    }
    return out;
}

QUrl FileBrowser::resolveFolder(const QString &text) const
{
    const QVariantMap target = resolveTarget(text);
    return target.value(QStringLiteral("ok")).toBool()
        ? target.value(QStringLiteral("folder")).toUrl()
        : QUrl();
}

QVariantMap FileBrowser::createFolder(const QUrl &parent, const QString &name) const
{
    QVariantMap out{
        {QStringLiteral("ok"), false},
    };
    const QString trimmed = name.trimmed();
    if (trimmed.isEmpty()) {
        out.insert(QStringLiteral("error"), tr("Enter a folder name."));
        return out;
    }
    if (trimmed == QStringLiteral(".") || trimmed == QStringLiteral("..")
        || trimmed.contains(QLatin1Char('/')) || trimmed.contains(QLatin1Char('\\'))) {
        out.insert(QStringLiteral("error"), tr("That name is not valid."));
        return out;
    }
#ifdef Q_OS_WIN
    static const QString invalidChars = QStringLiteral("<>:\"|?*");
    for (const QChar ch : invalidChars) {
        if (trimmed.contains(ch)) {
            out.insert(QStringLiteral("error"), tr("That name is not valid."));
            return out;
        }
    }
    if (trimmed.endsWith(QLatin1Char(' ')) || trimmed.endsWith(QLatin1Char('.'))) {
        out.insert(QStringLiteral("error"), tr("That name is not valid."));
        return out;
    }
#endif

    const QString parentPath = localPath(parent);
    if (parentPath.isEmpty()) {
        out.insert(QStringLiteral("error"), tr("This folder cannot be opened."));
        return out;
    }
    QDir dir(parentPath);
    if (!dir.exists() || !QFileInfo(dir.absolutePath()).isWritable()) {
        out.insert(QStringLiteral("error"), tr("This folder is read-only."));
        return out;
    }
    if (dir.exists(trimmed)) {
        out.insert(QStringLiteral("error"), tr("A folder with that name already exists."));
        return out;
    }
    if (!dir.mkdir(trimmed)) {
        out.insert(QStringLiteral("error"), tr("Could not create the folder."));
        return out;
    }
    out.insert(QStringLiteral("ok"), true);
    out.insert(QStringLiteral("url"), QUrl::fromLocalFile(dir.absoluteFilePath(trimmed)));
    return out;
}

QString FileBrowser::thumbnailSource(const QUrl &file, const QString &stamp) const
{
    const QString path = localPath(file);
    if (path.isEmpty()) {
        return {};
    }
    // Base64url keeps the id free of path separators and query
    // characters; the stamp lives in the query only to bust QML's
    // image cache, the provider ignores it.
    const QByteArray encoded = path.toUtf8().toBase64(QByteArray::Base64UrlEncoding);
    QString source = QStringLiteral("image://totmthumb/") + QString::fromLatin1(encoded);
    if (!stamp.isEmpty()) {
        source += QStringLiteral("?v=");
        source += QString::fromLatin1(QUrl::toPercentEncoding(stamp));
    }
    return source;
}
