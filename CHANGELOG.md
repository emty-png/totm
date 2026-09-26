# Changelog

All notable changes to `totm` are documented here. Format follows Keep a Changelog,
versioning follows SemVer once 1.0 ships. i try to keep this updated.

## [0.3.2] - 2026-09-26

### Added

* Theme-aware Bibata mouse cursors — every cursor (arrow, hand, resize grips, text beam, grabs, drag badges) renders from the Bibata set through `QCursor` pixmaps: Modern Ice for the light theme, Modern Classic for dark, repainting live on theme toggle. Wait/busy keep the system spinners (Bibata ships those animated); credited under GPL-3.0 in the Credits page.
* Doc-page favicons — the maker guide, credits, contributors and changelog pages carry the totm mark as an inline SVG favicon, so tabs stay recognizable with no extra files.
* Side-rail active blend plus tab-drag autoscroll — the active tab row blends into content like the top bar, and holding a dragged tab near the rail edge scrolls the list.

### Fixed

* Backward seeks and loop wraps freezing shapes — seeking before a clip's start (or wrapping) left stale authored values on the live nodes; the frame restores the pre-play base first now, matching export.
* Tab strip scrolled out of view — the strip used layouts inside a Flickable whose viewport shifts with scroll buttons; plain Row/Column pins every tab, and scrolls are instant instead of fighting the animation.
* Design context menu bloat — same compact treatment as layers: dead rows hide, and single-workspace menus show just Rename, Star, Export and Delete.
* Design header with nothing selected — the panel header only shows for a live selection; the empty state keeps its centered text.

## [0.3.1] - 2026-09-26

### Added

* Mask layers — any shape doubles as a mask over siblings above it via Use as Mask (`Ctrl+Alt+M`, layers context menu), Figma-style: stacked masks split the group into bands, nested groups intersect, masks never paint. Masked leaves share one CPU painter between canvas and export so they match; Mask Wipe (directional) and Mask Iris presets animate the mask box with feather and invert, and SVG component export emits clipPath for hard edges and alpha masks for feather/invert. Scenes bump to v3, old files load untouched.
* Keyframes on every custom clip — move, scale, rotate, opacity, resize, corner, font size, color, gradient, stroke, shadow, glow, blur and grain clips take clip-local keys with per-key easing (one key stores, two or more drive interpolation with the clip easing bypassed, shorter lists read as plain from-to so old clips never change behavior). The clip editor grows a generic Keyframes section that captures the live look at the playhead, and the C++ sampler mirrors the interpolation so export matches preview.
* Panel copy/paste for properties and clips — design and animation panel headers grow a three-dot menu with copy and paste in values, properties and both flavors on an app-wide clipboard, so styles and clips travel across shapes and designs. Design values land on same-index entries, properties rebuild structure, animation pastes match same-preset clips (missing ones are created at the playhead); every paste checkpoints once.
* Mask-aware home previews — design cards render masks through the same band rules as the editor instead of raw rectangles.
* Timeline keyframe ticks — lanes show a tick per stored key; clicking selects the clip and seeks to the key, dragging retimes it between neighbors with snapping in one undo entry. The Arrange submenu hides moves that can't reorder, like the main menu.
* Tab rail positions plus window-chrome toggles — tabs dock Top, Bottom, Left or Right from a new Settings → Appearance → Tabs card (side rails collapse to icons, scroll on overflow, keep vertical drag-reorder). The Window card gains top-bar, theme-button and top-bar-dragging switches; a hidden top bar falls back Top tabs to the bottom rail. Everything persists with Reset all coverage while theme packs leave it alone.

### Fixed

* Layers context menu bloat — every row hides when its action can't apply instead of sitting disabled, so single selections show ~9 rows and empty areas show just Paste; the popup height follows the visible rows and it stays shut when nothing applies.
* Preview hide frames leaking into snapshots — exporting or saving past a hide clip baked `visible=false` into the scene, and the sampler gates non-hide clips on static visibility, so the component rendered frozen with no further animations. Eye, flip and corner radius now rebase from the pre-play base like the other animated props (old saves keep their baked eye state: toggle the layer eye once to heal them).

## [0.3.0] - 2026-09-23

### Added

* Animation entry targeting — color, gradient, stroke, shadow and glow clips target any stack entry (index 0 = top) through an Entry dropdown that reseeds only the From side; cards and the clip editor show the entry (`Color · Fill 2`).
* Stroke-gradient width, dash and position — gradient strokes animate the same width, dash pair and stepped position as solid strokes.
* Clip deleting — a delete button in the clip editor, per-card delete in the animation lists, and one Delete/Backspace shortcut for shapes, clips and audio.
* Pretty build wrapper — `tools/build.sh` renders the presets as a single-line gradient bar with warning counts; full output stays in the log and failures print the real error tail.

### Fixed

* Top-entry shadow and glow clips clobbering multi-entry stacks — folds preserve the rest of the stack now, like fills and strokes.
* Glow typed-hex dropping stored alpha — strips and reattaches like shadow and its own picker.
* Timeline Delete never firing for clips: two shortcuts shared the sequence (Backspace never reached the timeline) — merged into one handler.

### Changed

* Behavior-preserving refactors (parity-harnessed): table-driven `DocAnimPresets` and clip seeds, shared clip editor rows (entry, dash, position, alpha wells), merged shadow/glow helpers in the effects panel.

## [0.2.3] - 2026-09-23

### Added

* SVG linear-gradient import — `url(#id)` fills and strokes land as editable `linear` stack entries (bbox and userSpace vectors, gradientTransform, href chains, multi-stop sampling with stop-opacity) instead of black; radial degrades to its first stop as solid.
* Drag-and-drop plus clipboard paste for images and SVG — files dropped anywhere over the editor stamp at the drop point (cascaded, one undo entry), Ctrl+V takes copied files then raw pixels at the viewport center; app clipboards keep precedence, inbound only.

## [0.2.2] - 2026-09-22

### Added

* Layers search and scrolling — the layers panel grew a search field matching by name or shape type with groups auto-expanded around hits (plus a no-matches empty state), and the row list scrolls so long designs no longer overflow the sidebar. Filtering suspends drag-reorder whose gap math assumes the full list; empty-area deselect and the empty context menu moved into the scroller with the presses it now eats.
* Official seal in the permission header — the permission popup drops the `Official plugin — shipped with totm.` text row and puts the verified-badge seal top-right of the Allow title instead (old copy kept as a hover tooltip).
* Dashed and dotted strokes — the stroke section grew a Solid/Dashed/Dotted preset row plus dash/gap lengths in stroke-width units, painted through the shared CPU painter so canvas, video, PNG and SVG export match (old scenes read as solid; native text outlines stay solid).
* SVG import as editable vectors — picking an `.svg` in the image tool vectorizes paths, rects, circles, ellipses, lines, polylines, polygons, `use`/symbol references and text glyph outlines into pen shapes in one undo entry (grouped under the file name), reusing the picker-then-place stamp flow. Unconvertible files fall back to image-blob placement. A new `SvgImport` backend unit mirrors the export-side `SvgPaint` parser; gradients, filters, clips and masks stay out of scope.
* Stacked fills and strokes — shapes now carry Figma-style `fills[]`/`strokes[]` stacks (index 0 paints topmost) with per-entry color, linear gradient, opacity, width, dash pair and center/inside/outside position, edited through per-entry cards with eye toggles and a dots menu for type, angle, position, dash style, order and delete. Canvas, video, PNG/SVG export and home previews all paint the stacks; old scenes fold their single keys into one-entry stacks untouched.
* Animation for the new paints — style clips target the top stack entry: color/gradient clips carry entry opacity, the Stroke clip carries opacity plus a lerped dash pair and stepped position, and a new Stroke gradient clip mirrors the fill gradient. Extended keys are opt-in so old clips never stomp custom values. The gallery routes Color rows to gradient clips for linear paints (seeded from the live stops) and solid clips auto-swap on open; clip editors grew opacity/dash/position fields plus the shared color picker on every well.
* Collapsible Export section — the header toggle owns expand/collapse with the body compact until opened, and the PNG scale-row + moved inside.

### Fixed

* Gradient strokes lost the width field: only the solid row carried it, so `linear` strokes could change nothing but the angle — the gradient row carries the same width control now.
* Numeric fields ate the minus key: a leading `-` typed next to existing text parsed as invalid, so negatives were unreachable without pre-selecting, and Enter died on out-of-range text — `-` now toggles the leading sign from any cursor spot (validator removed, commit still clamps to range).

## [0.2.1] - 2026-09-21

### Added

* Official plug-ins + theme pack — a new bundled plug-in class carrying a verified-badge `Official` seal (checksum-verified: edited copies keep working but lose the seal, and still go through the normal permission approval). The first official pack ships eighteen popular theme presets with light + dark variants (Tokyo Night, Catppuccin, Dracula, Nord, GitHub, Gruvbox, One Dark, Solarized, Rosé Pine, Everforest, Monokai, Night Owl, Kanagawa, Ayu, SynthWave '84, Palenight, Cobalt2, Horizon, plus the built-in Default for reset) as a gallery in Settings → Appearance via a new `appearanceSections` slot. One click fills the Light/Dark colors through a new mediated `appearance.write` permission (`PluginStore.applyAppearanceTheme`), so themes stay tweakable in the Colors card after.
* Timeline audio waveforms — every audio lane bar paints filled mini-bars over its clip file window, so beats and silence stay visible while trimming and arranging. Buckets follow the bar pixel width (~2px per bar), so timeline zoom re-slices the wave instead of stretching it; selection tints the bars red, muted clips dim. Peaks decode once per blob through system ffmpeg (mono 8kHz) and persist as a `<blob>.peaks` sidecar owned by the startup orphan sweep (never packed into `.totm` bundles, recomputed lazily on import); missing ffmpeg or undecodable files keep the plain bar. The audio clip count skips sidecars while disk use keeps counting them.
* WebM and GIF video export — the export picker grew an MP4/WebM/GIF row: WebM renders through libvpx-vp9 + Opus (audio mixed like MP4) with the encode effort mapped to VP9 cpu-used + CRF, GIF renders silent and looping through a single-pass palettegen/paletteuse filter (two passes would need the whole file up front, which a live pipe never has). Unknown formats coerce to MP4, temp files carry the matching suffix, and the choice persists as a new `defaultFormat` alongside the other export defaults in the General tab (covered by Reset all). The save picker filters on the finished format with a matching overwrite title.

### Fixed

* GIF renders failed every time (`Invalid argument`): a bare `gif` token in the ffmpeg args parsed as a second output URL instead of a format flag — now explicit `-f gif`.
* Video save probe ignored the finished format: `destinationExists` used the old MP4-only suffix rule while `saveAs` had moved on, so WebM/GIF saves could disagree with the overwrite guard — both share one rule now.
* Background-blur and image-glow blurs scaled with canvas zoom: the scaled ancestor already maps local px to screen px, so the extra factor grew screen blur as zoom-squared and pinned blur at max deep in — all blur sites use plain radius/64 like export now.

## [0.2.0] - 2026-09-19

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
