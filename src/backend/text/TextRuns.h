#pragma once

#include <QObject>
#include <QFont>
#include <QQmlEngine>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// TextRuns: plain-data rich-text spans for one text box, shared by the
// inline editor (HTML view) and the C++ glyph painter.
//
// A run is {start, len, bold, italic, underline, strike, color} over the
// box plain text (UTF-16 offsets, \n newlines). Empty list = single box
// style. Runs are sorted, non-overlapping, clamped to the content; only
// set flags survive normalization (a run with nothing set merges away).
// Color is "" when unset (box fills paint those glyphs); bold maps to
// weight 700 in paint, otherwise the box weight applies.
//
// The editor round-trips through a canonical HTML subset
// (<b><i><u><s><font color>) emitted and parsed here, so the mapping is
// exact by construction: parse(html(runs)) == normalize(runs), and
// plain text parses back to no runs. An explicitly black run folds to
// unset (visually identical). Length-changing case transforms are out
// of scope (same caveat as karaoke timing).
class TextRuns : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    static TextRuns *create(QQmlEngine *engine, QJSEngine *scriptEngine);
    explicit TextRuns(QObject *parent = nullptr);

    // Canonical HTML for content+runs (spans adjacent, never nested).
    Q_INVOKABLE QString htmlFromRuns(const QString &content, const QVariantList &runs) const;
    // Parse canonical (or pasted) rich HTML: {text, runs}. Colors equal
    // to defaultColor fold to unset; weights >= 600 read as bold.
    Q_INVOKABLE QVariantMap runsFromHtml(const QString &html, const QString &defaultColor) const;
    // Toggle one boolean flag over [selStart, selEnd): splits, flips the
    // covered runs (mixed coverage clears), merges, normalizes. Empty or
    // inverted selections return the input untouched.
    Q_INVOKABLE QVariantList toggleRunFlag(const QString &content, const QVariantList &runs, int selStart,
        int selEnd, const QString &flag) const;
    // Set (or clear with "") the run color over a range. Same
    // split/merge/normalize rules as the flag toggle.
    Q_INVOKABLE QVariantList setRunColor(const QString &content, const QVariantList &runs, int selStart,
        int selEnd, const QString &color) const;
    // Normalize only: sort, clamp, drop empties and no-op runs, merge
    // adjacent runs with identical style.
    Q_INVOKABLE QVariantList normalizeRuns(const QString &content, const QVariantList &runs) const;
    // Display font for QML text items (family, Qt 1..1000 weight, pixel
    // size, style flags, caps mode, absolute letter spacing). Variable
    // families interpolate the wght axis; static families behave
    // exactly like manual font.xxx bindings.
    Q_INVOKABLE QFont textFont(const QString &family, int weight, double pixelSize, bool italic, bool underline,
        bool strike, const QString &caps, double letterSpacing) const;
};
