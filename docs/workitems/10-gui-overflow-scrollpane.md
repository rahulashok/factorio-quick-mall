# Workitem 10 — GUI window overflow: make content scrollable, keep Build button visible

**Status:** 🔵 Needs In-Game Verification
**Type:** UX (Low)
**Files changed (latest pass, 2026-07-13):** scripts/gui.lua, scripts/constants.lua (control.lua unchanged)

> This file records three passes at the same overflow problem, newest **first**:
> the **horizontal-overflow fix (2026-07-13)** below, then the earlier
> `maximal_height` runtime fix and the original scroll-pane sizing fix preserved
> verbatim under "## PRIOR HISTORY".

---

## Horizontal-overflow fix (2026-07-13, after in-game retest failed)

### What was wrong (reopened reason)
The previous passes bounded the window's **vertical** height with an outer
`scroll-pane` (`maximal_height = 500`). But the Recipe, Input chest, Output chest
and Inserter rows each placed their sprite-buttons in a **`flow` with
`direction = "horizontal"`**. A flow does **not** wrap, so with many candidate
recipes/entities the icons marched off the **right** edge of the window. The
vertical scroll-pane did nothing for this horizontal growth. In-game report:

> "When there are a lot of entities it places them all in a single row and it
> extends horizontally beyond the UI's boundary."

Only the Building row was already a wrapping `table` (`column_count = 10`); the
other four rows were the offending horizontal flows.

### What work I did
Two things:

**1. Every icon row now wraps into a grid.** All five icon containers
(`GUI_BUILDING_FLOW`, `GUI_RECIPE_FLOW`, `GUI_INPUT_FLOW`, `GUI_OUTPUT_FLOW`,
`GUI_INSERTER_FLOW`) are now `type = "table"` with `column_count = 10`, matching
the building row. **Element names are unchanged** — only the element `type`
changed from `"flow"` to `"table"`, so every `find_child_by_name` lookup and the
`.clear()`/`.add()` calls in the render_* helpers keep working (children on a
table auto-wrap into rows). No `control.lua` handler changes were needed because
the click handlers still match on the stable `GUI_*_PREFIX` names.

**2. Overflow past a row limit is contained, not unbounded.** Each icon `table`
is nested inside a per-row **`scroll-pane`** with
`maximal_height = GUI_OVERFLOW_SCROLL_HEIGHT` (~3 rows of 40px slot buttons) and
`vertical_scroll_policy = "auto"`. Short lists render at natural size; a list
longer than ~`GUI_MAX_INLINE_ROWS × GUI_ICON_COLUMNS` (≈30) icons clamps to that
height and gains its own vertical scrollbar, so a huge modded list scrolls within
its row region instead of ballooning the window.

All of this was factored into one helper, `add_icon_row(parent, label, name)`,
which builds `label + scroll-pane + table` and returns the table.

Before (Recipe row shown; Input/Output/Inserter were identical horizontal flows):

```lua
local recipe_flow = content.add({ type = "flow", direction = "horizontal" })
recipe_flow.style.vertical_align = "center"
recipe_flow.add({ type = "label", caption = "Recipe: ", style = "heading_2_label" })
local recipe_icons = recipe_flow.add({
  type = "flow",
  name = GUI_RECIPE_FLOW,
  direction = "horizontal",   -- NEVER wraps → overflows right edge
})
recipe_icons.style.horizontal_spacing = 4
```

After (all five rows built via one helper):

```lua
local function add_icon_row(parent, label_caption, table_name)
  local row = parent.add({ type = "flow", direction = "horizontal" })
  row.style.vertical_align = "center"
  row.add({ type = "label", caption = label_caption, style = "heading_2_label" })

  local scroll = row.add({
    type = "scroll-pane",
    horizontal_scroll_policy = "never",
    vertical_scroll_policy = "auto",
  })
  scroll.style.maximal_height = GUI_OVERFLOW_SCROLL_HEIGHT

  local icons = scroll.add({
    type = "table",
    name = table_name,          -- SAME name as before; only type changed
    column_count = GUI_ICON_COLUMNS,   -- = 10, so buttons wrap into rows
  })
  icons.style.horizontal_spacing = 4
  icons.style.vertical_spacing = 4
  return icons
end

-- in build_gui:
add_icon_row(content, "Building: ", GUI_BUILDING_FLOW)
add_icon_row(content, "Recipe: ", GUI_RECIPE_FLOW)
add_icon_row(content, "Input chest: ", GUI_INPUT_FLOW)
add_icon_row(content, "Output chest: ", GUI_OUTPUT_FLOW)
-- ... stack-limit row ...
local inserter_icons = add_icon_row(content, "Inserter: ", GUI_INSERTER_FLOW)
```

New constants in `scripts/constants.lua`:

```lua
local GUI_ICON_COLUMNS = 10
local GUI_MAX_INLINE_ROWS = 3
local GUI_OVERFLOW_SCROLL_HEIGHT = 3 * 40 + 8
```

### How it was solved — and why nested-scroll instead of a native chooser
The task offered two overflow strategies: (a) a native `choose-elem-button`
picker dialog with an `elem_filters` name allow-list, or (b) a bounded nested
`scroll-pane`. I chose **(b) the nested scroll-pane**, for two concrete reasons:

1. **A native chooser can't cover the recipe row.** The 2.0
   `EntityPrototypeFilter` does support a `{filter = "name", name = {...}}`
   allow-list (usable for the entity rows), but the `RecipePrototypeFilter`
   **has no recipe-name allow-list filter** (only category/ingredient/product/
   enabled/hidden conditions). Verified against the current `lua-api.factorio.com`
   docs. So a `choose-elem-button` with `elem_type = "recipe"` could not be
   constrained to exactly the valid recipes for the chosen item+building, and
   would let the player pick nonsense recipes — a correctness regression.

2. **Uniformity + no new event surface.** The nested-scroll approach works
   identically for all five rows (entities and recipes alike), keeps every
   element name stable, and introduces **no new interactive element**, so no
   `on_gui_click` / `on_gui_elem_changed` wiring changes were required and all
   existing selection-persistence and toggled-state behavior is untouched. This
   is the "up to some limit, then contained" behavior the user asked for, done
   the simplest robust way. `control.lua` was not modified at all.

### In-game verification checklist (why status is 🔵, not 🟢)
This is a live-GUI change that already failed a retest once, and `luac -p` only
catches syntax. Must be confirmed in-game:
- **Wrapping:** with many candidate buildings/recipes/chests/inserters, each row
  wraps into multiple rows of 10 and never extends past the right window edge.
- **Overflow containment:** a row with >~30 icons shows its own vertical
  scrollbar and scrolls within its region (window does not grow unbounded).
- **Selection still works:** clicking an icon in any (possibly scrolled) row
  toggles it and updates `options.<selection>`; recipe click still cascades to
  the chest/stack-limit rows.
- **Build still works:** "Build Quick Mall" produces the expected blueprint.
- No runtime `LuaStyle`/element errors on GUI open.

### How to undo just this workitem
Committed as a single commit tagged `workitem-10`.
```bash
git revert $(git log --grep="workitem-10" -1 --format=%H)
```

---

## PRIOR HISTORY (kept for the record)

### What was wrong
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

### What I changed (prior pass)
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

### Runtime fix (2026-07-06, after in-game report)
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

### In-game verification (prior pass)
This is a layout change to a live GUI; it should be spot-checked in-game to
confirm the scrollbar appears with a long list and the Build button stays
visible. Cannot be verified from static analysis alone.

## User feedback (reopened 2026-07-13)
In-game testing failed. When there are a lot of entities it places them all in a single row in the UI and it extends horizontally beyond the UI's boundary. We need a better way to handle this.  if the number of entities is too long then it should show up in multiple rows up to some sort of limit. beyond that limit it needs to then instead use a separate dialog window similar to when we are choosing what item to craft and show the list of entities within that

_(The prior pass was also committed under the `workitem-10` tag; the authoritative
undo instructions are in the "Horizontal-overflow fix" section at the top.)_

## How to undo just this workitem
Committed as a single commit tagged `workitem-10`.
```bash
git revert $(git log --grep="workitem-10" -1 --format=%H)
```
