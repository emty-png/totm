# Changelog

All notable changes to `totm` are documented here. Format follows Keep a Changelog,
versioning follows SemVer once 1.0 ships. i try to keep this updated.

## [Unreleased]

### Added

* Component export — the design panel grew a Figma-style Export section: one PNG row per setting at 1x/2x/3x (rows add/remove, duplicate scales swap), rendering every selected top through the shared CPU painter on transparency at base values with playhead-frozen grain. A single file saves directly; several pack into a `{Design}.zip` of layer-named PNGs (`Name@2x.png`, `-1`/`-2` dedupe) through the in-app save picker with overwrite guards. The video rasterizer moved verbatim into a shared `FramePaint` unit first, so canvas, video and stills paint one path.
* SVG vector export — the Export section grew a PNG/SVG switch: SVG writes one resolution-independent `.svg` per selected top (scales don't apply) through a vector-native `SvgPaint` unit that shares the PNG scene handling and reuses the canvas outline builder, so silhouettes match. Solid/linear-gradient fills and strokes, rotation/flip/opacity, text (`<text>` with alignment and escaping) and images (base64 `<image>`, rounded-corner clip, neutral box when the blob is missing) all carry over, and effects render as per-leaf SVG filters in the PNG stack order (outer shadows/glows with spread, inner bands, whole-stack layer blur mixed by opacity, silhouette-confined grain; box radii map to sigma/2, grain is turbulence noise). Background blur has no standalone-SVG equivalent (no backdrop to sample) and is skipped. Multi-component picks pack into a `{Design}.zip` like PNG.
* Timeline zoom keys and joint clip drag — the timeline zooms with `=`/`-` keys on top of the existing ctrl+wheel path (all keeping the cursor/center time stable), and dragging a selected bar/diamond now moves the whole multi-selection as one formation (snapped off the dragged clip, clamped inside the composition, one undo entry). Also fixed `zoomAt` referencing an undefined `vx`, which threw on every ctrl+wheel zoom.
* Canvas guides and zoom-to-fit — the canvas grew persistent guides without ruler chrome: hover the top/left edges for a split cursor, drag out to create a guide, drag to move, release home or double-click to remove. Guides save with the scene and feed the snap targets, so moves, resizes and draws snap to them like edges. A bottom-right zoom pill (out, percent, in, fit) plus `Ctrl+=` / `Ctrl+-` / `Ctrl+0` keys cover the existing wheel path; the fit buttons use a new Phosphor `fit` (corners-out) glyph, and all five zoom chords are remappable in the Shortcut tab. The Appearance tab grew Canvas and Window cards with zoom-pill and window-controls Shown/Hidden switches (persisted, covered by Reset all).
* Starter templates replaced — the four sketch templates (logo sting, hero loop, lower third, onboarding) are out; two full-blown motion pieces are in, each with in/out beats across its whole duration: a 6s clean vertical 9:16 offer (headline, rule, checklist card cascade, breathing CTA) and a 7s 16:9 pricing scene (three cascading tiers with a glow-highlighted plan, price pops, outro fade). Builders still use only the public `Document`/`applyPreset` calls inside one undo entry, so previews match new designs by construction.
* General settings tab — the Settings strip grew a General tab (now the default) with new-design defaults (canvas size with 16:9 / 9:16 / 1:1 / 4:3 presets, scene background, timeline length), video-export defaults (quality, frame rate, encode effort) and a storage card (image/audio counts plus disk use, library path). Untitled designs start from the new-design defaults, the export picker opens from the export defaults and saves the used choice back on Render, and everything persists with a Reset all.

## [0.1.2] - 2026-09-17

### Added

* Design sharing — export any design to a single-file `.totm` bundle (scene plus image/audio blobs) from the card menu and import it back through the header Import button, with blobs remapped under fresh names so imports never collide and errors surfacing in the global bar. `.totm` files open in the app by default on Linux (shared-mime-info type plus desktop entry) with single-instance forwarding so repeat opens land in the running window, plus installer/bundle associations on Windows and macOS.
* Clip copy/paste — selected animation clips copy to an app-wide clipboard as relative-offset templates and paste onto the selected tops at the playhead, across shapes and designs, through the shortcuts and new Copy/Paste rows in the clip editor.
* Canvas align and distribute — align unlocked tops to their union box (left/center/right, top/middle/bottom) and spread even center spacing across 3+ tops, from new Align/Distribute rows in the Position section.
* Template picker — the header Template button opens a modal with a rendered scene preview for every starter (logo sting, hero loop, lower third, onboarding); the inline strip is gone and the previews build from the same one-undo-entry builders as new designs.
* In-app file picker — every open/save now uses a native-feeling browser in the app language (places sidebar, breadcrumb, filtered rows with size · date, save-mode name field) backed by a read-only FileBrowser store, replacing the unthemeable stock dialog; Phosphor outline glyphs throughout.
* Overwrite guards — `.totm` export and video save refuse existing destinations unless confirmed through a shared popup, with probes sharing each writer's suffix rule.

### Fixed

* Timeline top hairline buried under the opaque ruler block; render timeouts on slow machines (pipe/finish caps doubled, kills waited out).

## [0.1.1] - 2026-09-16

### Added

* Starter templates — a `Start from a template` strip above the home grid with four one-click designs (logo sting, hero loop, lower third, onboarding) built only from the public `Document`/`applyPreset` calls inside one undo entry, so the card preview is alive at once.
* Pen styling — new Pen section for pen shapes: close/open every subpath, fill on/off for line-art, plus stroke cap (round/square/flat) and join (round/bevel/miter). The shared CPU painter honors them on canvas and export, other shapes render exactly as before.
* Loopable animation kit — clips loop now (once/loop/ping-pong, sampled identically in preview and export, with lane badges), multi-selections cascade via a stagger offset in both galleries, new `customStrokeColor`/`customFontSize`/`customFlip` presets with seeded from-to editors, new pop/bounce/elastic/wipe/blur-in/pulse cards on back/bounce/elastic easings, instant stepped clips (appear/hide/flip) as single diamonds, duplicate-to-playhead, and one lane row per target with clip counts.

## [0.1.0] - 2026-09-15

### Added

* Initial launch: canvas, shapes, layers/groups, snapping, design panel, tabs, theme.

* Credits page — a `CREDITS.html` sibling to the plug-in guide (hero, numbered sections, theme toggle with saved choice) with the full Phosphor Icons (MIT) and Google Sans (OFL-1.1) license texts, plus a linked `CONTRIBUTORS.html` table (contributor, one-line contribution, version — v0.1.0 so far). A Credits row above Settings in the home sidebar opens it in the default browser via a new `SettingsStore.openCredits()` (both pages install to `share/doc/totm` alongside the guide).
* Text typing kit — the animate tab's text gallery grew Type (letters/words/lines with chars-per-second pacing and an optional `|` cursor), Blur (layer-blur relax to sharp) and Wave (rotation wobble) cards with live thumbnails. Type durations auto-size from the selection at the card speed and the clip editor retimes on cps edits. The `type` preset reuses the whole preset pipeline (timeline lanes, easing, undo, video-safe plain data) with one sampler in QML preview and C++ export so both reveal identical chunks.
* Editable shortcuts — every shortcut remaps from the Shortcut settings tab: click a badge and press keys (Esc cancels, duplicates blocked with a notice naming the owner), per-row undo plus Reset all, search filter, and a centered card layout. Overrides persist in the backend (`SettingsStore`, native `QSettings` group `shortcuts/`, canonical portable text, modifier-only/unknown ids rejected) and apply live to editor + home.

* Plugin system — QML-only plugins via folder drop-in (`<libraryDir>/plugins/<id>/` with `manifest.json` + QML). New `PluginStore` backend validates manifests, persists per-permission grants in `plugins.json`, and gates everything: toolbar tools, design-panel sections, canvas overlays, full-window advanced overlays, scoped KV storage, host-mediated image/audio picks (plugins only see blob names, never paths), and export quality suggestions surfaced in the quality popup. First launch shows a permission popup listing each request with the maker's reason. The home sidebar grew a Settings entry with an unclosable tab strip (starting with a Plugin tab that manages enable/disable, review, and rescan, plus a book button opening the `PLUG_IN.html` maker guide in the default browser). Sandboxed by a static import/identifier scan plus an engine-wide block on remote (http/https/ftp) transport.
* App icon — the "totm" wordmark ships in every size a desktop needs: hicolor PNGs (16–256) + desktop entry on Linux (X11 + Wayland via `cmake --install`), multi-size `.ico` wired into the Windows exe, `.icns` in the macOS bundle, and the window/taskbar icon set at runtime.
* Card previews + rename hardening — home thumbnails reuse the canvas `ShapeItem` through one shared mapping (real uids, paint-depth order, hidden-branch pruning, fixed-box wrapping, frosted-glass backdrop sampling), so they match the canvas for every tool and effect; blank designs show an "Empty canvas" placeholder. Renaming got sturdier too: double-click renames in place (single-click open waits out the double-click interval), Enter commits exactly once, fast re-targets can't clobber the live edit, and grid rebuilds no longer eat typed text.
* Draggable tabs — doc tabs drag to reorder with a live gap preview, selection follows the dragged tab.
* Audio properties — design-panel section for the audio selection (per-clip controls with mixed-value handling and undo-coalesced scrubs) plus timeline lane scrolling.
* Image tool — picker-then-place (click stamps natural size, drag stretches), PNG/JPG/WEBP/GIF/SVG blobs under `LibraryStore`, replaceable from the Image section, radius + stroke + glow aware, with a neutral placeholder when the blob goes missing.
* Effects engine — linear-gradient fill/stroke, stackable outer/inner shadows and glows in a fixed Figma-style render order, layer blur, frosted-glass background blur, and animated film grain. One CPU painter serves canvas preview and video export so they match by construction; text paints the full stack (shadows, glows, gradient fill, outline ring, layer blur, glyph-confined grain) through a shared glyph path.
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

* Home cards: click selects just that card, double-click opens the design (single click no longer navigates away, so selection — and the shortcuts driven by it — stays put). Rename stays on F2 and the card menu.

* App icon restyle — the mark now sits on a padded squircle (12.5% inset, ~23.5% corner radius) instead of a full-bleed square, so it no longer reads oversized on taskbars/docks. All sizes regenerated from a new `packaging/icons/totm.svg` source: hicolor PNGs (16–256), multi-size `.ico`, `.icns`, plus the runtime `:/icons/totm.png`.
* Library storage — scenes moved out of `library.json` into one file per design (`designs/<id>.json`), so an autosave writes a single scene instead of rewriting the whole library. Unreferenced image blobs are swept at startup, and the store reports blob count + bytes for a future storage UI. A corrupt design file is archived aside with a timestamp and starts fresh instead of blocking the library.
* Bottom panel now hosts the timeline (taller than before, 300px).
* Right panel got an animate mode with a preset/custom switcher.
* `Document.qml` and `EditorCanvas.qml` god files got split into focused helpers under `models/document/`, `canvas/`, `snap/`, `layers/`, `properties/` — cuz they were getting scary.

### Fixed

* Home "Open selected" never fired from the main keyboard: the sequence was keypad `Enter`, not `Return`. Default is `Return` now (keypad `Enter` kept as alias), and the shortcut recorder distinguishes the two keys.
* Home shortcuts now follow their settings tab values: undo/copy/paste/redo bind the editable sequences (redo keeps a native fallback for macOS Cmd+Shift+Z, deletes keep the Backspace alias), nudge 10px variants are separately remappable, and all shortcuts suspend while capturing a new sequence.

* Double-clicking a design card opened it before renaming — single-click open now waits out the double-click interval, and layer renames no longer write no-op undo entries on blank or identical commits.
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
