#include "CursorStore.h"

#include <QDebug>
#include <QGuiApplication>
#include <QImage>
#include <QPainter>
#include <QPixmap>
#include <QScreen>
#include <QSvgRenderer>

namespace {
// ViewBox of the vendored Bibata SVGs; hotspots below are in this space.
constexpr int kSvgSpace = 256;
} // namespace

CursorStore *CursorStore::s_instance = nullptr;

CursorStore *CursorStore::create(QQmlEngine *engine, QJSEngine *scriptEngine)
{
    Q_UNUSED(scriptEngine);
    auto *store = new CursorStore(engine);
    QJSEngine::setObjectOwnership(store, QJSEngine::CppOwnership);
    return store;
}

CursorStore *CursorStore::instance()
{
    return s_instance;
}

CursorStore::CursorStore(QObject *parent)
    : QObject(parent)
{
    s_instance = this;
    // Late windows (dialogs; the crash reporter is a separate process and
    // keeps system cursors) attach on first focus; refresh() scans the rest.
    if (qGuiApp) {
        connect(qGuiApp, &QGuiApplication::focusWindowChanged, this, [this](QWindow *window) {
            if (window)
                attach(window);
        });
    }
}

// Shape -> Bibata SVG + hotspot (256-space, from upstream x.build.toml;
// unspecified upstream hotspots default to the 128,128 center). Wait/Busy
// are intentionally absent: Bibata ships them animated and QCursor pixmaps
// are static, so the system spinners stay.
const CursorStore::Entry *CursorStore::entryFor(int shape)
{
    static const QHash<int, Entry> table = {
        {Qt::ArrowCursor, {"arrow.svg", 55, 17}},
        {Qt::UpArrowCursor, {"up-arrow.svg", 128, 33}},
        {Qt::CrossCursor, {"cross.svg", 128, 128}},
        {Qt::IBeamCursor, {"ibeam.svg", 128, 128}},
        {Qt::SizeVerCursor, {"size-ver.svg", 128, 128}},
        {Qt::SizeHorCursor, {"size-hor.svg", 128, 128}},
        {Qt::SizeBDiagCursor, {"size-bdiag.svg", 128, 128}},
        {Qt::SizeFDiagCursor, {"size-fdiag.svg", 128, 128}},
        {Qt::SizeAllCursor, {"size-all.svg", 128, 128}},
        {Qt::SplitVCursor, {"size-ver.svg", 128, 128}},
        {Qt::SplitHCursor, {"size-hor.svg", 128, 128}},
        {Qt::PointingHandCursor, {"hand.svg", 114, 18}},
        {Qt::ForbiddenCursor, {"forbidden.svg", 128, 128}},
        {Qt::WhatsThisCursor, {"whatsthis.svg", 42, 86}},
        {Qt::OpenHandCursor, {"open-hand.svg", 144, 79}},
        {Qt::ClosedHandCursor, {"grabbing.svg", 128, 66}},
        {Qt::DragMoveCursor, {"grabbing.svg", 128, 66}},
        {Qt::DragCopyCursor, {"drag-copy.svg", 100, 65}},
        {Qt::DragLinkCursor, {"drag-link.svg", 100, 65}},
    };
    auto it = table.constFind(shape);
    return it == table.constEnd() ? nullptr : &it.value();
}

void CursorStore::refresh(bool dark)
{
    const bool themeChanged = (dark != m_dark);
    m_dark = dark;
    // (Re)attach every window: covers windows created before the store.
    for (QWindow *window : QGuiApplication::allWindows()) {
        if (window)
            attach(window);
    }
    if (!themeChanged && !m_cache.isEmpty())
        return;
    reapply();
}

void CursorStore::setSize(int pixels)
{
    pixels = qBound(12, pixels, 32);
    if (pixels == m_size)
        return;
    m_size = pixels;
    reapply();
}

void CursorStore::reapply()
{
    m_cache.clear();
    m_guard = true;
    for (QWindow *window : QGuiApplication::allWindows()) {
        if (!window)
            continue;
        // A window hiding its cursor (BlankCursor) stays hidden.
        if (window->cursor().shape() == Qt::BlankCursor)
            continue;
        const int shape = m_shapes.value(window, static_cast<int>(Qt::ArrowCursor));
        const QCursor custom = cursorFor(shape, dprFor(window));
        if (!custom.pixmap().isNull())
            window->setCursor(custom);
    }
    m_guard = false;
}

qreal CursorStore::dprFor(QWindow *window) const
{
    // Per-window screen DPR so mixed-DPI drags stay crisp. Falls back to
    // the primary screen (then 1.0) when the window has no screen yet.
    if (window) {
        if (QScreen *s = window->screen())
            return s->devicePixelRatio();
    }
    if (QScreen *primary = QGuiApplication::primaryScreen())
        return primary->devicePixelRatio();
    return 1.0;
}

void CursorStore::attach(QWindow *window)
{
    if (!window || m_attached.contains(window))
        return;
    m_attached.insert(window);
    window->installEventFilter(this);
    connect(window, &QObject::destroyed, this, [this, window]() { detach(window); });
    // Mixed-DPI: repaint this window's cursors when it moves screens.
    connect(window, &QWindow::screenChanged, this, [this, window](QScreen *) {
        if (!window)
            return;
        if (window->cursor().shape() == Qt::BlankCursor)
            return;
        const int shape = m_shapes.value(window, static_cast<int>(Qt::ArrowCursor));
        const QCursor custom = cursorFor(shape, dprFor(window));
        if (!custom.pixmap().isNull()) {
            m_guard = true;
            window->setCursor(custom);
            m_guard = false;
        }
    });
}

void CursorStore::detach(QWindow *window)
{
    m_attached.remove(window);
    m_shapes.remove(window);
}

bool CursorStore::eventFilter(QObject *watched, QEvent *event)
{
    if (event->type() == QEvent::CursorChange && !m_guard) {
        if (auto *window = qobject_cast<QWindow *>(watched)) {
            const Qt::CursorShape shape = window->cursor().shape();
            // Ours already (pixmap cursors report BitmapCursor) or an
            // intentional hide: remember nothing, replace nothing.
            if (shape == Qt::BitmapCursor || shape == Qt::BlankCursor)
                return false;
            m_shapes.insert(window, static_cast<int>(shape));
            const QCursor custom = cursorFor(static_cast<int>(shape), dprFor(window));
            if (!custom.pixmap().isNull()) {
                m_guard = true;
                window->setCursor(custom);
                m_guard = false;
            }
        }
    }
    return false;
}

QCursor CursorStore::cursorFor(int shape, qreal dpr)
{
    if (!(dpr > 0.0))
        dpr = 1.0;
    const int bucket = qMax(1, qRound(dpr * 100.0));
    const QString key = QString::number(shape) + QLatin1Char('@') + QString::number(bucket);
    auto cached = m_cache.constFind(key);
    if (cached != m_cache.constEnd())
        return cached.value();
    const Entry *entry = entryFor(shape);
    if (!entry)
        return QCursor();
    const QString resource = (m_dark ? QStringLiteral(":/cursors/dark/") : QStringLiteral(":/cursors/light/"))
        + QString::fromLatin1(entry->file);
    const QCursor custom = loadSvg(resource, entry->hotX256, entry->hotY256, dpr);
    if (!custom.pixmap().isNull())
        m_cache.insert(key, custom);
    return custom;
}

QCursor CursorStore::loadSvg(const QString &resource, int hotX256, int hotY256, qreal dpr)
{
    QSvgRenderer renderer(resource);
    if (!renderer.isValid()) {
        qWarning() << "totm: bad cursor svg" << resource;
        return QCursor();
    }
    if (!(dpr > 0.0))
        dpr = 1.0;
    const int px = qMax(1, qRound(m_size * dpr));
    QImage image(px, px, QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    QPainter painter(&image);
    // Scale the 256-unit viewBox down into the cursor image. Without the
    // target rect the SVG paints at native size and only a giant cropped
    // corner lands in the pixmap.
    renderer.render(&painter, QRectF(0, 0, px, px));
    painter.end();
    QPixmap pixmap = QPixmap::fromImage(image);
    pixmap.setDevicePixelRatio(dpr);
    // Hotspot in device pixels, scaled from the 256 SVG space.
    const int hotX = qRound(hotX256 * px / static_cast<qreal>(kSvgSpace));
    const int hotY = qRound(hotY256 * px / static_cast<qreal>(kSvgSpace));
    return QCursor(pixmap, hotX, hotY);
}
