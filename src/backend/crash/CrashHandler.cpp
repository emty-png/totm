#include "CrashHandler.h"

#include <QProcess>
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <exception>

#ifndef Q_OS_WIN
#include <signal.h>
#include <unistd.h>
#else
#include <windows.h>
#endif

namespace {

std::atomic_flag g_fired = ATOMIC_FLAG_INIT;
char g_exe[4096] = {0};

bool claimFired()
{
    return !g_fired.test_and_set();
}

}

void CrashHandler::spawnReporter()
{
    if (!claimFired())
        return;
    if (g_exe[0] == '\0')
        return;
    QProcess::startDetached(QString::fromLocal8Bit(g_exe), {QStringLiteral("--crash-report")});
}

#ifndef Q_OS_WIN

void fatalSignal(int sig)
{
    if (claimFired() && g_exe[0] != '\0') {
        pid_t pid = fork();
        if (pid == 0) {
            execl(g_exe, g_exe, "--crash-report", (char *)nullptr);
            _exit(127);
        }
    }
    signal(sig, SIG_DFL);
    raise(sig);
}

#else

LONG WINAPI exceptionFilter(EXCEPTION_POINTERS *)
{
    CrashHandler::spawnReporter();
    return EXCEPTION_EXECUTE_HANDLER;
}

#endif

void terminateHandler()
{
    CrashHandler::spawnReporter();
    std::abort();
}

void CrashHandler::install(const QString &exePath)
{
    const QByteArray bytes = exePath.toLocal8Bit();
    std::strncpy(g_exe, bytes.constData(), sizeof(g_exe) - 1);
    std::set_terminate(terminateHandler);
#ifndef Q_OS_WIN
    struct sigaction action;
    std::memset(&action, 0, sizeof(action));
    action.sa_handler = fatalSignal;
    sigemptyset(&action.sa_mask);
    const int fatalSignals[] = {SIGSEGV, SIGABRT, SIGFPE, SIGILL, SIGBUS};
    for (int sig : fatalSignals)
        sigaction(sig, &action, nullptr);
#else
    SetUnhandledExceptionFilter(exceptionFilter);
#endif
}
