# Workitem 10 — GUI window overflow: make content scrollable, keep Build button visible

**Status:** Done
**Type:** UX (Low)
**Files changed:** control.lua

## What was wrong
The task was titled "entity overflow error", but that title is misleading. The
linked mod-portal discussion
(https://mods.factorio.com/mod/quick-mall/discussion/6a3c1ca62e6b3d3dc9466764)
is actually a **GUI sizing / overflow** problem, not an entity-count issue.

In a heavily-modded game the Quick Mall GUI builds one icon per candidate
building, recipe, chest and inserter. With many mods installed the building
table (`GUI_BUILDING_FLOW`, `column_count = 10`) alone can grow to dozens of
rows, and the recipe/chest flows add more. The root `frame` had no bounded
height, so the whole window grew **taller than the screen**. A user running at
75% UI scale reported that the bottom of the window — including the
"Build Quick Mall" button (`GUI_CREATE`) — was cut off and unreachable, with no
way to shrink the menu.

## What I changed
`build_gui` in `control.lua` previously added a single vertical `content` flow
directly to `frame`, put every selection row plus the final button flow inside
it, and let the frame size itself to fit everything.

Now the middle selection rows live inside a **`scroll-pane`** with a bounded
`maximum_height`, and the Build button is added to `frame` **after** the
scroll-pane so it always sits on screen below the (now scrollable) content.

Before:

```lua
local content = frame.add({ type = "flow", direction = "vertical" })
content.style.padding = 12
content.style.vertical_spacing = 8
-- ... all selection rows added to content ...
local button_flow = content.add({ type = "flow", direction = "horizontal" })
button_flow.style.horizontal_align = "right"
button_flow.add({ type = "button", name = GUI_CREATE, caption = "Build Quick Mall" })
```

After:

```lua
local scroll_pane = frame.add({
  type = "scroll-pane",
  horizontal_scroll_policy = "never",
  vertical_scroll_policy = "auto",
})
scroll_pane.style.maximal_height = 500

local content = scroll_pane.add({ type = "flow", direction = "vertical" })
content.style.padding = 12
content.style.vertical_spacing = 8
-- ... all selection rows still added to content (unchanged) ...

-- Build button now added to frame, outside the scroll-pane:
local button_flow = frame.add({ type = "flow", direction = "horizontal" })
button_flow.style.horizontal_align = "right"
button_flow.style.horizontally_stretchable = true
button_flow.style.padding = 12
button_flow.add({ type = "button", name = GUI_CREATE, caption = "Build Quick Mall" })
```

Notes:
- **No element names changed.** `GUI_BUILDING_FLOW`, `GUI_RECIPE_FLOW`,
  `GUI_INPUT_FLOW`, `GUI_OUTPUT_FLOW`, `GUI_STACK_LIMIT_FLOW`,
  `GUI_INSERTER_FLOW`, `GUI_QUALITY_WARNING`, `GUI_ITEM`, `GUI_CREATE`,
  `GUI_CLOSE` all keep their names.
- All the `find_child_by_name(frame, ...)` lookups still resolve: that helper
  walks `element.children` **recursively**, so it finds the selection rows even
  though they are now nested one level deeper inside the scroll-pane (which is
  itself a child of `frame`). The Build button is now a direct grandchild of
  `frame` via `button_flow`, still found by name.
- `frame.auto_center = true`, `player.opened = frame`, the titlebar drag
  targets, and every post-build render call
  (`update_quality_warning`, `render_building_buttons`,
  `render_recipe_buttons`, `render_input_chest_buttons`,
  `render_output_chest_buttons`, `render_stack_limit_ui`, and the inserter
  toggle loop) are all preserved unchanged.
- `maximal_height = 500` is a conservative fixed value that fits typical
  screens including reduced UI scales. If needed it could later be computed from
  `player.display_resolution` / `player.display_scale`, but a fixed value is
  safe and keeps behavior predictable.

Parse-checked with `luac -p control.lua` → PARSE_OK.

## Runtime fix (2026-07-06, after in-game report)
The original implementation set `scroll_pane.style.maximum_height`, which is
**not a valid LuaStyle key** — Factorio raised a non-recoverable runtime error
on GUI open:

```
LuaStyle doesn't contain key maximum_height.
  scripts/gui.lua:368: in function 'build_gui'
```

`luac -p` could not catch this (it is a valid Lua statement; the key is only
rejected at runtime by the game). Fixed by using the correct property name,
`maximal_height` (LuaStyle uses `minimal_height`/`maximal_height`, not
`minimum_`/`maximum_`). Verified against the LuaStyle API docs. This lives in
`scripts/gui.lua` after the workitem-12 module split.

## In-game verification
This is a layout change to a live GUI; it should be spot-checked in-game to
confirm the scrollbar appears with a long list and the Build button stays
visible. Cannot be verified from static analysis alone.

## How to undo just this workitem
Committed as a single commit tagged `workitem-10`.
```bash
git revert $(git log --grep="workitem-10" -1 --format=%H)
```
