# Contributing to totm

Thanks for picking up `totm` (that one tool for motion, part of `tot`).
This doc reflects how the app is actually built today (v0.1.2): an
offline Qt 6.8+ desktop editor where QML owns UI + app logic and a small
C++ backend owns storage, rendering help, and sandboxing.

By contributing you agree to follow the
[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). All contributions are
Apache-2.0 (see [`LICENSE`](LICENSE)).

## What you are working with

Cross-platform motion-graphics editor: vector shapes (rectangle, ellipse,
triangle, star, pen paths, text, images) with gradients / shadows / glows
/ blur / grain, layers + groups + drill-in, smart snapping, Figma-style
design panel, presets + custom from-to animation + motion paths + easing
graphs + timeline with audio lanes, SD/HD/4K MP4/WebM/GIF export through
system `ffmpeg`, home library (workspaces, starring, templates, live previews,
`.totm` share bundles), QML-only plugin system, editable shortcuts,
dark/light theme with appearance settings, and an in-app file picker.

Key contracts to know before you touch code:

- **Canvas/export parity is structural.** One CPU painter
  (`backend/effects/EffectPainter`) serves canvas preview and video
  export; one sampler (`backend/video/AnimSampler` + QML
  `DocAnimSample.presetOverlay`) drives preview and export frames. If you
  change how something renders or animates, change it in the shared path
  so both match by construction.
- **No QML-side file IO, ever.** All disk access lives in C++
  (`LibraryStore`, `SettingsStore`, `FileBrowser`, `VideoExporter`,
  `PluginStore`). QML binds to snapshots and calls `Q_INVOKABLE`
  mutators. New C++ stores need discussion first.
- **Atomic + forgiving persistence.** Writes use `QSaveFile`; corrupt
  `library.json` / design files are archived with a timestamp and reset,
  never deleted. `.totm` imports remap blobs under fresh uuid names with
  a 100 MB per-blob cap and an allow-list (`png jpg jpeg webp gif svg`,
  `mp3 wav ogg flac`).
- **Plugins are sandboxed QML.** Folder drop-in
  (`<AppData>/totm/plugins/<id>/manifest.json` + QML), permission-gated,
  static import/identifier scan plus an engine-wide `http/https/ftp`
  block (`PluginNetworkGuard.h`). See `src/docs/PLUG_IN.html` before
  touching `backend/plugins/` or `components/plugins/`.

## Project layout

```text
src/
  main.cpp               # boot, QLocalServer single-instance for .totm opens,
                         # engine-wide network block, qrc:/ Totm import
  backend/
    library/             # LibraryStore: library.json + designs/<id>.json,
                         # images/audio blobs, .totm export/import, QLockFile
    settings/            # SettingsStore: theme, window geometry, shortcuts,
                         # appearance (colors/radius/fonts) via QSettings
    effects/             # EffectSpec/EffectItem/EffectPainter (shared rasterizer)
    video/               # VideoExporter (ffmpeg pipe, worker thread, temps)
                         # + AnimSampler (1:1 with QML preview)
    plugins/             # PluginStore (manifests, grants in plugins.json,
                         # mediated picks, 1MB KV) + PluginNetworkGuard
    files/               # FileBrowser: read-only listing for the in-app picker
  qml/
    Main.qml             # frameless window + TitleBar + view switch
    theme/               # AppTheme singleton (only hex colors live here)
    stores/              # TabState, ToolState, ShortcutState singletons
    models/              # Document.qml facade + DocNode
    models/document/     # focused helpers: DocTree/Effective/LayersModel/
                         # Drill/Clipboard/Factory/Selection/Rename/Group/
                         # Reorder/Bounds/Edits/Pen/Corners/History/
                         # AnimSample/AnimPresets/CustomDefaults/Transport/
                         # Easing/PathSample/Anim/Audio
    views/
      home/              # HomeView (library, templates, import/export entry)
      editor/            # EditorView (canvas + panels + timeline wiring)
      settings/          # SettingsView + TabBar/Tab + Plugin/Shortcut/Appearance
    components/
      titlebar/ window/  # frameless chrome, tabs, mac traffic lights, resize
      toolbar/           # floating canvas toolbar
      fields/            # NumberField, HexField, RenameField
      menu/              # shared context-menu rows
      home/              # workspaces, design cards + live previews, templates
      selection/         # marquee selection
      dialogs/           # ConfirmPopup, FilePicker (in-app browser)
      icons/             # AppIcon global glyph set + PickerIcons (Phosphor)
      editor/canvas/     # Camera, tools (draw/pen/path/image/text), overlays,
                         # ShapeLayer, snapping glue, measure, breadcrumb
      editor/snap/       # SnapEngine/Targets/Edge/Spacing/Combinators
      editor/layers/     # LayersView/Row/ContextMenu + reorder/rename/toggles
      editor/shapes/     # ShapeItem/Geometry/GrainOverlay/TextGlyphs (+ .qsb)
      editor/properties/ # DesignPanel + sections (Position/Layout/Appearance/
                         # Fill/Stroke/Pen/Image/Audio/Effects/Typography) +
                         # galleries (Preset/Custom) + ClipEditor + graph
      editor/timeline/   # TimelineView/Lane/AudioLane/Ruler/Transport
      editor/export/     # ExportButton/QualityPopup/ProgressPopup
      plugins/           # PermissionPopup/Rows, ManagerRow, FilePicker, Slot
      settings/          # Shortcut + Appearance rows/sections
  docs/                  # PLUG_IN.html (maker guide), CREDITS.html,
                         # CONTRIBUTORS.html (install to share/doc/totm)
packaging/
  icons/, totm.desktop, mime/totm.xml, macos/Info.plist.in,
  arch/PKGBUILD (.SRCINFO kept in sync), nsis-deploy.cmake.in
.github/
  ISSUE_TEMPLATE/ (bug.yml, feature.yml), PULL_REQUEST_TEMPLATE.md
  workflows/ (ci.yml: qmlformat+lint, 3-OS build, desktop/MIME/plist checks)
CMakePresets.json        # dev (Debug) + ci (Release), Ninja
.qmlformat.ini (.qmllint.ini)  # 4-space indent; lint: unqualified/unresolved/missing
CHANGELOG.md             # Keep a Changelog, SemVer once 1.0 ships
```

## Ground rules

- **QML for UI + app logic.** Heavy math lives in small `QtObject`
  helpers under `models/document/`, `canvas/`, `snap/`, `layers/`,
  `properties/` — no `.js` libraries.
- **One responsibility per file.** `Document.qml` / `EditorCanvas.qml`
  are thin facades that delegate. If a file is getting scary, add a
  helper instead of growing the god file.
- **Qt6 QML conventions:** ordered attributes with blank-line groups,
  `required` props for external data, explicit `id` access, no outer-id
  leaks into delegates (policy callbacks wired in `onItemAdded`).
- **Preset pipeline for clips.** New animation types reuse the whole
  pipeline: `presetIds` + `defaultsFor` + `normalizeOptions` in
  `DocAnimPresets`, frame math in `AnimSample.presetOverlay` (+ writeback
  in `applySample`, capture in `DocAnim.captureBase`), gallery cards
  grouped like Custom (Transform / Style / Other / Path), and from-to
  editors under `properties/`. Overlapping customs resolve
  later-wins-per-property; preview and export must sample identically.
- **Comments explain why, not what.** Contracts (units, invariants,
  ownership, failure model) stay; what-the-code-says and lint war
  stories go.
- **Colors live in `AppTheme`.** No hex outside it (except
  `selection` / `snapGuide` accents). Mixed-value handling, undo
  coalescing on scrubs, and native-undo-preserving text fields are the
  expected patterns — copy the neighboring section.
- **Persistence goes through the backend.** `LibraryStore` for designs /
  blobs / `.totm`, `SettingsStore` for theme / geometry / shortcuts /
  appearance, `FileBrowser` for listing, `VideoExporter` for renders,
  `PluginStore` for plugin state. Writers share suffix rules with their
  `*Exists` probes, and destructive paths confirm via `ConfirmPopup` /
  `FilePicker` save mode.
- **Docs that ship:** maker guide + credits + contributors under
  `src/docs/` install to `share/doc/totm` — update them alongside the
  feature, not after.

## Workflow

1. **Fork, branch from `main`:** `feat/<short>`, `fix/<short>`.
2. **Build first** (needs CMake 3.21+, Qt 6.8+ with `Quick Svg
   Multimedia ShaderTools Network`, C++17, Ninja, and `ffmpeg` on `PATH`
   for export — see `README.md` per-OS steps):
   ```sh
   cmake --preset dev
   cmake --build --preset dev
   ./build/dev/src/totm
   ```
3. **Format + lint changed QML** (CI enforces this on every file):
   ```sh
   /usr/lib/qt6/bin/qmlformat -i $(git diff --name-only | grep '\.qml$')
   /usr/lib/qt6/bin/qmllint src/qml/**/*.qml
   ```
   The check CI runs is `qmlformat <file> | diff -u <file> -` plus
   `qmllint`, plus `desktop-file-validate` / `xmllint` for the `.totm`
   association files and a `plutil` + UTI grep on macOS.
4. **CI build** before pushing:
   ```sh
   cmake --preset ci && cmake --build --preset ci
   ```
   If you touched `packaging/arch/PKGBUILD`, regenerate and sync
   `.SRCINFO` (CI diffs `makepkg --printsrcinfo` against it).
5. **Smoke-test the app**, not just your panel. Minimum pass: new tab →
   draw each shape + pen + text + image → move/resize/snap (Alt
   suspends) → align/distribute → group/drill → layers reorder/rename/
   eye/lock + context menu → design panel edits → animate (preset +
   custom + path + audio lane + transport) → templates → `.totm`
   export/import → file picker + overwrite guard → shortcuts + theme /
   appearance → plugins enable/review → video export (MP4/WebM/GIF) + cancel. CI's build
   matrix is Ubuntu 24.04 / Windows 2022 / macOS 15 — call out anything
   platform-specific.
6. **Update the CHANGELOG** under Unreleased/`Added`/`Fixed` (Keep a
   Changelog style) and the relevant `src/docs/*.html` if you changed
   plugin contracts, credits, or contributors.
7. **Commit with clear scope** (`feat(canvas): …`, `fix(timeline): …`,
   `feat(home): …`, `fix(export): …`). Keep the public `Document` API
   compatible; removing a shim needs a note in the PR.
8. **Open a PR against `main`** using the template: what changed + why,
   how tested (`qmlformat` / `qmllint` / `ci` build / manual smoke
   checklist), screenshots for visual changes.

## Issues

- **Bug reports** (`bug.yml`): version/commit + Qt + OS, repro steps
  (1. New tab, 2. Draw rectangle, 3. …), expected vs actual. A minimal
  `.totm` or repro plugin folder beats a long description.
- **Feature requests** (`feature.yml`): the problem (what you cannot do
  today), the proposal (what should happen, where in the UI),
  alternatives considered. Small, composable proposals review fastest.

## What not to do

- Don't add hex colors outside `AppTheme`.
- Don't do file IO from QML — route through the backend stores.
- Don't grow `Document.qml` / `EditorCanvas.qml` back into god files.
- Don't add `.js` libs, remote imports, or network calls — the engine
  blocks `http/https/ftp` and the plugin scan rejects XHR/`fetch`,
  `WorkerScript`, `LocalStorage`, `Dialogs`, `StandardPaths`,
  `Multimedia`, and direct store access.
- Don't bypass permission gating, `pluginFileUrl` confinement,
  overwrite guards, or atomic-write (`QSaveFile`) patterns.
- Don't commit `build/`, `.qt/`, `*.user`, or local `plugins.json` /
  library data.
