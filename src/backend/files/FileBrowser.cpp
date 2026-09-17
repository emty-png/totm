#include "FileBrowser.h"

#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>

namespace {
QString localPath(const QUrl &url)
{
    if (url.isEmpty() || !url.isLocalFile()) {
        return {};
    }
    return url.toLocalFile();
}
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
        const QString name = QDir(crumb).isRoot() ? QStringLiteral("/") : QFileInfo(crumb).fileName();
        out.append(QVariantMap{
            {QStringLiteral("name"), name},
            {QStringLiteral("url"), QUrl::fromLocalFile(crumb)},
        });
    }
    return out;
}

QVariantList FileBrowser::list(const QUrl &folder, const QStringList &suffixes) const
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
    const QFileInfoList entries = dir.entryInfoList(
        QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot | QDir::Readable,
        QDir::DirsFirst | QDir::Name | QDir::IgnoreCase);
    for (const QFileInfo &info : entries) {
        const bool isDir = info.isDir();
        const QString suffix = info.suffix().toLower();
        if (!isDir && !wanted.isEmpty() && !wanted.contains(suffix)) {
            continue;
        }
        if (info.fileName().startsWith(QLatin1Char('.'))) {
            continue;
        }
        out.append(QVariantMap{
            {QStringLiteral("fileName"), info.fileName()},
            {QStringLiteral("url"), QUrl::fromLocalFile(info.absoluteFilePath())},
            {QStringLiteral("isDir"), isDir},
            {QStringLiteral("size"), isDir ? 0 : info.size()},
            {QStringLiteral("modified"), info.lastModified().toString(Qt::ISODate)},
            {QStringLiteral("suffix"), suffix},
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
        return QUrl::fromLocalFile(path);
    }
    return QUrl::fromLocalFile(dir.absolutePath());
}

bool FileBrowser::isReadable(const QUrl &folder) const
{
    const QString path = localPath(folder);
    return !path.isEmpty() && QDir(path).isReadable();
}
