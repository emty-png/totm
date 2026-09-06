# Changelog

All notable changes to `totm` are documented here. Format follows Keep a Changelog,
versioning follows SemVer once 1.0 ships.

## [Unreleased]

### Added

* Production skeleton: README, CONTRIBUTING, Code of Conduct, Security policy, CI, presets.
* Split `Document.qml` god file into `models/document/*` focused helpers (QML-only).
* Split `EditorCanvas.qml` into `canvas/*`, `SnapEngine` into `snap/*`, layers and design panel into sections.

### Removed

* Dead `_isEffectively` helper and flat-list compat shims (`moveRow`, `rowOf`, `snapshotAt`).

## [0.1.0] - 2026-09-06

* Initial prototype: infinite canvas, shapes, layers/groups, snapping, design panel, tabs, theme.
