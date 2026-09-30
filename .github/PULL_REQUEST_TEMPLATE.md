## What / why

Short description of the change and why it is needed.

Closes #(issue number, if any):

## Changes

- 
- 

## How tested

- [ ] `qmlformat` clean (`qmlformat <file> | diff -u <file> -` on changed QML)
- [ ] `qmllint` clean (`qmllint src/qml/**/*.qml`)
- [ ] `cmake --preset ci && cmake --build --preset ci` passes
- [ ] Manual smoke: new tab, draw, move/resize/snap, group/drill, layers, theme
  - Extended pass if touched: align/distribute, animate (preset + custom + path + audio), templates, `.totm` export/import, file picker + overwrite guard, shortcuts, plugins, video export (MP4/WebM/GIF) + cancel
- [ ] Platform notes (CI covers Ubuntu 24.04 / Windows 2022 / macOS 15 — call out anything platform-specific):

## Checklist

- [ ] `CHANGELOG.md` updated under `Unreleased` (Keep a Changelog style)
- [ ] Canvas / export parity kept (shared painter + sampler, preview matches PNG/SVG/video)
- [ ] No QML-side file IO (routed through `LibraryStore` / `SettingsStore` / `FileBrowser` / `VideoExporter` / `PluginStore`)
- [ ] No hex colors outside `AppTheme` (except `selection` / `snapGuide` accents)
- [ ] No new `.js` libs, remote imports, or network calls
- [ ] Atomic writes (`QSaveFile`) + overwrite guards kept for destructive paths
- [ ] `src/docs/*.html` updated if plugin contracts / credits / contributors changed
- [ ] `packaging/arch/.SRCINFO` re-synced if `PKGBUILD` touched (`makepkg --printsrcinfo`)

Screenshots (visual changes):
