#pragma once

#include <QDir>
#include <QFile>
#include <QSet>
#include <QStandardPaths>
#include <QString>
#include <QUrl>

// AppPaths: single source for the totm data dir + local-file suffix rule.
// The AppDataLocation-or-~/.totm fallback was copy-pasted across
// LibraryStore/FramePaint/PluginStore/VideoExporter; drift here breaks
// blob resolution, so all call sites delegate here.
namespace AppPaths {

inline QString totmBaseDir()
{
    // Windows: prefer Local (non-roaming) so GB-scale videos/ never roam
    // on domain profiles. Legacy installs used Roaming; keep reading them
    // when Local has no data yet so upgrades never lose designs.
#ifdef Q_OS_WIN
    const QString local = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    const QString roaming = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QString dir = !local.isEmpty() ? local : roaming;
    if (dir.isEmpty())
        dir = QDir::homePath() + QStringLiteral("/.totm");
    if (!dir.endsWith(QStringLiteral("/totm"), Qt::CaseInsensitive))
        dir += QStringLiteral("/totm");
    // Legacy Roaming preservation: first run after upgrade still sees old data.
    if (!roaming.isEmpty()) {
        QString legacy = roaming;
        if (!legacy.endsWith(QStringLiteral("/totm"), Qt::CaseInsensitive))
            legacy += QStringLiteral("/totm");
        if (legacy.compare(dir, Qt::CaseInsensitive) != 0 && QDir(legacy).exists()
            && !QDir(dir).exists()) {
            return legacy;
        }
    }
    return dir;
#else
    QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (dir.isEmpty())
        dir = QDir::homePath() + QStringLiteral("/.totm");
    if (!dir.endsWith(QStringLiteral("/totm"), Qt::CaseInsensitive))
        dir += QStringLiteral("/totm");
    return dir;
#endif
}

// ffmpeg lookup shared by VideoExporter, AudioPeaks, LibraryStore probe
// and FramePaint thumbnails. Finder-launched GUI apps on macOS do not
// inherit Homebrew's /opt/homebrew/bin PATH, so probe the brew prefixes
// explicitly. Windows tries ffmpeg.exe first (PATHEXT is not always
// honored by findExecutable call sites).
inline QString findFfmpeg()
{
#ifdef Q_OS_WIN
    QString found = QStandardPaths::findExecutable(QStringLiteral("ffmpeg.exe"));
    if (!found.isEmpty())
        return found;
    return QStandardPaths::findExecutable(QStringLiteral("ffmpeg"));
#elif defined(Q_OS_MACOS)
    QString found = QStandardPaths::findExecutable(QStringLiteral("ffmpeg"));
    if (!found.isEmpty())
        return found;
    static const char *kBrewPrefixes[] = {
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/opt/local/bin/ffmpeg",
    };
    for (const char *candidate : kBrewPrefixes) {
        if (QFile::exists(QString::fromLatin1(candidate)))
            return QString::fromLatin1(candidate);
    }
    return {};
#else
    return QStandardPaths::findExecutable(QStringLiteral("ffmpeg"));
#endif
}

// unzip lookup for plugin .zip import. Windows probes the .exe variant;
// callers fall back to PowerShell/tar when this returns empty.
inline QString findUnzip()
{
#ifdef Q_OS_WIN
    QString found = QStandardPaths::findExecutable(QStringLiteral("unzip.exe"));
    if (!found.isEmpty())
        return found;
#endif
    return QStandardPaths::findExecutable(QStringLiteral("unzip"));
}

// Local file path for a save destination with the container suffix
// appended when missing ("", when no usable path). Shared by the write
// and the QML overwrite probe so the two can never disagree.
inline QString resolveLocalFileWithSuffix(const QUrl &destination, const QString &suffix)
{
    QString local = destination.isLocalFile() ? destination.toLocalFile() : destination.toString();
    if (local.isEmpty())
        return {};
    if (!local.endsWith(suffix, Qt::CaseInsensitive))
        local += suffix;
    return local;
}

// Single media allowlists: image/audio/video extensions were triplicated
// across LibraryStore import sites + VideoExporter direct paths.
inline const QSet<QString> &imageExtensions()
{
    static const QSet<QString> s = {QStringLiteral("png"), QStringLiteral("jpg"),
        QStringLiteral("jpeg"), QStringLiteral("webp"), QStringLiteral("gif"), QStringLiteral("svg")};
    return s;
}

inline const QSet<QString> &audioExtensions()
{
    static const QSet<QString> s = {QStringLiteral("mp3"), QStringLiteral("wav"),
        QStringLiteral("ogg"), QStringLiteral("flac")};
    return s;
}

inline const QSet<QString> &videoExtensions()
{
    static const QSet<QString> s = {QStringLiteral("mp4"), QStringLiteral("webm"),
        QStringLiteral("mov"), QStringLiteral("m4v"), QStringLiteral("mkv")};
    return s;
}

} // namespace AppPaths
