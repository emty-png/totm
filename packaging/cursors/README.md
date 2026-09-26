# Bundled mouse cursors (Bibata)

The SVGs in `light/` and `dark/` are a recolored subset of
[Bibata Cursor](https://github.com/ful1e5/Bibata_Cursor) by Abdulkaiz Khatri,
which is licensed under the **GNU General Public License v3.0**
(full text in `src/docs/CREDITS.html`, section 3).

* `light/` — Bibata **Modern Ice** (white base `#FFFFFF`, black outline).
  Used for the app light theme.
* `dark/` — Bibata **Modern Classic** (black base `#000000`, white outline).
  Used for the app dark theme.

Modifications vs upstream (September 2026): flat recolor of the base
(`#00FF00`/`#FE0000`), outline (`#0000FF`) and watch (`#FF0000`) placeholders,
plus the `forbidden.svg` cross follows the outline color so it stays visible
on both fills. Badge colors (`#06B231`, `#606060`) and their white glyphs are
untouched, matching upstream builds. Wait/busy are not bundled (upstream
ships them animated; `QCursor` pixmaps are static, so the app keeps the
system spinners).

Sources (Modern set):

| file            | upstream source                                  |
|-----------------|--------------------------------------------------|
| `arrow.svg`     | `svg/groups/modern/left_ptr.svg`                 |
| `hand.svg`      | `svg/groups/hand/hand2.svg`                      |
| `open-hand.svg` | `svg/groups/hand/hand1.svg`                      |
| `grabbing.svg`  | `svg/groups/hand/grabbing.svg`                   |
| `ibeam.svg`     | `svg/groups/shared/xterm.svg`                    |
| `cross.svg`     | `svg/groups/shared/cross.svg`                    |
| `size-hor.svg`  | `svg/groups/modern-arrow/sb_h_double_arrow.svg`  |
| `size-ver.svg`  | `svg/groups/modern-arrow/sb_v_double_arrow.svg`  |
| `size-fdiag.svg`| `svg/groups/modern-arrow/bd_double_arrow.svg`    |
| `size-bdiag.svg`| `svg/groups/modern-arrow/fd_double_arrow.svg`    |
| `size-all.svg`  | `svg/groups/modern-arrow/move.svg`               |
| `forbidden.svg` | `svg/groups/shared/crossed_circle.svg`           |
| `drag-copy.svg` | `svg/groups/hand/dnd-copy.svg`                   |
| `drag-link.svg` | `svg/groups/hand/dnd-link.svg`                   |
| `whatsthis.svg` | `svg/groups/shared/question_arrow.svg`           |
| `up-arrow.svg`  | `svg/groups/modern-arrow/sb_up_arrow.svg`        |

Hotspots are applied in `src/backend/cursors/CursorStore.cpp` from the
hotspot values in upstream `configs/normal/x.build.toml`.
