#pragma once

#include <QDir>
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
    QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (dir.isEmpty())
        dir = QDir::homePath() + QStringLiteral("/.totm");
    if (!dir.endsWith(QStringLiteral("/totm"), Qt::CaseInsensitive))
        dir += QStringLiteral("/totm");
    return dir;
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
