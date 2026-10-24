#include "FileThumbnailProvider.h"

#include <QByteArray>
#include <QFileInfo>
#include <QImageReader>
#include <QMutexLocker>
#include <QString>

namespace {
constexpr int kDefaultThumb = 128;
constexpr int kMaxThumb = 512;
constexpr int kCacheKiB = 64 * 1024;
} // namespace

FileThumbnailProvider::FileThumbnailProvider()
    : QQuickImageProvider(QQuickImageProvider::Image)
{
    m_cache.setMaxCost(kCacheKiB);
}

QImage FileThumbnailProvider::requestImage(const QString &id, QSize *size,
                                           const QSize &requestedSize)
{
    QString encoded = id;
    const int query = encoded.indexOf(QLatin1Char('?'));
    if (query >= 0) {
        encoded = encoded.left(query);
    }
    const QByteArray raw = QByteArray::fromBase64(encoded.toLatin1(), QByteArray::Base64UrlEncoding);
    const QString path = QString::fromUtf8(raw);
    if (path.isEmpty() || !QFileInfo(path).isFile()) {
        return {};
    }

    const QSize target = requestedSize.isValid()
        ? QSize(qBound(16, requestedSize.width(), kMaxThumb),
                qBound(16, requestedSize.height(), kMaxThumb))
        : QSize(kDefaultThumb, kDefaultThumb);
    const QString key = encoded + QLatin1Char('|') + QString::number(target.width())
        + QLatin1Char('x') + QString::number(target.height());
    {
        QMutexLocker lock(&m_mutex);
        if (QImage *cached = m_cache.object(key)) {
            if (size) {
                *size = cached->size();
            }
            return *cached;
        }
    }

    QImageReader reader(path);
    reader.setAutoTransform(true);
    const QSize original = reader.size();
    QSize scaled = original;
    if (scaled.isValid()) {
        if (scaled.width() > target.width() || scaled.height() > target.height())
            scaled.scale(target, Qt::KeepAspectRatio);
        else
            scaled = original;
    } else {
        scaled = target;
    }
    if (scaled.isValid() && scaled != original) {
        reader.setScaledSize(scaled);
    }
    QImage image = reader.read();
    if (image.isNull()) {
        return {};
    }
    if (image.width() > target.width() || image.height() > target.height()) {
        image = image.scaled(target, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    }
    if (size) {
        *size = image.size();
    }

    const int cost = qMax(1, int(image.sizeInBytes() / 1024));
    QMutexLocker lock(&m_mutex);
    m_cache.insert(key, new QImage(image), cost);
    return image;
}
