#pragma once

#include <QString>

class CrashHandler {
public:
    static void install(const QString &exePath);
    static void spawnReporter();
};
