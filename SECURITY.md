# Security Policy

`totm` ("that one tool for motion", part of `tot`) is an offline-first,
cross-platform desktop motion-graphics editor (Qt 6.8+ / QML + C++).
There are no accounts, no servers, no telemetry, and no remote loading:
scenes, image/audio blobs, icons, fonts, and plugins are all local files.
This policy describes what is in scope, how the app protects you, and how
to report a vulnerability.

## Supported versions

`totm` is pre-1.0. Security fixes land on `main` and the latest tagged
release only.

| Version           | Supported          |
| ----------------- | ------------------ |
| `main` / latest tag | :white_check_mark: |
| older tags        | :x:                |

If you are on an older tag, update to the latest release first and check
whether the issue still reproduces.

## Threat model (what the app actually does)

Understanding the attack surface helps you write a useful report and helps
users stay safe.

### Offline by design, no network transport

- The app loads nothing remote. All scenes, blobs, icons, and QML come
  from local files or embedded resources (`qrc:/`).
- The QML engine denies remote transport engine-wide
  (`backend/plugins/PluginNetworkGuard.h`: `http` / `https` / `ftp` fail
  closed with `ProtocolUnknownError`). QtMultimedia uses its own backend
  and is unaffected.
- The `Network` Qt module is linked only because QML needs it for the
  engine; the app itself performs no network requests.

### Design library and `.totm` bundles (untrusted input)

- Storage lives under the platform app-data dir (`totm/`): `library.json`
  (workspace/design metadata only) plus one file per design in
  `designs/<id>.json` (`{ version, scene }`, schema v2). Image blobs live
  in `images/` as `<uuid>.<suffix>`, audio in `audio/`, plugin grants in
  `plugins.json`.
- All file IO lives in the C++ backend (`LibraryStore`, `SettingsStore`,
  `FileBrowser`, `VideoExporter`). QML never touches the disk directly.
- All writes are atomic (`QSaveFile`). A corrupt `library.json` or design
  file is archived aside with a timestamp (`library.corrupt.<ts>.json`,
  `<id>.corrupt.<ts>.json`) and replaced with a fresh default — never
  silently deleted, never blocking startup.
- A `.totm` share file is indented JSON
  (`{ app: "totm", kind: "totm-design", version, name, scene,
  blobs: { images, audio } }`) with base64 blobs. On import
  (`LibraryStore::importDesign`):
  - `app` / `kind` / `scene` are validated; anything else is rejected
    with "That file is not a totm design."
  - Referenced blobs are remapped under fresh uuid names so imports can
    never collide with or overwrite existing library files.
  - Blob suffixes are allow-listed (images: `png jpg jpeg webp gif svg`;
    audio: `mp3 wav ogg flac`), each blob is capped at 100 MB, and
    missing/invalid blobs keep their ref (neutral placeholder on canvas,
    skipped on export) instead of failing the whole import.
  - Only blobs actually referenced by the scene are extracted.
- Treat `.totm` files like any downloaded document: only open bundles
  from people you trust, and inspect the imported design before exporting.

### Images, audio, fonts (untrusted input)

- Image import (`LibraryStore::importImage`) accepts `png jpg jpeg webp
  gif svg` and normalizes unknown suffixes to `png`; audio import accepts
  `mp3 wav ogg flac`. Both are stored as opaque blobs under uuid names
  and rendered through Qt's image / QtMultimedia pipelines.
- Imported UI fonts (`SettingsStore`) are loaded by family name with a
  "Font not found" fallback to the system font when the file is gone —
  a missing font never breaks launch.
- Video export shells out to a **system `ffmpeg`** on `PATH` (bundled
  inside the AppImage; `brew` / `winget` / distro package elsewhere).
  The app never downloads or updates `ffmpeg` itself — install it from a
  source you trust and keep it updated. A missing binary only disables
  export with an installer hint; it never blocks the editor.
- Rendering happens on a low-priority worker thread streaming raw RGBA
  to `ffmpeg` stdin; cancel is polled (no blocking call exceeds ~500ms),
  partials are deleted, finished renders are copied out via `saveAs`,
  and orphaned `totm-export-*.mp4` temps are swept at startup.

### File picker and overwrite guards

- Every open/save uses the in-app picker (`components/dialogs/
  FilePicker.qml`) backed by the read-only `FileBrowser` store: local
  files only, dotfiles skipped, dirs-first listing, suffix-filtered rows.
  QML renders rows; it cannot read the disk itself.
- `.totm` export and video `saveAs` refuse an existing destination unless
  you confirm through the shared overwrite popup (`destinationExists` /
  `exportDestinationExists` share the writer's suffix rule), so a share
  or export can never silently clobber a file.

### Single instance and local socket

- Double-clicked `.totm` files are forwarded to the running window via a
  per-user `QLocalServer` (`main.cpp`, `SingleInstance`); a second launch
  forwards its argv and exits. A stale socket from a crash is reclaimed.
  On macOS, Finder opens arrive as `QFileOpenEvent` through the same
  path. The socket carries only local `.totm` file urls.
- A `QLockFile` additionally guards the library: a second instance gets
  a warning banner (last-writer-wins is documented in the header), so
  concurrent edits cannot silently corrupt data.

### Plugins (the biggest sandbox — read this before installing one)

Plugins are **QML-only folder drop-ins**
(`<AppData>/totm/plugins/<id>/` with `manifest.json` + QML). They are
the only third-party code the app ever runs, so they get defense in depth
(`backend/plugins/PluginStore.*`, `PluginNetworkGuard.h`):

1. **Manifest validation + explicit approval.** New plugins start
   disabled. First launch shows a permission popup listing each request
   with the maker's reason; `grantPending` persists only your
   per-permission choices in `plugins.json`. `setEnabled(true)` with
   missing grants reopens approval instead of enabling. One bad manifest
   disables that plugin only.
2. **Static sandbox scan.** Imports/identifiers are rejected by text:
   `Dialogs`, `StandardPaths`, `Multimedia`, XHR/`fetch`, `WorkerScript`,
   `LocalStorage`, and direct `LibraryStore` / `VideoExporter` /
   `SettingsStore` access. Allowed imports: `QtQuick`, `Layouts`,
   `Controls`, `Shapes`, `Effects`, `Totm`. Plugins go through the gated
   `PluginStore` API (slot models, `pluginFileUrl`, scoped KV).
3. **Engine-wide network block.** Even a scan-dodging plugin cannot
   exfiltrate or fetch remote code — `http/https/ftp` fail closed (see
   above).
4. **Mediated files + scoped storage.** Plugins never see file paths or
   dialogs: image/audio picks go through `requestImage`/`requestAudio`
   and the host `PluginFilePicker`; KV storage is capped at 1 MB per
   plugin in `plugins.json`. `pluginFileUrl` serves only relative `.qml`
   inside the plugin dir (no `..`, no absolute paths) and only for
   enabled plugins.
5. **Maker guide.** `src/docs/PLUG_IN.html` (installed to
   `share/doc/totm`, opened from Settings → Plugin) documents the
   permission catalog and slot contracts.

If you install third-party plugins: review the permission popup, prefer
plugins with source you can read, and disable anything you do not use
(Settings → Plugin → rescan / enable / review).

### Settings and privacy

- Preferences (`SettingsStore`, org `tot`, app `totm`) use native
  `QSettings`: theme choice, window geometry (validated against current
  screens), shortcut overrides, appearance colors/radius/fonts. No
  secrets, tokens, or telemetry are ever stored or sent — there is
  nowhere to send them to.
- The bundled docs (`PLUG_IN.html`, `CREDITS.html`, `CONTRIBUTORS.html`,
  installed to `share/doc/totm`) open in your default browser via a
  single `openGuide` / `openCredits` call. No in-app web content.

### What is NOT covered

- Upstream vulnerabilities in Qt, `ffmpeg`, system codecs, or distro
  packages — report those upstream, but tell us if `totm` needs a
  workaround.
- Social engineering (malicious plugin + user grants everything) — we
  mitigate with the approval UI and sandbox, but user judgment is the
  last layer.
- Physical access / compromised OS / malicious `ffmpeg` on `PATH` —
  outside what the app can defend.

## Reporting a vulnerability

**Do not open a public issue for an unpatched vulnerability.**

- Open a **private security advisory** on GitHub
  (`Security` → `Advisories` → `New draft advisory`), or email the
  maintainers (see recent commit history for contacts).
- Include:
  - affected version / commit + platform (e.g. `main @ abc123`,
    Qt 6.8.3, Arch / Ubuntu 24.04 / macOS 15 / Windows 11),
  - steps to reproduce (a minimal `.totm`, image, audio file, or plugin
    folder is ideal — prefer a small repro over a real-world file),
  - impact (what an attacker gains: code execution, file overwrite
    outside the library, sandbox escape, exfiltration, DoS),
  - which entry point it uses (`.totm` import, image/audio/font import,
    plugin install/grant, `ffmpeg` handling, picker destination, socket).
- We aim to acknowledge within **72 hours**, fix on `main`, and disclose
  once a patch (and, if needed, a release) is ready. We will credit you
  unless you ask to stay anonymous.
- Please keep the report confidential until we have shipped and disclosed
  it, and avoid destructive testing against other people's machines.

## After a fix

- The fix lands on `main` with a regression note; the CHANGELOG records
  it under `Fixed` (without exploit detail until users have had time to
  update).
- If the issue affects the current release, we tag a patch release and
  mention it in the release notes.
- Corrupt-file and sandbox behaviors above mean most malformed-input bugs
  degrade to an error bar or placeholder rather than data loss — reports
  that break that contract get priority.
