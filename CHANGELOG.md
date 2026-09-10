# Changelog

All notable changes to `totm` are documented here. Format follows Keep a Changelog,
versioning follows SemVer once 1.0 ships. i try to keep this updated.

## [Unreleased]

### Added

* Custom animations — the animate tab's Custom mode is real now: grouped Add list (Transform: Scale/Rotate/Move, Style: Opacity/Color, Other: Hide-Show/Resize/Corner Radius/Stroke) creating from-to clips that reuse the whole preset pipeline (timeline lanes, clip editor with per-type from-to fields, easing graph, undo, video-safe plain data). New clips seed From from your live selection so they start jump-free, and overlapping customs resolve later-wins-per-property like Figma.
* Motion path animation — draw a trajectory on the canvas (pen-like: click points, drag to bend, snapping, Alt frees), the shape follows it by arc length with optional follow-rotation and closed loops. Selected paths preview right on the canvas, and Edit path loads the trajectory for full point surgery (drag anchors/handles, double-click to smooth/sharpen, click an edge to insert, Delete to remove, wipe clean to start over). Enter commits once, Esc bails with nothing lost.
* Pen tool — vector path drawing (click to add points, drag for symmetric bezier handles, close by clicking first point, double-click/Enter to part, Esc to finish) plus point editing (double-click a pen shape, drag anchors/handles with snapping, click a segment to insert, Delete to remove, double-click anchor to toggle smooth/corner).
* Text shapes — click for auto-size / drag for fixed box, double-click inline WYSIWYG edit on the canvas in one undo entry, typography section (family, size, weight, letter spacing, h/v align). Icons centralized as `icons/AppIcon.qml`.
* Figma-style color picker — SV pad + hue slider + hex input with live preview, wired into fill/stroke with undo-coalesced scrubs.
* Text animation presets + `appear` preset — Basic/Slide/Scale galleries for text with live thumbnails, fontSize-aware slide/movescale so text reflows, no auto-resize during playback.
* Animation editing, the big one — preset gallery with live thumbnails, per-shape clips, clip editor (timing, easing, slide/spin options), bezier graph editor popup, and a timeline with lanes + ruler + playback transport. Scenes now carry an `anim` blob (library schema v2) that the video exporter reads.
* Undo/redo — full per-tab history, drag gestures coalesce into single entries, toolbar buttons + shortcuts. Text fields keep their own native undo so typing never eats your history.
* Persistent theme — new `SettingsStore` backend (`QSettings`, separate from `library.json`). First run follows your OS, the first toggle pins your choice forever.
* Window state manager — remembers size, position and maximized across restarts, clamps to your actual screens so a disconnected monitor never eats the window, resize handles hide while maximized, and mac gets proper traffic lights (red/yellow/green on the left) instead of windows-style controls.
* Design library — workspaces + designs backed by `library.json`, starring, move between workspaces, live card previews, inline rename. Corrupt files get archived aside with a timestamp (not deleted!) and a fresh default workspace is installed so you never boot into nothing. A lockfile stops two totms from stomping each other.
* Properties panel revamp — position / layout / appearance / fill / stroke sections, mixed-value handling when the selection disagrees, scrub-to-adjust number fields, add/remove fills and strokes.
* Canvas goodies — live measure readout while drawing, equal-gap spacing snaps, per-tab camera memory.
* Star shape (replaces diamond/polygon, rip).
* Video export — render any design to mp4 from the canvas export button (top-right): SD/HD/4K at 30/60fps picker, backend `VideoExporter` rasterizes a fresh scene snapshot with a 1:1 port of the animation sampler and pipes frames to system ffmpeg, live progress modal with Cancel, then a Save dialog copies the temp file out. Encoder threads are capped and the worker runs low-priority so the UI stays responsive mid-render.
* Timeline audio — import MP3/WAV/OGG/FLAC onto dedicated lane rows (one row per clip, free overlap), click to select, drag to move with snapping, Delete removes. Live preview through QtMultimedia players conducted by the transport clock, and exports mix every audible clip (delay + mix, AAC). Clips longer than the composition trim at its end.

### Changed

* Library storage — scenes moved out of `library.json` into one file per design (`designs/<id>.json`), so an autosave writes a single scene instead of rewriting the whole library. Unreferenced image blobs are swept at startup, and the store reports blob count + bytes for a future storage UI. A corrupt design file is archived aside with a timestamp and starts fresh instead of blocking the library.
* Bottom panel now hosts the timeline (taller than before, 300px).
* Right panel got an animate mode with a preset/custom switcher.
* `Document.qml` and `EditorCanvas.qml` god files got split into focused helpers under `models/document/`, `canvas/`, `snap/`, `layers/`, `properties/` — cuz they were getting scary.

### Fixed

* Typography panel warnings (`Unable to assign [undefined]`) when selecting groups — group snapshots carry geometry only, so `commonOf` now reports missing roles as mixed instead of leaking undefined into number fields.
* Layer eye/lock toggles show on row hover like a normal app.
* Corrupt library no longer nukes your stuff, it gets archived and you get a fresh default workspace.
* Second instance can't silently corrupt the library anymore (lockfile + warning banner).
* Custom Color clips threw `TypeError` (a param shadowed the `toHex` helper) which aborted whole-frame sampling — color animations never previewed and one color clip froze all preview motion; renamed, preview animates again.
* Failed video saves no longer vanish silently — the progress popup reopens showing the backend error.

### Removed

* Sampler conformance rig (`tests/samplerconf/`) — dropped, export now relies on the shared `AnimSampler` matching the canvas preview.
* Dead `_isEffectively` helper and flat-list compat shims (`moveRow`, `rowOf`, `snapshotAt`).
* Diamond and polygon shapes (star took their place).

## [0.1.0] - 2026-09-06

* Initial prototype: canvas, shapes, layers/groups, snapping, design panel, tabs, theme.
