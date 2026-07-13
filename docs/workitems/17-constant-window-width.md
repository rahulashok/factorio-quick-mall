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
Pin the `content` flow with a `minimal_width` FLOOR (not a min==max cap). This removes the
"size to widest child" jank — no row exceeds the floor, so the window looks constant — while
guaranteeing content is never cut off.

**Correction (2026-07-13):** the first attempt used `minimal_width == maximal_width = 10*40+60`
(≈460px). That was wrong on two counts and clipped the last ~2 icon columns:
1. **Too narrow.** Each icon row is laid out horizontally as `[heading label] [scroll-pane
   holding the 10-column table]`. The table alone is `10*40 + 9*4 = 436px`; add the ~120px
   heading label + content padding and 460px left far too little for the table.
2. **A max cap clips.** The per-row scroll-pane uses `horizontal_scroll_policy = "never"`, so
   whatever doesn't fit is cut off (not scrollable). A `maximal_width` cap therefore *hides*
   the last columns instead of showing them.

The fix: `GUI_CONTENT_WIDTH = GUI_ICON_COLUMNS*40 + (GUI_ICON_COLUMNS-1)*4 + 200` (= 636px for
10 columns) — full icon table + label + padding + scrollbar reserve — applied as
`minimal_width` only. Because it's a floor, if the estimate is ever slightly low the window
GROWS rather than clipping, which satisfies "must definitely show all contents." The width is
derived from `GUI_ICON_COLUMNS` so it stays correct if the column count changes.

Alternatives considered: sizing dynamically to the longest row (rejected — that is the jank
being removed); pinning the `frame` instead of `content` (rejected — titlebar/Build-button
live on the frame; `content` is the least intrusive point governing the selection rows).
`luac -p` passes on both files.

## How to undo just this workitem
Committed as a single commit tagged `workitem-17`.
```bash
git revert $(git log --grep="workitem-17" -1 --format=%H)
```
