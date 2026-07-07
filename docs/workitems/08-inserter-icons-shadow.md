# Workitem 8 — Remove inserter_icons local shadowing

**Status:** Done
**Type:** Minor / cleanup (Low)
**Files changed:** control.lua

## What was wrong
Inside `build_gui`, the local `inserter_icons` was declared twice at the same
top-level function scope:

1. First, it held the inserter flow element created via
   `inserter_flow.add({ ... name = GUI_INSERTER_FLOW ... })` and was used
   immediately to populate the inserter sprite-buttons.
2. Later (near the end of `build_gui`), `local inserter_icons =
   find_child_by_name(frame, GUI_INSERTER_FLOW)` re-declared the same name to
   re-find that flow and refresh the toggled state of its buttons.

The second `local` re-declares and shadows the first binding. Harmless in
practice (the first value is no longer needed by that point), but sloppy and
misleading.

## What I changed
I dropped the `local` keyword on the second occurrence so it reassigns the
existing local instead of introducing a new shadowing binding.

Before:
```lua
-- Update inserter buttons state
local inserter_icons = find_child_by_name(frame, GUI_INSERTER_FLOW)
```

After:
```lua
-- Update inserter buttons state
inserter_icons = find_child_by_name(frame, GUI_INSERTER_FLOW)
```

This is scope-safe: both statements live directly in the `build_gui` function
body with no intervening `do ... end` or other block scope between them, so the
first `local inserter_icons` is still in scope at the point of reassignment.
Reusing the local is behaviorally identical to the previous shadowing version,
just without the redundant declaration.

## How to undo just this workitem
Committed as a single commit tagged `workitem-8`.
```bash
git revert $(git log --grep="workitem-8" -1 --format=%H)
```
