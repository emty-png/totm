#pragma once

#include <QMap>
#include <QObject>
#include <QQmlEngine>
#include <QJSEngine>
#include <QSet>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// ScriptBridge: the `totm` object visible to user JS. Collects validated
// scene operations; it never touches the document (QML applies the op
// list through the normal factory/animation path in one undo entry).
// One instance per evaluation, same thread as its engine.
class ScriptBridge : public QObject
{
    Q_OBJECT

public:
    // Handles: 0..N-1 index pending creates; kFindBit marks a named
    // lookup resolved later at apply time (existing nodes by name).
    // Audio calls (audio/pickAudio) return kNoHandle: timeline clips
    // take no presets and join no groups.
    static const int kFindBit = 1 << 30;
    static const int kNoHandle = -2;

    // Resource caps: a tight JS loop (e.g. 100k totm.rect calls) must
    // fail with a readable error, never OOM the helper or the app.
    // The helper output stays small enough for the parent to parse on
    // the main thread, and QML apply stays inside one fast transaction.
    // QML mirrors these in DocScript (same numbers, same messages).
    static const int kMaxCreates = 2000;
    static const int kMaxGroups = 500;
    static const int kMaxAnimates = 2000;
    static const int kMaxSets = 5000;
    static const int kMaxRemoves = 2000;
    static const int kMaxFinds = 1000;
    static const int kMaxPicks = 32;
    static const int kMaxAudio = 128;
    static const int kMaxPenPoints = 4096;
    static const int kMaxGroupMembers = 2000;
    static const int kMaxNameLen = 256;
    static const int kMaxBlobLen = 512;
    static const int kMaxFillLen = 4096;
    static const int kMaxTextLen = 20000;
    static const int kMaxPresetLen = 128;
    static const int kMaxClasses = 32;
    static const int kMaxClassLen = 64;
    static const int kMaxSourceChars = 262144; // 256K chars per evaluation
    static const int kMaxAnimateOptsBytes = 65536; // one animate call's options+easing
    static const int kMaxOutputBytes = 4 * 1024 * 1024;

    explicit ScriptBridge(QJSEngine *engine, const QVariantMap &pickResults, QObject *parent = nullptr);

    Q_INVOKABLE int rect(const QVariantMap &opts);
    Q_INVOKABLE int ellipse(const QVariantMap &opts);
    Q_INVOKABLE int triangle(const QVariantMap &opts);
    Q_INVOKABLE int star(const QVariantMap &opts);
    Q_INVOKABLE int text(const QVariantMap &opts);
    Q_INVOKABLE int pen(const QVariantMap &opts);
    Q_INVOKABLE int image(const QString &blob, const QVariantMap &opts);
    Q_INVOKABLE int video(const QString &blob, const QVariantMap &opts);
    Q_INVOKABLE int audio(const QString &blob, const QVariantMap &opts);
    Q_INVOKABLE int pickImage(const QVariantMap &opts);
    Q_INVOKABLE int pickVideo(const QVariantMap &opts);
    Q_INVOKABLE int pickAudio(const QVariantMap &opts);
    Q_INVOKABLE int group(const QString &name, const QVariantList &handles);
    Q_INVOKABLE int find(const QString &name);
    Q_INVOKABLE void set(int handle, const QVariantMap &props);
    Q_INVOKABLE void remove(int handle);
    Q_INVOKABLE void animate(int handle, const QString &preset, const QVariantMap &opts);
    Q_INVOKABLE void setDuration(double seconds);

    QVariantMap takeResult() const;

private:
    int addShape(const QString &kind, const QVariantMap &opts);
    int addMedia(const QString &kind, const QString &blob, const QVariantMap &opts);
    // Pick plumbing: unresolved calls record a pick entry and yield a
    // placeholder (image/video: a blob-less create, so handles stay
    // stable across the replay); preloaded results build the real op.
    int pickMedia(const QString &kind, const QVariantMap &opts);
    double optNum(const QVariantMap &opts, const char *key, double fallback) const;
    void fail(const QString &message);

    QJSEngine *m_engine = nullptr;
    QVariantMap m_pickResults;
    int m_pickCursor = 0;
    QVariantList m_creates;
    QVariantList m_groups;
    QVariantList m_animates;
    QVariantList m_finds;
    QVariantList m_picks;
    QVariantList m_audio;
    QVariantList m_sets;
    QVariantList m_removes;
    double m_duration = 0.0;
    QSet<int> m_grouped;
};

// Synchronous headless evaluation shared by the --script-eval helper
// (main.cpp) and unit tests. pickResults maps pick-call order to stored
// blob names for replay runs ({} on first pass). Runs on the caller's
// thread in a private engine exposing only `totm` (plus stock
// JSON/Math): no filesystem, no network, no app internals. Result:
// {ok, ops:{creates, groups, animates, finds, picks, audio, duration}}
// or {ok:false, error, line}. Only JSON-safe values ride along.
QVariantMap evaluateScriptSource(const QString &code, const QVariantMap &pickResults = QVariantMap());

// ScriptRunner: sandboxed user-JS evaluation for dev scripts.
//
// Ownership: stateless app-wide singleton (QML_ELEMENT + QML_SINGLETON).
// Each run() evaluates in a HELPER PROCESS (this executable with
// --script-eval), never in-process: a hung or crashing script can only
// take down its own process, and abort() is a SIGKILL that always
// lands (unlike thread termination, which cannot stop JIT-spun
// QJSEngine evaluation). Results are plain op data for QML to validate
// and apply (native nodes + clips, export-safe).
// Threading: run() returns immediately with a run id; finished(runId,
// result) fires on the main thread. abort() kills the helper and still
// fires finished() with {ok:false, aborted:true} so QML always
// resolves. Result shape matches evaluateScriptSource.
class ScriptRunner : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    static ScriptRunner *create(QQmlEngine *engine, QJSEngine *scriptEngine);
    explicit ScriptRunner(QObject *parent = nullptr);
    ~ScriptRunner() override;

    Q_INVOKABLE int run(const QString &code, const QVariantMap &pickResults = QVariantMap());
    Q_INVOKABLE void abort(int runId);
    // Opens DEV_SCRIPT.html (the scripting guide) in the default browser.
    Q_INVOKABLE bool openGuide();

signals:
    void finished(int runId, const QVariantMap &result);

private slots:
    void onProcessFinished(int runId);

private:
    struct Active {
        class QProcess *process = nullptr;
        class QTemporaryFile *source = nullptr;
        class QTemporaryFile *picks = nullptr;
    };
    void finishAborted(int runId);
    QMap<int, Active> m_active;
    int m_nextId = 1;
};
