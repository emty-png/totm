#pragma once

#include <QMutex>
#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QtQml/qqmlregistration.h>

class QLockFile;

class CrashReporter : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool hasCrash READ hasCrash NOTIFY crashChanged)
    Q_PROPERTY(QString crashSummary READ crashSummary NOTIFY crashChanged)
    Q_PROPERTY(QString crashLog READ crashLog NOTIFY crashChanged)

public:
    static CrashReporter *create(QQmlEngine *engine, QJSEngine *scriptEngine);
    static CrashReporter *shared();
    static bool isReporterMode();
    explicit CrashReporter(QObject *parent);

    bool hasCrash() const;
    QString crashSummary() const;
    QString crashLog() const;
    bool anotherReporterShown() const;

    void appendLog(const QString &line);
    void markRunning();
    void markCleanExit();
    void writePendingReport();

    Q_INVOKABLE bool copyReport();
    Q_INVOKABLE bool openIssues();
    Q_INVOKABLE void dismiss();

signals:
    void crashChanged();

private:
    QString baseDir() const;
    QString logsDir() const;
    QString sentinelPath() const;
    QString pendingPath() const;
    QString logPath() const;
    void rotateLogIfNeeded();
    QString readLogTail() const;
    void loadPendingReport();
    void snapshotSentinel();

    mutable QMutex m_mutex;
    bool m_hasCrash = false;
    bool m_suppressed = false;
    QString m_crashSummary;
    QString m_crashLog;
    QLockFile *m_reportLock = nullptr;
};
