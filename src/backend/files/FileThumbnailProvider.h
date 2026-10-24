#pragma once

#include <QCache>
#include <QImage>
#include <QMutex>
#include <QQuickImageProvider>

// FileThumbnailProvider: bounded, scaled thumbnails for the file
// picker grid. QML receives `image://totmthumb/<base64 path>?v=...`
// from FileBrowser and never decodes a raw file url itself.
// Local files only. Decoding happens off the UI thread via Qt's image
// provider path; a small mutex-guarded cache absorbs grid scrolling.
class FileThumbnailProvider : public QQuickImageProvider
{
public:
    FileThumbnailProvider();

    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;

private:
    QMutex m_mutex;
    QCache<QString, QImage> m_cache;
};
