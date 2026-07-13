# Workitem 17 — Constant Quick Mall window width

**Status:** 🔵 Needs In-Game Verification
**Type:** UX (Low)
**Files changed:** scripts/constants.lua, scripts/gui.lua

## What was wrong
The Quick Mall window (`GUI_ROOT` frame → `content` flow) had no fixed width, so
Factorio sized it to its widest child on every (re)render. As the user changed
selections — different label lengths, different numbers of building/recipe/chest icons
per row — the window visibly grew and shrank horizontally. It felt janky and made the
layout unstable.

## What work I did
Added a fixed content-width constant and pinned the content flow to it.

`scripts/constants.lua` — new constant + export:
```lua
-- Fixed content width (workitem-17) ... sized to hold a full row of GUI_ICON_COLUMNS
-- (10) 40px slot buttons plus row label and padding.
local GUI_CONTENT_WIDTH = 10 * 40 + 60
...
GUI_CONTENT_WIDTH = GUI_CONTENT_WIDTH,
```

`scripts/gui.lua` — alias + apply in `build_gui` right after the `content` flow is added:
```lua
local GUI_CONTENT_WIDTH = constants.GUI_CONTENT_WIDTH
...
local content = scroll_pane.add({ type = "flow", direction = "vertical" })
content.style.padding = 12
content.style.vertical_spacing = 8
-- Pin a fixed content width (workitem-17) so the window no longer grows/shrinks
-- to fit the longest row. Setting min == max keeps it constant.
content.style.minimal_width = GUI_CONTENT_WIDTH
content.style.maximal_width = GUI_CONTENT_WIDTH
```

## How it was solved
Setting `minimal_width == maximal_width` on the `content` flow removes the "size to
widest child" behavior, so the window is a constant width no matter which row is longest.
The width is derived from `GUI_ICON_COLUMNS` (a full 10-wide icon row) plus label/padding
room, so a full icon row still fits without horizontal scrolling. This composes with the
workitem-10 fix: the per-row icon tables already wrap into a grid and scroll vertically
within bounded per-row scroll-panes, so no row can overflow the fixed width horizontally.

Alternatives considered: sizing the width dynamically to the current longest row (rejected —
that is the janky behavior we are removing) and setting width on the `frame` instead of
`content` (rejected — the titlebar/Build-button live on the frame and pinning `content` is
the least intrusive point that governs the selection rows). `luac -p` passes on both files.

## How to undo just this workitem
Committed as a single commit tagged `workitem-17`.
```bash
git revert $(git log --grep="workitem-17" -1 --format=%H)
```
