#include "CrashReporter.h"

#include <QClipboard>
#include <QCoreApplication>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLockFile>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QSysInfo>
#include <QUrl>

namespace {

constexpr qint64 kMaxLogBytes = 512 * 1024;
constexpr int kTailLines = 200;
constexpr qint64 kTailBytes = 64 * 1024;

QString issuesTabUrl()
{
    return QStringLiteral("https://github.com/emty-png/totm/issues");
}

} // namespace

CrashReporter *CrashReporter::create(QQmlEngine *engine, QJSEngine *scriptEngine)
{
    Q_UNUSED(engine);
    Q_UNUSED(scriptEngine);
    return shared();
}

CrashReporter *CrashReporter::shared()
{
    static CrashReporter *s_instance = nullptr;
    if (!s_instance)
        s_instance = new CrashReporter(nullptr);
    return s_instance;
}

bool CrashReporter::isReporterMode()
{
    return QCoreApplication::arguments().contains(QStringLiteral("--crash-report"));
}

CrashReporter::CrashReporter(QObject *parent)
    : QObject(parent)
{
    if (isReporterMode()) {
        QDir().mkpath(baseDir());
        m_reportLock = new QLockFile(baseDir() + QStringLiteral("/crash-report.lock"));
        m_reportLock->setStaleLockTime(30 * 1000);
        if (!m_reportLock->tryLock()) {
            m_suppressed = true;
            return;
        }
        loadPendingReport();
        if (!m_hasCrash)
            snapshotSentinel();
        return;
    }
    snapshotSentinel();
}

bool CrashReporter::hasCrash() const
{
    return m_hasCrash;
}

QString CrashReporter::crashSummary() const
{
    return m_crashSummary;
}

QString CrashReporter::crashLog() const
{
    return m_crashLog;
}

bool CrashReporter::anotherReporterShown() const
{
    return m_suppressed;
}

void CrashReporter::appendLog(const QString &line)
{
    QMutexLocker lock(&m_mutex);
    QDir().mkpath(logsDir());
    rotateLogIfNeeded();
    QFile log(logPath());
    if (!log.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text))
        return;
    const QString stamped = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs) + QStringLiteral(" ")
        + line + QStringLiteral("\n");
    log.write(stamped.toUtf8());
}

void CrashReporter::markRunning()
{
    if (isReporterMode())
        return;
    QDir().mkpath(baseDir());
    QSaveFile sentinel(sentinelPath());
    if (!sentinel.open(QIODevice::WriteOnly))
        return;
    const QJsonObject root{
        {QStringLiteral("pid"), QCoreApplication::applicationPid()},
        {QStringLiteral("version"), QCoreApplication::applicationVersion()},
        {QStringLiteral("startedAt"),
         QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd hh:mm:ss"))},
    };
    sentinel.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
    sentinel.commit();
}

void CrashReporter::markCleanExit()
{
    if (isReporterMode())
        return;
    QFile::remove(sentinelPath());
}

void CrashReporter::writePendingReport()
{
    if (isReporterMode() || !m_hasCrash)
        return;
    QDir().mkpath(baseDir());
    QSaveFile pending(pendingPath());
    if (!pending.open(QIODevice::WriteOnly))
        return;
    const QJsonObject root{
        {QStringLiteral("summary"), m_crashSummary},
        {QStringLiteral("log"), m_crashLog},
    };
    pending.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
    pending.commit();
}

bool CrashReporter::copyReport()
{
    QClipboard *board = QGuiApplication::clipboard();
    if (!board)
        return false;
    const QString report = m_crashSummary + QStringLiteral("\n") + QStringLiteral("Issues: ")
        + issuesTabUrl() + QStringLiteral("\n\n") + m_crashLog;
    board->setText(report);
    return true;
}

bool CrashReporter::openIssues()
{
    return QDesktopServices::openUrl(QUrl(issuesTabUrl()));
}

void CrashReporter::dismiss()
{
    if (!isReporterMode())
        QFile::remove(sentinelPath());
    if (m_hasCrash) {
        m_hasCrash = false;
        m_crashSummary.clear();
        m_crashLog.clear();
        emit crashChanged();
    }
}

QString CrashReporter::baseDir() const
{
    QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (dir.isEmpty())
        dir = QDir::homePath() + QStringLiteral("/.totm");
    if (!dir.endsWith(QStringLiteral("/totm"), Qt::CaseInsensitive))
        dir += QStringLiteral("/totm");
    return dir;
}

QString CrashReporter::logsDir() const
{
    return baseDir() + QStringLiteral("/logs");
}

QString CrashReporter::sentinelPath() const
{
    return baseDir() + QStringLiteral("/running.json");
}

QString CrashReporter::pendingPath() const
{
    return baseDir() + QStringLiteral("/pending-crash.json");
}

QString CrashReporter::logPath() const
{
    return logsDir() + QStringLiteral("/totm.log");
}

void CrashReporter::rotateLogIfNeeded()
{
    QFile log(logPath());
    if (!log.exists() || log.size() < kMaxLogBytes)
        return;
    QFile::remove(logPath() + QStringLiteral(".1"));
    QFile::rename(logPath(), logPath() + QStringLiteral(".1"));
}

void CrashReporter::snapshotSentinel()
{
    const QString sentinel = sentinelPath();
    QFile file(sentinel);
    if (!file.exists() || !file.open(QIODevice::ReadOnly))
        return;
    const QJsonObject root = QJsonDocument::fromJson(file.readAll()).object();
    file.close();
    const qint64 pid = root.value(QStringLiteral("pid")).toVariant().toLongLong();
    if (pid != 0 && pid == QCoreApplication::applicationPid())
        return;
    const QString at = root.value(QStringLiteral("startedAt")).toString();
    const QString version = root.value(QStringLiteral("version")).toString();
    m_hasCrash = true;
    m_crashSummary = tr("totm %1 · previous start %2 · %3")
                         .arg(version.isEmpty() ? QCoreApplication::applicationVersion() : version,
                               at.isEmpty() ? tr("unknown time") : at,
                               QSysInfo::prettyProductName());
    m_crashLog = readLogTail();
    QFile::remove(sentinel);
}

QString CrashReporter::readLogTail() const
{
    QFile log(logPath());
    if (!log.open(QIODevice::ReadOnly | QIODevice::Text))
        return tr("No log lines were recorded before the crash.");
    const qint64 size = log.size();
    if (size > kTailBytes)
        log.seek(size - kTailBytes);
    QString tail = QString::fromUtf8(log.readAll());
    QStringList lines = tail.split(u'\n');
    if (size > kTailBytes && !lines.isEmpty())
        lines.removeFirst();
    while (!lines.isEmpty() && lines.last().trimmed().isEmpty())
        lines.removeLast();
    if (lines.size() > kTailLines)
        lines = lines.mid(lines.size() - kTailLines);
    static const QRegularExpression stamp(QStringLiteral("^\\d{4}-\\d{2}-\\d{2}[T ]\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?Z?\\s+"));
    QStringList shown;
    for (QString line : lines) {
        if (line.contains(QStringLiteral("did not shut down cleanly")))
            continue;
        line.remove(stamp);
        if (!line.trimmed().isEmpty())
            shown.append(line);
    }
    if (shown.isEmpty())
        return tr("No log lines were recorded before the crash.");
    return shown.join(u'\n');
}

void CrashReporter::loadPendingReport()
{
    QFile pending(pendingPath());
    if (!pending.open(QIODevice::ReadOnly))
        return;
    const QJsonObject root = QJsonDocument::fromJson(pending.readAll()).object();
    pending.close();
    m_crashSummary = root.value(QStringLiteral("summary")).toString();
    m_crashLog = root.value(QStringLiteral("log")).toString();
    if (m_crashSummary.isEmpty() && m_crashLog.isEmpty())
        return;
    if (m_crashLog.isEmpty())
        m_crashLog = tr("No log lines were recorded before the crash.");
    m_hasCrash = true;
    QFile::remove(pendingPath());
}
