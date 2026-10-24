#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QStringList>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// FileBrowser: directory listing plus a small set of picker helpers.
//
// Ownership: all filesystem reads live here. QML renders rows and owns
// picked urls; it never touches the disk itself (same rule as the
// library: no QML-side file IO).
// Scope: local files only. Non-local urls yield empty results.
// Rows are plain maps for Repeater/ListView use:
//   places: {id, name, url} for well-known dirs that exist.
//   volumes: {id, name, url, detail} for user-visible mounts.
//   breadcrumbs: {name, url} from the filesystem root to the folder.
//   list: {fileName, url, isDir, size, modified, suffix}, dirs first
//     then the requested sort order. suffixes filters files by extension
//     ("totm"); empty lists every file. Hidden entries stay out unless
//     showHidden. modified is an ISO-8601 string for Date.parse in QML.
// Writes: createFolder is the only mutation (one name component, an
// existing parent, no overwrite). Everything else is read-only.
// Threading: main thread only. All calls are synchronous.
class FileBrowser : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    static FileBrowser *create(QQmlEngine *engine, QJSEngine *scriptEngine);
    explicit FileBrowser(QObject *parent = nullptr);

    Q_INVOKABLE QVariantList places() const;
    Q_INVOKABLE QVariantList volumes() const;
    Q_INVOKABLE QVariantList breadcrumbs(const QUrl &folder) const;
    Q_INVOKABLE QVariantList list(const QUrl &folder, const QStringList &suffixes,
                                  bool showHidden, const QString &sortKey, bool ascending) const;
    Q_INVOKABLE QUrl parentOf(const QUrl &folder) const;
    Q_INVOKABLE bool isReadable(const QUrl &folder) const;
    Q_INVOKABLE bool isWritable(const QUrl &folder) const;
    Q_INVOKABLE QString displayPath(const QUrl &folder) const;
    Q_INVOKABLE QUrl resolveFolder(const QString &text) const;
    // Resolves a typed path to {ok, folder, file}. A directory yields an
    // empty file; a file yields its containing folder plus the file url.
    Q_INVOKABLE QVariantMap resolveTarget(const QString &text) const;
    Q_INVOKABLE QVariantMap createFolder(const QUrl &parent, const QString &name) const;
    // Versioned image-provider url for a local file. stamp (usually the
    // row's modified value) busts the QML image cache after edits.
    Q_INVOKABLE QString thumbnailSource(const QUrl &file, const QString &stamp) const;
};
