# Workitem 1 — Fix undefined `is_fluid` in handle_create_click

**Status:** Done
**Type:** Bug (High)
**Files changed:** control.lua

## What was wrong
In `handle_create_click`, the guard `if is_fluid and quality_name ~= "normal" then ... end` (around line 1386) referenced a local `is_fluid` that was never declared anywhere in the function. As a result the expression was always `nil`, making the block dead code. The intent was: when the chosen signal is a fluid, reset the output quality to `"normal"` (fluids have no quality). Because `is_fluid` was undefined, that reset never happened in the create path.

## What I changed
I derived `is_fluid` locally at the same point where `item_name`/`quality_name` are computed from the selected signal (`item_value`). A fluid is indicated by `item_value.type == "fluid"` when `item_value` is a table.

Before:
```lua
  local item_name = item_value
  local quality_name = "normal"
  if type(item_value) == "table" then
    item_name = item_value.name
    quality_name = item_value.quality or "normal"
  end
```

After:
```lua
  local item_name = item_value
  local quality_name = "normal"
  local is_fluid = false
  if type(item_value) == "table" then
    item_name = item_value.name
    quality_name = item_value.quality or "normal"
    is_fluid = item_value.type == "fluid"
  end
```

The existing `if is_fluid and quality_name ~= "normal" then` block now works as intended.

## How to undo just this workitem
This change is committed as a single commit tagged `workitem-1`.
```bash
git revert $(git log --grep="workitem-1" -1 --format=%H)
```
