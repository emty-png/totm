#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QStringList>
#include <QUrl>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

// FileBrowser: read-only directory listing for the in-app file picker.
//
// Ownership: all filesystem reads live here. QML renders rows and owns
// picked urls; it never touches the disk itself (same rule as the
// library: no QML-side file IO).
// Scope: local files only. Non-local urls yield empty results.
// Rows are plain maps for Repeater/ListView use:
//   places: {id, name, url} for well-known dirs that exist.
//   breadcrumbs: {name, url} from the filesystem root to the folder.
//   list: {fileName, url, isDir, size, modified, suffix}, dirs first
//     then case-insensitive names, dotfiles skipped. suffixes filters
//     files by extension ("totm"); empty lists every file. modified is
//     an ISO-8601 string for Date.parse on the QML side.
// Threading: main thread only. All calls are synchronous.
class FileBrowser : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    static FileBrowser *create(QQmlEngine *engine, QJSEngine *scriptEngine);
    explicit FileBrowser(QObject *parent = nullptr);

    Q_INVOKABLE QVariantList places() const;
    Q_INVOKABLE QVariantList breadcrumbs(const QUrl &folder) const;
    Q_INVOKABLE QVariantList list(const QUrl &folder, const QStringList &suffixes) const;
    Q_INVOKABLE QUrl parentOf(const QUrl &folder) const;
    Q_INVOKABLE bool isReadable(const QUrl &folder) const;
};
