# canvas-interactions

Single source for pointer behavior. Keep code and this doc in sync.

* Wheel pans, Shift+wheel pans horizontally, Ctrl/Meta+wheel zooms to cursor (0.02–16).
* Middle-drag or Space+left-drag pans.
* Select tool: drag on empty = marquee (Shift adds), click empty clears. Shape press resolves leaves to their group target unless drilled in; Shift/Ctrl toggles.
* Shapes tool: drag draws (anchor + moving corner both snap), click drops 100×100, then returns to select.
* Resize handles scale the whole selection bbox from the press snapshot. Shift on corners locks aspect. Alt suspends snapping mid-gesture.
* Snapping threshold is 5 screen px. Targets are unselected visible leaves + group boxes + scene edges/center. Locked and hidden never attract. Guides show while dragging; resting geometry settles to whole pixels on release.
* Double-click drills into a group; Esc climbs out before closing menus.
