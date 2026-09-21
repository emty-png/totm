#include <QDebug>
#include <QFileInfo>
#include <QFileOpenEvent>
#include <QGuiApplication>
#include <QHash>
#include <QIcon>
#include <QLocalServer>
#include <QLocalSocket>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QStandardPaths>
#include <QUrl>

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
            m_buffers[client] += client->readAll();
        });
        connect(client, &QLocalSocket::disconnected, this, [this, client]() {
            m_buffers[client] += client->readAll();
            const QStringList files = QString::fromUtf8(m_buffers.take(client))
                                          .split(u'\n', Qt::SkipEmptyParts);
            client->deleteLater();
            emit filesRequested(files);
        });
    }

private:
    QString m_serverName;
    QStringList m_initial;
    QStringList m_pending;
    bool m_ready = false;
    QLocalServer *m_server = nullptr;
    QHash<QLocalSocket *, QByteArray> m_buffers;
};

QString singleInstanceServerName()
{
    QString user = QString::fromUtf8(qgetenv("USER"));
    if (user.isEmpty()) {
        user = QString::fromUtf8(qgetenv("USERNAME"));
    }
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

    QGuiApplication app(argc, argv);
    // Identity drives QSettings (org "tot", app "totm") and QStandardPaths.
    app.setApplicationName(QStringLiteral("totm"));
    app.setApplicationVersion(QStringLiteral("0.2.1"));
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
    const QStringList args = QCoreApplication::arguments();
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
    if (!single.ensurePrimary()) {
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
