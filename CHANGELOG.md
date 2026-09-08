# Changelog

All notable changes to `totm` are documented here. Format follows Keep a Changelog,
versioning follows SemVer once 1.0 ships. i try to keep this updated.

## [Unreleased]

### Added

* Animation editing, the big one — preset gallery with live thumbnails, per-shape clips, clip editor (timing, easing, slide/spin options), bezier graph editor popup, and a timeline with lanes + ruler + playback transport. Scenes now carry an `anim` blob (library schema v2) that the future video renderer will read.
* Undo/redo — full per-tab history, drag gestures coalesce into single entries, toolbar buttons + shortcuts. Text fields keep their own native undo so typing never eats your history.
* Persistent theme — new `SettingsStore` backend (`QSettings`, separate from `library.json`). First run follows your OS, the first toggle pins your choice forever.
* Window state manager — remembers size, position and maximized across restarts, clamps to your actual screens so a disconnected monitor never eats the window, resize handles hide while maximized, and mac gets proper traffic lights (red/yellow/green on the left) instead of windows-style controls.
* Design library — workspaces + designs backed by `library.json`, starring, move between workspaces, live card previews, inline rename. Corrupt files get archived aside with a timestamp (not deleted!) and a fresh default workspace is installed so you never boot into nothing. A lockfile stops two totms from stomping each other.
* Properties panel revamp — position / layout / appearance / fill / stroke sections, mixed-value handling when the selection disagrees, scrub-to-adjust number fields, add/remove fills and strokes.
* Canvas goodies — live measure readout while drawing, equal-gap spacing snaps, per-tab camera memory.
* Star shape (replaces diamond/polygon, rip).

### Changed

* Bottom panel now hosts the timeline (taller than before, 300px).
* Right panel got an animate mode with a preset/custom switcher.
* `Document.qml` and `EditorCanvas.qml` god files got split into focused helpers under `models/document/`, `canvas/`, `snap/`, `layers/`, `properties/` — cuz they were getting scary.

### Fixed

* Layer eye/lock toggles show on row hover like a normal app.
* Corrupt library no longer nukes your stuff, it gets archived and you get a fresh default workspace.
* Second instance can't silently corrupt the library anymore (lockfile + warning banner).

### Removed

* Dead `_isEffectively` helper and flat-list compat shims (`moveRow`, `rowOf`, `snapshotAt`).
* Diamond and polygon shapes (star took their place).

## [0.1.0] - 2026-09-06

* Initial prototype: infinite canvas, shapes, layers/groups, snapping, design panel, tabs, theme.
