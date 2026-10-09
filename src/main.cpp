#include <QDebug>
#include <QDir>
#include <QFileInfo>
#include <QFont>
#include <QFontDatabase>
#include <QFileOpenEvent>
#include <QGuiApplication>
#include <QHash>
#include <QIcon>
#include <QLocalServer>
#include <QLocalSocket>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QSettings>
#include <QStandardPaths>
#include <QThread>
#include <QUrl>

#ifndef Q_OS_WIN
#include <unistd.h>
#endif

#include "CrashHandler.h"
#include "CrashReporter.h"
#include "PluginNetworkGuard.h"

static CrashReporter *g_crashReporter = nullptr;

// Single-instance forwarding for .totm opens. The primary instance owns
// a QLocalServer (socket name is per-user so two accounts never collide);
// later launches send their file urls there and exit, so a double-click
// lands in the running window instead of spawning a second one. macOS
// Finder opens arrive as QFileOpenEvent instead of argv and go through
// the same submit() path. Messages arriving before QML is ready queue
// in m_pending and flush on setReady(); an empty request only raises.
class SingleInstance : public QObject
{
    Q_OBJECT
public:
    explicit SingleInstance(const QString &serverName, QObject *parent = nullptr)
        : QObject(parent)
        , m_serverName(serverName)
    {
    }

    void setInitialFiles(const QStringList &files)
    {
        m_initial = files;
    }

    // True when this process is the primary. A secondary forwards its
    // files and the caller should exit(0) immediately.
    bool ensurePrimary()
    {
        QLocalSocket probe;
        probe.connectToServer(m_serverName);
        if (probe.waitForConnected(500)) {
            const QByteArray out = m_initial.join(u'\n').toUtf8();
            if (!out.isEmpty()) {
                probe.write(out);
                probe.waitForBytesWritten(2000);
            }
            probe.disconnectFromServer();
            return false;
        }
        // A crashed run can leave the socket behind; take it over.
        QLocalServer::removeServer(m_serverName);
        m_server = new QLocalServer(this);
        connect(m_server, &QLocalServer::newConnection, this, &SingleInstance::acceptConnection);
        if (!m_server->listen(m_serverName)) {
            qWarning() << "totm: single-instance server failed:" << m_server->errorString();
        }
        return true;
    }

    // Restart path (--restart-wait): the old instance may still be
    // shutting down and holding the socket, so retry instead of
    // forwarding-and-exiting on the first probe.
    bool ensurePrimaryWait(int attempts = 24, int intervalMs = 250)
    {
        for (int i = 0; i < attempts; ++i) {
            if (ensurePrimary())
                return true;
            QThread::msleep(intervalMs);
        }
        return ensurePrimary();
    }

    void setReady()
    {
        m_ready = true;
        if (!m_pending.isEmpty()) {
            emit filesRequested(m_pending);
            m_pending.clear();
        }
    }

    void submitFiles(const QStringList &files)
    {
        if (m_ready) {
            emit filesRequested(files);
        } else {
            m_pending += files;
        }
    }

signals:
    void filesRequested(const QStringList &files);

protected:
    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (event->type() == QEvent::FileOpen) {
            const QUrl url = static_cast<QFileOpenEvent *>(event)->url();
            const QString path = url.isLocalFile() ? url.toLocalFile() : url.path();
            if (!url.isEmpty() && path.endsWith(QStringLiteral(".totm"), Qt::CaseInsensitive)) {
                submitFiles({url.toString()});
            }
            return true;
        }
        return QObject::eventFilter(watched, event);
    }

private slots:
    void acceptConnection()
    {
        QLocalSocket *client = m_server ? m_server->nextPendingConnection() : nullptr;
        if (!client) {
            return;
        }
        connect(client, &QLocalSocket::readyRead, this, [this, client]() {
            // Bound the forward buffer: a slow-loris peer must not OOM
            // the primary. Drop oversize forwards outright.
            if (m_buffers.value(client).size() > kMaxForwardBytes) {
                client->disconnectFromServer();
                return;
            }
            m_buffers[client] += client->readAll();
            if (m_buffers.value(client).size() > kMaxForwardBytes) {
                m_buffers.remove(client);
                client->disconnectFromServer();
            }
        });
        connect(client, &QLocalSocket::disconnected, this, [this, client]() {
            QByteArray pending = m_buffers.take(client);
            pending += client->readAll();
            client->deleteLater();
            if (pending.size() > kMaxForwardBytes)
                return;
            QStringList files = QString::fromUtf8(pending).split(u'\n', Qt::SkipEmptyParts);
            if (files.size() > kMaxForwardFiles)
                files = files.mid(0, kMaxForwardFiles);
            emit filesRequested(files);
        });
    }

private:
    static constexpr int kMaxForwardBytes = 64 * 1024;
    static constexpr int kMaxForwardFiles = 64;
    QString m_serverName;
    QStringList m_initial;
    QStringList m_pending;
    bool m_ready = false;
    QLocalServer *m_server = nullptr;
    QHash<QLocalSocket *, QByteArray> m_buffers;
};

QString singleInstanceServerName()
{
    // Per-user socket name without trusting spoofable $USER/$USERNAME env:
    // hash the home path (stable per account, not env-controlled). Unix
    // keeps the real uid fast path.
#ifndef Q_OS_WIN
    const QString user = QString::number(::getuid());
#else
    const QString home = QDir::homePath();
    QString user;
    if (!home.isEmpty())
        user = QString::number(qHash(home), 16);
    if (user.isEmpty()) {
        // Last resort only (home unavailable): env fallback.
        user = QString::fromUtf8(qgetenv("USERNAME"));
        if (user.isEmpty())
            user = QString::fromUtf8(qgetenv("USER"));
    }
#endif
    const QString base = QStringLiteral("totm-single-instance");
    return user.isEmpty() ? base : base + u'-' + user;
}

// Message filter for known-benign third-party noise: KDE Breeze styling
// of stock FileDialogs, missing desktop icon themes, the QtMultimedia
// backend banner, and VDPAU probes on machines without NVIDIA drivers
// (software fallback carries on). Scoped to those sources only; Totm
// QML and backend warnings still reach stderr.
void totMessageHandler(QtMsgType type, const QMessageLogContext &context, const QString &msg)
{
    const QString file = QString::fromUtf8(context.file ? context.file : "");
    if (file.contains(QStringLiteral("org/kde/breeze"))
        || file.contains(QStringLiteral("Dialogs/quickimpl/qml/SideBar.qml"))
        || msg.contains(QStringLiteral("kf.iconthemes"))
        || msg.contains(QStringLiteral("Using Qt multimedia with FFmpeg"))
        || msg.contains(QStringLiteral("Failed to open VDPAU backend"))) {
        return;
    }
    // Matches the default handler (bare message); aborts on fatal.
    fprintf(stderr, "%s\n", qPrintable(msg));
    if (g_crashReporter)
        g_crashReporter->appendLog(msg);
    if (type == QtFatalMsg) {
        CrashHandler::spawnReporter();
        abort();
    }
}

int main(int argc, char *argv[])
{
    qInstallMessageHandler(totMessageHandler);

    // Low-spec mode applies the single-threaded scene-graph loop, which
    // is read at Qt init: resolve it from storage before the application
    // object exists (explicit org/app match SettingsStore's identity).
    // An explicit env export always wins over the stored toggle.
    if (qEnvironmentVariableIsEmpty("QSG_RENDER_LOOP")) {
        const QSettings early(QStringLiteral("tot"), QStringLiteral("totm"));
        if (early.value(QStringLiteral("general/lowSpec"), false).toBool())
            qputenv("QSG_RENDER_LOOP", QByteArrayLiteral("basic"));
    }

    QGuiApplication app(argc, argv);
    // Identity drives QSettings (org "tot", app "totm") and QStandardPaths.
    app.setApplicationName(QStringLiteral("totm"));
    // Bundled UI typeface (Inter, OFL-1.1 — see src/fonts/inter/OFL.txt).
    // Loaded before any QML so the family resolves app-wide from the
    // first frame; failures only warn (Qt substitutes a system sans).
    // SettingsStore::applyFontFamily picks Inter vs. the user override.
    for (const QString &face : {QStringLiteral(":/fonts/inter/Inter-Regular.ttf"),
                                QStringLiteral(":/fonts/inter/Inter-Medium.ttf"),
                                QStringLiteral(":/fonts/inter/Inter-SemiBold.ttf"),
                                QStringLiteral(":/fonts/inter/Inter-Bold.ttf")}) {
        if (QFontDatabase::addApplicationFont(face) < 0)
            qWarning() << "totm: bundled font failed to load:" << face;
    }
    // UI typeface applies at startup: QML text resolves its family at
    // creation and ignores later setFont() calls, so the stored choice
    // must land before the engine loads (explicit org/app match
    // SettingsStore's identity, like the low-spec read above). Empty
    // means bundled Inter; "system" keeps the OS font. Changes made in
    // Appearance take effect on restart (noted on the font card).
    {
        const QSettings early(QStringLiteral("tot"), QStringLiteral("totm"));
        const QString stored =
            early.value(QStringLiteral("appearance/fontFamily"), QString()).toString().trimmed();
        if (stored.compare(QStringLiteral("system"), Qt::CaseInsensitive) == 0) {
            // OS default: leave the stock application font alone.
        } else {
            QFont appFont;
            appFont.setFamily(stored.isEmpty() ? QStringLiteral("Inter") : stored);
            QGuiApplication::setFont(appFont);
        }
    }
    app.setApplicationVersion(QStringLiteral("0.8.1"));
    app.setOrganizationName(QStringLiteral("tot"));
    // Window/taskbar icon (X11, Wayland, Windows).
    app.setWindowIcon(QIcon(QStringLiteral(":/icons/totm.png")));
    // The desktop id drives portal registration (Wayland app-id
    // matching, notifications). Claim it only when totm.desktop is
    // actually installed: dev builds run straight from the build tree,
    // where the portal lookup fails and Qt warns on every launch.
    if (!QStandardPaths::locateAll(QStandardPaths::ApplicationsLocation,
                                   QStringLiteral("totm.desktop"))
             .isEmpty()) {
        app.setDesktopFileName(QStringLiteral("totm"));
    }

    if (CrashReporter::isReporterMode()) {
        CrashReporter *report = CrashReporter::shared();
        g_crashReporter = report;
        if (!report->hasCrash() || report->anotherReporterShown())
            return 0;
        QQmlApplicationEngine engine;
        engine.addImportPath(QStringLiteral("qrc:/"));
        PluginNetworkFactory networkFactory;
        engine.setNetworkAccessManagerFactory(&networkFactory);
        QObject::connect(
            &engine, &QQmlApplicationEngine::objectCreationFailed,
            &app, []() { QCoreApplication::exit(-1); },
            Qt::QueuedConnection);
        engine.loadFromModule(QStringLiteral("Totm"), QStringLiteral("CrashWindow"));
        return app.exec();
    }

    // File association: the desktop entry passes dropped/opened .totm
    // bundles as argv (Exec=totm %F). Forward existing ones as file urls
    // for Main.qml to import + open on launch; anything else is ignored.
    CrashHandler::install(QCoreApplication::applicationFilePath());
    QStringList openFiles;
    QStringList args = QCoreApplication::arguments();
    // Internal relaunch flag (see SettingsStore::restartApp): not a file,
    // stripped before anything else sees argv.
    const bool restartWait = args.removeOne(QStringLiteral("--restart-wait"));
    for (int i = 1; i < args.size(); ++i) {
        const QFileInfo info(args.at(i));
        if (!info.suffix().compare(QStringLiteral("totm"), Qt::CaseInsensitive)
            && info.exists()) {
            openFiles.append(QUrl::fromLocalFile(info.absoluteFilePath()).toString());
        }
    }

    // A running instance owns .totm opens: forward and exit instead of
    // spawning a second window.
    SingleInstance single(singleInstanceServerName());
    single.setInitialFiles(openFiles);
    app.installEventFilter(&single);
    if (!(restartWait ? single.ensurePrimaryWait() : single.ensurePrimary())) {
        return 0;
    }

    QQmlApplicationEngine engine;
    CrashReporter *crashReporter = CrashReporter::shared();
    g_crashReporter = crashReporter;
    crashReporter->markRunning();
    if (crashReporter->hasCrash()) {
        qWarning() << "totm: previous run did not shut down cleanly; opening the crash reporter.";
        crashReporter->writePendingReport();
        QProcess::startDetached(QCoreApplication::applicationFilePath(),
                                {QStringLiteral("--crash-report")});
    }
    QObject::connect(&app, &QCoreApplication::aboutToQuit, crashReporter,
                     &CrashReporter::markCleanExit);
    // Resolve the Totm module from embedded resources (:/Totm/qmldir), so
    // packaged builds need no module files beside the executable (a Totm/
    // dir would collide with the `totm` exe on case-insensitive filesystems).
    engine.addImportPath(QStringLiteral("qrc:/"));
    // Remote transport is denied engine-wide (see PluginNetworkGuard):
    // the app loads nothing remote, and plugins must stay offline.
    PluginNetworkFactory networkFactory;
    engine.setNetworkAccessManagerFactory(&networkFactory);

    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed,
        &app, []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);

    engine.rootContext()->setContextProperty(QStringLiteral("totmSingleInstance"), &single);
    engine.rootContext()->setContextProperty(QStringLiteral("totmOpenFiles"), openFiles);

    engine.loadFromModule(QStringLiteral("Totm"), QStringLiteral("Main"));
    // QML is up: flush any file opens that arrived during startup.
    single.setReady();

    return app.exec();
}

#include "main.moc"
